#!/usr/bin/env bash
# Inicializacion de PostgreSQL.
#
# Cada servicio recibe base de datos y credenciales propias, aunque el motor sea
# compartido. Es la traduccion literal de la regla de propiedad de datos: ningun
# servicio puede leer el esquema de otro, ni siquiera por accidente.
#
# Era un `.sql` y ahora es un `.sh` por una razon concreta: un `.sql` no puede
# leer una variable de entorno, asi que las contrasenas de los tres usuarios
# estaban escritas en el fichero como la palabra literal `cambiar`. En la
# composicion de desarrollo eso es correcto y esta declarado; en una instancia
# real significaba que `POSTGRES_PASSWORD` recibia la contrasena buena y los
# tres usuarios que de verdad usan los servicios se quedaban con una conocida.
#
# El entrypoint oficial de la imagen ejecuta tanto `.sql` como `.sh` desde
# `/docker-entrypoint-initdb.d`, y a los `.sh` les pasa el entorno del
# contenedor. De ahi sale ahora la contrasena.
#
# ATENCION: esto se ejecuta UNA sola vez, cuando el directorio de datos esta
# vacio. Sobre un volumen ya inicializado no vuelve a correr, y cambiar este
# fichero no cambia las contrasenas existentes.
set -euo pipefail

if [ -z "${DB_PASSWORD:-}" ]; then
  echo "init-postgres: DB_PASSWORD no esta definida. Se aborta la inicializacion." >&2
  exit 1
fi

# `psql -v` con `:'variable'` entrecomilla el valor como literal de SQL. Es lo
# que evita que una contrasena con una comilla rompa la sentencia, o algo peor.
psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" \
  -v clave="$DB_PASSWORD" <<'EOSQL'
CREATE USER account WITH PASSWORD :'clave';
CREATE DATABASE account OWNER account;

CREATE USER community WITH PASSWORD :'clave';
CREATE DATABASE community OWNER community;

CREATE USER commerce WITH PASSWORD :'clave';
CREATE DATABASE commerce OWNER commerce;

-- Se retira el permiso por defecto que permitiria a cualquier usuario crear
-- objetos en el esquema publico de las bases ajenas.
REVOKE ALL ON DATABASE account FROM PUBLIC;
REVOKE ALL ON DATABASE community FROM PUBLIC;
REVOKE ALL ON DATABASE commerce FROM PUBLIC;
EOSQL

echo "init-postgres: tres bases y tres usuarios creados."
