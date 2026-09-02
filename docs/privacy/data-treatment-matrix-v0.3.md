# Matriz de tratamiento de datos — v0.3

Traza cada categoría de dato tratada por THE NEXUS BATTLES VI hasta: la
finalidad que declara la [Política v0.3](privacy-policy-v0.3.md), el bounded
context que la posee, y si es consultable/exportable/eliminable por el
titular a través del futuro Portal de privacidad.

**Convención de columnas:**

- **Fuente**: dónde se verificó el dato — campo de esquema real (con ruta de
  archivo) o "Política v0.3 §N" cuando la categoría existe en el requisito
  pero no en código todavía.
- **Owner/BC**: bounded context dueño, según
  [data-ownership.md](../architecture/data-ownership.md). "—" si el dato no
  existe todavía en ningún servicio.
- **Consultable**: el titular puede verla en el Portal de privacidad (lectura).
- **Exportable**: puede salir en JSON/XML/PDF (Política §9). Ver la regla de
  exclusión por defecto en [portability-contract-v1.md](portability-contract-v1.md).
- **Eliminable**: se elimina o anonimiza al ejecutar HU-43, sujeto a las
  excepciones de retención de la Política §10–11.
- **Retención**: régimen que aplica cuando la cuenta se elimina.

No se asume que un dato es exportable solo porque exista técnicamente — la
columna Exportable refleja una decisión explícita, no la mera presencia del
campo.

## Cuenta e identidad

