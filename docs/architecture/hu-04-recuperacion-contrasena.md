# HU-04 — Diseño de recuperación de contraseña

## Trazabilidad

- **Historia:** [HU-04 — Recuperación de contraseña](https://github.com/Nexus-Battle-VI/Nexus-Battle-Management/issues/13)
- **Diseño:** [TASK HU-04.1](https://github.com/Nexus-Battle-VI/Nexus-Battle-Management/issues/96)
- **Persistencia:** [TASK HU-04.2](https://github.com/Nexus-Battle-VI/Nexus-Battle-Management/issues/97)
- **API y flujo:** [TASK HU-04.3](https://github.com/Nexus-Battle-VI/Nexus-Battle-Management/issues/98)
- **Interfaz:** [TASK HU-04.4](https://github.com/Nexus-Battle-VI/Nexus-Battle-Management/issues/99)
- **Pruebas:** [TASK HU-04.5](https://github.com/Nexus-Battle-VI/Nexus-Battle-Management/issues/100)
- **Requisito:** `RF-04`
- **Bloqueada por:** [HU-01 — Registro de cuenta de jugador](https://github.com/Nexus-Battle-VI/Nexus-Battle-Management/issues/10),
  [HU-55 — Módulo de correo electrónico](https://github.com/Nexus-Battle-VI/Nexus-Battle-Management/issues/85)

Fuentes UML editables:

- [Caso de uso](../diagrams/hu-04-use-case.puml)
- [Actividad](../diagrams/hu-04-activity-recuperacion.puml)
- [Secuencia](../diagrams/hu-04-sequence-recuperacion.puml)
- [Dominio](../diagrams/hu-04-domain-recovery.puml)

## Decisiones funcionales resueltas

1. Las preguntas de seguridad son las mismas cuatro configuradas en el
   registro (HU-01). HU-04 no permite definir preguntas nuevas durante la
   recuperación; solo las vuelve a preguntar y compara contra el resumen ya
   guardado (`account_security_answers`).
2. El identificador inicial del flujo es el **correo electrónico**. El primer
   paso siempre devuelve el mismo catálogo de preguntas y un token de desafío,
   exista o no la cuenta con ese correo: no hay forma de distinguir "correo
   registrado" de "correo inexistente" por la respuesta, para no permitir
   enumerar cuentas.
3. El código de un solo uso nunca se persiste ni se responde en claro: la
   persistencia solo guarda su resumen (`codeHash`, HMAC-SHA-256), igual que
   las respuestas de seguridad. Tampoco se escribe en el registro estructurado
   (evento `recovery_otp_issued` sin el campo `code`).
4. El proceso es una máquina de estados estrictamente secuencial
   (`IDENTIFIED -> QUESTIONS_VERIFIED -> CODE_VERIFIED -> COMPLETED`).
   Saltarse una etapa —por ejemplo, pedir el cambio de contraseña sin haber
   validado el código— se rechaza con el mismo error genérico que una
   respuesta o código incorrectos.
5. El código consumido dejar de ser válido de inmediato: verificarlo avanza la
   etapa a `CODE_VERIFIED` y limpia `codeHash`, así que reutilizar el mismo
   código en una segunda llamada ya no encuentra ninguna etapa ni resumen que
   validar.
6. El origen del código depende del proveedor de identidad configurado, igual
   que ya decide `AUTHENTICATION_DRIVER` para el resto de Account: con
   proveedor real (Cognito) el código es aleatorio (`RandomRecoveryOtp`, CSPRNG
   de 6 dígitos); sin proveedor configurado es el fijo `000000`, igual que la
   confirmación de HU-01. Un código fijo en producción sería adivinable por
   construcción.
7. El envío del código y de la confirmación posterior se solicitan a HU-55
   (`NotificationRequestPort`); Account nunca envía correo directamente ni
   implementa un segundo mecanismo de envío.
8. El restablecimiento final de la contraseña usa el mecanismo seguro del
   proveedor de identidad (`IdentityPasswordResetPort`): con Cognito,
   `AdminSetUserPassword` con `Permanent: true`, para no dejar la cuenta en un
   reto `NEW_PASSWORD_REQUIRED` que HU-02 no sabe resolver.

## Caso de uso textual

### Recuperar contraseña

**Actor principal:** Usuario registrado que olvidó su contraseña.

**Entrada conceptual:** correo de la cuenta, respuestas a las preguntas de
seguridad, código recibido por correo, nueva contraseña.

**Precondiciones:**

- la cuenta, si existe, ya completó HU-01 (preguntas de seguridad
  configuradas);
- HU-55 está disponible para solicitar el envío del código y la confirmación.

**Flujo principal:**

1. Identificar la cuenta por correo; el sistema siempre devuelve el mismo
   catálogo de preguntas y un token de desafío.
2. Responder las preguntas de seguridad configuradas en el registro.
3. Recibir y validar el código de un solo uso enviado al correo registrado.
4. Establecer la nueva contraseña, solo tras superar ambas validaciones.
5. Recibir la notificación de confirmación en el correo registrado.

**Alternativas y fronteras:**

- correo no registrado: mismo catálogo de preguntas que uno registrado, y
  cualquier respuesta se rechaza de forma genérica (CA-01, CA-02);
- respuestas incorrectas: rechazo genérico, no avanza de etapa (CA-02);
- intento de establecer contraseña sin validar el código: rechazo genérico
  (CA-03);
- código incorrecto: rechazo genérico, no avanza de etapa (CA-05);
- código ya usado: rechazo, aunque el valor coincidiera (CA-06);
- ambas validaciones superadas: habilita el paso final (CA-07);
- contraseña válida según la política vigente: credencial actualizada, la
  anterior deja de ser válida (CA-08);
- éxito: se solicita a HU-55 la confirmación por correo (CA-09).

## Cobertura real y frontera

| Regla de HU-04 | Estado verificable |
| --- | --- |
| CA-01 a CA-03, CA-05 a CA-08 | Implementadas en `Nexus-Battle-Account` (casos de uso `StartPasswordRecovery`, `VerifyRecoveryAnswers`, `VerifyRecoveryCode`, `ResetRecoveryPassword`). |
| CA-04, CA-09 (envío por HU-55) | Account solicita `account-password-recovery-code` y `account-password-reset-confirmation` a `NotificationRequestPort`; las plantillas viven en `Nexus-Battle-Notifications`. El transporte real (cola/SMTP) depende de HU-55/ADR-006. |
| Expiración del código, máximo de intentos, reenvío | Pendientes: TASK HU-04.2 los deja como parámetros configurables preparados, no fijados, hasta que el cliente apruebe esa política. No se inventa un valor. |
| Interfaz responsive y accesible (TASK HU-04.4) | Implementada en `Nexus-Battle-Web` (`/recover`), verificada sin desbordamiento horizontal a 1360×768. |

## Contrato conceptual

El contexto Account/Identity ofrece estas capacidades, sin prescribir HTTP:

- iniciar un proceso de recuperación por correo, sin revelar si la cuenta
  existe;
- presentar las preguntas de seguridad ya configuradas para esa cuenta;
- validar las respuestas contra el resumen guardado en HU-01;
- emitir y solicitar el envío de un código de un solo uso;
- validar el código y marcarlo consumido, sin exponerlo nunca en claro;
- autorizar el cambio de contraseña solo tras ambas validaciones;
- actualizar la credencial mediante el proveedor de identidad;
- solicitar la notificación de confirmación a HU-55.

La autorización de cada etapa vive en el dominio (`RecoveryChallenge`, máquina
de estados). Los adaptadores traducen protocolo, persistencia, el proveedor de
identidad y el servicio de correo, pero no deciden si una etapa puede
avanzar.

## Persistencia e integración

`recovery_challenges` es la fuente de verdad del proceso temporal; no duplica
`accounts` ni `account_security_answers`, que siguen siendo de HU-01. Sin
motor de base de datos configurado (`PERSISTENCE_DRIVER=memory`), el mismo
contrato lo cumple un repositorio en memoria: el proceso completo se puede
probar sin PostgreSQL, y el estado se pierde al reiniciar el servicio.

```text
recuperar: identificar -> validar preguntas -> emitir codigo -> HU-55 (envio)
         -> validar codigo -> establecer contrasena -> proveedor de identidad
         -> HU-55 (confirmacion)
```

Web nunca calcula si una cuenta existe, si una respuesta es correcta o si un
código es válido: cada paso solo avanza cuando Account responde 200, y
cualquier rechazo se presenta con el mismo mensaje genérico
("No fue posible continuar con la recuperación..."), sin distinguir el motivo.

## Impacto arquitectónico

- **Account/Identity:** propietario del proceso de recuperación, del código de
  un solo uso y de la actualización de credencial.
- **Cognito (proveedor de identidad):** origen real del código cuando hay
  proveedor configurado, y ejecutor de `AdminSetUserPassword` en el paso
  final.
- **Notifications (HU-55):** dueño de las plantillas
  `account-password-recovery-code` y `account-password-reset-confirmation` y
  del envío real (SMTP/cola).
- **Web:** las cuatro pantallas de `/recover`, consistentes visualmente con
  login y registro; no duplica ninguna regla de negocio del backend.
- **Infrastructure:** sin cambio de IAM adicional sobre el ya existente para
  operaciones `Admin*` de Cognito (mismo permiso que HU-02/HU-39).

Ningún servicio consulta directamente los datos de otro bounded context: Web
solo habla con Account, y Account solo habla con el proveedor de identidad y
con Notifications.
