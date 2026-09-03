#!/usr/bin/env python3
"""Verifica EN-027.5 sobre la composicion real del nodo de datos."""

from __future__ import annotations

import concurrent.futures
import base64
import hashlib
import json
import os
from pathlib import Path
import secrets
import subprocess
import tempfile
import time
import uuid


ROOT = Path(__file__).resolve().parents[1]
COMPOSE_DIR = ROOT / "compose"
PROJECT_PREFIX = "nb-en0275-"
PASSWORD = "Validacion-EN0275-2026!"
CREDENTIALS = {
    "catalog-runtime": "Catalog-Runtime-EN0275x",
    "catalog-migration": "Catalog-Migration-EN0275x",
    "inventory-runtime": "Inventory-Runtime-EN0275x",
    "inventory-migration": "Inventory-Migration-EN0275x",
}


def execute(
    *arguments: str,
    env: dict[str, str] | None = None,
    check: bool = True,
) -> subprocess.CompletedProcess[str]:
    result = subprocess.run(
        list(arguments),
        cwd=COMPOSE_DIR,
        env=env,
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


class OperationalReplicaSet:
    def __init__(self, project: str, environment: dict[str, str]) -> None:
        if not project.startswith(PROJECT_PREFIX):
            raise ValueError("Nombre de proyecto fuera del prefijo de la prueba")
        self.project = project
        self.environment = environment
        self.base = (
            "docker",
            "compose",
            "-p",
            project,
            "-f",
            "nodes/data.yml",
        )

    def compose(self, *arguments: str, check: bool = True) -> subprocess.CompletedProcess[str]:
        return execute(*self.base, *arguments, env=self.environment, check=check)

    def mongo(
        self,
        javascript: str,
        *,
        user: str = "root",
        database: str = "admin",
    ) -> str:
        return self.compose(
            "exec",
            "-T",
            "mongo",
            "mongosh",
            "--host",
            "127.0.0.1",
            "--quiet",
            "--username",
            user,
            "--password",
            CREDENTIALS.get(user, PASSWORD),
            "--authenticationDatabase",
            database,
            "--eval",
            javascript,
        ).stdout.strip()

    def wait_for_primary(self, attempts: int = 90) -> None:
        for _ in range(attempts):
            result = self.compose(
                "exec",
                "-T",
                "mongo",
                "mongosh",
                "--host",
                "127.0.0.1",
                "--quiet",
                "--username",
                "root",
                "--password",
                PASSWORD,
                "--authenticationDatabase",
                "admin",
                "--eval",
                'quit(db.hello().isWritablePrimary === true ? 0 : 1)',
                check=False,
            )
            if result.returncode == 0:
                return
            time.sleep(1)
        raise RuntimeError("MongoDB no alcanzo PRIMARY en 90s")

    def prepare_legacy_standalone_volume(self) -> None:
        """Crea el estado desplegado previo: auth, datos y ningun replica set."""
        volume = self.project + "_mongo-data"
        container = self.project + "-legacy"
        execute(
            "docker",
            "volume",
            "create",
            "--label",
            f"com.docker.compose.project={self.project}",
            "--label",
            "com.docker.compose.volume=mongo-data",
            volume,
            env=self.environment,
        )
        try:
            execute(
                "docker",
                "run",
                "-d",
                "--name",
                container,
                "--memory",
                "384m",
                "-e",
                "MONGO_INITDB_ROOT_USERNAME=root",
                "-e",
                f"MONGO_INITDB_ROOT_PASSWORD={PASSWORD}",
                "-v",
                f"{volume}:/data/db",
                "mongo:8",
                env=self.environment,
            )
            for _ in range(90):
                ping = execute(
                    "docker",
                    "exec",
                    container,
                    "mongosh",
                    "--host",
                    "127.0.0.1",
                    "--quiet",
                    "--username",
                    "root",
                    "--password",
                    PASSWORD,
                    "--authenticationDatabase",
                    "admin",
                    "--eval",
                    'quit(db.adminCommand("ping").ok === 1 ? 0 : 1)',
                    env=self.environment,
                    check=False,
                )
                if ping.returncode == 0:
                    break
                time.sleep(1)
            else:
                raise RuntimeError("El standalone legado no inicio en 90s")

            execute(
                "docker",
                "exec",
                container,
                "mongosh",
                "--host",
                "127.0.0.1",
                "--quiet",
                "--username",
                "root",
                "--password",
                PASSWORD,
                "--authenticationDatabase",
                "admin",
                "--eval",
                r'''
for (const identity of [
  {database:"catalog",user:"catalog"},
  {database:"player-inventory",user:"inventory"}
]) {
  db.getSiblingDB(identity.database).createUser({
    user:identity.user,pwd:"Validacion-EN0275-2026!",
    roles:[{role:"readWrite",db:identity.database},{role:"dbAdmin",db:identity.database}]
  });
}
db.getSiblingDB("catalog").products.insertOne({_id:"legacy-product",version:0});
''',
                env=self.environment,
            )
            print("LEGACY_STANDALONE_READY=true")
        finally:
            execute("docker", "rm", "-f", container, env=self.environment, check=False)

    def bootstrap(self) -> str:
        result = self.compose("run", "--rm", "mongo-bootstrap")
        self.wait_for_primary()
        if "MONGO_BOOTSTRAP_OK=" not in result.stdout:
            raise RuntimeError(f"El bootstrap no entrego evidencia:\n{result.stdout}")
        return result.stdout.strip()

    def verify_topology_and_roles(self) -> None:
        topology = self.mongo(
            "const s=rs.status(); "
            "const o=db.getSiblingDB('local').oplog.rs.stats(); "
            "print(EJSON.stringify({set:s.set,members:s.members.length,"
            "primary:s.members.filter(m=>m.stateStr==='PRIMARY').length,"
            "oplogMaxSize:o.maxSize}))"
        )
        parsed = json.loads(topology.splitlines()[-1])
        if parsed != {
            "set": "rs0",
            "members": 1,
            "primary": 1,
            "oplogMaxSize": 134217728,
        }:
            raise RuntimeError(f"Topologia u oplog inesperados: {parsed}")
        print("TOPOLOGY_OK=" + json.dumps(parsed, separators=(",", ":")))

        self.mongo(
            r'''
for (const name of ["products", "audit_log", "outbox"]) {
  const catalog=db.getSiblingDB("catalog");
  if (!catalog.getCollectionNames().includes(name)) catalog.createCollection(name);
}
db.getSiblingDB("catalog").outbox.insertOne({_id:"outbox-role-check",status:"PENDING"});
const inventory=db.getSiblingDB("player-inventory");
if (!inventory.getCollectionNames().includes("inventories")) inventory.createCollection("inventories");
'''
        )

        runtime = self.mongo(
            r'''
const target = db.getSiblingDB("catalog");
target.products.updateOne({_id:"role-check"},{$set:{ok:true}},{upsert:true});
target.audit_log.insertOne({_id:"audit-role-check",action:"CREATED"});
let schemaDenied = false;
try {
  target.runCommand({collMod:"products",validator:{ok:{$type:"bool"}}});
} catch (error) {
  schemaDenied = error.code === 13 || error.codeName === "Unauthorized";
}
let auditMutationDenied = false;
try {
  target.audit_log.updateOne({_id:"audit-role-check"},{$set:{action:"ALTERED"}});
} catch (error) {
  auditMutationDenied = error.code === 13 || error.codeName === "Unauthorized";
}
if (!schemaDenied) throw new Error("catalog-runtime obtuvo privilegios de esquema");
if (!auditMutationDenied) throw new Error("catalog-runtime pudo mutar audit_log");
print("RUNTIME_SCHEMA_DENIED=true");
print("RUNTIME_AUDIT_MUTATION_DENIED=true");
''',
            user="catalog-runtime",
            database="catalog",
        )
        if (
            "RUNTIME_SCHEMA_DENIED=true" not in runtime
            or "RUNTIME_AUDIT_MUTATION_DENIED=true" not in runtime
        ):
            raise RuntimeError(runtime)

        migration = self.mongo(
            r'''
const result = db.getSiblingDB("catalog").runCommand({
  collMod:"products",validator:{ok:{$type:"bool"}}
});
if (result.ok !== 1) throw new Error(EJSON.stringify(result));
print("MIGRATION_SCHEMA_ALLOWED=true");
''',
            user="catalog-migration",
            database="catalog",
        )
        if "MIGRATION_SCHEMA_ALLOWED=true" not in migration:
            raise RuntimeError(migration)
        print("IDENTITY_SEPARATION_OK=runtime_without_dbAdmin,migration_with_dbAdmin")

    def workload(self, user: str, database: str, collection: str) -> dict[str, object]:
        script = f'''
const target=db.getSiblingDB("{database}").getCollection("{collection}");
const latency=[];
for (let i=0;i<250;i+=1) {{
  const start=Date.now();
  target.updateOne({{_id:"load-"+i}},{{$inc:{{writes:1}},$set:{{source:"{user}",ok:true}}}},{{upsert:true}});
  latency.push(Date.now()-start);
}}
latency.sort((a,b)=>a-b);
print(EJSON.stringify({{actor:"{user}",operations:latency.length,p95Ms:latency[Math.ceil(latency.length*0.95)-1]}}));
'''
        output = self.mongo(script, user=user, database=database)
        return json.loads(output.splitlines()[-1])

    def verify_joint_load(self) -> None:
        with concurrent.futures.ThreadPoolExecutor(max_workers=2) as executor:
            futures = [
                executor.submit(self.workload, "catalog-runtime", "catalog", "products"),
                executor.submit(
                    self.workload,
                    "inventory-runtime",
                    "player-inventory",
                    "inventories",
                ),
            ]
            measurements = [future.result() for future in futures]

        oplog = json.loads(
            self.mongo(
                r'''
const op=db.getSiblingDB("local").oplog.rs;
const first=Number(op.find().sort({$natural:1}).limit(1).next().ts.getHighBits());
const last=Number(op.find().sort({$natural:-1}).limit(1).next().ts.getHighBits());
print(EJSON.stringify({first:new Date(first*1000).toISOString(),last:new Date(last*1000).toISOString(),windowSeconds:last-first}));
'''
            ).splitlines()[-1]
        )
        container = self.compose("ps", "-q", "mongo").stdout.strip()
        if not container:
            raise RuntimeError("No se encontro el contenedor MongoDB")
        state = json.loads(
            execute("docker", "inspect", container, env=self.environment).stdout
        )[0]["State"]
        memory = execute(
            "docker", "stats", "--no-stream", "--format", "{{.MemUsage}}", container,
            env=self.environment,
        ).stdout.strip()
        if state.get("OOMKilled") is not False:
            raise RuntimeError(f"MongoDB fue terminado por OOM: {state}")

        print("JOINT_LOAD=" + json.dumps(measurements, separators=(",", ":")))
        print("OPLOG_WINDOW=" + json.dumps(oplog, separators=(",", ":")))
        print(f"MEMORY_EVIDENCE={memory}")
        print("OOM_KILLED=false")

    def verify_backup_restore(self) -> None:
        dump_command = (
            *self.base,
            "exec",
            "-T",
            "mongo",
            "mongodump",
            "--host",
            "127.0.0.1",
            "--username",
            "root",
            "--password",
            PASSWORD,
            "--authenticationDatabase",
            "admin",
            "--db",
            "catalog",
            "--archive",
            "--gzip",
        )
        dumped = subprocess.run(
            dump_command,
            cwd=COMPOSE_DIR,
            env=self.environment,
            check=False,
            capture_output=True,
        )
        if dumped.returncode != 0 or not dumped.stdout:
            raise RuntimeError(
                "No se pudo crear el backup: "
                + dumped.stderr.decode("utf-8", errors="replace")
            )

        configuration = self.mongo('print(EJSON.stringify(rs.conf()))')
        collections = json.loads(
            self.mongo(
                'print(EJSON.stringify(db.getSiblingDB("catalog").getCollectionNames().sort()))'
            ).splitlines()[-1]
        )
        required = {"products", "audit_log", "outbox"}
        if not required.issubset(collections):
            raise RuntimeError(f"El backup no cubre las colecciones obligatorias: {collections}")

        self.mongo('db.getSiblingDB("catalog").dropDatabase()')
        restore_command = (
            *self.base,
            "exec",
            "-T",
            "mongo",
            "mongorestore",
            "--host",
            "127.0.0.1",
            "--username",
            "root",
            "--password",
            PASSWORD,
            "--authenticationDatabase",
            "admin",
            "--drop",
            "--archive",
            "--gzip",
        )
        restored = subprocess.run(
            restore_command,
            cwd=COMPOSE_DIR,
            env=self.environment,
            input=dumped.stdout,
            check=False,
            capture_output=True,
        )
        if restored.returncode != 0:
            raise RuntimeError(
                "No se pudo restaurar el backup: "
                + restored.stderr.decode("utf-8", errors="replace")
            )

        counts = json.loads(
            self.mongo(
                r'''
const catalog=db.getSiblingDB("catalog");
print(EJSON.stringify({
  products:catalog.products.countDocuments({}),
  audit_log:catalog.audit_log.countDocuments({}),
  outbox:catalog.outbox.countDocuments({})
}));
'''
            ).splitlines()[-1]
        )
        if any(counts[name] < 1 for name in required):
            raise RuntimeError(f"Restauracion incompleta: {counts}")
        if json.loads(configuration.splitlines()[-1])["_id"] != "rs0":
            raise RuntimeError("El backup no registro la configuracion de rs0")
        digest = hashlib.sha256(dumped.stdout).hexdigest()
        print(
            "BACKUP_RESTORE_OK="
            + json.dumps(
                {"counts": counts, "replicaSet": "rs0", "sha256": digest},
                separators=(",", ":"),
            )
        )

    def verify_restart_and_idempotency(self) -> None:
        self.compose("restart", "mongo")
        output = self.bootstrap()
        if "replica set ya configurado; no se modifica" not in output:
            raise RuntimeError(f"El segundo bootstrap no fue idempotente:\n{output}")
        print("RESTART_PRIMARY_OK=true")
        print("IDEMPOTENT_BOOTSTRAP_OK=true")

    def verify_standalone_rollback_read(self) -> None:
        """Comprueba el rollback aprobado sin tocar ningun volumen no temporal."""
        rollback_container = self.project + "-rollback"
        volume = self.project + "_mongo-data"
        if not rollback_container.startswith(PROJECT_PREFIX) or not volume.startswith(
            PROJECT_PREFIX
        ):
            raise RuntimeError("Se rechazo operar fuera de los recursos de la prueba")

        self.compose("stop", "mongo")
        try:
            execute(
                "docker",
                "run",
                "-d",
                "--name",
                rollback_container,
                "--memory",
                "384m",
                "-v",
                f"{volume}:/data/db",
                "mongo:8",
                "mongod",
                "--bind_ip_all",
                "--auth",
                env=self.environment,
            )
            for _ in range(90):
                result = execute(
                    "docker",
                    "exec",
                    rollback_container,
                    "mongosh",
                    "--host",
                    "127.0.0.1",
                    "--quiet",
                    "--username",
                    "root",
                    "--password",
                    PASSWORD,
                    "--authenticationDatabase",
                    "admin",
                    "--eval",
                    'quit(db.getSiblingDB("catalog").products.countDocuments({}) > 0 ? 0 : 1)',
                    env=self.environment,
                    check=False,
                )
                if result.returncode == 0:
                    print("STANDALONE_ROLLBACK_READ_OK=true")
                    break
                time.sleep(1)
            else:
                raise RuntimeError("El rollback standalone no pudo leer Catalog")
        finally:
            execute(
                "docker",
                "rm",
                "-f",
                rollback_container,
                env=self.environment,
                check=False,
            )

        self.compose("up", "-d", "mongo")
        self.bootstrap()

    def cleanup(self) -> None:
        self.compose("down", "--volumes", "--remove-orphans", check=False)


def main() -> None:
    project = PROJECT_PREFIX + uuid.uuid4().hex[:10]
    with tempfile.TemporaryDirectory(prefix=PROJECT_PREFIX) as temporary:
        keyfile = Path(temporary) / "mongo-keyfile"
        keyfile.write_text(
            base64.b64encode(secrets.token_bytes(756)).decode("ascii"),
            encoding="ascii",
        )
        keyfile.chmod(0o600)
        environment = os.environ.copy()
        environment.update(
            {
                "DB_PASSWORD": PASSWORD,
                "MONGO_CATALOG_RUNTIME_PASSWORD": CREDENTIALS["catalog-runtime"],
                "MONGO_CATALOG_MIGRATION_PASSWORD": CREDENTIALS["catalog-migration"],
                "MONGO_INVENTORY_RUNTIME_PASSWORD": CREDENTIALS["inventory-runtime"],
                "MONGO_INVENTORY_MIGRATION_PASSWORD": CREDENTIALS["inventory-migration"],
                "MONGO_KEYFILE_PATH": str(keyfile),
                "MONGO_REPLICA_HOST": "mongo:27017",
                "NEXUS_COMPOSE_ASSET_DIR": str(COMPOSE_DIR),
            }
        )
        verification = OperationalReplicaSet(project, environment)
        try:
            verification.prepare_legacy_standalone_volume()
            verification.compose("up", "-d", "mongo")
            print(verification.bootstrap())
            verification.verify_topology_and_roles()
            verification.verify_joint_load()
            verification.verify_backup_restore()
            verification.verify_restart_and_idempotency()
            verification.verify_standalone_rollback_read()
        finally:
            verification.cleanup()


if __name__ == "__main__":
    main()
