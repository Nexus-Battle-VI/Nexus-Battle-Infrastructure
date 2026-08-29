# ADR-004 — Identidad, directorio y control de acceso

- **Estado:** **Accepted** el 2026-08-25 — proveedor elegido. **Pool aprovisionado** el 2026-08-26 (`us-east-1_HrEiSzzKW`). **Verificación de identidad ACTIVA en los cinco servicios** desde el 2026-08-29 (`AUTH_MODE=jwt`, comprobada de extremo a extremo). **El rol viaja en el testimonio** desde el 2026-08-29 (Account decide, el pool refleja). **TOTP confirmado como segundo factor administrativo** el 2026-08-29. El pool lo tiene activo con `mfa_configuration = OPTIONAL`, que según AWS solo reta a quien tenga factor inscrito: falta crear la identidad e inscribir su autenticador, no configurar el pool. **Ninguna cuenta administrativa existe todavía**, así que el control pasa por ausencia.
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
3. ~~Se define **`IdentityProviderPort`** como frontera: alta, consulta y baja del sujeto de identidad.~~ **Superado el 2026-08-29**: el producto dejó de dar de alta identidades, el puerto se quedó sin consumidores y se eliminó. La frontera hoy son tres contratos estrechos —`TokenVerifierPort`, `AuthenticationProviderPort` y `RoleDirectoryPort`— en lugar de uno ancho. Ver «Camino de resolución».
4. ~~En Foundation opera **`FakeIdentityProvider`**.~~ Eliminado junto con el puerto. Los dobles que quedan son `FakeAuthenticationProvider` e `InMemoryRoleDirectory`, cada uno de un contrato que sí existe.
5. **RBAC se implementa ya**, en el dominio de Account, porque no depende del proveedor.

## BLOCKER — Identity provider approval

**Estado del blocker al 2026-08-29: resuelto en su parte técnica. Queda abierto el segundo factor administrativo.**

El pool existe, está aplicado, y los cinco servicios corren con `AUTH_MODE=jwt`
sobre los nodos de la demo. La tabla de más abajo describe lo que ocurría con
`AUTH_MODE=disabled` y **ya no describe el estado actual**: se conserva porque
sigue siendo exacta para cualquier entorno que arranque sin el pool.

### Lo que se comprobó, y cómo

No se da por bueno que «el código lo hace». Se ejecutó contra el sistema
desplegado, a través del proxy:

| Ruta | Sin testimonio | Con testimonio |
| --- | --- | --- |
| `/`, `/api/products`, `/api/threads` (declaradas `@Public()`) | 200 | — |
| `GET /api/inventories/:id` | **401** | 404 |
| `GET /api/orders` | **401** | **200** |
| `POST /api/threads` | **401** | — |
| `GET /api/accounts/me` | — | **200**, resuelto desde el `sub` del testimonio |

El testimonio se obtuvo del propio sistema: `POST /api/sessions` con un usuario
`PLAYER` real, que Account verifica contra PostgreSQL y luego contra Cognito por
`AdminInitiateAuth`. Su firma se validó **contra el JWKS del pool** —RS256, `kid`
presente— y transporta `cognito:groups: ["PLAYER"]`.

`readRoles` acepta únicamente grupos que sean roles conocidos: un grupo inventado
en el pool no puede fabricar un permiso.

### Lo que sigue abierto

- **Segundo factor por correo para `ADMINISTRATOR` y `SUPER_ADMINISTRATOR`.**
  El pool tiene TOTP porque el MFA por correo exige SES, decisión pendiente.
  `LoginAccount` **falla cerrado** mientras tanto: si Cognito entrega un token
  para un rol administrativo sin haber retado el segundo factor, devuelve
  `providerUnavailable` en lugar de autenticar.
- **HU-01 no crea todavía la identidad en Cognito.** La cuenta de prueba se
  alineó a mano entre el pool y PostgreSQL.
- **`public_ingress_cidrs` sigue vacío.** Abrirlo es una decisión aparte, que
  ahora es discutible y antes no lo era.

