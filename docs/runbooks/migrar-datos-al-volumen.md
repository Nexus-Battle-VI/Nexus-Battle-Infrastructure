# Migrar las bases al volumen de datos

> Procedimiento de EN-027.10 #298. Se ejecuta una sola vez, con parada acordada.
> Desbloquea EN-027.5 #289 y, con ella, la ruta crítica de HU-33.

## Por qué hace falta

Las dos bases viven hoy en el volumen **raíz** del nodo `data`, que se declara
con `delete_on_termination = true`. Y `compose/nodes/data.yml` viaja dentro de
`user_data`, que con `user_data_replace_on_change = true` reemplaza la instancia
en cuanto cambia.

La suma de las dos cosas: **cualquier edición de la composición del nodo de
datos, aplicada, borra todas las cuentas y todos los productos.** Comprobado en
la máquina, no deducido del código:

```
NAME          SIZE MOUNTPOINT
nvme0n1        20G
└─nvme0n1p1    20G /

/var/lib/docker/volumes/nexus-battles-vi-data_mongo-data/_data
```

Un solo volumen, montado en `/`, con los volúmenes de Docker dentro.

## El orden importa, y por qué

El montaje del volumen vive detrás de `mount_data_volume`, apagada por defecto.
Con la bandera apagada, la plantilla **no emite ni una línea** sobre el volumen,
así que el arranque renderizado es idéntico al de antes y Terraform no propone
reemplazo.

Comprobado renderizando la plantilla con `terraform console` en los dos estados:
con la bandera apagada el resultado es byte a byte el mismo que el de la versión
anterior; con la bandera encendida difiere. Eso es lo que hace seguro el paso 1.

## Paso 1 — Crear y adjuntar el volumen, sin tocar el nodo

```bash
terraform -chdir=infra/envs/prod plan
```

El plan debe decir **`1 to add`** para `aws_ebs_volume.datos`, **`1 to add`**
para `aws_volume_attachment.datos`, y **ninguna instancia reemplazada**. Si
aparece `aws_instance.node["data"]` como `must be replaced`, **parar aquí**: algo
más cambió el arranque y aplicarlo destruiría los datos.

```bash
terraform -chdir=infra/envs/prod apply
```

Comprobar en la máquina que el dispositivo está:

```bash
lsblk -o NAME,SIZE,MOUNTPOINT
```

Deben verse dos discos. El nuevo aparece sin punto de montaje.

## Paso 2 — Migrar los datos, con el sistema parado

Este es el paso peligroso. No es el de Terraform.

```bash
# 1. Recuento ANTES. Sin esto no hay forma de saber si la copia salió bien.
docker exec nexus-battles-vi-data-postgres-1 \
  psql -U nexus -d nexus -tAc 'select count(*) from account_roles'
docker exec nexus-battles-vi-data-mongo-1 \
  mongosh --quiet -u root -p "$DB_PASSWORD" --authenticationDatabase admin \
  --eval 'db.getSiblingDB("catalog").products.countDocuments()'

# 2. Parar. Con las bases escribiendo, la copia queda inconsistente.
cd /opt/nexus && docker compose down

# 3. Preparar el volumen nuevo. `blkid` decide: NUNCA formatear "por si acaso".
DISCO=/dev/nvme1n1
blkid "$DISCO" || mkfs.xfs "$DISCO"
mkdir -p /mnt/datos-nuevo
mount "$DISCO" /mnt/datos-nuevo

# 4. Copiar preservando dueños y permisos. Sin `-a`, PostgreSQL no arranca.
cp -a /var/lib/docker/volumes/. /mnt/datos-nuevo/

# 5. Comparar tamaños antes de destruir nada.
du -sb /var/lib/docker/volumes /mnt/datos-nuevo

# 6. Montar en su sitio definitivo.
umount /mnt/datos-nuevo
mv /var/lib/docker/volumes /var/lib/docker/volumes.anterior
mkdir -p /var/lib/docker/volumes
UUID=$(blkid -s UUID -o value "$DISCO")
echo "UUID=$UUID /var/lib/docker/volumes xfs defaults,nofail 0 2" >> /etc/fstab
mount /var/lib/docker/volumes

# 7. Arrancar y volver a contar. Los números deben coincidir con el paso 1.
docker compose up -d
```

**No borrar `/var/lib/docker/volumes.anterior`** hasta que los recuentos
coincidan y el sistema lleve un tiempo funcionando. Es la única vuelta atrás.

## Paso 3 — Incorporar el montaje al arranque

Solo cuando el paso 2 esté verificado:

```hcl
mount_data_volume = true
```

```bash
terraform -chdir=infra/envs/prod plan
```

Ahora **sí** debe aparecer `aws_instance.node["data"]` como `must be replaced`, y
eso ya es seguro: los datos están en un volumen que no se destruye con la
instancia. El volumen lleva `prevent_destroy`, así que Terraform se negaría a
retirarlo aunque alguien lo intentara.

## Condición de finalización

Reemplazar el nodo a propósito y comprobar que las bases vuelven **con sus
datos**:

```bash
terraform -chdir=infra/envs/prod apply -replace='module.compute.aws_instance.node["data"]'
```

Y repetir los dos recuentos del paso 2. Si coinciden, la Task está hecha. Si no
se hace este ensayo, nadie sabe si el volumen sobrevive de verdad: se sabrá el
día que haga falta, que es el peor momento para averiguarlo.
