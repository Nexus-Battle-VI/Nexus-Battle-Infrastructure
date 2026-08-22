# Flujo de trabajo del desarrollo

## Modelo de repositorios

```text
Nexus-Battle-Management
  Issues + Product Backlog + Project + gobierno Scrum
  SIN Pull Requests de desarrollo

Repositorios de codigo (8)
  Codigo + Pull Requests + CI
  SIN Issues ni Projects propios
```

Management es la **fuente única de verdad**. Los repositorios de código no duplican Epics, Historias de Usuario, Enablers, Tasks ni Bugs. Por eso las Issues están deshabilitadas en los ocho.

## Trazabilidad

Todo Pull Request referencia su Issue central con el **nombre completo del repositorio**:

```text
Refs Nexus-Battle-VI/Nexus-Battle-Management#NUMERO
```

Nunca `#NUMERO` a secas: desde otro repositorio apuntaría a una Issue local inexistente o equivocada.

`Closes` se emplea **únicamente** cuando el Pull Request completa totalmente una Task, un Bug o una Task subordinada de un Enabler. **Un Pull Request no cierra la Historia de Usuario padre.** La HU permanece abierta hasta que todos los módulos estén integrados, se cumpla la Definition of Done, exista evidencia y el Product Owner acepte el resultado.

Política completa en [cross-repository-traceability.md](https://github.com/Nexus-Battle-VI/Nexus-Battle-Management/blob/main/docs/governance/cross-repository-traceability.md) de Management.

## Ramas

*Trunk-based* liviano. La única rama permanente es **`main`**.

No existen `develop`, `qa`, `staging` ni `release/*`. `dev`, `test` y `prod` son **entornos de despliegue, no ramas**.

```text
feat/hu-33-listar-catalogo
fix/bug-12-filtro-catalogo
chore/bootstrap-sprint1-foundation
ci/cache-dependencias
docs/contrato-openapi
test/cobertura-registro
refactor/cliente-http
```

La rama se elimina automáticamente al integrar.

## Commits y títulos

Conventional Commits con los tipos `feat`, `fix`, `docs`, `test`, `refactor`, `chore`, `ci` y `build`.

El **título del Pull Request es el mensaje del commit de integración**, porque `main` solo admite *squash*:

```text
feat(catalog): [HU-33] crear producto
feat(notifications): [HU-55] enviar correo transaccional
fix(commerce): [BUG-12] corregir el total del pedido
```

El identificador `[HU-NN]` en el título es la clave de trazabilidad que sobrevive en el historial de `main`.

## Verificación antes de abrir un Pull Request

```bash
npm ci
npm run lint
npm run format:check
npm run typecheck
npm run test:coverage
npm run build
```

La cobertura mínima es del **80 %** y está configurada como umbral: por debajo, el comando falla.

## Ciclo completo

```text
1. La Issue cumple la Definition of Ready
2. Rama desde main actualizada
3. Desarrollo Red -> Green -> Refactor
4. Verificacion local completa
5. Pull Request con la plantilla completada
6. Revision del Code Owner
7. Integracion por squash con el pipeline verde
8. Evidencia registrada desde la Issue central
```

## Integración continua

Se dispara en `pull_request` hacia `main` y en `push` a `main`. Concurrencia con cancelación de ejecuciones anteriores.

| Etapa | Comando |
| --- | --- |
| Instalación | `npm ci` |
| Lint | `npm run lint` |
| Formato | `npm run format:check` |
| Tipos | `npm run typecheck` |
| Pruebas | `npm run test:unit` y `test:integration` |
| Cobertura | `npm run test:coverage` |
| Compilación | `npm run build` |
| Imagen | `docker build` y arranque real del contenedor |

**El job de Docker no solo construye**: levanta el contenedor y comprueba las sondas. Una imagen que compila pero no arranca no aporta confianza.

**CI no depende de AWS.** No hay credenciales, no hay despliegue y no se necesita ninguna cuenta.

## Nombres de los checks

Los contextos reales que producen los workflows, y que usan los rulesets:

| Contexto | Repositorios |
| --- | --- |
| `Calidad y pruebas` | Los ocho |
| `Imagen del worker` | Notifications |
| `Imagen del servicio` | Account, Player-Inventory, Catalog, Community, Commerce |
| `Imagen estatica` | Web |

## Seguridad de Actions

- Acciones de terceros fijadas por **SHA de commit completo**, resuelto desde GitHub.
- `permissions: contents: read` por defecto.
- Aprobación requerida para workflows de contribuciones externas.
- El token del workflow no puede crear ni aprobar Pull Requests.
- Retención de artefactos: 60 días.

## OIDC para despliegue futuro

No se usan claves de acceso de larga duración de AWS. Cuando exista despliegue, la autenticación será OIDC con credenciales de corta duración:

```yaml
permissions:
  contents: read
  id-token: write
```

Los *subjects* inmutables por repositorio, para la política de confianza:

```text
repo:Nexus-Battle-VI/Nexus-Battle-Account:environment:prod
repo:Nexus-Battle-VI/Nexus-Battle-Player-Inventory:environment:prod
repo:Nexus-Battle-VI/Nexus-Battle-Catalog:environment:prod
repo:Nexus-Battle-VI/Nexus-Battle-Community:environment:prod
repo:Nexus-Battle-VI/Nexus-Battle-Commerce:environment:prod
repo:Nexus-Battle-VI/Nexus-Battle-Notifications:environment:prod
repo:Nexus-Battle-VI/Nexus-Battle-Web:environment:prod
```

Emisor: `token.actions.githubusercontent.com`. Audiencia: `sts.amazonaws.com`.

**No se ha creado ninguna política de confianza en AWS.** Depende de [ADR-007](../adr/ADR-007-aws-cost-optimized-platform.md).

Acotar el *subject* al **entorno** y no solo al repositorio es deliberado: sin esa restricción, cualquier rama del repositorio podría asumir el rol de producción.

## Entornos

`dev`, `test` y `prod` existen como entornos de GitHub **sin credenciales de AWS**. `prod` exige revisión antes de ejecutar cualquier workflow dirigido a él.

No hay despliegue real todavía.
