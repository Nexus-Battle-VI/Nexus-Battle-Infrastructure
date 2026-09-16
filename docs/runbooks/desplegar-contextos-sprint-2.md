# Desplegar los contextos de Sprint 2 (ADR-019)

Combat, Missions, Auction y Wallet entran en el nodo `app` con este orden. **Cada paso
tiene su comprobación, y no se pasa al siguiente sin ella.** Aplicar la composición antes
de que existan las bases o las imágenes deja esos contenedores fallando en bucle; aplicar
el cambio de tipo de instancia sin revisar el `plan` reemplaza el nodo sin aviso.

## 0. Condiciones previas

| Condición | Comprobación |
| --- | --- |
| ADR-019 aceptado | Estado `Accepted` en el propio ADR, con evidencia |
| CI en verde en `main` de los cuatro repositorios | `gh run list -R Nexus-Battle-VI/Nexus-Battle-<Servicio> --branch main --limit 1` |
| Imagen publicada y **descargable sin credenciales** | Ver abajo. Un paquete nuevo de GHCR nace privado; el nodo no tiene credenciales de registro y no debe tenerlas |

```bash
for s in combat missions auction wallet; do
  t=$(curl -s "https://ghcr.io/token?scope=repository:nexus-battle-vi/nexus-battle-$s:pull&service=ghcr.io" | python -c "import sys,json; print(json.load(sys.stdin).get('token',''))")
  curl -s -o /dev/null -w "$s %{http_code}\n" -H "Authorization: Bearer $t" \
    -H "Accept: application/vnd.oci.image.index.v1+json" \
    "https://ghcr.io/v2/nexus-battle-vi/nexus-battle-$s/manifests/latest"
done
```

Debe responder `200` para los cuatro. Un `401` significa que el paquete sigue privado: se
cambia a público en *Package settings* de la organización.

## 1. Crear bases y usuarios en el nodo de datos existente

`init-postgres.sh` e `init-mongo.js` **solo se ejecutan sobre un volumen vacío** y además
viajan en el `user_data` del nodo `data`: tocarlos reemplaza ese nodo sin crear ninguna
base. Por eso las bases de Sprint 2 están en ficheros aparte e idempotentes,
[`compose/init-postgres-sprint-2.sh`](../../compose/init-postgres-sprint-2.sh) y
[`compose/init-mongo-sprint-2.js`](../../compose/init-mongo-sprint-2.js), que se ejecutan
dentro de cada contenedor. **La contraseña no aparece en ningún comando**: los scripts la
leen del entorno del contenedor.

Obtener el identificador del nodo sin fijarlo en ningún documento:

```bash
terraform -chdir=infra/envs/prod output -json nodes
```

Construir los parámetros de `ssm send-command` desde los ficheros del repositorio, para que
lo que se ejecuta sea exactamente lo revisado:

```bash
python - <<'PY' > "$TEMP/ssm-sprint-2.json"
import base64, json
pg = base64.b64encode(open('compose/init-postgres-sprint-2.sh', 'rb').read()).decode()
mg = base64.b64encode(open('compose/init-mongo-sprint-2.js', 'rb').read()).decode()
mongo = ("cat > /tmp/sprint2.js && mongosh --quiet -u \"$MONGO_INITDB_ROOT_USERNAME\" "
         "-p \"$MONGO_INITDB_ROOT_PASSWORD\" --authenticationDatabase admin /tmp/sprint2.js; "
         "rc=$?; rm -f /tmp/sprint2.js; exit $rc")
print(json.dumps({'commands': [
    'set -eu',
    f'echo {pg} | base64 -d | docker exec -i $(docker ps -qf name=postgres) bash -s',
    f"echo {mg} | base64 -d | docker exec -i $(docker ps -qf name=mongo) sh -c '{mongo}'",
]}))
PY
aws ssm send-command --profile nexus-battles --instance-ids <id-del-nodo-data>   --document-name AWS-RunShellScript --parameters "file://$TEMP/ssm-sprint-2.json"
```

**Comprobación**: la salida del propio comando lista `auction`, `missions` y `wallet` con su
dueño, y los roles `readWrite` y `dbAdmin` de `combat` sobre su base. Ejecutarlo dos veces
debe dar la misma salida sin errores. **El resultado es la comprobación; que el comando
termine sin error, no.**

## 2. Revisar el plan por nodo

Cambiar `compose/nodes/app.yml`, `compose/Caddyfile` o el tipo de instancia **reemplaza el
nodo `app`**. El nodo `data` no debe aparecer en el plan.

```bash
terraform -chdir=infra/envs/prod plan -out sprint2.plan
```

- `module.compute...["app"]`: reemplazo esperado.
- `module.compute...["data"]` y su `aws_volume_attachment`: **ningún cambio**. Si aparecen, se
  detiene aquí: algo cambió el `user_data` del nodo de datos.
- `aws_s3_bucket_cors_configuration`: sin cambios. Si quita orígenes, el último `apply` usó
  un `-var` que no está en `terraform.tfvars`; se añade ahí antes de seguir.
- La IP elástica `54.83.38.198` se conserva asociada.
- `terraform.tfvars` es local y está ignorado por git: el tipo `t4g.medium` se cambia ahí,
  no solo en el ejemplo. Terraform no recuerda las banderas `-var`.

## 3. Aplicar y comprobar

```bash
terraform -chdir=infra/envs/prod apply sprint2.plan
```

Comprobaciones en el nodo `app`, por SSM:

```bash
docker ps --format '{{.Names}} {{.Status}}' | grep -E 'combat|missions|auction|wallet'
for s in combat:3006 missions:3007 auction:3008 wallet:3009; do
  docker exec nexus-battles-vi-proxy-1 wget -qO- "http://$s/api/health/ready"; echo
done
free -m
```

Las cuatro readiness deben responder con su motor en `ok`. **Control**: un contenedor
`Up (healthy)` no dice qué versión corre; se compara el digest con el publicado.

Comprobación del enrutado desde internet, sin credenciales:

```bash
for p in combat missions auctions wallet; do
  curl -s -o /dev/null -w "$p %{http_code} %{content_type}\n" "https://nexus.simuladorupbbga.app/api/v1/$p/no-existe"
done
```

Debe responder `401` o `404` con `application/json`, que es NestJS. Un `200` con
`text/html` significa que la ruta cayó en Web y el enrutado no está aplicado.