**Estado anterior, conservado como referencia:**

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
2. Adaptador del alta de sujetos             -> RETIRADO: el producto no da de alta identidades
3. Validar el testimonio                     -> HECHO: JWKS del pool, aws-jwt-verify
4. Cada servicio valida el testimonio        -> HECHO: los cinco servicios NestJS
5. Activar RBAC en operaciones sensibles     -> HECHO
6. Reflejar el rol en el proveedor           -> HECHO: Account decide, el pool recoge
```

**El paso 2 no se completó: desapareció**, y merece decirse así en lugar de
marcarlo como hecho. El 2026-08-29 se eligió entre dos diseños coherentes y ganó
el que saca a Account del negocio de crear identidades: **el alta ocurre en la
pantalla del proveedor**, de modo que al llegar a `POST /accounts` la identidad
ya existe y lo que falta es la cuenta del producto. Sin sujeto verificado el
registro responde 401 en vez de inventar uno.

Con eso `IdentityProviderPort` se quedó **sin un solo consumidor** y se eliminó,
junto con `FakeIdentityProvider` y `CognitoIdentityProvider` —este último
mergeado el día anterior—. Es preferible a dejar un adaptador que parece vivo y
no lo está.

**Este ADR describía ese puerto como la frontera del dominio con el proveedor
(punto 3 de la Decisión). Ya no existe.** La frontera hoy son
`TokenVerifierPort` (verificar el testimonio), `AuthenticationProviderPort`
(comprobar la contraseña) y `RoleDirectoryPort` (reflejar el rol) — tres
contratos estrechos en lugar de uno ancho.

El paso 6 es nuevo y no estaba previsto aquí; ver «El rol viaja en el
testimonio» más abajo.

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

El pool real **ya existe**: `us-east-1_HrEiSzzKW`, con sus cuatro grupos —`PLAYER`, `MODERATOR`, `ADMINISTRATOR`, `SUPER_ADMINISTRATOR`— y el cliente de Web con codigo de autorizacion y PKCE. El emisor de testimonios que faltaba esta en pie. Ver [«Login server-side de Account (HU-02)»](#login-server-side-de-account-hu-02) para el segundo flujo que ese mismo cliente autoriza, y `SUPER_ADMINISTRATOR` mas abajo en esa misma seccion.

**Aun asi el sistema no esta expuesto**, y es deliberado: `public_ingress_cidrs` sigue vacio y los grupos de seguridad no tienen ninguna regla de entrada desde internet. Exponerlo es una decision aparte de tener identidad, y se toma cuando haya algo desplegado que valga la pena exponer.

Notas de implementación que condicionan los pasos 2 a 4:

- El pool se provisiona con **Terraform** ([ADR-008](ADR-008-iac.md)), no a mano, para que no haya deriva entre el entorno y el código.
- El cliente de aplicación de Web es **público: sin secreto de cliente**, con *authorization code grant* y **PKCE**. Un secreto en el navegador no es un secreto.
- La validación del JWT se hace **contra el JWKS del pool**, comprobando `iss`, `aud`, `token_use` y `exp`, con biblioteca mantenida. No se implementa verificación de firma a mano.
- El identificador estable del sujeto es el `sub` del pool, que es lo que `TokenVerifierPort` entrega ya verificado. El correo **no** sirve como identificador: puede cambiar y puede repetirse entre proveedores.

## Login server-side de Account (HU-02)

Actualiza lo que este ADR describía como "el cliente de Web": ahora autoriza dos flujos, no uno. Esto es una corrección sobre lo escrito arriba, no una decisión nueva de proveedor: Cognito sigue siendo el mismo, el pool sigue siendo el mismo.

**El problema.** `AuthenticationProviderPort` (HU-02, `Nexus-Battle-Account`) necesita verificar contraseña y segundo factor contra Cognito desde el backend, no desde el navegador. La opción obvia — habilitar `ALLOW_USER_PASSWORD_AUTH` en el cliente público de Web — se descartó explícitamente: ese flujo solo exige el `client_id`, y el `client_id` de un cliente público **viaja en el bundle de Web**, por definición pública. Habilitarlo abriría un camino directo a Cognito que cualquiera podría invocar sin pasar por Account, saltándose el guard aplicativo que impide que `ADMINISTRATOR`/`SUPER_ADMINISTRATOR` autentiquen sin segundo factor (CA-06) — porque `mfa_configuration` del pool es `OPTIONAL`, no forzado por grupo, así que una cuenta administrativa sin TOTP inscrito pasaría de largo.

**La decisión.** El mismo cliente de aplicación (`web`, sin secreto) gana un segundo flujo explícito: `ALLOW_ADMIN_USER_PASSWORD_AUTH`, para que Account invoque `AdminInitiateAuth`/`AdminRespondToAuthChallenge` con `AuthFlow = ADMIN_USER_PASSWORD_AUTH`. La diferencia con `USER_PASSWORD_AUTH` no es cosmética: las operaciones `Admin*` exigen además una petición firmada con credenciales de AWS que tengan el permiso IAM `cognito-idp:AdminInitiateAuth`/`AdminRespondToAuthChallenge` sobre este pool concreto. El `client_id` público deja de ser suficiente por sí solo — la autorización real la da IAM, no el cliente.

No se creó un segundo App Client. Se evaluó y se descartó: los cuatro servicios de dominio (`Catalog`, `Commerce`, `Community`, `Player-Inventory`) verifican el `client_id` del token contra un único valor de configuración (`COGNITO_CLIENT_ID`, compartido desde el PR #13), código idéntico en los cuatro, sin soporte de lista ni de `null`. Un segundo cliente emitiría tokens con un `client_id` distinto que esos cuatro servicios rechazarían con 401, y modificarlos está fuera del alcance de `Nexus-Battle-Infrastructure`. Aislar de verdad el flujo de Account del de Web exige que los cinco servicios acepten varios `client_id` válidos — se deja registrado como trabajo futuro, no como algo resuelto aquí.

**Quién tiene el permiso IAM, y su límite honesto.** El rol de instancia del nodo `app` (`infra/modules/compute`) es el único principal al que se le concedió `cognito-idp:AdminInitiateAuth`/`AdminRespondToAuthChallenge`, acotado por `Resource` a este pool exacto — nunca `cognito-idp:*`. Desde el 2026-08-29 tiene además tres acciones para reflejar el rol (`AdminListGroupsForUser`, `AdminAddUserToGroup`, `AdminRemoveUserFromGroup`), con el mismo acotamiento; ver «El rol viaja en el testimonio». No se generó ninguna clave de acceso de AWS (`AWS_ACCESS_KEY_ID`/`AWS_SECRET_ACCESS_KEY`): el SDK de Account obtiene credenciales de la cadena por defecto, que en este nodo resuelve al perfil de instancia vía IMDSv2. IAM es aquí un **control técnico**, no una regla funcional: no decide qué puede hacer un rol de producto, solo qué principal de AWS puede firmar esta llamada concreta.

Ese control tiene un límite que este ADR no puede disimular: **es el único rol que existe para el nodo `app`**, y ADR-011 pone los seis contenedores de ese nodo —proxy, web, account, inventory, catalog, community, commerce— en la misma instancia EC2. Docker no aísla por contenedor el acceso al servicio de metadatos; en la práctica, cualquier contenedor del nodo `app` puede obtener las mismas credenciales que Account y llamar estas dos acciones, no solo Account. Aislarlo de verdad —una identidad de AWS por servicio— es la clase de cambio de topología (ECS/Fargate con roles de tarea, instancia por servicio) que ADR-011 ya descartó por coste. Es una limitación aceptada de esta topología, no un descuido de esta rama, y queda dicha en lugar de aparentar un aislamiento que no existe.

**`SUPER_ADMINISTRATOR`.** El dominio de Account (y el backlog de Management, HU-02/HU-39) ya reconocen un cuarto rol, además de `PLAYER`/`MODERATOR`/`ADMINISTRATOR`. Este pool ahora tiene el grupo `SUPER_ADMINISTRATOR` (`precedence = 0`, por encima de `ADMINISTRATOR`). El grupo existe; no hay cuenta, no hay contraseña, no hay usuario aprovisionado y no se asigna a nadie desde el login — eso es HU-39, no esta rama. **Inconsistencia transversal registrada, no resuelta aquí**: los cuatro servicios de dominio todavía reconocen solo tres roles en su propio enum (`ALL_ROLES`); ese código está fuera de este repositorio.

**Corrección de política de contraseña.** `minimum_length` baja de 12 a 9. HU-01 (CA-03) exige "más de ocho caracteres"; nueve es el mínimo que lo cumple, y no existe ninguna aclaración formal del cliente ni del profesor —auditada contra el backlog de Management— que autorice doce. Era una política más estricta que la historia de usuario sin decisión que la respalde.

**Lo que sigue pendiente, sin resolver aquí.** El segundo factor administrativo del producto está confirmado por el cliente como **correo electrónico** (aclaración PO-12, 2026-08-19, backlog de Management). Lo que Cognito tiene aprovisionado sigue siendo **TOTP** (ver más abajo, «El MFA por correo exige SES»): `Nexus-Battle-Notifications` no tiene todavía un adaptador SES real (solo `Fake`/`SMTP`), así que activar `mfa_method = "email"` en Terraform seguiría fallando el `apply`. Esta rama no lo resuelve: sería inventar una decisión de tres repositorios (Infrastructure, Notifications, y el aprovisionamiento de SES) que nadie ha tomado todavía.

## El rol viaja en el testimonio

**Estado:** decidido y aplicado el 2026-08-29. Comprobado de extremo a extremo
contra el pool real.

### El problema: dos fuentes de verdad que nadie sincronizaba

Account escribía el rol en `account_roles` (PostgreSQL) y el testimonio viajaba
**sin `cognito:groups`**. Los otros cuatro servicios leen el rol del testimonio,
así que veían a quien se registrase por la pantalla del proveedor **sin ningún
rol**.

**No daba síntoma, y eso es lo que lo hacía peligroso.** Las ocho puertas
`@Roles(...)` del sistema piden `ADMINISTRATOR` o `MODERATOR`; ninguna pide
`PLAYER`. Un jugador auto-registrado podía navegar el catálogo, comprar, escribir
en la comunidad y ver su inventario con normalidad. La divergencia era
**invisible, no inexistente**: habría dado la cara el día que alguien escribiera
`@Roles(Role.Player)`, con el síntoma «los usuarios nuevos no pueden hacer nada»
y ninguna pista que apuntara aquí.

### La decisión, y las dos que se descartaron

Gana **Account decide, el pool refleja**. Es lo que el módulo `identity` ya
declaraba de sus grupos —«la fuente de verdad de los roles sigue siendo Account:
aquí solo se refleja la pertenencia para que viaje en el testimonio»—; lo que
faltaba era el código que refleja, y el permiso que lo permite.

Se descartó que **los cuatro servicios preguntaran a Account** el rol en cada
petición: elimina la duplicidad de raíz, pero acopla los cuatro a Account en el
camino caliente y convierte una caída de Account en una caída de la autorización
de todo el sistema.

Un **disparador de Cognito** (*pre token generation*) ni siquiera entró en la
comparación: sería Lambda, que el alcance actual prohíbe sin un ADR que lo
autorice.

### La dirección es de un solo sentido, y el orden importa

`RoleDirectoryPort` refleja hacia el proveedor y nunca lee de él como autoridad.
El reflejo ocurre **antes** de persistir la cuenta: al revés, un fallo dejaría
una cuenta guardada cuyo rol no viaja, e irreparable por reintento porque el
segundo intento chocaría con el correo ya registrado. En este orden lo peor que
puede pasar es un sujeto en el grupo sin cuenta, que no concede nada —toda ruta
protegida resuelve la cuenta desde el sujeto y no la encontraría— y que el
reintento absorbe, porque el reflejo es idempotente.

El adaptador **calcula la diferencia** en lugar de solo añadir: un reflejo que
solo suma no es un reflejo, y revocar un rol nunca llegaría al testimonio. Y solo
toca grupos del vocabulario de roles: reflejar no es apropiarse del pool.

Si el proveedor no responde, el registro **falla cerrado** y devuelve 503 — no
500: el servicio funciona, la dependencia no, y reintentar más tarde tiene
sentido.

### El permiso, y lo que deliberadamente no se concedió

| Acción | Por qué |
|---|---|
| `AdminListGroupsForUser` | Lectura, para calcular la diferencia |
| `AdminAddUserToGroup` | Conceder |
| `AdminRemoveUserFromGroup` | Revocar |

Verificado con `iam simulate-principal-policy`, **con controles negativos**:
`AdminCreateUser`, `AdminDeleteUser` y `CreateGroup` responden `implicitDeny`.
Account dejó de crear identidades y no debe recuperar esa capacidad por la puerta
de atrás; los grupos los declara este repositorio, y que el servicio pudiera
crearlos dejaría a la infraestructura describiendo algo distinto de lo que existe.

**Esto corrige a la baja** lo que se afirmó al retirar la creación de
identidades: que el rol de instancia no necesitaba escritura sobre el pool. No
necesita crear identidades —sigue siendo cierto—, pero gestionar pertenencia a
grupos **es** una escritura, y llamarla de otro modo sería maquillarla.

El límite de topología descrito más arriba aplica igual a estas tres acciones:
cualquier contenedor del nodo `app` puede invocarlas, no solo Account.

### La comprobación

```text
1. grupos ANTES del registro -> (ninguno)
2. registro por la API       -> HTTP 201, roles ["PLAYER"]
3. grupos DESPUES            -> PLAYER

