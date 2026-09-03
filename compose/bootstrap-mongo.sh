#!/bin/bash
set -Eeuo pipefail

: "${MONGO_INITDB_ROOT_PASSWORD:?MONGO_INITDB_ROOT_PASSWORD es obligatoria}"
: "${MONGO_CATALOG_RUNTIME_PASSWORD:?MONGO_CATALOG_RUNTIME_PASSWORD es obligatoria}"
: "${MONGO_CATALOG_MIGRATION_PASSWORD:?MONGO_CATALOG_MIGRATION_PASSWORD es obligatoria}"
: "${MONGO_INVENTORY_RUNTIME_PASSWORD:?MONGO_INVENTORY_RUNTIME_PASSWORD es obligatoria}"
: "${MONGO_INVENTORY_MIGRATION_PASSWORD:?MONGO_INVENTORY_MIGRATION_PASSWORD es obligatoria}"

intento=0
while [ "$intento" -lt 90 ]; do
  if mongosh --host mongo --quiet \
      --username root \
      --password "$MONGO_INITDB_ROOT_PASSWORD" \
      --authenticationDatabase admin \
      --eval 'quit(db.adminCommand("ping").ok === 1 ? 0 : 1)' >/dev/null 2>&1; then
    exec mongosh --host mongo --quiet \
      --username root \
      --password "$MONGO_INITDB_ROOT_PASSWORD" \
      --authenticationDatabase admin \
      /opt/nexus/bootstrap-mongo.js
  fi

  intento=$((intento + 1))
  sleep 2
done

echo "bootstrap-mongo: MongoDB no acepto autenticacion en 180s" >&2
exit 1
