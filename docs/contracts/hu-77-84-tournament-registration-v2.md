# HU-77/HU-84 — Registro y confirmación de cupo, revisión 2

Versión común: `torneos-hu77-84-78-hu83-v2.0.0`.
Estado: especificación técnica para implementación local; revisión entre responsables y aceptación funcional pendientes.
Fuentes vigentes: [HU-77 #467](https://github.com/Nexus-Battle-VI/Nexus-Battle-Management/issues/467) y [HU-84 #468](https://github.com/Nexus-Battle-VI/Nexus-Battle-Management/issues/468). Propiedad de datos: ADR-022.

## Decisiones de alcance y cambios frente al prototipo

El usuario confirmó en esta coordinación: el creador administra y paga; el compañero acepta desde su sesión; cualquiera puede cancelar antes del pago; sustituir integrantes requiere cancelar y registrar de nuevo. También confirmó créditos y pago simulado según configuración, importes independientes sin conversión, y compensación automática de cobros sin cupo. Cancelar/devolver una inscripción ya confirmada queda fuera de este incremento.

El usuario eligió reutilizar la identidad existente: validación del nombre y avatar de uno de los integrantes, sin añadir carga de imágenes. No se atribuye a estas decisiones aceptación del Product Owner ni aprobación de consumidores.

Cambios explícitos del contrato local v1, aún no publicado: se añade pago simulado, se sustituye `ORBIT|BOLT|SHIELD` por una referencia al avatar existente, se usa la política de nombre de Account en vez de 1–32 caracteres, se separan recibos y se fija una política de pago tipada. Las fuentes originales y sus pruebas se conservan; sus DTOs/tests deben adaptarlos sus propietarios, no pegarse sobre `develop`.

## Identidad, miembros y consentimiento

Dos sujetos de Account distintos; `ownerId` sale del JWT y `companionId` identifica al otro jugador. No son IDs internos de filas de Account. Account confirma que ambos existen, están `ACTIVE` y tienen rol `PLAYER`. Se revalida al registrar, aceptar y comenzar un intento nuevo de confirmación. Un equipo activo por jugador y torneo, protegido también por PostgreSQL.

El nombre se normaliza con la política existente `DisplayName` de Account: trim, espacios consecutivos reducidos a uno, 3–32 caracteres, inicio/fin con letra o número Unicode; en el interior letras, números, espacio, `_`, `.` y `-`. Se consulta su lista vigente de nombres bloqueados. No se aplica a equipos la unicidad global de nicknames de cuentas: ese requisito no figura en HU-77.

`TeamAvatar = {kind:'ACCOUNT_AVATAR',subject:string}`. El sujeto debe ser `ownerId` o `companionId` y tener avatar existente validado por Account. Tournament conserva la referencia, no bytes, URLs S3 ni claves de almacenamiento. Web utiliza con JWT la ruta ya publicada `GET /api/accounts/by-subject/:subject/avatar`, descarga la imagen y maneja su ausencia/error explícitamente. Ningún emblema local acredita ahora la política de HU-01.

El avatar se hereda de la cuenta seleccionada: si esa cuenta cambia su imagen, la referencia del equipo continúa apuntando al mismo sujeto. No se promete una copia inmutable de los bytes. Una imagen ausente en una lectura posterior no se sustituye por una imagen inventada ni modifica un pago ya confirmado; la UI muestra que no está disponible. La validación de nuevas operaciones sigue usando la política vigente de Account.

Nombre normalizado, referencia de avatar e integrantes quedan inmutables en el registro. El creador consiente al registrar y se guarda su sujeto, instante de servidor y versión `team-registration-v2`. El compañero consiente sobre ese mismo contenido desde su propia sesión; se guardan sujeto, instante y versión. Rechazar cancela el registro y libera pertenencias activas. No se permite aceptar en nombre del compañero ni editar después el contenido consentido.

Héroes y loadouts no se seleccionan ni se inventan en HU-77. Su resolución autoritativa corresponde a la preparación HU-85/Combat; no se exige un héroe para afirmar que se registró un equipo.

## Account — consultas internas nuevas

Ambas rutas usan el HMAC existente y permiten exclusivamente el caller `tournament` por ruta; el JWT del navegador no concede acceso interno. Caddy mantiene bloqueado `/api/internal*`. No se amplían privilegios globales sobre otras rutas de Account.

| Ruta | Entrada | Salida 200 y validaciones |
| --- | --- | --- |
| `GET /api/internal/accounts/:subject/tournament-eligibility` | Sujeto de identidad | `{subject,displayName,eligible}`; `eligible` solo si ACTIVE y PLAYER; no correo, nombre legal ni lista de roles |
| `POST /api/internal/accounts/tournament-team-identity/validation` | `{name,avatarSubject}` | `{name,avatar:{kind:'ACCOUNT_AVATAR',subject},policyVersion:'account-team-identity-v1'}`; normalización/validación de nombre, blacklist y avatar recuperable existentes |

La segunda ruta es una validación sin escrituras: reutiliza las políticas/repositorios actuales, no registra cuentas ni sube archivos. Tournament comprueba además que `avatarSubject` pertenece a los dos miembros del equipo. Esto evita copiar y divergir de la política de Account o confundir un avatar preset con uno existente. Es una extensión técnica de la entrega Account: aún no está implementada en su `develop`.

Cuenta inexistente: 404. Identidad de equipo inválida: 422 `{code:'INVALID_TEAM_NAME'|'INVALID_TEAM_AVATAR',message}`. Dependencia de almacenamiento no disponible: 503, no un avatar falsamente válido. La ruta de elegibilidad conserva sus errores existentes. Un timeout no se interpreta como cuenta inelegible comprobada ni permite registrar.

## Política de métodos e importes

Cada torneo tiene `entryPolicy` inmutable; se devuelve antes de confirmar. Se distinguen:

```ts
type EntryPolicy =
  | { version: 1; free: true; methods: [] }
  | {
      version: 1; free: false;
      methods: Array<
        | { method: 'CREDITS'; amount: number }
        | { method: 'SIMULATED_MONEY'; amountMinor: number; currency: string; minorUnit: number }
      >
    }
```

En pago: uno o ambos métodos configurados, sin duplicados. Cada importe es un entero positivo seguro. Los créditos son unidades de crédito; `amountMinor` son unidades menores de la moneda **configurada** y `minorUnit` es su precisión decimal explícita (entero de 0 a 6, sin usarlo como tasa). La moneda es un código configurado de tres letras mayúsculas. Las conversiones automáticas no existen. No se fijan valores de producción, moneda por país, tasas o equivalencias entre ambos precios.

Gratis se configura con `free:true`; no se llama a Wallet ni a la pasarela y no se crea un cobro simulado de cero. Si se conserva el campo local `entryFee`, es una proyección del importe CREDITS, 0 para gratuito o `null` para un torneo solo simulado; no es la autoridad de precio. La creación antigua con `entryFee` se puede aceptar como compatibilidad explícita: 0 deriva gratuito y positivo deriva únicamente CREDITS. No se acepta `entryFee` y `entryPolicy` simultáneamente. El administrador debe configurar dinero simulado de manera explícita.

## API pública y DTO de registro

Todas las rutas requieren JWT y la identidad proviene del token verificado. Registro/consentimiento/cancelación/pago requieren jugador; el servidor comprueba pertenencia y función del actor. Crear/publicar usa las guardas administrativas actuales.

| Ruta | Cuerpo | Resultado |
| --- | --- | --- |
| `GET /api/v1/tournaments` | Ninguno | Array de `PublicTournament`; no equipos pendientes ajenos ni saldos |
| `GET /api/v1/tournaments/:id/registration` | Ninguno | `{tournament:PublicTournament,capacity:{confirmed,reserved,available},teams:TeamRegistration[]}` solo con los equipos del actor |
| `POST /api/v1/tournaments/:id/teams` | `{operationId,name,avatar:TeamAvatar,companionId}` | 200 `TeamRegistration` AWAITING_CONSENT con comprobante de registro, sin cupo/pago |
| `POST /api/v1/tournaments/:id/teams/:teamId/consent` | `{operationId,accept:boolean}` | 200 `TeamRegistration`; solo compañero; aceptar → PENDING_PAYMENT, rechazar → CANCELLED |
| `POST /api/v1/tournaments/:id/teams/:teamId/cancel` | `{operationId}` | 200 `TeamRegistration`; cualquiera de los dos, solo antes de iniciar/confirmar pago |
| `POST /api/v1/tournaments/:id/teams/:teamId/entry` | `{operationId,method?,card?}` | 200 `TeamRegistration`; solo creador; CONFIRMED o estado pendiente comprobado; rechazo conocido devuelve su error durable |
| `POST /api/v1/tournaments/admin` | `{operationId,name,entryPolicy,opensAt,closesAt,startsAt}` o forma antigua de `entryFee` exclusiva | 200 `PublicTournament`; ID generado por servidor; replay conserva ese ID |

`PublicTournament`: `id,name,entryPolicy,entryFee,opensAt,closesAt,startsAt,bracketPublished,open`. `open` se calcula en servidor por periodo y ausencia de bracket publicado. Ocupación no implica que un registro pendiente ya tenga plaza. `reserved` cuenta PAYMENT_PENDING/COMPENSATING; `available = 8 - confirmed - reserved`.

`TeamRegistration`: `id,tournamentId,name,avatar,ownerId,companionId,status,createdAt,consentAt,consentVersion,slot,confirmedAt,registrationReceipt,entryReceipt,failure`. Fechas ISO UTC; valores aún inexistentes son `null`. `failure` es `null` o `{code,message}` seguro para UI, no una excepción de proveedor. Las intenciones internas, tarjeta y JWT no se devuelven. Cada mutación devuelve este mismo DTO.

En `/entry`, `method` es obligatorio si hay dos métodos pagados. La forma anterior sin método solo se acepta para gratis o para el único método CREDITS. Dinero simulado requiere selección explícita y, para un intento nuevo, `card:{holder,number,expiry,securityCode}`. Un replay ya resuelto no exige reenviar datos sensibles. El cliente nunca envía importe, moneda, cupo, pagador o estado como autoridad; esos campos extra se rechazan.

Los identificadores de operación son texto no vacío de hasta 100 caracteres. La huella de intención incluye actor, acción, torneo/equipo y valores de negocio normalizados. El namespace de registro/pago/bracket es `(tournamentId,operationId)`; crear torneo tiene un registro administrativo separado. Mismo ID/intención recupera el registro/resultado durable; otra intención da 409 `OPERATION_CONFLICT`. La autorización se verifica antes de revelar un replay. Rechazos definitivos de pago son inmutables: corregir saldo/tarjeta usa **otro** operationId; no se cambia el desenlace del anterior.

## Recibos y estados

`RegistrationReceipt = {id,kind:'TEAM_REGISTRATION',tournamentId,teamId,memberIds,registeredAt,status:'REGISTERED'}`. Se emite una vez por registro válido y se recupera en reintentos. No acredita pago o cupo, incluso cuando después exista una confirmación. Rechazos de registro no emiten un comprobante válido.

`EntryReceipt` solo existe si hubo confirmación: `{id,kind:'ENTRY_CONFIRMATION',tournamentId,teamId,slot,confirmedAt,payment}`. `payment` es una de estas variantes, siempre con `payerId` igual al creador y `realMoneyMoved:false`:

- `{method:'FREE',amount:0,chargeId:null}`: confirmación gratuita, sin afirmar pago financiero.
- `{method:'CREDITS',amount,chargeId}`: identifica el cobro durable de Wallet.
- `{method:'SIMULATED_MONEY',amountMinor,currency,minorUnit,chargeId,reference,maskedCard,simulated:true}`: identifica el pago simulado aprobado; `maskedCard` contiene como máximo los últimos cuatro dígitos o el marcador enmascarado de la política HU-59.

No se crea `EntryReceipt` en PAYMENT_PENDING, COMPENSATING o rechazo. Los identificadores de recibo, equipo y cobro los genera/deriva el servidor y permanecen estables. Ningún comprobante de cobro compensado autoriza mostrar un cupo confirmado.

| Estado | Plaza | Transición permitida |
| --- | --- | --- |
| AWAITING_CONSENT | Ninguna | Aceptación del compañero → PENDING_PAYMENT; rechazo/cancelación → CANCELLED |
| PENDING_PAYMENT | Ninguna | Intento con consentimiento y periodo/capacidad válida; gratis → CONFIRMED; créditos → PAYMENT_PENDING; simulado se resuelve en transacción local |
| PAYMENT_PENDING | Reserva 1–8 | CHARGED y condiciones vigentes → CONFIRMED; rechazo definitivo → PENDING_PAYMENT sin plaza; cobro sin inscripción válida → COMPENSATING |
| COMPENSATING | Conserva reserva | REFUNDED comprobado → PENDING_PAYMENT sin plaza y sin recibo de confirmación; timeout conserva estado |
| CONFIRMED | Cupo confirmado | Replay devuelve misma confirmación; no admite nueva edición/pago/cancelación en este alcance |
| CANCELLED | Ninguna | Histórico inmutable; pertenencias liberadas; un nuevo equipo necesita registro/consentimiento nuevos |

## Wallet — créditos, contrato conservado

HMAC existente, caller exclusivo `tournament`, rutas internas bloqueadas por el proxy público.

- `POST /api/internal/v1/wallet/tournament-entry-fees`: `{operationId,payerId,tournamentId,teamId,amount}`; importe positivo entero seguro. Devuelve `{operationId,chargeId,payerId,tournamentId,teamId,amount,status:'CHARGED'|'REFUNDED',applied:boolean}`. Se valida toda la tupla, no solo `chargeId/status`, antes de confirmar.
- `POST /api/internal/v1/wallet/tournament-entry-fees/:chargeId/refunds`: `{operationId}`. Mismo DTO con `status:'REFUNDED'`; el pagador/importe se derivan del cobro guardado, nunca del cuerpo de devolución. El eco `operationId` corresponde a esa operación; el ID de cobro permanece igual.

Descontar solo `available`, sin tomar créditos reservados; movimiento de ledger y cobro en una transacción de Wallet. Replays no mueven saldo otra vez. Un cobro devuelto no se reactiva y su replay devuelve REFUNDED. Saldo insuficiente: 422 `INSUFFICIENT_BALANCE`, rechazo REJECTED persistido sin movimiento; repetir el ID conserva ese rechazo aunque después llegue saldo. Cobro inexistente: 404 `CHARGE_NOT_FOUND`; intención distinta: 409 `OPERATION_CONFLICT`.

Wallet conserva el comportamiento recién publicado de balances en medios créditos y devoluciones parciales de subasta; que **esta tarifa** sea entera no permite volver a restringir todo el saldo a enteros. La migración de tarifas se reserva como `008-wallet-tournament-entry-fees`; no se reemplaza la `007` publicada.

## Pago simulado local

Se reutiliza la política/formato de `SimulatedPaymentGateway` de Commerce `a8b4e4738f265b1db14c54b345782f9dc243c05d`: cuatro campos obligatorios, rechazo reproducible para número terminado en `0000`, referencia estable `sim-<transactionId>`, tarjeta enmascarada. No se llama al carrito, no se conecta un proveedor financiero y no se inventan validaciones de banco/marca/Luhn. Web identifica claramente el pago como simulado.

La memoria `approved` del gateway no es la persistencia autoritativa de Tournament. Se usa una decisión local sin red/efectos financieros: bloqueo de plaza, decisión, referencia/resultado saneado, inscripción/recibo y liberación si se rechaza se guardan en una sola transacción. Los datos de tarjeta solo existen en memoria de la petición. No se guardan completos, cifrados, en hashes de intención, logs, outbox ni respuestas; no se guarda un CVV. La redacción de observabilidad incluye este cuerpo.

Una caída antes del commit no deja un pago financiero ni una aprobación parcial durable; el usuario puede reenviar. Tras el commit, el resultado saneado y la confirmación/rechazo se recuperan por operationId sin volver a decidir con otra tarjeta. No se necesita un reconciliador que recupere tarjetas. Si se separa el simulador a otro proceso en el futuro, cambia el contrato de recuperación y debe coordinarse antes de implementarlo.

## Cupos, incertidumbre y compensación

Todas las confirmaciones, de ambos métodos y gratuitas, compiten por las mismas ocho plazas mediante bloqueo de la fila del torneo y unicidad de slot 1–8. Las pertenencias activas tienen unicidad `(torneo,jugador)` y FK al equipo. Una reserva de pago sigue consumiendo plaza hasta conocer rechazo o devolución. No se permite intentar otro método u otra intención mientras la anterior esté pendiente/compensándose.

Para créditos se persiste PAYMENT_PENDING y su intención antes de llamar a Wallet, sin mantener una transacción SQL abierta durante la red. ID de cobro: `entry:{teamId}:{operationId}:charge`; devolución: mismo prefijo con `:refund`. Un reconciliador retoma intenciones pendientes tras reinicio con los mismos IDs.

Timeout/503 significa efecto incierto. Se recupera el mismo cobro, nunca se interpreta automáticamente como saldo insuficiente ni se crea otro ID. Una respuesta 409 contractual queda pendiente de revisión/recuperación con su intención original, sin autorizar otro cobro. Rechazos definitivos documentados liberan la reserva; incertidumbre no.

Si el periodo cierra o falla la confirmación después de un CHARGED comprobado, pasa a COMPENSATING; la devolución idempotente debe confirmarse antes de liberar la plaza. Si todavía se desconoce el cobro, primero se recupera mediante replay. Un REFUNDED recuperado nunca confirma cupo. El fallo después de devolver se recupera también sin duplicar la devolución. La simulación registra su compensación lógica local sin dinero real si no puede confirmar; ningún método deja un cobro definitivo sin inscripción válida.

Confirmar y publicar bracket usan el mismo bloqueo de torneo. Ocho plazas ocupadas por pendientes no son ocho confirmaciones para HU-78. Crear torneo aplica la regla global de 91 × 24 horas de [HU-78](hu-78-tournament-bracket-v2.md), con exclusión persistente y replay administrativo, no solo memoria.

## Errores y evidencia requerida

Formato: 400 de la validación HTTP; sesión: 401; actor/función no permitido: 403. Negocio `{code,message}`: 404 `TOURNAMENT_NOT_FOUND`/`TEAM_NOT_FOUND`; 409 `REGISTRATION_CLOSED`, `CAPACITY_EXHAUSTED`, `ALREADY_REGISTERED`, `CONSENT_REQUIRED`, `INVALID_TEAM_STATE`, `OPERATION_CONFLICT`, `CALENDAR_CONFLICT`; 422 `INVALID_PLAYER`, `INVALID_TEAM_NAME`, `INVALID_TEAM_AVATAR`, `INVALID_CONFIGURATION`, `INVALID_OPERATION`, `PAYMENT_METHOD_NOT_CONFIGURED`, `INSUFFICIENT_BALANCE`, `SIMULATED_PAYMENT_DECLINED`; dependencia incierta 503 sin afirmar rechazo definitivo. Los errores de Wallet/Account se traducen sin exponer datos internos.

Se deben probar registro/consentimiento e identidad reales, replays, autorización, gratis sin llamadas, créditos y simulador, moneda/unidades/importe del servidor, rechazo de tarjeta, último cupo mixto concurrente, saldo disponible/reservado, cierre, caídas y recuperación tras débito/devolución, privacidad y persistencia con motor real. Los valores 100 créditos y saldos 120/99 son **datos propuestos de prueba de HU-84**, no tarifas o balances reales. Web requiere dos sesiones Cognito reales y administrador para la evidencia integrada. Las suites históricas, compilar o tener tests verdes no cierran estas historias.
