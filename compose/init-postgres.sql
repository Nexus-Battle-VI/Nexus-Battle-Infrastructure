-- Inicializacion de PostgreSQL para la composicion de referencia.
--
-- Cada servicio recibe base de datos y credenciales propias, aunque el motor
-- sea compartido. Es la traduccion literal de la regla de propiedad de datos:
-- ningun servicio puede leer el esquema de otro, ni siquiera por accidente.
--
-- Las contrasenas son de ejemplo. Deben sustituirse antes de cualquier uso
-- que no sea desarrollo local.

CREATE USER account WITH PASSWORD 'cambiar';
CREATE DATABASE account OWNER account;

CREATE USER community WITH PASSWORD 'cambiar';
CREATE DATABASE community OWNER community;

CREATE USER commerce WITH PASSWORD 'cambiar';
CREATE DATABASE commerce OWNER commerce;

-- Se retira el permiso por defecto que permitiria a cualquier usuario crear
-- objetos en el esquema publico de las bases ajenas.
REVOKE ALL ON DATABASE account FROM PUBLIC;
REVOKE ALL ON DATABASE community FROM PUBLIC;
REVOKE ALL ON DATABASE commerce FROM PUBLIC;