| Dato | Fuente | Finalidad (Política §) | Owner/BC | Consultable | Exportable | Eliminable | Retención | HUs consumidoras |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| Nombres, apellidos | `accounts.first_names/last_names` ([schema](https://github.com/Nexus-Battle-VI/Nexus-Battle-Account/blob/main/src/adapters/outbound/persistence/schema.ts)) | §4, §5, §7.1 | Account | Sí | Sí | Sí | Ninguna tras eliminación válida | HU-01, HU-05, HU-43, HU-45 |
| Correo electrónico | `accounts.email` | §4, §5, §7.1, §7.6 | Account | Sí | Sí | Sí, salvo evidencia de consentimiento (ver abajo) | Copia mínima puede sobrevivir en evidencia de consentimiento (Política §6) | HU-01, HU-02, HU-04, HU-05, HU-43, HU-45 |
| Apodo (`display_name`) | `accounts.display_name` | §4, §5, §7.1, §15 | Account | Sí | Sí | Sí | Ninguna | HU-01, HU-02, HU-05, HU-45 |
| Avatar | `accounts.avatar_storage_key/mime_type/size_bytes/original_name` + `AVATAR_STORAGE_PATH` | §4, §7.1 | Account | Sí | Sí (binario o referencia, a decidir en HU-45) | Sí | Ninguna | HU-01, HU-05, HU-45 |
| Contraseña / credencial | **No almacenada por el producto** — custodiada por Cognito, fuera del alcance de las bases propias ([security.md](../architecture/security.md): "Account no almacena contraseñas") | §4, §7.1, §12 | Proveedor de identidad (Cognito), fuera de los bounded contexts | No | **No — nunca** | Sujeto a la eliminación del usuario en Cognito, fuera del alcance de HU-43 sobre datos propios | — | — |
| Preguntas y respuestas de seguridad | `account_security_answers.answer_hash` (SHA-256, irreversible) | §4, §7.1 | Account | Solo la pregunta (`question_id`), nunca la respuesta ni su hash | **No — es un hash interno, no un dato de presentación** | Sí | Ninguna | HU-04 |
| Códigos de recuperación (OTP) | `RecoveryChallenge` en memoria/Postgres (vida corta) | §4, §7.1 | Account | No aplica (efímero) | No | Se descarta por expiración, no por HU-43 | Vida corta (minutos) | HU-04 |
| Roles y permisos | `account_roles.role` + grupos Cognito | §4, §5, §7.1 | Account (fuente de verdad) + reflejo en Cognito | Sí | Sí, como metadato de cuenta — **ver observación de alcance abajo** | Se elimina con la cuenta; el rol `PLAYER` no puede "retirarse" en vida de la cuenta ([RolePolicy](https://github.com/Nexus-Battle-VI/Nexus-Battle-Account/blob/main/src/domain/policies/RolePolicy.ts)) | Ninguna | HU-39, HU-45 |
| `terms_accepted` (consentimiento) | `accounts.terms_accepted` (booleano, sin versión ni fecha — ver [consent-versioning.md](consent-versioning.md)) | §6, Anexo A | Account | Sí | Sí | **Pendiente decisión** — ver consent-versioning.md | Política §6: debe existir evidencia verificable, forma de conservación no fijada | EN-011, HU-45 |
| Estado técnico (`status`: `PENDING_VERIFICATION`/`ACTIVE`/`SUSPENDED`) | `accounts.status` | Operación interna del sistema, no declarado como contenido del portal por la Política | Account | **No exigido por Política/SRS como contenido mínimo del portal — no convertir en requisito por defecto** | No | Se elimina con la cuenta | Ninguna | — |
| `created_at`/`updated_at` de cuenta | `accounts.created_at/updated_at` | Auditoría técnica interna | Account | **No exigido como contenido mínimo del portal** — evaluar si aporta valor al titular antes de incluirlo | No, salvo decisión explícita futura | Se elimina con la cuenta | Ninguna | — |

## Actividad de juego

| Dato | Fuente | Finalidad (Política §) | Owner/BC | Consultable | Exportable | Eliminable | Retención | HUs consumidoras |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| Inventario (ítems, cantidades) | `InventoryDocument`/`SlotDocument` ([mapping.ts](https://github.com/Nexus-Battle-VI/Nexus-Battle-Player-Inventory/blob/main/src/adapters/outbound/persistence/mapping.ts)), clave `ownerId` = Account | §4, §5, §7.3 | Player / Inventory | Sí | Sí (PDF exige explícitamente inventario, Política §9) | Sí | Ninguna | HU-45 |
| Héroes, equipamiento, estadísticas, logros, progreso | Política §4, §7.3 — **no existe todavía un dominio de "héroes"/estadísticas de juego en ningún servicio desplegado** (`Player-Inventory` solo modela ítems genéricos; no hay servicio de progreso/logros) | §4, §5, §7.3 | **Pendiente asignación de owner** — probablemente Player/Inventory o un contexto de Juego futuro | Pendiente | Pendiente (Política §9 exige "estadísticas" en el PDF) | Pendiente | Pendiente | HU-45 |

## Comunidad y moderación

| Dato | Fuente | Finalidad (Política §) | Owner/BC | Consultable | Exportable | Eliminable | Retención | HUs consumidoras |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| Comentarios / mensajes de hilo | `PostsTable.content` ([schema.ts](https://github.com/Nexus-Battle-VI/Nexus-Battle-Community/blob/main/src/adapters/outbound/persistence/schema.ts)), `author_id` = Account | §4, §5, §7.2 | Community | Sí | Sí (PDF exige explícitamente comentarios, Política §9) | **Depende del régimen de moderación** — ver observación | Sujeto a §10/§11 si hay sanción o auditoría vinculada | HU-45 |
| Hilos (`title`, `status`) | `ThreadsTable` | §4, §5, §7.2 | Community | Sí | Sí, como contexto de los comentarios propios | Sí, salvo que el hilo tenga posts de otros usuarios | Igual que comentarios | HU-45 |
| Calificaciones, reportes, advertencias, sanciones, apelaciones | Política §4, §7.2 — **no implementado**: Community solo tiene ocultar post (`hidden`) y cerrar hilo (`status`); no hay tabla de reportes, advertencias, sanciones ni apelaciones en ningún servicio | §4, §5, §7.2 | **Pendiente asignación de owner** | Pendiente | Pendiente | Pendiente — Política §10 exige régimen de excepción para "sanciones definitivas" que hoy no existen como entidad | Pendiente — Política §11 (auditoría, 5 años) aplicaría cuando exista | HU-43 |

## Transacciones (comercio simulado)

| Dato | Fuente | Finalidad (Política §) | Owner/BC | Consultable | Exportable | Eliminable | Retención | HUs consumidoras |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| Pedidos (`status`, `currency`) | `OrdersTable`, `customer_id` = Account ([schema.ts](https://github.com/Nexus-Battle-VI/Nexus-Battle-Commerce/blob/main/src/adapters/outbound/persistence/schema.ts)) | §4, §5, §7.4 | Commerce | Sí | Sí (PDF exige explícitamente historial de transacciones, Política §9) | **No por defecto** — Política §10–11: registros financieros se conservan tras eliminación durante "el periodo exigido por las obligaciones aplicables" (**periodo concreto no fijado por la Política**; no se inventa uno en este PR) | Indeterminada — pendiente decisión legal/financiera | HU-43, HU-45 |
| Líneas de pedido (SKU, importe) | `OrderLinesTable` | §4, §5, §7.4 | Commerce | Sí | Sí, junto al pedido | Igual que el pedido | Igual que el pedido | HU-45 |
| Lista de deseos (`wishlist_items`) | `WishlistItemsTable` (`customer_id`, `sku`) | No descrita explícitamente en la Política v0.3 — funcionalidad de Commerce no contemplada por el documento fuente | Commerce | Sí | **Pendiente** — no está en el alcance mínimo del PDF (§9); no se agrega por defecto | Sí | Ninguna | — |
| Datos de formulario de pago simulado | Política §7.4: no deben convertirse en datos permanentes del perfil por esa sola circunstancia | §7.4 | — (flujo académico, sin persistencia declarada) | No aplica | No | No aplica | No debe persistir | — |

## Chatbot

| Dato | Fuente | Finalidad (Política §) | Owner/BC | Consultable | Exportable | Eliminable | Retención | HUs consumidoras |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| Historial y contexto de conversación, retroalimentación | Política §4, §5, §7.5 — **el chatbot no existe como servicio en ninguno de los 8 repositorios de Nexus-Battle-VI al momento de este PR** | §4, §5, §7.5 | **No asignado — módulo no incorporado al sistema** | No aplica | No aplica | No aplica | No aplica | — |

> Toda la Sección 7.5 de la Política (chatbot) describe un módulo que **no
> está implementado**. Se documenta la finalidad declarada para cuando el
> módulo se incorpore formalmente, tal como exige la Política §1 ("ninguna
> funcionalidad podrá ampliar por sí sola las categorías... sin actualización
> formal"). No se crea un owner ni un contrato para un servicio inexistente.

## Comunicaciones

| Dato | Fuente | Finalidad (Política §) | Owner/BC | Consultable | Exportable | Eliminable | Retención | HUs consumidoras |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| Correo registrado (uso para envío) | `accounts.email` (mismo dato de Cuenta, tratamiento adicional) | §4, §5, §7.6 | Account (dato) / Notifications (tratamiento de envío) | Sí (es el mismo correo de cuenta) | Sí (es el mismo correo de cuenta) | Sí, con la cuenta | Ninguna | HU-45 |
| Plantillas y variables de notificación enviadas (`NotificationRequest`) | [`NotificationRequestPort`](https://github.com/Nexus-Battle-VI/Nexus-Battle-Account/blob/main/src/application/ports/NotificationRequestPort.ts) — **Notifications no persiste histórico de envíos** ([data-ownership.md](../architecture/data-ownership.md): "Sin base obligatoria") | §5, §7.6 | Notifications | No — no hay histórico persistente que consultar | No | No aplica (no persiste) | No aplica | — |

## Auditoría administrativa

| Dato | Fuente | Finalidad (Política §) | Owner/BC | Consultable | Exportable | Eliminable | Retención | HUs consumidoras |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| Fecha/hora, administrador, tipo de acción, afectado, valores anteriores/nuevos, motivo, IP | Política §4, §5, §7.2, §11 — **no existe todavía una tabla o servicio de auditoría administrativa en ningún repositorio**; HU-39 gestiona roles pero no deja registro de auditoría propio verificado en código | §4, §11 | **Pendiente asignación de owner** — candidato natural: Account (donde ocurre la gestión de roles) o un contexto de Auditoría transversal, a decidir | **No — la Política exige que sea "accesible únicamente a los roles autorizados", nunca al titular ordinario** | **No — nunca al titular; es un registro sobre la acción de un administrador, no un dato exportable del titular afectado** | **No — la Política exige inmutabilidad y retención mínima de 5 años, con excepción explícita frente a la eliminación de cuenta (§10 PARÁGRAFO)** | **Mínimo 5 años, inmutable** (Política §11) | HU-43 (como excepción de retención) |

## Datos que la Política v0.3 exige **excluir** de la exportación por defecto

Ver el detalle normativo en [portability-contract-v1.md](portability-contract-v1.md).
Resumen:

| Dato | Motivo de exclusión |
| --- | --- |
| Contraseñas, hashes de contraseña | Nunca almacenados por el producto; y aunque lo estuvieran, son secreto de autenticación, no dato de presentación |
| Tokens de acceso/actualización, claims internos del JWT | Credencial técnica de sesión, no dato personal de presentación |
| Secretos TOTP/MFA | Secreto de autenticación |
| Hashes de respuestas de seguridad | Secreto de recuperación, irreversible por diseño |
| Credenciales/claves de AWS | Nunca pertenecen al titular; son infraestructura |
| Datos internos de Cognito no reflejados en Account (`sub` técnico aparte del ya usado como clave, atributos internos del pool) | Identificador técnico del proveedor, sin valor funcional para el titular |
| Identificadores técnicos sin valor funcional (IDs internos de fila, claves foráneas opacas de otro servicio) | No aportan información al titular; exponerlos filtra estructura interna |
| Datos de terceros (otro `author_id`, otro `customer_id`, comentarios de otro usuario en el mismo hilo) | El portal "deberá impedir que un titular visualice o exporte datos pertenecientes a otra persona" (Política §8) |

## Pendientes explícitos de esta matriz

1. **Owner de "héroes/estadísticas/progreso/logros"** — no existe ese dominio
   en el sistema actual. Requiere decisión de Product Owner/Arquitectura antes
   de que HU-45 pueda exportarlo.
2. **Owner de "reportes/advertencias/sanciones/apelaciones"** — Community solo
   implementa ocultar post y cerrar hilo. El régimen de excepción de
   retención de sanciones definitivas (Política §10 PARÁGRAFO) no tiene dónde
   aplicarse todavía.
3. **Owner de auditoría administrativa transversal** — no existe como
   servicio o tabla. HU-43 necesita esta pieza para poder declarar la
   excepción de retención de 5 años sobre algo real.
4. **Periodo concreto de retención de datos financieros/transaccionales tras
   eliminación** — la Política dice "el periodo exigido por las obligaciones
   aplicables" sin fijar un número. No se inventa un plazo en este PR.
5. **Decisión sobre exportabilidad del avatar** — binario vs. referencia/URL
   en la exportación PDF/JSON, ver [HU-45](hu-45-data-portability-design.md).
