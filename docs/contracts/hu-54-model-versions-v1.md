# Contrato HU-54 — Versiones, validación y prueba A/B del modelo (v1)

- **Estado:** contrato de TASK HU-54.1. Lo implementan TASK HU-54.2 (entrenar y promover) y TASK HU-54.3 (reparto y precisión). El panel es TASK HU-54.4.
- **Historia:** [HU-54 #84](https://github.com/Nexus-Battle-VI/Nexus-Battle-Management/issues/84) · **Tasks:** [#525](https://github.com/Nexus-Battle-VI/Nexus-Battle-Management/issues/525), [#526](https://github.com/Nexus-Battle-VI/Nexus-Battle-Management/issues/526), [#527](https://github.com/Nexus-Battle-VI/Nexus-Battle-Management/issues/527) · Team Alfa.
- **Consulta que anota:** [hu-47-conversation-v1](hu-47-conversation-v1.md). **Diccionario:** [hu-53-knowledge-base-v1](hu-53-knowledge-base-v1.md). **Historial y valoración:** [HU-51 #81](https://github.com/Nexus-Battle-VI/Nexus-Battle-Management/issues/81).

## 1. Motor, ya aprobado

La HU-54 no exige un algoritmo. El motor del Sprint 3 ya está cerrado en [ADR-022](../adr/ADR-022-sprint-3-bounded-contexts.md) (`Accepted`, 2026-09-30), que es la decisión que pide [EN-025 #204](https://github.com/Nexus-Battle-VI/Nexus-Battle-Management/issues/204): necesidad, alternativas y justificación antes de adoptarlo.

El documento del curso recomienda un motor de lenguaje natural y un marco de entrenamiento, y no nombra biblioteca. ADR-022 compara un modelo gestionado, una base vectorial, un clasificador escrito a mano y un bot de palabras clave, y se queda con el clasificador propio: n-gramas de caracteres y regresión logística, en Python con scikit-learn. Cambiar ese motor es otro ADR. No es un criterio de aceptación de esta historia.

Los números del primer entreno (techo de rasgos, `C`, peso de clases, umbral de respuesta `0.55` y reparto 80/20) ya están fijados junto a ese motor. Este contrato no los mueve. Fija el ciclo de versiones.

## 2. Estados

Una versión nace `CANDIDATE`. Como mucho una versión está `ACTIVE`. No hay un tercer estado.

| Estado | Atiende |
| --- | --- |
| `CANDIDATE` | A nadie, salvo la que esté marcada en prueba (sección 5). |
| `ACTIVE` | Al resto de las sesiones. Si no hay candidata en prueba, a todas. |

Entrenar no promueve. Si la candidata no cumple la sección 4, se guarda con sus métricas y sigue en `CANDIDATE`.

## 3. Conjunto

Cada ejemplo es un texto ya normalizado y una etiqueta `idioma:intención`.

| Fuente | Entra cuando |
| --- | --- |
| Variación del diccionario (HU-53) | Siempre. Es el ejemplo de esa intención e idioma. |
| Conversación (HU-51) | El jugador la valoró útil **o** no útil, el historial no fue borrado y la respuesta tenía intención. |

Una conversación sin valoración no está revisada y no entra. El historial borrado no se recupera para el conjunto, aunque antes tuviera valoración.

Valoración útil: la pregunta y la intención que produjo esa respuesta entran como ejemplo. Valoración no útil: queda revisada y no se suma como ejemplo de esa intención. No se le inventa otra etiqueta. Sin intención asignada no hay ejemplo.

El texto del conjunto es el que ya se guardó. Contraseñas y secuencias de 13 a 19 dígitos quedan como `[redactado]` (HU-47.3). El secreto original no se reconstitue. El historial de una persona no se usa para contestar a otra.

## 4. Validación y promoción

El conjunto se parte 80/20, estratificado por etiqueta. Cada clase con dos o más ejemplos aparece en los dos lados. Una clase con un solo ejemplo se queda en el entrenamiento y el informe lo dice.

Sobre el 20 % se guardan, junto a la versión: exactitud, F1 por intención, F1 macro y la matriz de confusión.

| Situación | Pasa a `ACTIVE` |
| --- | --- |
| No hay ninguna `ACTIVE` | La exactitud de validación es al menos `0.80`. |
| Ya hay una `ACTIVE` | La exactitud es al menos `0.80` y el F1 macro no baja respecto de esa versión. |

Si no se alcanza, faltan variaciones. No se cambia el algoritmo de la sección 1. La candidata no atiende.

Al promover, la `ACTIVE` anterior deja de serlo y se conserva con sus métricas. Sigue habiendo una sola `ACTIVE`.

## 5. Prueba A/B

El porcentaje de sesiones que ven a la candidata lo decide el Product Owner. Este contrato no lo elige.

El parámetro es un entero de 0 a 100. Mientras no esté definido, vale 0: todas las sesiones usan la `ACTIVE`.

Cuando hay una sola `CANDIDATE` marcada en prueba y el porcentaje es mayor que 0, el reparto es un hash estable del actor de la sesión (el sujeto del jugador, o el `sessionId` del visitante). La misma sesión no cambia de versión entre mensajes. Sin candidata en prueba, el porcentaje no se aplica.

La candidata en prueba no sustituye a la `ACTIVE`. Sigue en `CANDIDATE`.

## 6. Qué versión respondió

Cada respuesta que se guarda lleva el identificador de la versión que la produjo. La consulta de HU-47 gana un campo aditivo, que añade HU-54.3:

| Campo | Regla |
| --- | --- |
| `modelVersion` | Identificador de la versión, o `null` mientras no exista una `ACTIVE`. |

La precisión en vivo de una versión es el cociente entre valoraciones útiles y valoraciones útiles o no útiles de las respuestas de esa versión. Las respuestas sin valorar no entran en el cociente. Es distinta de la exactitud de la sección 4: aquella se mide antes de promover; esta se consulta de forma continua (HU-52 lee la precisión, no la calcula).

La caché de respuestas incluye la versión en la clave. Promover o cambiar la candidata en prueba no reutiliza la respuesta de otra versión.

## 7. Lo que este contrato no hace

No implementa el job, el reparto ni el panel. No administra el diccionario. No define el porcentaje A/B. No abre la retención del historial: el plazo de borrado sigue pendiente en ADR-022.
