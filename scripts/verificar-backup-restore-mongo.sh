#!/bin/bash
set -Eeuo pipefail

root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
project="nb-en0275-backup-$(date +%s)-$RANDOM"
temporary=$(mktemp -d)
export DB_PASSWORD='Validacion-EN0275-2026!'
export MONGO_CATALOG_RUNTIME_PASSWORD='Catalog-Runtime-EN0275x'
export MONGO_CATALOG_MIGRATION_PASSWORD='Catalog-Migration-EN0275x'
export MONGO_INVENTORY_RUNTIME_PASSWORD='Inventory-Runtime-EN0275x'
export MONGO_INVENTORY_MIGRATION_PASSWORD='Inventory-Migration-EN0275x'
export MONGO_KEYFILE_PATH="$temporary/mongo-keyfile"
export MONGO_REPLICA_HOST='mongo:27017'
export NEXUS_COMPOSE_ASSET_DIR="$root/compose"
export COMPOSE_PROJECT_NAME="$project"
export NEXUS_COMPOSE_FILE="$root/compose/nodes/data.yml"
export NEXUS_PROJECT_DIRECTORY="$root/compose"

cleanup() {
  docker compose --project-directory "$root/compose" \
    -f "$root/compose/nodes/data.yml" down --volumes --remove-orphans >/dev/null 2>&1 || true
  rm -rf -- "$temporary"
}
trap cleanup EXIT

openssl rand -base64 756 | tr -d '\n' > "$MONGO_KEYFILE_PATH"
chmod 0600 "$MONGO_KEYFILE_PATH"

compose=(docker compose --project-directory "$root/compose" -f "$root/compose/nodes/data.yml")
"${compose[@]}" up -d mongo
"${compose[@]}" run --rm mongo-bootstrap

"${compose[@]}" exec -T mongo mongosh --host 127.0.0.1 --quiet \
  --username root --password "$DB_PASSWORD" --authenticationDatabase admin --eval '
const catalog=db.getSiblingDB("catalog");
catalog.products.insertOne({_id:"backup-product",version:0});
catalog.audit_log.insertOne({_id:"backup-audit",productId:"backup-product"});
catalog.outbox.insertOne({_id:"backup-outbox",productId:"backup-product",status:"PENDING"});
'

bash "$root/compose/backup-mongo.sh" "$temporary/backup"

for collection in products audit_log outbox; do
  if ! grep -q "\"$collection\"" "$temporary/backup/catalog-collections.json"; then
    echo "El backup no registro la coleccion obligatoria $collection" >&2
    exit 1
  fi
done

"${compose[@]}" exec -T mongo mongosh --host 127.0.0.1 --quiet \
  --username root --password "$DB_PASSWORD" --authenticationDatabase admin \
  --eval 'db.getSiblingDB("catalog").dropDatabase()'

bash "$root/compose/restore-mongo.sh" "$temporary/backup" --confirmar-restauracion

counts=$("${compose[@]}" exec -T mongo mongosh --host 127.0.0.1 --quiet \
  --username root --password "$DB_PASSWORD" --authenticationDatabase admin --eval '
const catalog=db.getSiblingDB("catalog");
print(["products","audit_log","outbox"].map(name=>catalog[name].countDocuments({})).join(","));
')
if [ "$counts" != "1,1,1" ]; then
  echo "Restauracion incompleta: $counts" >&2
  exit 1
fi

echo "BACKUP_RESTORE_OK=products:1,audit_log:1,outbox:1,replicaSet:rs0"
