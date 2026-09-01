# Diseño: integración y sincronización multirrepositorio de `main` y `develop`

Fecha: 2026-08-31

## Objetivo

Integrar en `main` todo el trabajo funcional que exista únicamente en `develop` para Infrastructure, Notifications, Web, Commerce y Catalog. Después, hacer que `main` y `develop` apunten al mismo SHA remoto en cada repositorio, sin perder una referencia recuperable al estado anterior de `develop`.

Esta fase termina en GitHub y en la publicación automática de artefactos GHCR. No ejecuta Terraform, SSM, migraciones sobre producción ni cambios en AWS; el despliegue será un proyecto posterior.

## Estado remoto auditado

| Repositorio | `main` | `develop` | Divergencia `main...develop` | Decisión |
| --- | --- | --- | ---: | --- |
| Infrastructure | `ddf2d6d` | `61a0e31` | 3 / 0 | `main` ya contiene todo |
| Notifications | `5f0ec86` | `da4419f` | 0 / 1 | integrar HU-04 en `main` |
| Web | `16e1299` | `338f6c1` | 14 / 24 | integrar semánticamente HU-05.4 sobre HU-04 |
| Commerce | `497e009` | `773968b` | 0 / 1 | integrar HU-56 en `main` |
| Catalog | `be0d70f` | `c20c2ef` | 3 / 0 | `main` ya contiene todo |

Los SHA se consideran una fotografía de diseño. La ejecución debe consultarlos nuevamente y detenerse si existe deriva concurrente.

## Estrategia elegida

La integración se realiza primero mediante PR hacia `main`. Solo cuando el contenido único de `develop` esté preservado en `main`, se crea un respaldo remoto de `develop` y se refleja `develop` al SHA final de `main`.

No se utilizará un merge bidireccional como mecanismo de sincronización. Los rulesets permiten únicamente squash en PR; por ello, un PR inverso puede igualar contenido, pero no SHA. La igualdad exacta requiere suspender temporalmente y restaurar el ruleset de `develop` durante el movimiento final de la referencia.

## Tratamiento por repositorio

### Infrastructure

`develop` es ancestro de `main` y no tiene contenido exclusivo. La ejecución validará el CI verde de `main`, creará `archive/develop-before-sync-2026-08-31` en el SHA antiguo y avanzará `develop` directamente al SHA de `main` durante la ventana controlada del ruleset.

### Notifications

El único commit exclusivo de `develop` es `da4419f`, HU-04: plantillas de recuperación, SMTP con autenticación y ampliación del health check. Se abrirá un PR `develop → main`, se esperarán las comprobaciones y la revisión requeridas, y se fusionará mediante el método permitido. Después se respaldará el antiguo `develop` y se reflejará al nuevo SHA de `main`.

### Commerce

El único commit exclusivo de `develop` es `773968b`, HU-56: lista de deseos y marca de adquirido, incluida la migración `002-wishlist`. Se abrirá un PR `develop → main`, se validarán pruebas unitarias, integración, PostgreSQL y construcción de imagen, y se fusionará mediante el método permitido. Después se respaldará y reflejará `develop`.

### Catalog

`develop` es ancestro de `main`; HU-33.2, HU-33.3 y HU-33.4 ya están en `main`. No se crea un PR de código. Se valida `main`, se respalda el `develop` anterior y se avanza al SHA exacto de `main`.

### Web

No se fusionará toda la historia divergente a ciegas. La auditoría demostró:

- El árbol de `3a67f09` en `develop` es idéntico al árbol de `efd08b2` en `main`.
- El árbol posterior a HU-03, `0082cff` en `develop`, es idéntico al árbol de `860a1d4` en `main`.
- Por tanto, la diferencia funcional nueva de `develop` después del último punto equivalente es HU-05.4 en `338f6c1`.
- `main` añade después HU-04 en `16e1299`, que debe conservarse.

Se creará una rama de integración desde `main` y se aplicará únicamente el cambio de HU-05.4. Los 18 conflictos detectados pertenecen al merge histórico completo que se descartó; la simulación de tres vías del cambio único sobre HU-04 termina sin conflictos. Si una nueva prevalidación deja de aplicar limpiamente, se detendrá la ejecución para reauditar en lugar de elegir globalmente `ours` o `theirs`.

La rama resultante deberá superar formato, lint, tipos, build, suite completa y construcción Docker antes del PR hacia `main`. Tras el merge y la publicación GHCR, se respaldará y reflejará `develop` al SHA final de `main`.

## Protecciones de GitHub

Los rulesets de `main` permanecen activos en todo momento. Los PR deben cumplir revisiones, CODEOWNERS, resolución de conversaciones y comprobaciones requeridas.

Para cada movimiento final de `develop`:

1. Consultar y guardar la configuración actual de su ruleset.
2. Verificar los SHA esperados de `main` y `develop`.
3. Comprobar que no existe una rama de respaldo con el nombre previsto.
4. Crear y verificar la rama remota de respaldo.
5. Suspender únicamente el ruleset de `develop`.
6. Actualizar `develop` con un lease explícito contra su SHA auditado.
7. Restaurar el ruleset en un bloque de cierre aunque falle una verificación posterior.
8. Confirmar desde GitHub que `main` y `develop` comparten SHA y árbol, y que el respaldo conserva el SHA anterior.

Si el lease falla, si cambian los SHA, si el respaldo ya existe con otro objetivo o si el ruleset no puede restaurarse, el repositorio se detiene y no se continúa con el siguiente.

## Validaciones

- Todos los proyectos Node usan `fnm use 24.14.0` antes de instalaciones o scripts.
- Notifications: instalación reproducible, formato, lint, tipos, build, pruebas y Docker.
- Commerce: los controles anteriores más la suite PostgreSQL/Testcontainers y verificación de la migración sobre una base desechable.
- Web: instalación reproducible, formato, lint, tipos, build, suite completa y Docker.
- Infrastructure: `terraform fmt -check`, `terraform init -backend=false`, `terraform validate` y validadores documentales del CI; no se ejecuta `plan` ni `apply` en esta fase.
- Catalog: comprobar el CI exitoso del SHA vigente de `main` y que la sincronización no cambie su árbol.
- En todos los repositorios, revisar los jobs remotos requeridos antes de fusionar o mover referencias.

## Publicación y límite de despliegue

Los workflows de Notifications, Web, Commerce y Catalog publican imágenes GHCR únicamente tras un push a `main`. Esa publicación forma parte de esta fase y debe verificarse por job y SHA. Una imagen publicada no se considera desplegada en producción.

Quedan expresamente fuera de esta fase:

- `terraform apply` o cambios de estado de Terraform.
- Comandos SSM sobre instancias.
- Migraciones contra bases de producción.
- Reinicio o reemplazo de contenedores en AWS.
- Pruebas mutantes contra datos productivos.

## Exclusiones

Los PR abiertos de Dependabot no forman parte de la integración porque no proceden de `develop`. Tampoco se modifican Account, Community, Player Inventory ni Management en esta fase.

## Criterios de aceptación

- Notifications, Web y Commerce tienen en `main` el trabajo nuevo auditado de `develop`.
- Los PR de integración están fusionados con todos los controles requeridos en verde.
- Los jobs de publicación GHCR ejecutados por los nuevos pushes a `main` terminan correctamente.
- Infrastructure, Notifications, Web, Commerce y Catalog terminan con `main` y `develop` en el mismo SHA y árbol.
- Cada antiguo `develop` está conservado en una rama remota de respaldo verificada.
- Todos los rulesets quedan activos con su configuración original.
- No se ejecuta ninguna mutación en AWS ni en datos productivos.
