#!/usr/bin/env python3
"""PoC reproducible de EN-027.2; solo crea contenedores Docker temporales."""

from __future__ import annotations

import os
import subprocess
import time
import uuid


IMAGE = os.environ.get("MONGO_POC_IMAGE", "mongo:8.0")
PREFIX = "nb-en0272-"


def execute(*arguments: str, check: bool = True) -> subprocess.CompletedProcess[str]:
    result = subprocess.run(
        list(arguments),
        check=False,
        capture_output=True,
        text=True,
        encoding="utf-8",
    )
    if check and result.returncode != 0:
        raise RuntimeError(
            f"Fallo ({result.returncode}): {' '.join(arguments)}\n"
            f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
        )
    return result


def docker(*arguments: str, check: bool = True) -> subprocess.CompletedProcess[str]:
    return execute("docker", *arguments, check=check)


def mongo(container: str, javascript: str) -> str:
    return docker(
        "exec",
        container,
        "mongosh",
        "mongodb://127.0.0.1:27017/?retryWrites=false",
        "--quiet",
        "--eval",
        javascript,
    ).stdout.strip()


def wait_for_ping(container: str, attempts: int = 45) -> None:
    for _ in range(attempts):
        result = docker(
            "exec",
            container,
            "mongosh",
            "--quiet",
            "--eval",
            'db.adminCommand("ping").ok',
            check=False,
        )
        if result.returncode == 0 and "1" in result.stdout:
            return
        time.sleep(1)
    raise RuntimeError(f"MongoDB no respondió en el contenedor {container}.")


def wait_for_primary(container: str, attempts: int = 45) -> None:
    for _ in range(attempts):
        result = docker(
            "exec",
            container,
            "mongosh",
            "--quiet",
            "--eval",
            'db.hello().isWritablePrimary === true ? "PRIMARY" : "WAIT"',
            check=False,
        )
        if result.returncode == 0 and "PRIMARY" in result.stdout:
            return
        time.sleep(1)
    raise RuntimeError(f"El replica set de {container} no eligió PRIMARY.")


def remove_container(container: str) -> None:
    if not container.startswith(PREFIX):
        raise RuntimeError(f"Se rechazó eliminar un contenedor fuera de la PoC: {container}")
    docker("rm", "-f", container, check=False)


def verify_standalone(container: str) -> None:
    docker("run", "-d", "--name", container, "--memory", "384m", IMAGE)
    wait_for_ping(container)
    output = mongo(
        container,
        r'''
try {
  const result = db.getSiblingDB("catalog_atomicity_poc").runCommand({
    insert: "products",
    documents: [{_id: "standalone-product"}],
    lsid: {id: UUID()},
    txnNumber: NumberLong("1"),
    startTransaction: true,
    autocommit: false
  });
  if (result.ok !== 1) {
    print("STANDALONE_REJECTED=" + JSON.stringify({
      code: result.code ?? null,
      codeName: result.codeName ?? null,
      message: result.errmsg ?? null
    }));
  } else {
    print("STANDALONE_UNEXPECTEDLY_ACCEPTED");
  }
} catch (error) {
  print("STANDALONE_REJECTED=" + JSON.stringify({
    code: error.code ?? null,
    codeName: error.codeName ?? null,
    message: error.message ?? String(error)
  }));
}
''',
    )
    if "STANDALONE_REJECTED=" not in output or "STANDALONE_UNEXPECTEDLY_ACCEPTED" in output:
        raise RuntimeError(f"El standalone no produjo el rechazo esperado:\n{output}")
    print(output)


