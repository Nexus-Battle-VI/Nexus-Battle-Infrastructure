# ADR-001 — Estrategia de repositorios

- **Estado:** Proposed
- **Fecha:** 2026-08-21
- **Decide:** Arquitectura, con validación de Scrum Masters y Product Owners
- **Relacionado:** [ADR-002](ADR-002-backend-stack.md), [ADR-005](ADR-005-data-strategy.md), [ADR-006](ADR-006-messaging.md)

## Contexto

Nexus Battles VI es **un producto único** desarrollado por tres Teams (Alfa, Beta y Gama) con 18 integrantes en total. Existe un repositorio de gestión, `Nexus-Battle-Management`, que es la fuente única de Issues, Product Backlog y gobierno Scrum, y ocho repositorios de código.

La pregunta que este ADR responde es **qué determina la existencia de un repositorio**, y ninguna de las respuestas intuitivas sirve:

- *1 Épica = 1 repositorio* haría que el número de servicios dependiera de cómo se escribió el backlog.
- *1 Historia de Usuario = 1 repositorio* produciría decenas de servicios triviales.
- *1 Team = 1 repositorio* alinearía la arquitectura con el organigrama en lugar de con el problema, y dejaría a los tres Teams sin poder tocar la aplicación web.

## Decisión

Un repositorio existe cuando hay un **deployable independiente**, y un deployable independiente existe cuando se cumple la cadena completa:

```text
requisito -> dominio -> bounded context -> propiedad de datos
          -> dependencias -> contrato -> deployable -> Team -> repositorio
```

El punto que decide es la **propiedad exclusiva de datos**: si dos candidatos comparten almacén, no son dos servicios, son uno con dos procesos.

Bounded contexts identificados y su correspondencia:

| Bounded context | Repositorio | Team propietario | Datos que posee |
| --- | --- | --- | --- |
| Account / Identity | `Nexus-Battle-Account` | Alfa | Cuentas, estado, roles |
| Player / Inventory | `Nexus-Battle-Player-Inventory` | Alfa | Inventarios y ranuras |
| Catalog | `Nexus-Battle-Catalog` | Gama | Productos y precios |
| Community | `Nexus-Battle-Community` | Gama | Hilos y mensajes |
| Commerce | `Nexus-Battle-Commerce` | Beta | Pedidos y líneas |
| Notifications | `Nexus-Battle-Notifications` | Alfa | Registro de idempotencia |

Además:

- **`Nexus-Battle-Web`** es la interfaz de los seis contextos. Es un deployable propio porque su ciclo de vida, su stack y su forma de desplegarse son distintos. Los tres Teams lo comparten; la propiedad se reparte **por feature** en `CODEOWNERS`, alineada con la propiedad de cada servicio.
- **`Nexus-Battle-Infrastructure`** no es un servicio: es la fuente de verdad técnica del sistema. No tiene Team propietario inventado; lo custodian Scrum Masters y Product Owners, que son roles reales y existentes.

## Consecuencias

**Lo que se gana**

- El número de servicios lo determina el dominio, no el backlog ni el organigrama.
- Cada servicio puede desplegarse, escalar y fallar por separado.
- La propiedad de datos es verificable: cada repositorio declara qué posee y ningún otro accede a ese almacén.

**Lo que cuesta**

- Ocho repositorios para 18 personas es una relación alta. Se acepta porque el objetivo académico incluye demostrar una arquitectura de microservicios, y porque el andamiaje común está automatizado.
- El código que parece duplicado entre servicios **no se extrae a un paquete común**. `Money` existe por separado en Catalog y en Commerce de forma deliberada: un paquete compartido de objetos de dominio acoplaría ambos y convertiría cualquier cambio en uno en un despliegue coordinado del otro.
- La coordinación entre contextos exige contratos explícitos y, en algunos casos, procesos de larga duración. Ver [ADR-006](ADR-006-messaging.md).

**Lo que queda prohibido**

- Acceso directo a la base de datos de otro servicio.
- Claves foráneas entre servicios.
- Entidades de dominio compartidas a través de un paquete común.

## Alternativas consideradas

| Alternativa | Por qué se descartó |
| --- | --- |
| Monorepo con todos los servicios | Simplifica la gestión, pero difumina la frontera de datos: nada impide un `import` entre dominios, y la restricción pasa a depender de la disciplina en lugar de la estructura |
| Monolito modular | Sería defendible para 18 personas, pero el requisito académico exige demostrar microservicios, y el objetivo de escalado independiente no se cumpliría |
| Un repositorio por Team | Alinea la arquitectura con el organigrama. La aplicación web, que los tres Teams necesitan tocar, no encajaría en ninguno |

## Evidencia

- Los nueve repositorios existen en la organización `Nexus-Battle-VI` con `main` y CI verde.
- La prohibición de importar adaptadores desde el dominio está implementada como reglas `no-restricted-imports` de ESLint en los seis servicios, de modo que CI rechaza una violación.
- `Nexus-Battle-Commerce` consulta precios a Catalog mediante `ProductPricingPort`, nunca por acceso al almacén.

## Pendiente de aprobación

Este ADR permanece en `Proposed` hasta que Product Owners y Scrum Masters lo validen en Refinement.
