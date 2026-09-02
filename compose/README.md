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
               +-- /api/sessions    -> Account      :3000
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

La politica de publicacion **ya esta decidida**: cada integracion en `main` publica en GHCR con tres etiquetas —`latest`, `sha-<12>` y la version de `package.json`—. Surte efecto cuando entran los siete PR que anaden el job `publish` a cada repositorio de servicio. Hasta entonces, `ghcr.io/nexus-battle-vi/...` no existe y hay que construir en local.

## Composiciones por nodo

`nodes/app.yml` y `nodes/data.yml` son la particion de este mismo fichero segun la topologia T2 de [ADR-011](../docs/adr/ADR-011-deployment-topology.md). Las escribe Terraform en cada instancia por `user_data`, y el CI las valida con el mismo `docker compose config` que valida esta.

La diferencia estructural con este fichero no es cosmetica: aqui las migraciones esperan a `postgres` con `service_healthy` porque el motor esta al lado; en `nodes/app.yml` el motor esta en otra maquina, asi que esa espera no puede existir.

Para ejecutar con imagenes locales, se construyen antes en cada repositorio:

```bash
docker build -t ghcr.io/nexus-battle-vi/nexus-battle-account:latest ../../Nexus-Battle-Account
```

## Orden de despliegue del contrato interno MFA

Las mutaciones administrativas de Catalog fallan cerradas cuando no pueden
comprobar en Account una evidencia `AUTHENTICATOR_APP`. Por eso el orden es
parte del contrato operativo:

1. publicar primero imágenes compatibles de Account y Catalog;
2. definir `internal_service_auth_secret` en el `terraform.tfvars` real con el
   mismo valor para ambos servicios;
3. revisar `terraform plan`, teniendo presente que el cambio de `user_data`
   reemplaza el nodo de aplicaciones;
4. ejecutar el `apply` únicamente en una ventana aprobada;
5. comprobar `201`, `403` y `503` mediante el recorrido integrado.

Este repositorio no incluye el valor del secreto. Si queda vacío o difiere,
Account no abre el endpoint: responde `503`, y Catalog no ejecuta la escritura.
Aplicar Infrastructure antes de publicar las imágenes compatibles puede dejar
el catálogo temporalmente inadministrable, aunque nunca permisivo.