cognito:groups en un testimonio NUEVO -> ["PLAYER"]
```

La última línea es la que cierra el asunto: el testimonio usado para registrar se
emitió *antes* del reflejo, así que solo uno nuevo demuestra que el rol viaja de
verdad.

## El sistema esta expuesto desde el 2026-08-29

`https://nexus.simuladorupbbga.app` sirve desde internet con certificado de
Let's Encrypt (`CN=YE1`, vigente hasta el 27 de noviembre de 2026). El puerto 443
esta abierto a `0.0.0.0/0` y el 80 responde **308** hacia HTTPS: solo redirige.

Comprobado desde fuera: HTTPS valida sin `-k`, `/api/products` responde 200 y
`/api/orders` responde **401**. La autorizacion funciona contra el origen
publico, no solo contra `127.0.0.1`.

**Lo que sigue abierto es el segundo factor**, y con el sistema ya expuesto pasa
a ser lo mas urgente. Ver la seccion siguiente: el codigo esta, las variables no
estan puestas.

## Exponer el sistema: lo que hizo falta, y lo que sigue desaconsejando abrirlo del todo

**Registrado el 2026-08-29.** Abrir `public_ingress_cidrs` era, hasta ahora, una
variable que no habría servido de nada: el grupo de seguridad abre 443 y 80, y el
proxy escuchaba **solo en 8080**. Se habrían abierto dos puertos donde no había
nadie escuchando.

