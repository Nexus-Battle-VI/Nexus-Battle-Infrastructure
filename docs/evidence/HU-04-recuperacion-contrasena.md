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
