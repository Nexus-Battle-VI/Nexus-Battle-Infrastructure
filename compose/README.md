# Composicion de referencia

Reproduce en una maquina de desarrollo la misma topologia que la arquitectura de demo.

## Uso

```bash
cp compose.example.yml compose.yml
# revisar y sustituir las credenciales de ejemplo
docker compose up -d
```

| Destino | URL |
| --- | --- |
| Aplicacion | http://localhost:8080 |
| Correos capturados | http://localhost:8025 |

## Que reproduce

```text
navegador -> Caddy :8080
               |
               +-- /                -> Web
               +-- /api/accounts    -> Account      :3000
               +-- /api/inventories -> Inventory    :3002
               +-- /api/products    -> Catalog      :3003
               +-- /api/threads     -> Community    :3004
               +-- /api/orders      -> Commerce     :3005

               Notifications worker (sin puerto publico)
               PostgreSQL + MongoDB con volumenes propios
               Mailpit para inspeccionar los correos
```

## Propiedad de datos, tambien aqui

`init-postgres.sql` crea **una base de datos y un usuario por servicio**. El motor es compartido; el esquema no.

Compartir host es una concesion de coste. Compartir esquema seria renunciar a la arquitectura, y por eso ni siquiera en la composicion de desarrollo se hace.

## Limitaciones

Este fichero **no es apto para produccion**:

- credenciales de ejemplo en claro;
- sin TLS;
- sin replica, copias de seguridad ni limites de recursos;
- **los servicios no verifican quien realiza la peticion** (ver [ADR-004](../docs/adr/ADR-004-identity-directory.md)).

Las imagenes referenciadas todavia **no se publican en GHCR**: CI las construye y verifica su arranque, pero publicarlas requiere decidir la politica de etiquetado y el destino de despliegue.

Para ejecutar con imagenes locales, se construyen antes en cada repositorio:

```bash
docker build -t ghcr.io/nexus-battle-vi/nexus-battle-account:latest ../../Nexus-Battle-Account
```
