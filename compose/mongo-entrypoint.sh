#!/bin/bash
set -Eeuo pipefail

# Docker Compose monta los secretos basados en fichero sin garantizar el
# propietario que exige MongoDB. La copia privada permite aplicar 0400 y evita
# que mongod lea directamente un bind mount con permisos demasiado amplios.
install -d -m 0700 -o mongodb -g mongodb /data/configdb/nexus
install -m 0400 -o mongodb -g mongodb /run/secrets/mongo-keyfile /data/configdb/nexus/keyfile

exec /usr/local/bin/docker-entrypoint.sh "$@"
