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

`init-postgres.sh` e `init-mongo.js` **solo se ejecutan sobre un volumen vacío**. El nodo
de datos ya está inicializado, así que las bases nuevas se crean aparte. Los comandos son
idempotentes y **no contienen la contraseña**: la leen del entorno de cada contenedor.

Obtener el identificador del nodo sin fijarlo en ningún documento:

```bash
terraform -chdir=infra/envs/prod output -json nodes
```

Parámetros de `ssm send-command` (`AWS-RunShellScript`) contra el nodo `data`:

```json
{
  "commands": [
    "set -eu",
    "p=$(docker ps -qf name=postgres)",
    "docker exec -i $p sh -c 'psql -v ON_ERROR_STOP=1 -U \"$POSTGRES_USER\" -d \"$POSTGRES_DB\" -v clave=\"$DB_PASSWORD\"' <<'EOSQL'\nSELECT format('CREATE USER %I WITH PASSWORD %L', u, :'clave') FROM unnest(ARRAY['missions','auction','wallet']) AS u WHERE NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = u)\\gexec\nSELECT format('CREATE DATABASE %I OWNER %I', u, u) FROM unnest(ARRAY['missions','auction','wallet']) AS u WHERE NOT EXISTS (SELECT 1 FROM pg_database WHERE datname = u)\\gexec\nSELECT format('REVOKE ALL ON DATABASE %I FROM PUBLIC', u) FROM unnest(ARRAY['missions','auction','wallet']) AS u\\gexec\nEOSQL",
    "m=$(docker ps -qf name=mongo)",
    "docker exec $m sh -c 'mongosh --quiet -u root -p \"$DB_PASSWORD\" --authenticationDatabase admin --eval \"const d = db.getSiblingDB(\\\"combat\\\"); if (d.getUser(\\\"combat\\\") === null) { d.createUser({ user: \\\"combat\\\", pwd: process.env.DB_PASSWORD, roles: [{ role: \\\"readWrite\\\", db: \\\"combat\\\" }, { role: \\\"dbAdmin\\\", db: \\\"combat\\\" }] }) } print(JSON.stringify(d.getUser(\\\"combat\\\").roles))\"'"
  ]
}
```

**Comprobación**, en el mismo nodo:

```bash
docker exec $(docker ps -qf name=postgres) sh -c 'psql -U "$POSTGRES_USER" -At -c "select datname from pg_database where datname in (\$\$missions\$\$,\$\$auction\$\$,\$\$wallet\$\$) order by 1"'
```

Debe listar las tres bases. Para MongoDB, la salida del propio comando imprime los dos
roles de `combat` acotados a su base. **El resultado es la comprobación; que el comando
termine sin error, no.**

## 2. Revisar el plan por nodo

Cambiar `compose/nodes/app.yml`, `compose/Caddyfile` o el tipo de instancia **reemplaza el
nodo `app`**. El nodo `data` no debe aparecer en el plan.

```bash
terraform -chdir=infra/envs/prod plan -out sprint2.plan
```

- `module.compute...["app"]`: reemplazo esperado.
- `module.compute...["data"]`: **ningún cambio**. Si aparece, se detiene aquí.
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
