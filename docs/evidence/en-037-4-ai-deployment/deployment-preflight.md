# EN-037.4 (Management #573) — Preflight antes de cualquier despliegue real

Este documento es un CHECKLIST para quien ejecute el despliegue real en AWS
(no se ejecutó desde este entorno — ver `deployment-result.md`). Incluye un
hallazgo crítico que DEBE resolverse antes de correr `terraform plan`.

## ⚠️ Hallazgo crítico: drift en `infra/envs/prod/terraform.tfvars`

`infra/envs/prod/terraform.tfvars` (archivo real, local, `.gitignore`d —
**no es parte de este PR ni de ningún commit**, por lo que no puede
corregirse desde una Pull Request) fija:

```hcl
app = {
  instance_type = "t4g.small"
  ...
}
```

con un comentario que cita la justificación ORIGINAL de ADR-011 ("1340 MiB
necesarios de 2048"). Esto **ya no coincide con la topología real**: ADR-019
(2026-09-16) redimensionó `app` a `t4g.medium`, y `terraform.tfvars.example`
(el archivo de ejemplo versionado) ya refleja correctamente `t4g.medium`.

**Riesgo concreto:** si alguien ejecuta `terraform plan`/`apply` en
`infra/envs/prod` usando el `terraform.tfvars` real tal como está hoy,
Terraform propondrá (o aplicará) achicar o reemplazar la instancia `app`
de producción — exactamente el tipo de acción destructiva que el prompt
maestro de #573 prohíbe ejecutar sin autorización explícita.

**Acción requerida ANTES de cualquier `terraform plan` para EN-037.4 (o
cualquier otro cambio):**

1. Abrir `infra/envs/prod/terraform.tfvars` (local, no en Git).
2. Confirmar que `app.instance_type` sea `"t4g.medium"` (el valor
   REALMENTE desplegado, según ADR-019/ADR-022 y `terraform.tfvars.example`).
3. Corregirlo si no lo es.
4. Solo entonces correr `terraform plan` y revisar el diff completo —
   debe mostrar **cero cambios de instancia**, no un "no-op" casual.

**EN-037.4 no modifica Terraform** (no se necesitó: los workers son
contenedores Compose, no recursos de infraestructura nuevos) — este
hallazgo se documenta porque esta auditoría lo encontró al revisar el
estado real antes de proponer cualquier cambio, no porque esta Issue lo
cause o lo corrija.

## Checklist de preflight (antes de desplegar `combat-trainer`/`combat-evaluator`)

- [ ] Hallazgo de arriba resuelto (`terraform.tfvars` corregido y
      `terraform plan` muestra cero cambios de instancia).
- [ ] SHA de Combat confirmado: la imagen que se va a desplegar corresponde
      a un commit real y revisado (nunca "lo que esté en `latest`" sin
      verificar el tag `sha-<corto>`).
- [ ] Imágenes `nexus-battle-combat:sha-<corto>` y
      `nexus-battle-combat-trainer:sha-<corto>` existen en GHCR, con
      arquitectura `linux/arm64` presente en el manifest (`docker buildx
      imagetools inspect ghcr.io/.../nexus-battle-combat-trainer:sha-<corto>`).
- [ ] `COMBAT_SOURCE_COMMIT` en el `.env` generado por Terraform coincide
      EXACTAMENTE con el SHA de la imagen desplegada.
- [ ] Medición SSM real completada (`resource-measurements.md`, las cuatro
      filas "NO EJECUTADO" ya tienen números reales) — **sin esto, no
      desplegar los workers en el nodo real**, el prompt maestro de #573 lo
      exige explícitamente como condición de finalización.
- [ ] Backup/estado de MongoDB verificado (replica set `rs0` saludable,
      `rs.status()` sin miembros caídos) ANTES de aplicar las 5 migraciones
      nuevas de IA (`027`-`031`) si todavía no están aplicadas en producción
      — confirmar primero si ya lo están (Combat PR #91/#92/#93 ya
      mergeados implica que SÍ deberían estarlo si `combat-migrate` ya
      corrió desde esos merges).
- [ ] Espacio en EBS del nodo `app` verificado para las dos imágenes nuevas
      (`docker system df`) — la imagen `trainer` es sustancialmente más
      grande que `runtime` por PyTorch CPU.
- [ ] Plan de rollback leído y entendido (`docs/runbooks/en-037-4-despliegue-ia-combat.md`,
      sección Rollback) ANTES de arrancar, no después de un incidente.
- [ ] Orden de despliegue respetado (§15.3 del prompt maestro): nunca
      arrancar `combat-trainer` y `combat-evaluator` simultáneamente como
      primer experimento contra el nodo real.

## Recursos que este cambio NO afecta (confirmado por auditoría, no por suposición)

- Nodo `data` (Postgres/MongoDB): sin cambios de Terraform, sin cambios de
  Compose en `data.yml`.
- Seguridad de red: sin puertos nuevos, sin cambios en `infra/modules/network`.
- IAM: sin cambios en `infra/modules/iam` — los workers no necesitan
  permisos AWS nuevos (solo MongoDB, que ya alcanzan vía la red interna
  existente).
- GHCR: ninguna credencial nueva en el nodo — las imágenes se siguen
  descargando de forma anónima, igual que las 14 imágenes actuales.
