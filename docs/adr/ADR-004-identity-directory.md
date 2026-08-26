# ADR-004 — Identidad, directorio y control de acceso

- **Estado:** **Accepted** el 2026-08-25 — proveedor elegido. **Pool aprovisionado** el 2026-08-26 (`us-east-1_HrEiSzzKW`). **El BLOCKER sigue ACTIVO**: nada esta expuesto a internet, y el segundo factor no es el que este ADR previo
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

**Estado del blocker al 2026-08-25: el código está listo, el proveedor no existe todavía.**

Los cinco servicios validan el testimonio y aplican control de acceso. Lo que falta no es código de producto: es **el user pool de Cognito**, que Terraform describe pero que no se ha aplicado.

La tabla siguiente describe lo que ocurre **si el sistema se despliega sin ese pool**, es decir con `AUTH_MODE=disabled`. Sigue siendo exacta, con un matiz que antes no existía: ahora el sujeto que se registra es literalmente `anonymous`, de modo que los datos dicen que nadie fue verificado en lugar de aparentar personas concretas.

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
1. Aprobar un proveedor de identidad        -> HECHO: Cognito Essentials, aprovisionado
2. Adaptador del alta de sujetos             -> PENDIENTE: opera FakeIdentityProvider
3. Validar el testimonio                     -> HECHO: JWKS del pool, aws-jwt-verify
4. Cada servicio valida el testimonio        -> HECHO: los cinco servicios NestJS
5. Activar RBAC en operaciones sensibles     -> HECHO
```

**Cuatro de los cinco pasos están implementados.** Falta el 2, y su alcance se ha reducido: `POST /accounts` toma el sujeto del testimonio, de modo que el alta en el proveedor ya no la hace el producto. `IdentityProviderPort.register` solo se usa cuando la autenticación está desactivada.

### Qué protege ya cada servicio

| Servicio | Antes | Ahora |
| --- | --- | --- |
| Account | Cualquier testimonio leía cualquier cuenta | El agregado guarda su `subject`. `/me` resuelve la propia; `/:id` exige `ADMINISTRATOR` |
| Catalog | Crear, publicar, archivar y cambiar precio no exigían nada | Rol `ADMINISTRATOR` |
| Community | `authorId` y `moderatorId` los declaraba el cliente | Salen del `sub`. Moderar exige `MODERATOR` o `ADMINISTRATOR` |
| Commerce | `customerId` lo declaraba el cliente | Sale del `sub`. Un pedido ajeno responde 404 |
| Player-Inventory | El `ownerId` de la URL no se comprobaba | Debe coincidir con el `sub` |

En los tres casos con propiedad, un recurso ajeno responde **404 y no 403**: distinguirlos confirmaría que existe, y con eso se pueden enumerar recursos ajenos probando identificadores.

### La regla que hace inaplazable el paso 2

**Un binario de producción sin verificación de identidad no arranca.** Con `NODE_ENV=production` y `AUTH_MODE=disabled`, la carga de configuración falla y el servicio no llega a escuchar. Un aviso en el registro se pasa por alto; un arranque que falla, no.

Con la autenticación desactivada no se deja pasar sin más: se atribuye el sujeto literal `anonymous`. Sin proveedor **no se sabe** quién realiza la petición, y el dato que se guarde debe decirlo. Un hilo firmado por `anonymous` es honesto; uno firmado por un identificador sin verificar, no.

El pool real **ya existe**: `us-east-1_HrEiSzzKW`, con sus tres grupos —`PLAYER`, `MODERATOR`, `ADMINISTRATOR`— y el cliente de Web con codigo de autorizacion y PKCE. El emisor de testimonios que faltaba esta en pie.

**Aun asi el sistema no esta expuesto**, y es deliberado: `public_ingress_cidrs` sigue vacio y los grupos de seguridad no tienen ninguna regla de entrada desde internet. Exponerlo es una decision aparte de tener identidad, y se toma cuando haya algo desplegado que valga la pena exponer.

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

### El MFA por correo exige SES, y este ADR no lo contemplo

Al aprovisionar el pool, Cognito rechazo la configuracion que este ADR daba por
hecha:

```
InvalidParameterException: Cannot set EmailMfaConfiguration when user pool
EmailConfiguration contains an EmailSendingAccount of COGNITO_DEFAULT.
```

El emisor de correo por defecto de Cognito **no sirve** para el segundo factor.
Para usarlo hace falta SES con una identidad verificada, y salir de su entorno
de pruebas para poder escribir a cualquiera.

Hubo un segundo rechazo, y su motivo merece anotarse porque es correcto:

```
Cannot set EmailMfaConfiguration when user pool AccountRecoverySetting
is not set or contains only verified_email in RecoveryMechanisms.
```

Si el correo es a la vez el segundo factor y el unico modo de recuperar la
cuenta, el circulo se cierra sobre si mismo: quien tenga el correo se salta el
MFA pidiendo una recuperacion, y el segundo factor deja de serlo. La
recuperacion quedo en `admin_only`, que no se puede combinar con otros
mecanismos — y esa es justo la propiedad util: **no hay autoservicio de
recuperacion**, y queda dicho en lugar de aparentar que lo hay.

**Estado actual: el segundo factor es una aplicacion autenticadora (TOTP)**, no
correo. No cuesta nada, no necesita SES, y es mas fuerte: un codigo por correo
lo intercepta quien tenga acceso al correo.

Volver al correo es aprovisionar SES y cambiar una variable
(`mfa_method = "email"`). Es una decision pendiente, no un olvido, y hasta que se
tome **este ADR no describe lo que hay desplegado en ese punto**.

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
