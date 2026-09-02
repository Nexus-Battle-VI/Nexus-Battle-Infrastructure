# HU-04 — Matriz de trazabilidad y verificación local

- **Issue central:** [Nexus-Battle-VI/Nexus-Battle-Management#13](https://github.com/Nexus-Battle-VI/Nexus-Battle-Management/issues/13)
- **Diseño:** [HU-04 — Diseño de recuperación de contraseña](../architecture/hu-04-recuperacion-contrasena.md)
- **Fecha de la verificación:** 2026-08-31
- **Ambiente:** local — `PERSISTENCE_DRIVER=memory`, `AUTHENTICATION_DRIVER=fake` (Account); `EMAIL_DRIVER=smtp` con un proveedor SMTP real (Notifications)
- **Build verificado:** ramas sin mergear —
  `Nexus-Battle-Account@feat/hu-04-recuperacion-contrasena`,
  `Nexus-Battle-Web@feat/hu-04-recuperar-contrasena`,
  `Nexus-Battle-Notifications@feat/hu-04-plantillas-recuperacion`
- **Estado:** verificación local completa; **pendiente** un recorrido contra un
  pool de Cognito real y contra un entorno desplegado (ver «Riesgo residual»)

Esta es una verificación **previa al PR**, no evidencia de producción: no hay
despliegue, no hay digests de contenedor y no se afirma nada sobre un ambiente
que no existe todavía. Se corrigió deliberadamente para no repetir el patrón
de otras HUs cuya evidencia sí describe producción.

## Matriz de trazabilidad (RF-04)

| CA | Escenario | Datos | Resultado esperado | Tipo | Script |
| --- | --- | --- | --- | --- | --- |
| CA-01 | Cuenta con preguntas configuradas responde correctamente | Cuenta de prueba, 4 respuestas correctas | Avanza a `QUESTIONS_VERIFIED`, se emite el código | Unitaria, integración, componente | Account `test/unit/password-recovery.spec.ts` (*recorre los cuatro pasos...*), `test/integration/recovery-http.spec.ts` (*completa el flujo de cuatro pasos...*); Web `RecoveryPage.test.tsx` (*recorre los cuatro pasos...*) |
| CA-02 | Correo no registrado, o respuestas incorrectas de una cuenta real | Correo inexistente; o 4 respuestas erróneas | Rechazo genérico, no revela si la cuenta existe, no avanza | Unitaria, integración, componente | Account `password-recovery.spec.ts` (*el correo desconocido...*, *rechaza respuestas incorrectas...*), `recovery-http.spec.ts` (*un correo inexistente no se distingue...*); Web `RecoveryPage.test.tsx` (*no avanza si las respuestas son rechazadas*) |
| CA-03 | Intento de restablecer sin validar el código (saltar etapa) | Token en `QUESTIONS_VERIFIED`, llamada directa a `/password` | Rechazo genérico | Unitaria, integración | Account `password-recovery.spec.ts` (parte final de *rechaza respuestas incorrectas...*), `recovery-http.spec.ts` (*no permite saltar al cambio de contraseña*) |
| CA-04 | Al validar preguntas, se solicita el envío del código a HU-55 | `templateId=account-password-recovery-code` | `NotificationRequestPort.request` se invoca con la plantilla correcta | Unitaria, integración, manual | Account `password-recovery.spec.ts` (assert `notifications[0].templateId`); Notifications `tests/unit/adapters/adapters.test.ts` (render de la plantilla); envío SMTP real verificado manualmente (ver abajo) |
| CA-05 | Código incorrecto | `'111111'` contra un desafío real | Rechazo genérico, no avanza | Unitaria | Account `password-recovery.spec.ts` (*rechaza respuestas incorrectas y un código ya gastado...*) |
| CA-06 | Reutilizar un código ya validado | Mismo `challengeToken` y código, tras completar el flujo | Rechazo — el código consumido no vuelve a servir | Unitaria | Account `password-recovery.spec.ts` (última aserción del flujo feliz) |
| CA-07 | Ambas validaciones superadas | Flujo feliz completo | El desafío llega a `CODE_VERIFIED`; `/password` acepta | Unitaria, integración | Mismos scripts del flujo feliz (CA-01) |
| CA-08 | Contraseña nueva válida | `'NuevaClave9!'` | Credencial actualizada; login con la nueva funciona, con la anterior falla | Unitaria, integración, manual | Account `password-recovery.spec.ts` (login tras reset); `recovery-http.spec.ts`; recorrido manual en navegador (ver abajo) |
| CA-09 | Tras éxito, se solicita la confirmación a HU-55 | `templateId=account-password-reset-confirmation` | `NotificationRequestPort.request` se invoca | Unitaria, integración, manual | Account `password-recovery.spec.ts` (assert `notifications[1].templateId`); Notifications `adapters.test.ts`; envío SMTP real verificado manualmente |

Reglas transversales, no ligadas a un único CA:

| Regla | Verificación | Script / evidencia |
| --- | --- | --- |
| El código nunca se registra en claro | Inspección del log estructurado durante el recorrido manual: el evento `recovery_otp_issued` solo lleva `templateId`, sin `code` | Manual (ver abajo); `src/application/use-cases/VerifyRecoveryAnswers.ts` |
| El código nunca se devuelve en una respuesta de API | Ninguna respuesta HTTP de `/accounts/recovery/*` incluye `code` en el cuerpo | Account `recovery.controller.ts` (contrato), `recovery-http.spec.ts` |
| El enunciado de la pregunta permanece visible si la respuesta queda vacía | Regresión del defecto reportado durante la sesión anterior | Web `RecoveryPage.test.tsx` (*deja visible el enunciado si una respuesta queda vacía*) |
| Responsividad 1360×768 sin desbordamiento horizontal | `document.documentElement.scrollWidth === window.innerWidth === 1360` | Manual, navegador real (ver abajo) |
| Mensajes de error genéricos, sin distinguir el motivo | Un solo mensaje (`RECOVERY_MESSAGES.rejected`) para respuesta incorrecta, código incorrecto y etapa saltada | Web `validation.test.ts`, `RecoveryPage.test.tsx` |

## Recorrido manual (navegador real)

Contra Account (`memory`/`fake`) y Web, con una cuenta de prueba registrada
para esta verificación:

1. Registro y confirmación de la cuenta de prueba → `ACTIVE`.
2. `/recover`, paso 1: correo de la cuenta → 4 preguntas, mismo catálogo que
   mostraría un correo inexistente.
3. Paso 2: respuestas correctas → avanza; se confirmó en el log que
   `recovery_otp_issued` **no** lleva el código.
4. Paso 3: código `000000` (fijo, sin proveedor de identidad configurado) →
   avanza.
5. Paso 4: `NuevaClave9!` → `Contraseña actualizada`.
6. Login con la nueva contraseña → `AUTHENTICATED`.
7. Viewport a 1360×768: sin scroll horizontal.

Adicionalmente, con Notifications corriendo en modo `EMAIL_DRIVER=smtp`
contra un proveedor real, se disparó el mismo flujo desde una cuenta de
prueba con dominio inexistente. El correo se generó con el asunto, el
formato y el código esperados — solo rebotó por el dominio de prueba, lo cual
confirma que la plantilla y el transporte SMTP funcionan de punta a punta sin
depender del entorno de pruebas del equipo.

## Totales de esta ejecución

| Repositorio | Suite | Resultado | Cobertura |
| --- | --- | --- | --- |
| Account | `npm test` (unit + integration) | **353 / 353** | 91% statements, 82% branches |
| Web | `npm test` | **326 / 326** | — (sin umbral configurado en este repo) |
| Notifications | `npm run test:coverage` | **137 / 137** | 99% statements, 96% branches |

Bloqueadas o no ejecutadas en este entorno:

- `Account/test/db/postgres-recovery-challenge-repository.spec.ts` — necesita
  Docker (testcontainers), no disponible en esta máquina.
- Verificación contra un **pool de Cognito real** (`AdminSetUserPassword` vía
  `CognitoIdentityPasswordReset`, y el código aleatorio de `RandomRecoveryOtp`
  bajo ese driver) — cubierta con pruebas unitarias que interceptan el SDK de
  AWS, no ejercitada contra un pool real; no hay credenciales de AWS en este
  entorno.
- Recorrido humano contra un ambiente desplegado — no hay despliegue de HU-04
  todavía.

## Defectos encontrados y corregidos durante esta revisión

| Defecto | Severidad | Corrección |
| --- | --- | --- |
| El código de recuperación se registraba en claro en el log estructurado | Alta (seguridad) | Se retiró el campo `code` del evento `recovery_otp_issued`. |
| El código era fijo (`000000`) incluso con proveedor de identidad real configurado | Alta (seguridad) | `RandomRecoveryOtp`, activado automáticamente cuando hay Cognito configurado. |
| El paso final de cambio de contraseña fallaba siempre con Cognito real (adaptador ausente) | Alta (funcional) | `CognitoIdentityPasswordReset` sobre `AdminSetUserPassword`. |
| El proceso de recuperación no tenía persistencia real, solo memoria | Media (completitud) | `PostgresRecoveryChallengeRepository` + migración `hu04-recovery-challenges`. |
| `lint`/`typecheck`/`format:check` fallaban en Account y Web sobre el código de HU-04 | Media (calidad) | Corregidos; las cuatro verificaciones quedan en verde en ambos repos. |

## Riesgo residual

- El adaptador de Cognito para el restablecimiento y el generador de código
  aleatorio están probados solo con dobles del SDK de AWS, no contra un pool
  real. Es el mismo nivel de cobertura que ya tienen los adaptadores Cognito
  equivalentes de HU-02/HU-39 en este repositorio antes de su propio
  recorrido humano.
- La persistencia PostgreSQL de `recovery_challenges` sigue exactamente el
  patrón de `PostgresAccountRepository`/`PostgresNicknameBlacklist`, pero no
  se ejecutó contra un motor PostgreSQL real en este entorno.

## Recomendación

Apta para abrir Pull Request y revisión de Team Beta. **No** apta para cerrar
la HU-04 hasta completar un recorrido humano contra Cognito real y un
entorno desplegado, según la Definition of Done que ya usa este proyecto
para historias equivalentes (HU-39).

---

# Verificación contra PRODUCCIÓN — 2026-09-01

Esta sección la añade una verificación posterior, ejecutada contra el entorno
desplegado. Responde en parte a lo que la sección anterior dejaba como
pendiente («recorrido humano contra un ambiente desplegado»), y **encuentra un
bloqueo duro que impide completarlo**.

- **Ambiente:** `https://nexus.simuladorupbbga.app` (nodo `app`, `us-east-1`)
- **Account:** `ghcr.io/nexus-battle-vi/nexus-battle-account@sha256:92503aaa5a14f18db9dcd9e0392a031dfacc63852e662a61cbd326e30339fcbc`
- **Notifications:** `ghcr.io/nexus-battle-vi/nexus-battle-notifications@sha256:d7766a12e8f969e03299e2ab09972c1cccf058cf54f27ec847ff62d9d5be2541`
- **Drivers reales:** `AUTH_MODE=jwt` contra el pool `us-east-1_HrEiSzzKW`;
  `recovery_otp` con `driver=aleatorio` (confirmado en el log del contenedor)

## Lo que SÍ queda verificado en producción

| # | Comprobación | Resultado | Control que la respalda |
| --- | --- | --- | --- |
| 1 | Las cuatro rutas de recuperación están registradas | `POST` con cuerpo vacío → **400** en las cuatro | Una ruta hermana inexistente devuelve **404**, así que el 400 es validación real y no un comodín |
| 2 | CA-02 — no hay enumeración de cuentas | Correo existente y correo inexistente devuelven **la misma forma**: `challengeToken` + las mismas 4 preguntas | Los dos cuerpos se compararon en la misma ejecución |
| 3 | CA-02 — rechazo genérico | Respuestas incorrectas sobre cuenta real, sobre cuenta inexistente y con token inventado: **las tres respuestas byte a byte idénticas** (400, mismo mensaje) | El propio contraste entre los tres casos |
| 4 | CA-01 y CA-04 — el flujo avanza y pide el envío | En el log de Account: `recovery_otp_issued` seguido de `notification_requested` con `templateId=account-password-recovery-code` | `VerifyRecoveryAnswers` solo alcanza esas líneas tras superar todas las guardas, así que su presencia prueba que unas respuestas correctas fueron aceptadas para una cuenta real |
| 5 | El código nunca se registra en claro | `recovery_otp_issued` lleva solo `templateId`; `notification_requested` lleva `notificationId`, `templateId` y **el dominio**, nunca la dirección completa ni el código | Inspección directa del log del contenedor desplegado |
| 6 | `driver=aleatorio` en producción | El log de arranque lo declara | Confirma que `RandomRecoveryOtp` está activo, no el fijo `000000` |

**El punto 4 es el hallazgo importante:** la cadena funciona de extremo a
extremo *dentro de Account*. El fallo no está en la lógica de HU-04.

## El bloqueo: los pasos 3 y 4 NO se pueden verificar hoy

**No existe ninguna forma de obtener el código en producción.** No es una
dificultad operativa; es una consecuencia del diseño, y es correcta:

1. El código se genera con `RandomRecoveryOtp` (CSPRNG, seis dígitos).
2. Se guarda **hasheado**: `markQuestionsVerified(hashSecurityAnswer(code))`.
   En PostgreSQL no hay texto claro que leer.
3. Se entrega únicamente a `NotificationRequestPort`, y el adaptador activo es
   `LoggingNotificationRequester`, que **registra metadatos y descarta las
   variables**. El código no llega al log.

En claro, el código existe solo en memoria durante la petición.

> Una nota para quien retome esto: la idea de «sacar el código del log por SSM»
> **no funciona**, aunque parezca lo obvio. Se comprobó y el log no lo lleva.

### Por qué el código no sale de Account: el transporte no existe

Verificado desde los dos extremos, no supuesto:

| Extremo | Comprobación | Resultado |
| --- | --- | --- |
| Emisor | `NOTIFICATIONS_INGEST_URL` en el contenedor de Account | **No definido** → se selecciona `LoggingNotificationRequester` |
| Receptor | Servidor HTTP de Notifications (puerto `HEALTH_PORT=3001`) | `POST` a `/`, `/notifications`, `/ingest`, `/notifications/ingest` → **405 `method_not_allowed`** en las cuatro. **Salvedad importante: `POST /dev/enqueue` SÍ responde 202** — ver la sección siguiente |
| Receptor | Control positivo | `GET /health/ready` → **200**: el servidor está vivo |
| Receptor | Control de enrutado | `GET /no-existe` → **404 `not_found`**: el 405 es rechazo por método, no un comodín |
| Buzón | Bandeja de Mailpit | **`total: 0`**, vacía por completo, pese al OTP emitido y a dos notificaciones de bienvenida el mismo día |

El servidor de Notifications es, por diseño, solo de sondas: rechaza **todo**
método distinto de `GET` antes de enrutar. Su comentario lo dice sin rodeos:
*«El worker no expone API de negocio: su entrada es la cola de mensajes»*. Y la
cola es `InMemoryMessageQueue`, dentro del proceso, sin ningún productor.

La bandeja vacía de Mailpit es la confirmación desde el lado receptor: no es
que el correo se envíe y se pierda — **nunca llega a intentarse**.

## Hallazgo de SEGURIDAD: `/dev/enqueue` está vivo en producción

> Corrección de la tabla anterior. Se sondearon cuatro rutas plausibles y las
> cuatro dieron 405, pero **faltaba probar la que existe de verdad**. Al leer el
> código de `main` apareció `POST /dev/enqueue`, y en producción **responde**.

El contenedor de Notifications corre con `NODE_ENV=development`, y el servidor
de sondas inyecta el endpoint `/dev/enqueue` **solo bajo esa condición**. La
configuración del nodo lo deja, por tanto, activo en producción.

Comprobado ejecutando la inyección:

```
POST /dev/enqueue  ->  202 {"status":"queued"}
```

Ese mensaje se proceso y se entrego:

```
notification_enqueued
notification_sent        notificationId=sonda-...  attempt=1
batch_processed          received=1 sent=1 duplicated=0 deadLettered=0
```

El correo aparecio en Mailpit con su asunto y su cuerpo correctos.

**Dos consecuencias, y la segunda es la grave:**

1. **Buena noticia:** queda demostrado que **toda la cadena aguas abajo funciona
   en producción** — cola, consumidor, renderizado de plantilla, envío. Lo único
   que faltaba era el tramo Account → Notifications. Esto refuerza la conclusión
   de esta verificación en lugar de contradecirla.

2. **Riesgo:** `/dev/enqueue` **no valida el cuerpo ni pide credencial alguna**.
   Publica en la cola lo que reciba. Hoy el daño es limitado porque el remitente
   es `no-reply@nexus-battles.local` y la entrega termina en Mailpit, dentro del
   nodo. **Deja de ser limitado en cuanto se active `EMAIL_DRIVER=ses`**: pasaría
   a permitir enviar correo arbitrario firmado como
   `no-reply@simuladorupbbga.app`, el dominio verificado, a cualquiera que
   alcance la red interna de Docker.

**Por eso `NODE_ENV=production` debe entrar en el MISMO cambio que active SES**,
nunca después. Activar SES sin cerrar esto convertiría una comodidad de
desarrollo en un vector de suplantación del dominio.

Conviene además valorar retirar `/dev/enqueue` del código: desde que existe un
servidor de ingesta con validación y autenticación opcional, es redundante, y
depender de acertar con `NODE_ENV` es una garantía más débil que no tener el
endpoint.

## Estado de los criterios de aceptación en producción

| CA | Estado | Nota |
| --- | --- | --- |
| CA-01 | ✅ verificado | Punto 4 de la tabla |
| CA-02 | ✅ verificado | Puntos 2 y 3 |
| CA-03 | ⛔ bloqueado | Exige un código válido |
| CA-04 | ✅ verificado | La solicitud se emite con la plantilla correcta |
| CA-05 a CA-09 | ⛔ bloqueados | Todos dependen de disponer del código |

## Conclusión

**HU-04 no se puede cerrar todavía, y el motivo no es un defecto de HU-04.**
Su lógica queda verificada en producción hasta el último punto verificable. Lo
que falta es el transporte Account → Notifications, que **no está construido** y
cuya forma decide **ADR-006** (abierto como EN-027.4: ingesta HTTP frente a
SQS).

Mientras esa decisión no se tome, los pasos 3 y 4 no son verificables por
ningún medio, ni en producción ni manualmente.
