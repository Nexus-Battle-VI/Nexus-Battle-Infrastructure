# Desplegar los contextos de Sprint 3 (ADR-022)

Tournament (NestJS, 3010) y Chatbot (Python/FastAPI, 3011) entran en el nodo `app` con
este orden. **Cada paso tiene su comprobación, y no se pasa al siguiente sin ella.**

## Por qué este despliegue NO es un `terraform apply`

Sprint 2 desplegó con `apply`, que reemplazó el nodo `app` ([el runbook de Sprint
2](desplegar-contextos-sprint-2.md)). Hoy eso es más arriesgado que entonces, por tres
hechos comprobados el 2026-09-30:

1. **`aws_instance.node` no tiene `create_before_destroy`, y la IP privada es fija.**
   Terraform destruye el nodo `app` antes de crear el nuevo. Si la creación falla, el sitio
   queda caído hasta que alguien lo arregle.
2. **El `user_data` comprimido del nodo `app` está cerca del límite de 16 384 bytes** que
   EC2 aplica antes de base64. Una estimación (plantilla + `app.yml` + `Caddyfile`, con
   `gzip -9`) da **~15 200 bytes antes y ~15 800 después** de este cambio. La estimación no
   es el valor exacto. Si se pasa, el fallo llega **en la creación**, que es justo el punto
   del hecho 1.
