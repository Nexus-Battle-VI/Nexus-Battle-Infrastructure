# ADR-004 — Identidad, directorio y control de acceso

- **Estado:** **Accepted** el 2026-08-25 — proveedor elegido. **El BLOCKER sigue ACTIVO** hasta que el adaptador esté implementado
- **Fecha:** 2026-08-21, aceptado el 2026-08-25
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

**Estado del blocker al 2026-08-25: la aprobación existe, la implementación no.**

Ya hay proveedor autorizado y presupuesto ([ADR-007](ADR-007-aws-cost-optimized-platform.md) está `Accepted`). Eso resuelve el paso 1 del camino de resolución y **solo el paso 1**.

**Elegir el proveedor no protege ni un solo endpoint.** Mientras el adaptador OIDC no sustituya a `FakeIdentityProvider` y los servicios no validen el testimonio, todo lo que sigue continúa siendo cierto sin ningún matiz.

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
1. Aprobar un proveedor de identidad        -> HECHO el 2026-08-25: Cognito Essentials
2. Implementar el adaptador OIDC             -> sustituye a FakeIdentityProvider
3. Account emite o valida el testimonio      -> JWT verificable contra el JWKS del pool
4. Cada servicio valida el testimonio        -> guard comun en el borde HTTP
5. Activar RBAC en las operaciones sensibles -> las reglas ya existen en Account
```

El paso 1 está resuelto. Del 2 al 5 son trabajo conocido y ya no bloqueado: es implementación pendiente, no incertidumbre.

**Hasta completar el paso 5, el sistema sigue sin poder exponerse a internet.**

Notas de implementación que condicionan los pasos 2 a 4:

- El pool se provisiona con **Terraform** ([ADR-008](ADR-008-iac.md)), no a mano, para que no haya deriva entre el entorno y el código.
- El cliente de aplicación de Web es **público: sin secreto de cliente**, con *authorization code grant* y **PKCE**. Un secreto en el navegador no es un secreto.
- La validación del JWT se hace **contra el JWKS del pool**, comprobando `iss`, `aud`, `token_use` y `exp`, con biblioteca mantenida. No se implementa verificación de firma a mano.
- El identificador estable del sujeto es el `sub` del pool, que es lo que `IdentityProviderPort` ya modela. El correo **no** sirve como identificador: puede cambiar y puede repetirse entre proveedores.

## Decisión de proveedor: Amazon Cognito, plan Essentials

Opciones evaluadas, con precios reales de la Price List API en `us-east-1` al 2026-08-25:

| Opción | Coste real | Veredicto |
| --- | --- | --- |
| **Cognito user pool, plan Essentials** | 0,015 USD/MAU | **Seleccionada** |
| Cognito user pool, plan Lite | 0,0055 USD/MAU | Descartada: no incluye MFA por correo |
| Cognito user pool, plan Plus | 0,020 USD/MAU | Descartada: su valor añadido es protección frente a amenazas, que no es el problema a resolver |
| IdP autoalojado en la misma EC2 | Solo cómputo ya presupuestado | Descartada: añade custodia de credenciales, justo lo que este ADR evita |
| Managed Microsoft AD | Varias veces el techo mensual completo | Descartada por coste |

### Por qué Essentials y no Lite

El requisito contempla **segundo factor por correo**. La documentación de AWS es explícita: Essentials incorpora *«advanced authentication features like choice-based sign-in and email MFA»*, y Lite es un plan de autenticación básica que no las incluye.

Lite costaría menos de un tercio, pero **no cumple el requisito**. Elegirlo obligaría a implementar el segundo factor por cuenta propia, es decir, a custodiar secretos de segundo factor: exactamente lo que la decisión 2 de este ADR prohíbe.

### Coste, sin asumir capa gratuita

| Usuarios activos al mes | Coste mensual |
| --- | --- |
| 30 | 0,45 USD |
| 100 | 1,50 USD |
| 500 | 7,50 USD |

**No se asume capa gratuita**, en coherencia con [assumptions.md](../costs/assumptions.md). Si existe, el coste real será menor que el estimado, nunca mayor.

A la escala prevista de la demo el coste es marginal frente al cómputo. **El coste nunca fue la razón por la que faltaba identidad**: faltaba una decisión.

## Consecuencias

**Lo que se gana**

- El producto no custodia credenciales, que es la clase de dato con mayor consecuencia en caso de filtración.
- Sustituir el proveedor no toca el dominio ni los casos de uso: solo el adaptador.
- La ausencia de control de acceso está declarada en README, `SECURITY.md` y `docs/architecture.md` de cada servicio afectado, no oculta.

**Lo que cuesta**

- El sistema **no es desplegable públicamente** hasta completar los pasos 2 a 5. Es la limitación más relevante del Sprint 1 y así se reporta.
- Cognito **no es un Directorio Activo**. Es un IdP con OIDC. El requisito literal de directorio corporativo sigue sin cumplirse, y esta decisión no lo disimula.
- El requisito de Directorio Activo queda sin cumplir, con su justificación de coste registrada.

## Evidencia

- `Nexus-Battle-Account` no contiene ningún campo de contraseña, hash ni secreto en su agregado.
- `FakeIdentityProvider` implementa el contrato completo de `IdentityProviderPort` y está cubierto por pruebas.
- `RegisterAccount` compensa el alta de identidad si falla la persistencia, para no dejar sujetos huérfanos.
