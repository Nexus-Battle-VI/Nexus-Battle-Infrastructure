# Contrato HU-47 — Consulta, intención y respuesta del chatbot (v1)

- **Estado:** contrato de TASK HU-47.1. Lo implementa `Nexus-Battle-Chatbot` en TASK HU-47.2.
- **Historia:** [HU-47 #66](https://github.com/Nexus-Battle-VI/Nexus-Battle-Management/issues/66) · **Tasks:** [#530](https://github.com/Nexus-Battle-VI/Nexus-Battle-Management/issues/530), [#531](https://github.com/Nexus-Battle-VI/Nexus-Battle-Management/issues/531) · Team Alfa.
- **Arquitectura aplicada, sin reabrirla:** [ADR-022](../adr/ADR-022-sprint-3-bounded-contexts.md) y [EN-025 #204](https://github.com/Nexus-Battle-VI/Nexus-Battle-Management/issues/204). El motor es el clasificador propio ya decidido. Esta historia no impone otra técnica.
- **Diccionario:** [hu-53-knowledge-base-v1](hu-53-knowledge-base-v1.md). Esta consulta lo lee. No lo administra.

## 1. Quién llama

`POST /api/v1/chatbot/messages`.

- Sin token: visitante. Solo recibe texto de la base pública.
- Con token de acceso válido: jugador. La identidad sale del token. El cuerpo no acepta un identificador de usuario.
- Token presente pero inválido: `401`.

## 2. Petición

```json
{
  "text": "cuanto dura un turno",
  "view": "misiones"
}
```

| Campo | Regla |
| --- | --- |
| `text` | Obligatorio. De 1 a 500 caracteres. |
| `view` | Opcional. Minúsculas, números, guion o guion bajo, hasta 40 caracteres. Es la vista actual del jugador. |

Un campo de más responde `400`.

## 3. Respuesta

```json
{
  "answered": true,
  "intent": "regla_turno",
  "language": "es",
  "confidence": 0.82,
  "answer": "El combate es por turnos.",
  "kind": "direct",
  "suggestions": [],
  "view": "misiones"
}
```

| Campo | Regla |
| --- | --- |
| `answered` | `true` solo si la confianza llega al umbral `0.55` y hay una entrada. |
| `intent` | Intención elegida, o `null` si no se responde. |
| `language` | `es` o `en`, o `null` si no se responde. |
| `confidence` | Probabilidad de la clase ganadora, entre 0 y 1. |
| `answer` | Texto ya escrito en el diccionario, o `null`. Nunca se redacta uno nuevo. |
| `kind` | `direct`, `steps` (la respuesta trae saltos de línea), `enriched` (trae un enlace) o `contextual` (había una entrada de esa vista). |
| `suggestions` | Hasta 3 preguntas de otras intenciones cuando no se responde. Vacío cuando sí se responde. |
| `view` | La vista recibida, o `null`. |

Si varias entradas comparten intención e idioma, gana la de mayor prioridad. Si la petición trae `view` y existe una entrada de esa vista, esa gana sobre la entrada sin vista.

No se devuelven datos del jugador. Inventario, misiones en curso, subasta y créditos son HU-48.

## 4. Caché

Las respuestas frecuentes se guardan en memoria del proceso, como máximo 128, con clave (pregunta normalizada, vista). Cambiar el diccionario invalida la caché. No es una caché de otro servicio.

## 5. Errores de la conversación segura

La task HU-47.3 los aplica. Este contrato fija la forma, la misma del resto de servicios: `{statusCode, message, error}`.

| Situación | Estado |
| --- | --- |
| Token inválido | `401` |
| Demasiadas consultas | `429` |
| El texto se interpreta como código o inyección | `400` |
| Contenido no admitido | `400` |

## 6. Lo que este contrato no hace

No entrena ni promueve versiones. Ese ciclo es [hu-54-model-versions-v1](hu-54-model-versions-v1.md): cada respuesta guardada queda ligada a la versión que la produjo. No abre el widget (HU-47.4). No escala a un ticket (HU-49). No ejecuta acciones (HU-50).
