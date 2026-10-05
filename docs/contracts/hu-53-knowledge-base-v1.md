# Contrato HU-53 — Diccionario del chatbot (v1)

- **Estado:** contrato de TASK HU-53.1. Lo implementa `Nexus-Battle-Chatbot`.
- **Historia:** [HU-53 #83](https://github.com/Nexus-Battle-VI/Nexus-Battle-Management/issues/83) · **Task:** [#529](https://github.com/Nexus-Battle-VI/Nexus-Battle-Management/issues/529) · Team Alfa.
- **Arquitectura aplicada, sin reabrirla:** [ADR-022](../adr/ADR-022-sprint-3-bounded-contexts.md). El clasificador y el umbral de respuesta no son de esta task: viven en HU-47 y HU-54.

## 1. Qué es una entrada

El diccionario es la base de conocimiento que un administrador mantiene. Cada entrada guarda:

| Campo | Regla |
| --- | --- |
| `id` | UUID que genera el servicio. El cliente no lo envía al crear. |
| `intent` | Minúsculas, números o `_`. Empieza por letra. Hasta 64 caracteres. |
| `language` | `es` o `en`. El mismo tema en los dos idiomas son dos entradas. |
| `priority` | Entero. Si dos entradas comparten intención e idioma, quien las liste las ordena de mayor a menor. |
| `answer` | Texto no vacío, hasta 8000 caracteres. Lo escribe el administrador. El modelo no lo redacta. |
| `variations` | De 1 a 30 preguntas, sin vacías, sin repetidas, cada una hasta 500 caracteres. Son los ejemplos de reconocimiento y de entrenamiento. |

Dos entradas pueden llevar la misma respuesta y distinta intención. No hay un campo aparte para eso.

No entran en esta versión: dato vivo del jugador, acción asistida, importación, exportación ni actualizaciones programadas. Siguen en HU-53, HU-48 y HU-50.

## 2. Rutas

Prefijo público `/api/v1/chatbot/admin/knowledge`. Todas exigen un token de acceso con rol `ADMINISTRATOR`. `SUPER_ADMINISTRATOR` también pasa. Un jugador recibe `403`. Sin token, `401`.

El cuerpo no acepta campos de más (`400`). No trae identificador de usuario: la identidad sale del token.

| Método | Ruta | Efecto |
| --- | --- | --- |
| `GET` | `/api/v1/chatbot/admin/knowledge` | Lista las entradas, con sus variaciones, ordenadas por intención, idioma y prioridad. |
| `POST` | `/api/v1/chatbot/admin/knowledge` | Crea. Responde `201` y la entrada con su `id`. |
| `PUT` | `/api/v1/chatbot/admin/knowledge/{id}` | Reemplaza intención, idioma, prioridad, respuesta y variaciones. El `id` no cambia. |
| `DELETE` | `/api/v1/chatbot/admin/knowledge/{id}` | Borra. Responde `204`. |

Una entrada que no existe responde `404` al editar o al borrar.

Ejemplo de alta:

```json
{
  "intent": "regla_turno",
  "language": "es",
  "priority": 10,
  "answer": "El combate es por turnos.",
  "variations": ["como funciona el turno", "cuanto dura un turno"]
}
```

## 3. Errores

La forma es la del resto de servicios: `{statusCode, message, error}`.

| Situación | Estado |
| --- | --- |
| Sin token, o token inválido | `401` |
| Token de jugador | `403` |
| Cuerpo con un campo no declarado, o entrada que no cumple la tabla de arriba | `400` |
| `id` desconocido | `404` |

## 4. Persistencia

Tabla `knowledge_entries` en la base propia de Chatbot. La migración es `001-knowledge-entries`. El idioma, la forma de la intención, la respuesta no vacía y al menos una variación los impone también la base. Ningún otro servicio lee esta tabla.