Corregido: el proxy sirve ahora un sitio público en 443, con certificado de la CA
local de Caddy o de Let's Encrypt según se configure un dominio. HTTPS y no HTTP
porque **Cognito rechaza URL de retorno que no sean HTTPS**, salvo `localhost`:
expuesto por HTTP plano, el sistema sería alcanzable y nadie podría iniciar
sesión.

### Lo que desaconseja abrirlo a internet hoy

El pool tiene `mfa_configuration = OPTIONAL` y **ningún usuario tiene segundo
factor configurado**. Quien entra por el hosted UI obtiene un testimonio sin
reto, y si esa cuenta está en `ADMINISTRATOR` los otros cuatro servicios lo
honran: leen el rol de `cognito:groups` y no saben nada de segundos factores.

**El `LoginAccount` que falla cerrado protege la ruta de Account, no ese
camino.** Es una defensa aplicativa sobre un flujo concreto, no sobre el
proveedor.

Forzar el segundo factor para todos (`mfa_configuration = ON`) tampoco vale
mientras SES siga en el entorno de pruebas: los códigos solo llegan a direcciones
verificadas, de modo que dejaría fuera a todos los jugadores. Es exactamente el
«dejaría a todo el mundo fuera» que este ADR ya preveía.

Conclusión, sin adornos: **una cuenta administrativa estaría protegida solo por
contraseña, y el sistema ya está abierto a todo internet.** Se abrió por decisión
del equipo, con este riesgo sobre la mesa y no descubierto después.

