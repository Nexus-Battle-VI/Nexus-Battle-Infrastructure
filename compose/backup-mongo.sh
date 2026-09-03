#!/bin/bash
set -Eeuo pipefail

: "${DB_PASSWORD:?DB_PASSWORD es obligatoria}"

destino="${1:-}"
if [ -z "$destino" ]; then
  echo "Uso: $0 DIRECTORIO_NUEVO" >&2
  exit 2
fi
if [ -e "$destino" ]; then
  echo "El destino ya existe; no se sobrescribe: $destino" >&2
  exit 2
fi

compose_file="${NEXUS_COMPOSE_FILE:-/opt/nexus/compose.yml}"
project_directory="${NEXUS_PROJECT_DIRECTORY:-$(dirname "$compose_file")}"
compose=(docker compose --project-directory "$project_directory" -f "$compose_file")
mkdir -p "$destino"

"${compose[@]}" exec -T mongo mongodump \
  --host 127.0.0.1 \
  --username root \
  --password "$DB_PASSWORD" \
  --authenticationDatabase admin \
  --db catalog \
  --archive \
  --gzip > "$destino/catalog.archive.gz"

"${compose[@]}" exec -T mongo mongosh \
  --host 127.0.0.1 \
  --username root \
  --password "$DB_PASSWORD" \
  --authenticationDatabase admin \
  --quiet \
  --eval 'print(EJSON.stringify(rs.conf(), null, 2))' > "$destino/replica-set-config.json"

"${compose[@]}" exec -T mongo mongosh \
  --host 127.0.0.1 \
  --username root \
  --password "$DB_PASSWORD" \
  --authenticationDatabase admin \
  --quiet \
  --eval 'print(EJSON.stringify(db.getSiblingDB("catalog").getCollectionNames().sort()))' \
  > "$destino/catalog-collections.json"

(
  cd "$destino"
  sha256sum catalog.archive.gz replica-set-config.json catalog-collections.json > SHA256SUMS
)

echo "Backup creado en $destino"
echo "Incluye la base Catalog (products, audit_log y outbox cuando existan) y la configuracion del replica set."
