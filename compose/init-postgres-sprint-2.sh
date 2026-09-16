#!/usr/bin/env bash
# Bases y usuarios de PostgreSQL para los contextos de Sprint 2 (ADR-019):
# Missions, Auction y Wallet.
#
# POR QUE ES UN FICHERO APARTE Y NO UNAS LINEAS MAS EN `init-postgres.sh`.
# `init-postgres.sh` viaja dentro del `user_data` del nodo `data`, y cualquier
# cambio en ese contenido REEMPLAZA el nodo de datos al aplicar Terraform. Para
# nada: sobre un volumen ya inicializado los scripts de
# `docker-entrypoint-initdb.d` no vuelven a ejecutarse, asi que el cambio no
# crearia ninguna base. Este fichero no viaja en `user_data`.
#
# Se usa de dos formas, y por eso es IDEMPOTENTE:
#
#   1. Volumen vacio, composicion de referencia: se monta en
#      `docker-entrypoint-initdb.d` junto a `init-postgres.sh`.
#   2. Nodo `data` ya inicializado: se ejecuta dentro del contenedor con
#      `docker exec -i <postgres> bash -s`, como describe
#      `docs/runbooks/desplegar-contextos-sprint-2.md`.
#
# La contrasena NO esta aqui ni en el comando: sale de `DB_PASSWORD`, del
# entorno del propio contenedor, y `psql` la entrecomilla como literal.
set -euo pipefail

if [ -z "${DB_PASSWORD:-}" ]; then
  echo "init-postgres-sprint-2: DB_PASSWORD no esta definida. Se aborta." >&2
  exit 1
fi

psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" \
  -v clave="$DB_PASSWORD" <<'EOSQL'
SELECT format('CREATE USER %I WITH PASSWORD %L', servicio, :'clave')
FROM unnest(ARRAY['missions', 'auction', 'wallet']) AS servicio
WHERE NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = servicio)
\gexec

SELECT format('CREATE DATABASE %I OWNER %I', servicio, servicio)
FROM unnest(ARRAY['missions', 'auction', 'wallet']) AS servicio
WHERE NOT EXISTS (SELECT 1 FROM pg_database WHERE datname = servicio)
\gexec

-- Mismo criterio que `init-postgres.sh`: nadie mas puede crear objetos en la
-- base de otro servicio.
SELECT format('REVOKE ALL ON DATABASE %I FROM PUBLIC', servicio)
FROM unnest(ARRAY['missions', 'auction', 'wallet']) AS servicio
\gexec

-- La salida es la comprobacion: debe listar las tres bases con su dueno.
SELECT datname AS base, pg_get_userbyid(datdba) AS dueno
FROM pg_database
WHERE datname IN ('missions', 'auction', 'wallet')
ORDER BY datname;
EOSQL
