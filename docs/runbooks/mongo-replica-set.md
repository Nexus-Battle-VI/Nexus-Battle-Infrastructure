# Runbook — MongoDB replica set de la demo

Este procedimiento implementa [ADR-015](../adr/ADR-015-catalog-atomicity-audit-outbox.md)
y [Management #289](https://github.com/Nexus-Battle-VI/Nexus-Battle-Management/issues/289).
El replica set `rs0` tiene un solo miembro y habilita transacciones; **no ofrece
alta disponibilidad**.

## Precondiciones

- backup restaurable antes de cambiar un volumen existente;
- `DB_PASSWORD` de al menos 16 caracteres;
- cuatro credenciales Mongo de al menos 16 caracteres, distintas entre sí y de
  `db_password`;
- ventana aprobada para reemplazar el nodo, porque Terraform cambia `user_data`;
- imágenes de Catalog e Inventory compatibles con las nuevas URI.

Para la composición local se genera el keyfile fuera de Git:

```bash
openssl rand -base64 756 | tr -d '\n'
```

En AWS, cloud-init genera el keyfile directamente en el nodo `data`; no viaja
por Terraform ni queda en el estado. Las credenciales de usuarios sí se definen
en `mongo_credentials` dentro del `terraform.tfvars` ignorado y heredan la
exposición ya aceptada de `db_password` en estado/user_data. No deben enviarse
por chat ni registrarse.

Las contraseñas se generan con caracteres URI-safe porque se interpolan en
`MONGODB_URI`, por ejemplo:

```bash
openssl rand -base64 24 | tr -d '\n=' | tr '+/' '-_'
```

## Despliegue

1. detener escrituras de Catalog e Inventory;
2. crear un backup y copiarlo fuera del nodo de datos;
3. definir las cuatro `mongo_credentials` y revisar `terraform plan`;
4. aplicar primero el nodo `data`, verificar `mongo-bootstrap` y conservar los
   usuarios legados durante la ventana de rollback;
5. aplicar el nodo `app`, ejecutar migraciones y después procesos runtime;
6. comprobar salud y topología;
7. ejecutar la prueba conjunta antes de reabrir tráfico;
8. retirar las identidades legadas en otra ventana, cuando expire el rollback.

El bootstrap puede repetirse: si `rs0` ya existe con el miembro esperado, no lo
reconfigura. Si encuentra otro nombre, más miembros o un host diferente, falla
cerrado para impedir una reconfiguración accidental.

```bash
cd /opt/nexus
docker compose run --rm mongo-bootstrap
docker compose ps
docker compose exec -T mongo mongosh --host 127.0.0.1 --quiet \
  --username root --password "$DB_PASSWORD" --authenticationDatabase admin \
  --eval 'const s=rs.status(); printjson({set:s.set, members:s.members.length, primary:s.members.filter(m=>m.stateStr==="PRIMARY").length})'
```

La salida válida es `set: rs0`, `members: 1` y `primary: 1`. Un simple `ping`
no es evidencia suficiente.

## Identidades

| Identidad | Base | Capacidades |
| --- | --- | --- |
| `catalog-runtime` | `catalog` | datos de `products`; insert/read de `audit_log`; insert/read/update de `outbox` |
| `catalog-migration` | `catalog` | `readWrite` + `dbAdmin` para migraciones |
| `inventory-runtime` | `player-inventory` | `readWrite` |
| `inventory-migration` | `player-inventory` | `readWrite` + `dbAdmin` para migraciones |

Las cuatro identidades conservan bases y contraseñas separadas. Reutilizar el
valor permitiría a runtime autenticarse como migración y anularía la separación.

## Backup y restauración

El backup guarda toda la base privada `catalog` —incluidas `products`,
`audit_log` y `outbox` cuando existan—, la configuración de `rs0`, el inventario
de colecciones y checksums. El directorio destino debe ser nuevo.

```bash
cd /opt/nexus
sudo -E ./backup-mongo.sh /var/backups/nexus/catalog-$(date +%Y%m%dT%H%M%S)
```

Copiar después el directorio a almacenamiento externo al volumen. Un backup en
el mismo EBS no protege frente a la pérdida del nodo.

La restauración es destructiva para las colecciones presentes en el archivo y
exige un argumento explícito. Primero detener escrituras y conservar otro
backup.

```bash
cd /opt/nexus
sudo -E ./restore-mongo.sh /ruta/al/backup --confirmar-restauracion
```

El script verifica checksums y que el nombre del replica set coincida. No aplica
automáticamente `rs.reconfig()`: la configuración respaldada es evidencia para
una recuperación dirigida, no una orden que deba ejecutarse a ciegas.

## Pruebas y gates

```bash
python3 scripts/verificar-replica-set-operativo.py
bash scripts/verificar-backup-restore-mongo.sh
```

La primera prueba levanta recursos efímeros, verifica autenticación por keyfile,
PRIMARY, oplog de 128 MiB, separación de permisos, carga simultánea de Catalog e
Inventory, p95, memoria, OOM, reinicio, bootstrap idempotente y lectura durante
el rollback standalone. La segunda crea y restaura documentos en las tres
colecciones. Ambas eliminan únicamente contenedores y volúmenes con su prefijo
de prueba.

No promover si existe `OOM_KILLED=true`, no hay PRIMARY, el oplog no tiene 128
MiB, falla la restauración o alguna identidad runtime obtiene `dbAdmin`.

La ventana observada del oplog es una medida del workload ejecutado, no una
retención garantizada. Debe compararse con el tiempo operativo necesario para
detectar y diagnosticar incidentes.

## Rollback

1. detener escrituras y dispatcher;
2. conservar el backup previo y comprobar checksums;
3. detener MongoDB limpiamente;
4. restaurar las versiones compatibles de Compose, URI y aplicaciones;
5. si es imprescindible, arrancar el mismo volumen como standalone con
   autenticación y sin `--replSet`;
6. verificar lectura de Catalog antes de reabrir tráfico.

No se elimina el oplog ni las colecciones durante el rollback. Volver a
standalone deshabilita transacciones, por lo que Catalog no debe ejecutar la
escritura atómica de HU-33 en ese estado.