### Corrección del 2026-08-29: SES no es el camino corto, y la exposición es latente

Esta sección decía antes que cerrarlo era «poner las tres variables de SES». Al
comprobarlo contra el pool, esa recomendación resultó equivocada en dos puntos.

**Primero, el pool ya tiene un segundo factor aprovisionado y activo:**

```
GetUserPoolMfaConfig(us-east-1_HrEiSzzKW)
  -> {"SoftwareTokenMfaConfiguration": {"Enabled": true},
      "MfaConfiguration": "OPTIONAL"}
```

Y la documentación de AWS es explícita sobre lo que `OPTIONAL` significa:

> If MFA is optional, then MFA is added at the user level. Only users who have
> MFA configured are prompted with an MFA challenge during sign in.

Es decir: **`OPTIONAL` ya produce el comportamiento que ADR-004 quiere.** Reta a
quien tiene factor inscrito y no molesta a los jugadores. Lo que falta no es
configuración del pool ni SES: es que **alguien inscriba el factor** en las
cuentas administrativas. La protección se consigue por inscripción, no por
imposición, y por eso no hay ningún error que delate su ausencia.

**Segundo, hoy no hay nada expuesto.** El pool no tiene ninguna cuenta en
`ADMINISTRATOR` ni en `SUPER_ADMINISTRATOR`. El riesgo es **latente**: aparece en
el momento en que se cree la primera, no antes.

