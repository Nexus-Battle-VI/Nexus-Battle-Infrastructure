# ADR-004 — Identidad, directorio y control de acceso

- **Estado:** Proposed — **contiene un BLOCKER activo**
- **Fecha:** 2026-08-21
- **Decide:** Arquitectura, con aprobación obligatoria de gobierno del proyecto y presupuesto
- **Relacionado:** [ADR-007](ADR-007-aws-cost-optimized-platform.md)

## Contexto

Existe un requisito de **Directorio Activo**. Al mismo tiempo, el Sprint tiene un techo de coste de USD 100 al mes, y AWS Managed Microsoft AD cuesta por sí solo varias veces esa cifra.

Este ADR existe porque «identidad» se usa habitualmente para nombrar cinco cosas distintas que tienen costes, plazos y responsables diferentes. Confundirlas es lo que produce decisiones imposibles de cumplir.

## Las cinco cosas que hay que separar

| Concepto | Qué es | Quién lo provee | Coste |
| --- | --- | --- | --- |
| **Directorio** | El censo de personas y grupos de la organización | Directorio Activo, LDAP | Alto y fijo |
| **Proveedor de identidad (IdP)** | Quien **demuestra** que alguien es quien dice | OIDC / SAML sobre el directorio | Medio, por usuario activo |
| **JWT / sesión** | El testimonio verificable de esa prueba | Emitido por el IdP o por Account | Nulo |
| **RBAC** | Qué puede hacer cada quien | **Account**, en su dominio | Nulo |
| **Segundo factor por correo** | Refuerzo de la prueba de identidad | IdP + Notifications | Bajo, por envío |

De las cinco, **solo RBAC pertenece hoy al producto**. Account ya lo implementa: roles `PLAYER`, `MODERATOR` y `ADMINISTRATOR`, con la regla de que el rol base no puede retirarse y solo un administrador gestiona los demás.

Las otras cuatro dependen de un proveedor que **no existe todavía**.

## Decisión

1. **No se provisiona Managed Microsoft AD** en el alcance de Sprint 1. Su coste fijo excede por sí solo el techo completo.
2. **El producto no almacena contraseñas propias.** Ni hashes, ni sales, ni tokens de sesión, ni secretos de segundo factor. El agregado `Account` modela cuenta y roles, no credenciales.
3. Se define **`IdentityProviderPort`** como frontera: alta, consulta y baja del sujeto de identidad. Es lo único que el dominio conoce del proveedor.
4. En Foundation opera **`FakeIdentityProvider`**, implementación completa del puerto sobre almacenamiento en memoria y sin credenciales. No es una simulación del comportamiento: es una implementación real de un contrato deliberadamente estrecho.
5. **RBAC se implementa ya**, en el dominio de Account, porque no depende del proveedor.

## BLOCKER — Identity provider approval

**No existe un proveedor de identidad autorizado ni presupuesto aprobado para un directorio corporativo.**

Consecuencia directa y declarada en todos los servicios afectados:

| Servicio | Qué queda sin proteger |
| --- | --- |
| Account | El registro y la verificación no exigen credencial |
| Catalog | Crear, publicar, archivar y cambiar precios no exige rol de administrador |
| Community | El `moderatorId` llega sin verificar: cualquiera podría ocultar mensajes o cerrar hilos |
| Commerce | El `customerId` llega sin verificar: cualquiera podría confirmar pedidos a nombre de otra persona |
| Web | `useSession` guarda una identidad no verificada |

**Ninguno de estos servicios debe desplegarse en un entorno accesible desde internet sin resolver este blocker.**

Se decidió **no añadir comprobaciones de rol sin identidad verificable**. Un `if (rol === 'ADMINISTRATOR')` sobre un identificador que el cliente envía sin firmar no es un control de seguridad: es seguridad aparente, y es peor que su ausencia, porque induce a creer que existe una protección.

## Camino de resolución

```text
1. Aprobar un proveedor de identidad        -> gobierno del proyecto + presupuesto
2. Implementar el adaptador OIDC             -> sustituye a FakeIdentityProvider
3. Account emite o valida el testimonio      -> JWT verificable
4. Cada servicio valida el testimonio        -> guard comun en el borde HTTP
5. Activar RBAC en las operaciones sensibles -> las reglas ya existen en Account
```

Los pasos 1 y 2 son los únicos bloqueados. Del 3 al 5 son trabajo conocido que puede planificarse en cuanto el 1 se desbloquee.

Opciones a evaluar cuando haya decisión, en orden de coste creciente:

| Opción | Coste aproximado | Nota |
| --- | --- | --- |
| Cognito user pool | Gratuito hasta un umbral de usuarios activos | No es un directorio corporativo, pero sí un IdP con OIDC |
| IdP autoalojado en la misma EC2 | Solo el coste de cómputo ya presupuestado | Añade operación y responsabilidad de custodia |
| Managed Microsoft AD | Muy por encima del techo del Sprint | Cumple el requisito literal de Directorio Activo |

Ninguna se selecciona en este ADR: la elección exige aprobación de presupuesto.

## Consecuencias

**Lo que se gana**

- El producto no custodia credenciales, que es la clase de dato con mayor consecuencia en caso de filtración.
- Sustituir el proveedor no toca el dominio ni los casos de uso: solo el adaptador.
- La ausencia de control de acceso está declarada en README, `SECURITY.md` y `docs/architecture.md` de cada servicio afectado, no oculta.

**Lo que cuesta**

- El sistema **no es desplegable públicamente** en su estado actual. Es la limitación más relevante del Sprint 1 y así se reporta.
- El requisito de Directorio Activo queda sin cumplir, con su justificación de coste registrada.

## Evidencia

- `Nexus-Battle-Account` no contiene ningún campo de contraseña, hash ni secreto en su agregado.
- `FakeIdentityProvider` implementa el contrato completo de `IdentityProviderPort` y está cubierto por pruebas.
- `RegisterAccount` compensa el alta de identidad si falla la persistencia, para no dejar sujetos huérfanos.