3. **Hay deriva conocida en el nodo `data`.** Su `compose.yml` se actualizó por SSM (PR #156)
   y su `user_data` en el estado no. Un `apply` sin `-target` también lo reemplazaría.

Por eso se sigue el procedimiento de los despliegues del 2026-09-24 en adelante:
**sustituir `/opt/nexus/compose.yml` y `Caddyfile` en el nodo por los del repositorio, a un
SHA fijo y comprobado con SHA-256**, y levantar solo lo nuevo. La deriva entre el `user_data`
del estado y lo que corre en el nodo ya existía. Este despliegue no la agrava: el compose
del nodo vuelve a coincidir con el repositorio.

> **Antes de cualquier `apply` futuro que reemplace el nodo `app`**, hay que medir el
> `user_data` exacto (no la estimación). Por ejemplo, con un `output` temporal y local
> `length(base64gzip(...))` sobre `local.arranque["app"]`. Si se acerca a 16 384, la salida
> es la que ya anticipa el comentario de `infra/modules/compute/main.tf`: dejar de meter
> ficheros en el arranque.

## 0. Condiciones previas

| Condición | Comprobación |
| --- | --- |
| ADR-022 aceptado | Estado `Accepted` en el propio ADR |
| CI en verde en `main` de Tournament y Chatbot | `gh run list -R Nexus-Battle-VI/Nexus-Battle-<Servicio> --workflow CI --branch main --limit 1` |
| Imágenes descargables **sin credenciales** | Ver abajo. El nodo no tiene credenciales de registro y no debe tenerlas |
| Este PR de Infra integrado | El SHA que se despliega debe existir en el repositorio público |

```bash
for s in tournament chatbot; do
  t=$(curl -s "https://ghcr.io/token?scope=repository:nexus-battle-vi/nexus-battle-$s:pull" \
    | node -e 'let s="";process.stdin.on("data",d=>s+=d).on("end",()=>console.log(JSON.parse(s).token||""))')
  curl -s -o /dev/null -w "$s %{http_code}\n" -H "Authorization: Bearer $t" \
    -H "Accept: application/vnd.oci.image.index.v1+json" \
    "https://ghcr.io/v2/nexus-battle-vi/nexus-battle-$s/manifests/latest"
done
```

Debe responder `200` para las dos. **Control:** la misma consulta sobre un nombre
inexistente debe dar `401` o `404`. Si diera `200`, el comando no estaría comprobando nada.

## 1. Crear bases y usuarios en el nodo de datos

[`compose/init-postgres-sprint-3.sh`](../../compose/init-postgres-sprint-3.sh) es
idempotente y **no viaja en `user_data`**. Se ejecuta dentro del contenedor de PostgreSQL;
la contraseña la lee del entorno del contenedor, no del comando.

```bash
# Identificador del nodo sin fijarlo en ningún documento:
terraform -chdir=infra/envs/prod output -json nodes

pg=$(base64 -w0 compose/init-postgres-sprint-3.sh)
aws ssm send-command --profile nexus-battles --instance-ids <id-del-nodo-data> \
  --document-name AWS-RunShellScript \
  --parameters "commands=[\"set -eu\",\"echo $pg | base64 -d | docker exec -i \$(docker ps -qf name=postgres) bash -s\"]"
```

**Comprobación:** la salida lista `chatbot` y `tournament` con su dueño. Ejecutarlo dos veces
da la misma salida. **Control de aislamiento:** `tournament` no puede conectarse a la base
`chatbot` (debe fallar con `permission denied for database`).

## 2. Sustituir la composición y el Caddyfile en el nodo `app`

1. **Copias de seguridad** en el nodo:
   ```bash
   cp -p /opt/nexus/compose.yml /opt/nexus/compose.yml.bak-<fecha>-pre-sprint-3
   cp -p /opt/nexus/Caddyfile   /opt/nexus/Caddyfile.bak-<fecha>-pre-sprint-3
   ```
2. **Descargar a un SHA fijo** y comprobar el SHA-256 contra `git show <sha>:<fichero> | sha256sum`
   calculado en local:
   - `https://raw.githubusercontent.com/Nexus-Battle-VI/Nexus-Battle-Infrastructure/<sha>/compose/nodes/app.yml`
   - `https://raw.githubusercontent.com/Nexus-Battle-VI/Nexus-Battle-Infrastructure/<sha>/compose/Caddyfile`

   Si el hash no coincide, se aborta sin tocar nada.
3. **Diferencias esperadas**:
   ```bash
   diff /opt/nexus/compose.yml.bak-<fecha>-pre-sprint-3 /tmp/app.yml
   ```
   Solo deben aparecer los bloques `tournament`, `chatbot` y sus `*-migrate`. Cualquier otra
   diferencia es deriva y se investiga antes de seguir.
4. **El Caddyfile se escribe sobre el MISMO fichero** (`cat /tmp/Caddyfile > /opt/nexus/Caddyfile`),
   no con `mv`. Es un montaje de un solo fichero, y un fichero nuevo (otro inodo) no lo vería
   el contenedor.

   **Esto solo funciona si el contenedor ve AHORA el mismo inodo que el host, y eso no está
   garantizado.** Ocurrió en este despliegue (2026-10-01): un despliegue anterior había
   sustituido el fichero, y el proxy llevaba desde el 2026-09-27 sirviendo una versión antigua.
   `caddy reload` recargó esa versión y respondió «recargado» sin errores. **Lo detectó el
   control de internet del paso 4**: las rutas nuevas devolvían `200 text/html`. Comprobar
   antes de recargar:

   ```bash
   sha256sum /opt/nexus/Caddyfile
   docker exec nexus-battles-vi-proxy-1 sha256sum /etc/caddy/Caddyfile
   ```

   Si los hashes difieren, `caddy reload` no basta. Hay que volver a montar el fichero con
   `docker restart nexus-battles-vi-proxy-1`: el proxy volvió en ~1,4 s y conservó los
   certificados, que viven en su volumen. Antes, diferenciar lo servido frente a lo nuevo con
   `docker exec <proxy> cat /etc/caddy/Caddyfile`, para saber qué más entra con el reinicio.
5. **Composición**: `install -m 0644 /tmp/app.yml /opt/nexus/compose.yml`.

## 3. Levantar solo lo nuevo

```bash
cd /opt/nexus
docker compose pull tournament tournament-migrate chatbot chatbot-migrate
docker compose up -d tournament chatbot          # sus *-migrate corren antes por depends_on
docker compose exec proxy caddy reload --config /etc/caddy/Caddyfile
```

**Sin `depends_on` desde el proxy**, igual que los de Sprint 2: con
`service_completed_successfully`, una migración rota de Chatbot dejaría sin arrancar también
al proxy, y con él todo el sitio.

## 4. Comprobar

En el nodo `app`, por SSM:

```bash
docker compose ps tournament chatbot tournament-migrate chatbot-migrate
docker logs nexus-battles-vi-tournament-migrate-1 | tail -2
docker logs nexus-battles-vi-chatbot-migrate-1 | tail -2
for s in tournament:3010 chatbot:3011; do
  docker exec nexus-battles-vi-proxy-1 wget -qO- "http://$s/api/health/ready"; echo
done
docker stats --no-stream --format '{{.Name}} {{.MemUsage}}' | grep -E 'tournament|chatbot'
free -m
docker images --digests | grep -E 'nexus-battle-(tournament|chatbot)'
```

- Las dos readiness responden con `database` en `ok`.
- **El digest que corre coincide con el publicado** en GHCR. Un contenedor `healthy` no dice
  qué versión ejecuta.
- **Los servicios existentes no cambiaron**: 13 contenedores previos siguen con el mismo
  `Created` y `healthy`.
- Se anota en ADR-022 la RAM real de Chatbot. El andamiaje midió ~51 MiB en local.

Desde internet, sin credenciales:

```bash
for p in tournaments chatbot; do
  curl -s -o /dev/null -w "$p %{http_code} %{content_type}\n" \
    "https://nexus.simuladorupbbga.app/api/v1/$p/no-existe"
done
curl -s -o /dev/null -w "control %{http_code}\n" https://nexus.simuladorupbbga.app/api/v1/auctions
```

Debe dar `401` o `404` con `application/json`. Un `200` con `text/html` significa que la
ruta cayó en Web y Caddy no tiene la ruta. El control (`auctions`, `401`) confirma que lo
existente sigue respondiendo.

## Reversión

```bash
cd /opt/nexus
docker compose stop tournament chatbot && docker compose rm -f tournament chatbot tournament-migrate chatbot-migrate
cp -p compose.yml.bak-<fecha>-pre-sprint-3 compose.yml
cat Caddyfile.bak-<fecha>-pre-sprint-3 > Caddyfile && docker compose exec proxy caddy reload --config /etc/caddy/Caddyfile
```

Las bases `tournament` y `chatbot` pueden quedarse: están vacías y aisladas.
