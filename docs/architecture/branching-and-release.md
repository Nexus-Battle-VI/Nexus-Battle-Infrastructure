# Ramas y publicación

## Estrategia

*Trunk-based* liviano. **`main` es la única rama permanente** en los ocho repositorios de código.

```text
main  ─────●──────────●──────────●──────────●────>
            \        /            \        /
             ●──────●              ●──────●
        feat/hu-33-...        fix/bug-12-...
```

Cada cambio vive en una rama de corta duración, se integra por *squash* y la rama se elimina automáticamente.

## Lo que no existe, y por qué

| Rama | Por qué no |
| --- | --- |
| `develop` | Añade un punto de integración intermedio que retrasa la detección de conflictos sin aportar aislamiento real |
| `qa`, `staging` | Confunden entorno con rama. Un entorno es dónde se despliega un artefacto, no de qué rama salió |
| `release/*` | Con integración continua y `main` siempre desplegable, una rama de publicación solo sirve para retener cambios |

**`dev`, `test` y `prod` son entornos de despliegue, no ramas.** El mismo artefacto de `main` se promueve entre ellos.

## Nomenclatura

```text
feat/     funcionalidad nueva
fix/      correccion de defecto
chore/    mantenimiento
ci/       cambios en el pipeline
docs/     documentacion
test/     pruebas
refactor/ reestructuracion sin cambio de comportamiento
build/    empaquetado y dependencias
```

Ejemplos reales del proyecto:

```text
feat/hu-33-crear-producto
fix/bug-12-correo-duplicado
chore/bootstrap-sprint1-foundation
```

**No se define un ruleset de nomenclatura de ramas.** Es deliberado: una regla estricta rompería las ramas que crea Dependabot (`dependabot/npm_and_yarn/...`) y las de otros automatismos. La convención se sostiene por `CONTRIBUTING.md` y por la revisión, no por un bloqueo que produciría más fricción que beneficio.

## Integración

**Solo *squash*.** Las otras dos estrategias están deshabilitadas en los ocho repositorios:

| Estrategia | Estado | Motivo |
| --- | --- | --- |
| Squash | **Habilitada** | Un cambio, un commit en `main`. Historial lineal y legible |
| Merge commit | Deshabilitada | Introduce ramificaciones que dificultan `git bisect` |
| Rebase | Deshabilitada | Reescribe el historial de forma menos predecible para el equipo |

Configuración asociada:

| Ajuste | Valor |
| --- | --- |
| Título del commit de squash | `PR_TITLE` |
| Cuerpo del commit de squash | `BLANK` |
| Eliminar rama tras integrar | Sí |
| Sugerir actualizar la rama | Sí |
| Auto-merge | No |

El cuerpo queda en blanco de forma deliberada: la plantilla de Pull Request incluye la Definition of Done completa, y volcarla en cada commit produciría un historial ilegible. La trazabilidad la aporta `[HU-NN]` en el título, más el enlace permanente al Pull Request desde la Issue central.

## Protección de `main`

Mediante ruleset `main-protection`. Plantilla en [../governance/rulesets/main-protection.template.json](../governance/rulesets/main-protection.template.json).

| Regla | Efecto |
| --- | --- |
| `deletion` | `main` no puede eliminarse |
| `non_fast_forward` | No se admite forzar la subida |
| `required_linear_history` | Historial lineal, coherente con squash |
| `pull_request` | Revisión obligatoria, 1 aprobación, **Code Owner requerido**, hilos resueltos, aprobaciones descartadas al subir cambios |
| `required_status_checks` | Los checks reales del repositorio deben estar verdes |

Los rulesets se crean **después** del primer CI real, para poder referenciar contextos de check que existen. Un ruleset con un nombre de check inventado bloquea todas las integraciones de forma permanente.

## Versionado

Semantic Versioning. Todos los repositorios están hoy en `0.1.0`: la superficie pública todavía puede cambiar sin aviso.

La versión se expone en tiempo de ejecución en `/version`, lo que permite confirmar qué está desplegado sin consultar el registro de imágenes.

## Publicación de imágenes

**GHCR**, no ECR. Está incluido en el plan de la organización, mientras que ECR cobra almacenamiento y transferencia. Ver [ADR-007](../adr/ADR-007-aws-cost-optimized-platform.md).

La infraestructura ya está aprobada y aplicada, y el destino de despliegue existe: el nodo `app` de [ADR-011](../adr/ADR-011-deployment-topology.md). Con eso, la política de etiquetado queda decidida así:

| Etiqueta | Responde a |
| --- | --- |
| `latest` | lo que la composición de referencia trae por defecto |
| `sha-<12>` | de qué commit exacto salió esa imagen |
| `<semver>` | qué versión declara el paquete, la misma que sirve `/version` |

Publica el job `publish`, **solo desde `main`** y nunca desde un pull request, con `packages: write` concedido en el propio job y no en la cabecera del workflow. Surte efecto cuando entran los siete PR que lo añaden.

## Inmutabilidad de las publicaciones

El ajuste **Release immutability** no está expuesto en la API REST de GitHub. Se ha verificado: la clave no existe en el objeto del repositorio y un `PATCH` explícito se ignora.

Queda como **paso manual pendiente** en la interfaz de cada repositorio, y así se reporta.
