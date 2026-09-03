#!/bin/bash
set -Eeuo pipefail

: "${DB_PASSWORD:?DB_PASSWORD es obligatoria}"

origen="${1:-}"
confirmacion="${2:-}"
if [ -z "$origen" ] || [ "$confirmacion" != "--confirmar-restauracion" ]; then
  echo "Uso: $0 DIRECTORIO_BACKUP --confirmar-restauracion" >&2
  exit 2
fi
for file in catalog.archive.gz replica-set-config.json catalog-collections.json SHA256SUMS; do
  if [ ! -f "$origen/$file" ]; then
    echo "Falta $origen/$file" >&2
    exit 2
  fi
done

(
  cd "$origen"
  sha256sum --check SHA256SUMS
)

compose_file="${NEXUS_COMPOSE_FILE:-/opt/nexus/compose.yml}"
project_directory="${NEXUS_PROJECT_DIRECTORY:-$(dirname "$compose_file")}"
compose=(docker compose --project-directory "$project_directory" -f "$compose_file")
actual_replica_set=$("${compose[@]}" exec -T mongo mongosh \
  --host 127.0.0.1 \
  --username root \
  --password "$DB_PASSWORD" \
  --authenticationDatabase admin \
  --quiet \
  --eval 'print(rs.conf()._id)')

backup_replica_set=$(sed -n 's/.*"_id"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' \
  "$origen/replica-set-config.json" | head -n 1)
if [ -z "$backup_replica_set" ] || [ "$actual_replica_set" != "$backup_replica_set" ]; then
  echo "Replica set incompatible: actual=$actual_replica_set backup=$backup_replica_set" >&2
  exit 1
fi

"${compose[@]}" exec -T mongo mongorestore \
  --host 127.0.0.1 \
  --username root \
  --password "$DB_PASSWORD" \
  --authenticationDatabase admin \
  --drop \
  --archive \
  --gzip < "$origen/catalog.archive.gz"

"${compose[@]}" exec -T mongo mongosh \
  --host 127.0.0.1 \
  --username root \
  --password "$DB_PASSWORD" \
  --authenticationDatabase admin \
  --quiet \
  --eval 'print("RESTORE_OK=" + EJSON.stringify({replicaSet: rs.conf()._id, collections: db.getSiblingDB("catalog").getCollectionNames().sort()}))'

echo "La configuracion se verifico, no se reconfiguro automaticamente."
