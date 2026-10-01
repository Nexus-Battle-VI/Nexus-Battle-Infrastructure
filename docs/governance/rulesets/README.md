# Rulesets de protección de `main`

## Qué protege

| Regla | Efecto |
| --- | --- |
| `deletion` | `main` no puede eliminarse |
| `non_fast_forward` | No se admite forzar la subida |
| `required_linear_history` | Historial lineal, coherente con la integración por *squash* |
| `pull_request` | Revisión obligatoria: 1 aprobación, **Code Owner requerido**, hilos resueltos, aprobaciones descartadas al subir cambios |
| `required_status_checks` | Los checks del repositorio deben estar verdes, con la rama actualizada |

`bypass_actors` está **vacío de forma deliberada**: nadie, ni siquiera la administración de la organización, integra sin cumplir las reglas.

## El placeholder no es opcional

[`main-protection.template.json`](main-protection.template.json) contiene:

```json
{ "context": "REEMPLAZAR-POR-CHECK-REAL-DEL-REPOSITORIO" }
```

**Aplicar la plantilla sin sustituirlo bloquea todas las integraciones de forma permanente.** GitHub esperaría un check que ningún workflow produce, y ningún Pull Request podría integrarse jamás.

El nombre del contexto es exactamente el valor de `jobs.<id>.name` del workflow. La única forma fiable de obtenerlo es **leerlo de una ejecución real**, no deducirlo.

## Checks reales por repositorio

Obtenidos de ejecuciones reales de CI:

| Repositorio | Contextos |
| --- | --- |
| `Nexus-Battle-Account` | `Calidad y pruebas`, `Imagen del servicio` |
| `Nexus-Battle-Player-Inventory` | `Calidad y pruebas`, `Imagen del servicio` |
| `Nexus-Battle-Catalog` | `Calidad y pruebas`, `Imagen del servicio` |
| `Nexus-Battle-Community` | `Calidad y pruebas`, `Imagen del servicio` |
| `Nexus-Battle-Commerce` | `Calidad y pruebas`, `Imagen del servicio` |
| `Nexus-Battle-Notifications` | `Calidad y pruebas`, `Imagen del worker` |
| `Nexus-Battle-Web` | `Calidad y pruebas`, `Imagen estatica` |
| `Nexus-Battle-Combat` | `Calidad y pruebas`, `Imagen del servicio` (+ `develop antes que main` en `main`) |
| `Nexus-Battle-Missions` | `Calidad y pruebas`, `Imagen del servicio` (+ `develop antes que main` en `main`) |
| `Nexus-Battle-Auction` | `Calidad y pruebas`, `Imagen del servicio` (+ `develop antes que main` en `main`) |
| `Nexus-Battle-Wallet` | `Calidad y pruebas`, `Imagen del servicio` (+ `develop antes que main` en `main`) |
| `Nexus-Battle-Infrastructure` | `Validacion de documentacion` |

Tournament y Chatbot ([ADR-022](../../adr/ADR-022-sprint-3-bounded-contexts.md)) usarán los mismos tres nombres. Sus rulesets se crean **después** de la primera ejecución de CI, siguiendo el orden de aplicación de abajo.

### `develop` también está protegida

Los repositorios de código tienen dos rulesets: `main-protection` (solo *merge*, para la promoción) y `develop-protection` (solo *squash*). Comprobado el 2026-09-30 en Combat, Missions, Auction y Wallet con `gh api repos/Nexus-Battle-VI/<REPO>/rulesets`.

**Divergencia comprobada el 2026-09-30:** en esos cuatro repositorios, `main-protection` y `develop-protection` declaran `bypass_actors` (`OrganizationAdmin` y un usuario). Eso contradice el párrafo de arriba sobre `bypass_actors` vacío. Hay que decidir cuál de los dos es la política y alinear el otro; los rulesets de los repositorios nuevos seguirán la que se decida.

## Orden de aplicación

```text
1. Existe main
2. Existe un workflow de CI
3. Se ejecuta CI al menos una vez  <- aqui aparecen los nombres reales
4. Se leen los contextos de esa ejecucion
5. Se sustituye el placeholder
6. Se aplica el ruleset
7. Se verifica con GET
```

Crear el ruleset antes del paso 3 es el error que este documento existe para evitar.

## Aplicación

```bash
gh api -X POST repos/Nexus-Battle-VI/<REPO>/rulesets --input ruleset.json
```

Si ya existe, se actualiza en lugar de duplicarse:

```bash
gh api -X PUT repos/Nexus-Battle-VI/<REPO>/rulesets/<ID> --input ruleset.json
```

Siempre se verifica después:

```bash
gh api repos/Nexus-Battle-VI/<REPO>/rulesets/<ID>
```

## `do_not_enforce_on_create`

Está en `true` para no bloquear la creación de la rama inicial en un repositorio que aún no la tuviera. No afecta a la protección de los Pull Requests.

## Dependencia de CODEOWNERS

`require_code_owner_review` solo surte efecto si el equipo referenciado en `CODEOWNERS` **tiene acceso de escritura** al repositorio.

Verificado: `team-alfa`, `team-beta` y `team-gama` tienen `write` en los nueve repositorios, y `product-owner` y `scrum-master` tienen `maintain`. Todas las asignaciones de `CODEOWNERS` son por tanto efectivas.

Si un equipo referenciado perdiera el acceso, la regla dejaría de exigir su revisión **en silencio**. Es un fallo silencioso y conviene revisarlo al cambiar permisos.

## Nomenclatura de ramas: deliberadamente sin ruleset

No se define un ruleset de nomenclatura de ramas. Una regla estricta rompería:

- las ramas de Dependabot (`dependabot/npm_and_yarn/...`);
- las de cualquier automatismo futuro.

La convención se sostiene por `CONTRIBUTING.md` y por la revisión, que es donde produce beneficio sin fricción artificial.