def verify_replica_set(container: str) -> None:
    docker(
        "run",
        "-d",
        "--name",
        container,
        "--memory",
        "384m",
        IMAGE,
        "--replSet",
        "rs0",
        "--bind_ip_all",
        "--oplogSize",
        "128",
    )
    wait_for_ping(container)
    mongo(
        container,
        'rs.initiate({_id:"rs0",members:[{_id:0,host:"127.0.0.1:27017"}]})',
    )
    wait_for_primary(container)

    output = mongo(
        container,
        r'''
const databaseName = "catalog_atomicity_poc";
db.getSiblingDB(databaseName).dropDatabase();
const setup = db.getSiblingDB(databaseName);
setup.audit_log.createIndex({eventId: 1}, {unique: true});
setup.outbox.createIndex({eventId: 1}, {unique: true});

const first = db.getMongo().startSession();
try {
  first.startTransaction({
    readConcern: {level: "snapshot"},
    writeConcern: {w: "majority"}
  });
  const catalog = first.getDatabase(databaseName);
  catalog.products.insertOne({_id: "product-1", name: "Espada", version: 0});
  catalog.audit_log.insertOne({_id: "audit-1", eventId: "event-1", action: "CREATED"});
  catalog.outbox.insertOne({_id: "outbox-1", eventId: "event-1", status: "PENDING"});
  first.commitTransaction();
} finally {
  first.endSession();
}

const committed = db.getSiblingDB(databaseName);
if (committed.products.countDocuments({_id: "product-1"}) !== 1 ||
    committed.audit_log.countDocuments({eventId: "event-1"}) !== 1 ||
    committed.outbox.countDocuments({eventId: "event-1"}) !== 1) {
  throw new Error("La transacción válida no confirmó los tres documentos.");
}
print("TRANSACTION_COMMIT=3_OF_3");

const failing = db.getMongo().startSession();
try {
  failing.startTransaction({writeConcern: {w: "majority"}});
  const catalog = failing.getDatabase(databaseName);
  catalog.products.insertOne({_id: "product-rollback", name: "Debe revertirse", version: 0});
  catalog.outbox.insertOne({_id: "outbox-rollback", eventId: "event-rollback", status: "PENDING"});
  catalog.audit_log.insertOne({_id: "audit-duplicate", eventId: "event-1", action: "CREATED"});
  failing.commitTransaction();
  throw new Error("La transacción inválida fue confirmada.");
} catch (error) {
  try { failing.abortTransaction(); } catch (_) {}
} finally {
  failing.endSession();
}

if (committed.products.countDocuments({_id: "product-rollback"}) !== 0 ||
    committed.outbox.countDocuments({_id: "outbox-rollback"}) !== 0) {
  throw new Error("El fallo dejó escrituras parciales.");
}
print("TRANSACTION_ROLLBACK=0_OF_2_PARTIAL_WRITES");

const updated = committed.products.findOneAndUpdate(
  {_id: "product-1", version: 0},
  {$set: {name: "Espada actualizada"}, $inc: {version: 1}},
  {returnDocument: "after"}
);
const stale = committed.products.findOneAndUpdate(
  {_id: "product-1", version: 0},
  {$set: {name: "Escritor obsoleto"}, $inc: {version: 1}},
  {returnDocument: "after"}
);
if (updated === null || stale !== null || updated.version !== 1) {
  throw new Error("El control de versión optimista no funcionó.");
}
print("OPTIMISTIC_CONCURRENCY=STALE_REJECTED");

const status = rs.status();
const primaryCount = status.members.filter(member => member.stateStr === "PRIMARY").length;
print("REPLICA_STATUS=" + JSON.stringify({ok: status.ok, members: status.members.length, primaryCount}));
''',
    )
    for marker in (
        "TRANSACTION_COMMIT=3_OF_3",
        "TRANSACTION_ROLLBACK=0_OF_2_PARTIAL_WRITES",
        "OPTIMISTIC_CONCURRENCY=STALE_REJECTED",
        'REPLICA_STATUS={"ok":1,"members":1,"primaryCount":1}',
    ):
        if marker not in output:
            raise RuntimeError(f"Falta evidencia {marker}:\n{output}")

    memory = docker("stats", "--no-stream", "--format", "{{.MemUsage}}", container).stdout.strip()
    print(output)
    print(f"MEMORY_LIMIT_EVIDENCE={memory}")
    print("POC_AUTHENTICATION=NOT_EVALUATED")


def main() -> None:
    suffix = uuid.uuid4().hex[:10]
    standalone = f"{PREFIX}standalone-{suffix}"
    replica = f"{PREFIX}replica-{suffix}"
    try:
        verify_standalone(standalone)
    finally:
        remove_container(standalone)
    try:
        verify_replica_set(replica)
    finally:
        remove_container(replica)


if __name__ == "__main__":
    main()