**El control.** `scripts/verificar-segundo-factor-administrativo.py` lista los
miembros de ambos grupos y exige que cada uno tenga un factor **confirmado**
(`UserMFASettingList`, no `MFAOptions`, que está obsoleto y solo refleja SMS).
Como mientras no haya cuentas administrativas la comprobación pasa por ausencia
—y una comprobación que solo sabe pasar no comprueba nada— el guion admite
`GRUPOS_ADMINISTRATIVOS` por entorno para ejercitar el camino de fallo sin tocar
ningún permiso:

```
$ python scripts/verificar-segundo-factor-administrativo.py
  No hay ninguna cuenta administrativa en el pool.        -> salida 0

$ GRUPOS_ADMINISTRATIVOS=PLAYER python scripts/...py
  SIN 2FA  94f884e8-...  [PLAYER]                         -> salida 1
```

**Decisión de producto confirmada el 2026-08-29: TOTP.** La aclaración PO-12
había fijado originalmente el segundo factor **por correo**. Tras contrastar la
limitación de SES y la fuerza de ambos factores, se eligió TOTP. La comparación
que sustentó la decisión queda registrada:

| | TOTP (lo que hay) | Correo (lo que pidió el cliente) |
| --- | --- | --- |
| Requiere `apply` | No, ya está activo | Sí, tres variables de SES |
| A quién protege | A cualquier cuenta | Solo a las 7 direcciones verificadas en SES |
| Fuerza | Mayor: canal distinto del correo | Menor: el correo es también el canal de recuperación |
| Cumple PO-12 | No | Sí |

**Ejecución de la decisión:** inscribir TOTP antes de conceder el primer rol
administrativo. `scripts/inscribir_totp_administrativo.py` mantiene la
contraseña y el código fuera de argumentos y archivos, y el verificador existente
confirma después el factor contra el pool. Añadir correo en el futuro seguiría
siendo compatible, pero exigiría cambiar el módulo, que hoy trata los métodos
como excluyentes mediante un único `mfa_method`.

Mientras no se inscriba ningún factor: **no crear cuentas con rol
administrativo.**

## La URL de retorno ata la exposición a la identidad

**Registrado el 2026-08-29.** Hasta ese día la única URL de retorno registrada en
el cliente de Web era `http://localhost:5173/auth/callback`, de modo que **el
circuito de identidad funcionaba de extremo a extremo solo desde desarrollo
local**. El Web desplegado no habría podido completar el flujo aunque se
expusiera: Cognito habría respondido `redirect_mismatch`.

No daba síntoma porque nada estaba expuesto a internet, y por eso las dos cosas
parecían decisiones independientes. **No lo son.** El día que
`public_ingress_cidrs` dejase de estar vacío, había que añadir el origen
desplegado a `callback_urls` **en el mismo cambio**, o el inicio de sesión se
rompería la primera vez que alguien lo usara.

**Resuelto el mismo día**, y comprobado contra el cliente desplegado:

```
callbacks: ["http://localhost:5173/auth/callback",
            "https://nexus.simuladorupbbga.app/auth/callback"]
logout:    ["http://localhost:5173/",
            "https://nexus.simuladorupbbga.app/"]
```

La URL pública se **deriva** de `public_site_address` en `envs/prod/main.tf`, no
se escribe a mano. Es lo que impide que vuelvan a separarse: no se puede fijar un
dominio sin registrar su retorno.

## Decisión de proveedor: Amazon Cognito, plan Essentials

Opciones evaluadas, con precios reales de la Price List API en `us-east-1` al 2026-08-25:

| Opción | Coste real | Veredicto |
| --- | --- | --- |
| **Cognito user pool, plan Essentials** | 0,015 USD/MAU | **Seleccionada** |
| Cognito user pool, plan Lite | 0,0055 USD/MAU | Descartada: no incluye MFA por correo |
| Cognito user pool, plan Plus | 0,020 USD/MAU | Descartada: su valor añadido es protección frente a amenazas, que no es el problema a resolver |
| IdP autoalojado en la misma EC2 | Solo cómputo ya presupuestado | Descartada: añade custodia de credenciales, justo lo que este ADR evita |
| Managed Microsoft AD | Varias veces el techo mensual completo | Descartada por coste |

### Resuelto el 2026-08-29, con un limite que hay que decir entero

El pool ya puede usar el correo como segundo factor: emisor `DEVELOPER` sobre la
identidad verificada `nexusbattle67@gmail.com`, en la misma region. Cognito crea
por su cuenta el rol vinculado al servicio; no hace falta politica de
autorizacion de envio en la identidad porque esta en la misma cuenta.

Y hay una precondicion que hace fallar el **plan**, no el apply, si alguien pone
`mfa_method = "email"` sin identidad: sin ella el error llegaba desde AWS
describiendo el sintoma en lugar de la causa.

**El limite: SES esta en el entorno de pruebas, y la solicitud para salir de el
fue DENEGADA** (caso 178781013000904). En ese entorno solo se puede escribir a
direcciones ya verificadas.

Consecuencia practica, dicha sin adornos: **el segundo factor por correo funciona
para las cuentas administrativas cuyo correo este verificado en SES, y para nadie
mas.** Es suficiente para lo que el requisito pide -el segundo factor es de
`ADMINISTRATOR` y `SUPER_ADMINISTRATOR`, que son cuentas contadas- pero no es un
flujo que pueda ofrecerse a cualquier usuario. Prometerlo sin esta frase seria
prometer algo que no ocurre.

Ampliarlo exige que AWS conceda el acceso de produccion, que ya nego una vez. Eso
es una gestion, no un cambio de codigo.

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

Volver al correo sería una nueva decisión: exige aprovisionar SES y cambiar
`mfa_method = "email"`. No forma parte del cierre actual, que mantiene TOTP.

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

- ~~El sistema **no es desplegable públicamente** hasta completar los pasos 2 a 5.~~ **Superado**: los pasos 3, 4, 5 y 6 están hechos y el 2 se retiró. Lo que queda para exponerlo no es identidad: es la decisión de `public_ingress_cidrs` y, atada a ella, la URL de retorno (ver más arriba).
- Cognito **no es un Directorio Activo**. Es un IdP con OIDC. El requisito literal de directorio corporativo sigue sin cumplirse, y esta decisión no lo disimula.
- El requisito de Directorio Activo queda sin cumplir, con su justificación de coste registrada.

## Evidencia

- `Nexus-Battle-Account` no contiene ningún campo de contraseña, hash ni secreto en su agregado.
- ~~`FakeIdentityProvider` implementa el contrato completo de `IdentityProviderPort`.~~ **Ambos eliminados el 2026-08-29.** Los dobles vigentes son `FakeAuthenticationProvider` e `InMemoryRoleDirectory`.
- ~~`RegisterAccount` compensa el alta de identidad si falla la persistencia.~~ **Ya no hay alta que compensar**: el caso de uso no crea identidades. Lo único que compensa es el avatar.
- `RegisterAccount` refleja el rol en el proveedor **antes** de persistir, y falla cerrado (503) si no puede. Comprobado con un control: invirtiendo ese orden, la prueba que lo fija falla.
- El registro exige un sujeto ya verificado; sin él responde 401, no 500.
