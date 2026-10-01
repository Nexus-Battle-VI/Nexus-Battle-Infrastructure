# ADR-022 — Contextos acotados de Sprint 3: Tournament y Chatbot

- **Estado:** **Accepted** el 2026-09-30 — validado por Product Owners y Scrum Masters (nombres, alcance y Teams)
- **Fecha:** 2026-09-30
- **Decide:** Arquitectura, con validación obligatoria de Product Owners y Scrum Masters (nombre, alcance y Team de cada repositorio, conforme a [ADR-001](ADR-001-repository-strategy.md))
- **Relacionado:** [ADR-001](ADR-001-repository-strategy.md), [ADR-002](ADR-002-backend-stack.md), [ADR-005](ADR-005-data-strategy.md), [ADR-006](ADR-006-messaging.md), [ADR-007](ADR-007-aws-cost-optimized-platform.md), [ADR-011](ADR-011-deployment-topology.md), [ADR-019](ADR-019-sprint-2-bounded-contexts.md), [ADR-020](ADR-020-realtime-combat.md), [EPIC-04 #4](https://github.com/Nexus-Battle-VI/Nexus-Battle-Management/issues/4), [EPIC-09 #9](https://github.com/Nexus-Battle-VI/Nexus-Battle-Management/issues/9), [EN-012 #198](https://github.com/Nexus-Battle-VI/Nexus-Battle-Management/issues/198), [EN-025 #204](https://github.com/Nexus-Battle-VI/Nexus-Battle-Management/issues/204), [EN-032 #461](https://github.com/Nexus-Battle-VI/Nexus-Battle-Management/issues/461)

## Contexto

Sprint 3 (milestone M3, cierre 2026-10-18) trae dos épicas que ningún servicio
existente cubre: **Chatbot** (EPIC-04, HU-47 a HU-54, todas en M3) y **Torneo**
(EPIC-09, HU-77 a HU-86 y EN-033, asumidas por Team Beta el 2026-09-30 y todavía
sin milestone). Como en [ADR-019](ADR-019-sprint-2-bounded-contexts.md), antes de
crear repositorios se aplica la cadena de ADR-001 —requisito, dominio, contexto,
**propiedad de datos**, dependencias, contrato, deployable, Team—.

Seis hechos verificados condicionan la decisión:

1. **Ningún servicio posee torneos, equipos de jugadores, inscripciones ni
   brackets.** «Team» solo existe dentro de Combat como lado A/B de una sala. Web
   tiene `/tournament` como marcador (`ModuleUnavailable`). Missions ya conoce
   `TOURNAMENT` como motivo de héroe ocupado (`busyWith`), pero Player/Inventory
   solo implementa los compromisos `BATTLE` y `MISSION`.
2. **Ningún repositorio contiene código de asistente conversacional, NLP ni
   modelos.** No hay base de conocimiento, historial, tickets ni métricas de
   chatbot en ningún almacén.
3. **El documento oficial del proyecto fija el chatbot como «microservicio
   independiente»** (§7.4.9) con «base de datos para almacenamiento de historial
   y base de conocimiento», «sistema de caché para respuestas frecuentes» y
   «framework de inteligencia artificial para entrenamiento del modelo». En
   §7.4.10 pide reentrenamiento periódico, **validación antes de desplegar** y
   **A/B testing** entre modelos. HU-54 lo recoge. HU-53 pide que los
   administradores registren **variaciones de pregunta** e intenciones: son, por
   construcción, el conjunto de entrenamiento.
4. **El documento fija el torneo así** (§7.9): equipos de dos jugadores, máximo
   seis jugadores por batalla, ocho equipos con relleno de equipos de IA, árbol
   de ganadores (E1–E6, E11, final) y de secundarios (E7–E10, E12, E13),
   inscripción en «dinero real o créditos», premio de créditos y recompensa
   épica, y **un torneo cada 91 días**.
5. **Combat ya cubre la batalla de una justa**: sala, orden de turnos, tiempo
   real con tickets (ADR-020) y `BattleFinalizer`, que emite `winnerTeamLabel`.
   **No** tiene sala creada por otro servicio, notificación de resultado hacia
   fuera (su publicador solo registra) ni rol de espectador. Las salas JcE se
   crean, pero la IA no actúa: los participantes `AI` no tienen perfil y su turno
   se cierra sin acción.
6. **Capacidad medida el 2026-09-30 por SSM**, no estimada:

   | Nodo | Memoria total | En uso | Disponible | Observación |
   | --- | ---: | ---: | ---: | --- |
   | `app` (`t4g.medium`) | 3 830 MiB | 1 574 MiB | 2 066 MiB | 13 contenedores; cada servicio NestJS usa 52–75 MiB en reposo; suma de `mem_limit` en marcha: 1 744 MiB; disco 40 % |
   | `data` (`t4g.small`) | 1 841 MiB | 657 MiB | 956 MiB | MongoDB 412/640 MiB, PostgreSQL 103/288 MiB; disco 19 % |

## Decisión

### Dos contextos nuevos

| Contexto | Repositorio | Datos que posee en exclusiva | Motor | Puerto | Ruta pública | Team |
| --- | --- | --- | --- | ---: | --- | --- |
| Tournament | `Nexus-Battle-Tournament` | Torneos y su calendario, equipos inscritos y sus miembros, inscripciones y pagos de cupo, bracket, justas y su vínculo con la sala de Combat, resultados confirmados, entrega de premios | PostgreSQL | 3010 | `/api/v1/tournaments*` | Team Beta y Team Gama |
| Chatbot | `Nexus-Battle-Chatbot` | Base de conocimiento (entradas, variaciones, intenciones, prioridades), conversaciones e historial, valoraciones, tickets de escalamiento, versiones del modelo con sus métricas, métricas de uso | PostgreSQL | 3011 | `/api/v1/chatbot*` | Team Alfa |

Las rutas de administración de cada contexto viven **bajo su propio prefijo**
(`/api/v1/tournaments/admin/...`, `/api/v1/chatbot/admin/...`), para que Caddy no
necesite rutas sueltas como la que exigió `/api/v1/admin/missions`.

### Por qué cada uno es un contexto

**Tournament no es un módulo de Combat.** Combat posee **una** batalla: su
agregado nace al iniciar y muere al terminar. El torneo posee lo que dura
semanas y abarca muchas batallas: quién se inscribió, quién pagó, qué cupo
ocupa cada equipo, qué justa se juega después y quién avanza. Meter el bracket
en Combat convertiría al servicio de tiempo real en dueño de un proceso
administrativo con pagos. **Tampoco es un módulo de Missions**: aquel es
asíncrono y de un solo jugador. Se elige **PostgreSQL** porque sus invariantes
son relacionales y el motor puede imponerlas:

- la carrera por el octavo cupo se resuelve con `SELECT ... FOR UPDATE` sobre el
  torneo (HU-84: «como máximo uno obtiene el cupo»);
- «un jugador no está en dos equipos del mismo torneo» es un índice único;
- «un torneo cada 91 días» es una restricción sobre la fecha de los torneos;
- las justas y su avance son filas con origen y destino declarados en una tabla
  fija, no un documento que se reescribe entero.

**Chatbot es un contexto propio.** Sus datos —conocimiento, conversaciones,
valoraciones, tickets, modelos— no pertenecen a ningún otro servicio, y su ciclo
de vida (entrenar, validar, promover) tampoco. El documento lo exige como
microservicio independiente. Se elige **PostgreSQL** porque:

- la búsqueda en la base de conocimiento usa **full-text en español e inglés**
  (`tsvector` con índice GIN) sin servicio adicional;
- los modelos entrenados se guardan **en la base**, como `bytea` versionado. El
  nodo `app` no guarda estado y S3 está prohibido por ADR-007 salvo para el
  estado de Terraform;
- «solo una versión `ACTIVE`» es un índice único parcial.

### Excepción a ADR-002: Chatbot en Python

Chatbot se implementa en **Python 3.13 con FastAPI y scikit-learn**, no en
NestJS. Es la **única** excepción al arquetipo de [ADR-002](ADR-002-backend-stack.md),
y se justifica por el requisito, no por preferencia:

- El documento pide un **modelo propio entrenable** con validación y A/B. El
  ecosistema de aprendizaje automático maduro es Python (scikit-learn); hacerlo
  en TypeScript obligaría a reimplementar vectorización, regresión logística y
  validación cruzada sin la madurez ni las pruebas de esa biblioteca.
- La decisión de producto es **no** depender de un LLM de terceros: el motor se
  entrena con datos del proyecto (ver «Motor propio»).

**La excepción no relaja ninguna garantía del arquetipo.** Cada pieza se
reimplementa con paridad y con un control que fallaría si no la cumpliera:

| Garantía del arquetipo (NestJS) | Equivalente en Chatbot | Control |
| --- | --- | --- |
| Clean + Hexagonal con `no-restricted-imports` en CI | `app/{domain,application,adapters,infrastructure}` con **import-linter** (contratos de capas) en CI | Una importación prohibida rompe `lint-imports` |
| Casos de uso sin decoradores, fábricas explícitas | Casos de uso como clases planas; composición en `infrastructure/bootstrap` | Ningún módulo de `application` importa FastAPI |
| `CognitoTokenVerifier` + `JwtAuthGuard` | PyJWT con el JWKS del pool; exige `token_use=access`, `client_id` e `iss`; roles solo de `cognito:groups` conocidos; jerarquía de `SUPER_ADMINISTRATOR` en el guard | Firma ajena → 401; grupo desconocido no concede rol; `ADMINISTRATOR` no satisface `SUPER_ADMINISTRATOR` |
| Toda ruta nace protegida; `@Public()` para abrir | Dependencia global de identidad; apertura explícita por ruta | Una ruta nueva sin marcar responde 401 sin token |
| `@InternalOnly()` HMAC-SHA256 | Mismo esquema (`x-internal-service`, `x-internal-timestamp`, `x-internal-signature`, JSON canónico, ventana de 30 s) | Vectores de las pruebas de Wallet pasan; un byte alterado → 403 |
| No arranca en producción con `AUTH_MODE=disabled` ni persistencia en memoria | Misma validación al arrancar | La CI arranca la imagen así y exige que muera |
| Sondas `/api/health/live`, `/api/health/ready`, `/api/version` | Idénticas | Ready 200 con base; **503 con la base parada y el proceso vivo** |
| Pool de `pg` con oyente de `error` | `psycopg_pool` con verificación de conexión | Misma prueba de CI que destapó el defecto de Sprint 2 |
| Migraciones propias numeradas, contenedor `<svc>-migrate` | SQL numerado (`001-...sql`), tabla `_migrations`, `chatbot-migrate` | Numeración secuencial, nunca por fecha |
| Jest ≥ 80 % en dos suites, Testcontainers | pytest + pytest-cov ≥ 80 % en unitaria y `db` (testcontainers-python) | El comando falla por debajo del umbral |
| ESLint + Prettier + `typecheck` | ruff (lint y formato) + mypy estricto | Fallo de CI |
| `npm ci` desde lockfile | **uv** con `uv.lock` (`uv sync --frozen`) | Lockfile obligatorio |
| Imagen `node:24-alpine`, `USER node`, multi-arquitectura | `python:3.13-slim` (Alpine no tiene ruedas de numpy), usuario no root, `linux/amd64,linux/arm64` | Ruedas `cp313 manylinux aarch64` comprobadas en PyPI para scikit-learn 1.9.1, numpy 2.5.3, scipy 1.18.1 y psycopg-binary 3.3.6 |
| Checks `Calidad y pruebas`, `Imagen del servicio`, `develop antes que main` | Mismos nombres | Los rulesets se copian de Wallet sin tocar nombres |

**Lista blanca de acciones:** los repositorios admiten `actions/*`,
`github/codeql-action/*`, `docker/setup-buildx-action@*` y
`docker/build-push-action@*`. `actions/setup-python` está incluida;
`astral-sh/setup-uv` **no**, así que uv se instala con `pip install uv`. La lista
no se amplía.

**Versiones de partida** (PyPI, 2026-09-30): Python 3.13, FastAPI 0.142.2,
uvicorn 0.54.0, pydantic 2.13.5, scikit-learn 1.9.1, numpy 2.5.3, joblib 1.6.0,
PyJWT 2.15.1, cryptography 50.0.2, psycopg 3.3.6, psycopg-pool 3.3.3,
pytest 9.1.1, pytest-cov 7.1.0, testcontainers 4.15.0, ruff 0.16.9, mypy 2.3.1,
import-linter 2.15, uv 0.12.21.

**Tournament no tiene excepción**: hereda íntegro el arquetipo de ADR-002 y se
crea copiando el andamiaje de Wallet, igual que en Sprint 2.

### Motor propio del Chatbot

- **Clasificador de intención**: `TfidfVectorizer` con n-gramas de caracteres
  (`char_wb`, 2 a 5) + `LogisticRegression`. Los n-gramas de caracteres toleran
  errores ortográficos y no necesitan un tokenizador por idioma, así que la
  misma tubería sirve para español e inglés (§7.4.2).
- **Umbral de confianza**: por debajo, el bot no inventa. Ofrece preguntas
  relacionadas y la vía de escalamiento (HU-49).
- **Datos de entrenamiento**: las variaciones de pregunta de la base de
  conocimiento (HU-53) y las conversaciones etiquetadas tras revisión (HU-51).
  Ninguna conversación entra al entrenamiento sin pasar por esa revisión.
- **Ciclo de vida del modelo (HU-54)**:
  1. Entrenar produce una versión `CANDIDATE` con métricas sobre un conjunto de
     validación separado (exactitud, F1 por intención, matriz de confusión).
  2. Solo pasa a `ACTIVE` si supera el umbral mínimo **y** a la versión
     vigente. Es «validación antes de desplegar».
  3. La prueba A/B reparte sesiones por hash estable entre `ACTIVE` y
     `CANDIDATE`; cada respuesta guarda la versión que la produjo, que es lo que
     mide HU-52.
- **Entrenamiento dentro del proceso**: con el volumen esperado (miles de
  ejemplos) tarda segundos. Corre en segundo plano con el patrón de
  temporizadores de ADR-019 (estado en la base, una sola ejecución a la vez) y
  `max_features` acotado para que el modelo y su memoria tengan techo.
- **Caché de respuestas frecuentes** (§7.4.9): LRU en proceso con clave
  (versión del modelo, pregunta normalizada). Cambiar de versión la invalida.
  No se añade Redis ni ElastiCache.

### Integraciones

Criterio de [ADR-006](ADR-006-messaging.md): síncrono cuando quien llama no
puede continuar sin la respuesta. Contratos como OpenAPI en `docs/contracts/`
**antes** de implementar.

| Origen | Destino | Operación | Modo | Idempotencia |
| --- | --- | --- | --- | --- |
| Tournament | Account | Validar que los miembros existen y están activos | Síncrono | — |
| Tournament | Wallet | Cobrar la inscripción en créditos; reembolsar si el cupo no se confirma; abonar el premio al campeón | Síncrono | `operationId` |
| Tournament | Player/Inventory | Compromiso `TOURNAMENT` del héroe; liberarlo; entregar la recompensa épica (`grants`) | Síncrono | `operationId` |
| Tournament | Combat | Crear la sala de una justa con participantes fijos; consultar su resultado | Síncrono | `operationId` (= justa) |
| Combat | Tournament | Notificar el resultado de una sala vinculada a una justa | Síncrono, con reintento; Tournament también puede consultarlo | `roomId` |
| Tournament, Chatbot | Notifications | Avisos (inscripción, próxima justa, ticket de soporte) | Asíncrono por ingesta HTTP | Identificador del mensaje |
| Chatbot | Rutas `/me` públicas de Player/Inventory, Missions, Auction, Wallet, Notifications y Tournament | Leer los datos del propio usuario (HU-48) | Síncrono | Solo lectura |

**Chatbot no recibe privilegios propios.** Para leer datos del jugador reenvía
**el testimonio del propio usuario** a las rutas públicas `/me` que ya existen,
por la red interna. Por eso no necesita figurar en ningún `INTERNAL_CALLERS`,
solo ve lo que el usuario ya podría ver, y una cuenta sin sesión solo recibe la
base de conocimiento pública. Es lo que exigen HU-48 («nunca datos de otro
usuario») y HU-50 («los permisos del propio usuario, sin privilegios
adicionales»).

**Cambios en contextos existentes**, todos aditivos y cada uno en el PR de la HU
que lo necesite:

| Contexto | Cambio | HU |
| --- | --- | --- |
| Wallet | Rutas internas de cobro/reembolso de inscripción y abono de premio, modeladas sobre `auction-publication-fees` y `credits/mission-reward`; `tournament` en la lista de esas rutas | HU-84, HU-86 |
| Player/Inventory | Compromiso con propósito `TOURNAMENT`; `tournament` autorizado en `grants` **por ruta** (`@InternalCallers`), sin ampliar la lista global | HU-77/HU-85, HU-86 |
| Combat | Ruta interna para crear la sala de una justa; adaptador HTTP del publicador de resultados hacia Tournament; rol de espectador de solo lectura en el WebSocket | HU-85, HU-80, HU-79/HU-81 |
| Notifications | Plantillas nuevas; es un cambio de contrato en `event-catalog.md` | Varias |
| Web | Módulos `tournament` y `chatbot` con la línea visual del remaster (EN-029/EN-030) | Todas |

### JcE de Jugar Online queda dentro de Combat

Hacer que la IA juegue en una sala JcE **no crea un contexto**: la IA no posee
datos. Su comportamiento opera sobre el agregado de batalla y el documento exige
que «las normas de combate son idénticas» con IA o con jugadores (§6.1). Vivirá
en Combat, reutilizando las conductas de `MissionSimulation`
(`AGGRESSIVE`, `GUARDED`, `BOSS`) y las mismas políticas de ataque, habilidad y
Poder que un humano. **Ninguna HU lo cubre todavía**: se implementará cuando el
Product Owner la cree. Tournament depende de ello para que los equipos de IA
rellenen y jueguen el bracket.

### Topología y coste

La topología T2 de [ADR-011](ADR-011-deployment-topology.md) **no cambia** y
**ninguna instancia cambia de tipo**:

| Escenario | Suma de `mem_limit` en marcha | Memoria del nodo `app` |
| --- | ---: | ---: |
| Hoy | 1 744 MiB | 3 830 MiB (`t4g.medium`) |
| **Con Tournament (160 MiB) y Chatbot (384 MiB)** | 2 288 MiB | 3 830 MiB |

El límite de Chatbot (384 MiB) es una estimación: numpy, scipy y scikit-learn
cargados ocupan bastante más que un servicio NestJS en reposo. Se mide con
`docker stats` tras desplegar y se corrige en este ADR. El nodo `data` solo gana
dos bases lógicas en un PostgreSQL que usa 103 de 288 MiB.

**Coste añadido: 0 USD.** Este ADR **no introduce ningún servicio de AWS nuevo**:
ningún LLM gestionado (Bedrock), ninguna base de conocimiento gestionada
(Bedrock Knowledge Bases exigiría OpenSearch Serverless, incompatible con el
techo de 100 USD), ninguna caché gestionada y ninguna cola.

**Riesgo declarado:** `user_data` del nodo `app` viaja comprimido con un límite
de 16 KB (`infra/modules/compute/main.tf`). Hoy `compose/nodes/app.yml` comprime
a ~8,6 KB y el Caddyfile a ~3,5 KB. Dos servicios más caben, pero el `plan` debe
comprobarlo antes del `apply`.

## Consecuencias

**Lo que se gana**

- Torneo y Chatbot poseen sus datos en exclusiva y pueden desplegarse y fallar
  por separado. Una caída del Chatbot no toca ninguna transacción del juego.
- El Chatbot cumple los requisitos del documento sobre entrenamiento,
  validación y A/B con un modelo propio, auditable y sin coste por consulta.
- Ninguna capacidad de lectura del Chatbot exige privilegios internos nuevos.
- Ningún servicio de AWS nuevo, ninguna cola y ningún cambio de instancia.

**Lo que cuesta**

- **Dos lenguajes de backend.** Las piezas transversales (verificación de
  Cognito, firma interna, sondas, migraciones) existen dos veces, y un cambio en
  una de ellas debe aplicarse en las dos. Se mitiga con los vectores de
  conformidad compartidos (pruebas del uno usadas como casos del otro) y se
  acepta porque la alternativa era reimplementar aprendizaje automático en
  TypeScript.
- **Quince contenedores de larga duración** en el nodo `app` (más once de
  migración). Cada cambio de composición reemplaza el nodo.
- **Un modelo propio responde peor que un LLM** a preguntas abiertas fuera de
  la base de conocimiento. Es una decisión de producto: el bot reconoce lo que
  no sabe y escala, en vez de inventar.
- Tournament depende de cambios en Combat, Wallet y Player/Inventory que son de
  otros Teams: los contratos van primero y cada Team trabaja contra adaptadores
  en memoria mientras tanto.
- Entrenar dentro del proceso consume memoria del mismo contenedor que atiende
  consultas. Se acota con `max_features` y se mide.

## Alternativas consideradas

| Alternativa | Por qué se descartó |
| --- | --- |
| Torneo como módulo de Combat | Convierte al servicio de tiempo real en dueño de un proceso de semanas con pagos; mezcla dos ciclos de vida en un almacén |
| Chatbot con LLM gestionado (Amazon Bedrock) | Cumple el lenguaje natural con menos trabajo, pero el documento pide un modelo **entrenable** con validación y A/B propios, y el producto decidió no depender de un tercero. Añadiría un servicio de AWS, coste por consulta y un ADR de coste |
| Bedrock Knowledge Bases para la base de conocimiento | Requiere un almacén vectorial gestionado (OpenSearch Serverless) cuyo mínimo supera el techo mensual de ADR-007 |
| Chatbot en NestJS con un clasificador escrito a mano | Mantiene un solo lenguaje, pero reimplementa vectorización, regresión y validación sin la madurez de scikit-learn; el riesgo de un modelo mal validado es mayor que el de dos lenguajes con paridad comprobada |
| Chatbot sin modelo (reglas y palabras clave) | No cumple §7.4.2 (intención, errores ortográficos, formulaciones distintas) ni HU-54 |
| Base vectorial con pgvector | PostgreSQL del nodo `data` es `postgres:17-alpine` sin la extensión; cambiar la imagen reemplaza el nodo `data`. El full-text basta para la base de conocimiento |

## Lo que este ADR no hace

- No define los contratos detallados: se publican en `docs/contracts/` antes de
  implementar cada integración.
- No decide las reglas de producto pendientes. Son del Product Owner:
  - **Formato de la justa**: el documento dice «equipos de dos jugadores con un
    máximo de seis por batalla» y Combat solo admite equipos iguales de 1 a 3.
  - Cuota de inscripción, quién la paga y reembolsos; «dinero real» frente a la
    pasarela simulada de HU-84.
  - Reparto del premio entre los dos miembros y qué ocurre si gana un equipo de IA.
  - Empates, incomparecencias y correcciones de resultado.
  - Destino de los tickets de HU-49 y qué es «generar reportes de actividad» en
    HU-50.
  - Retención del historial del chatbot (la política de privacidad ya prevé su
    borrado).
  - La HU de JcE para Jugar Online.

## Evidencia de aceptación

- Validado por Product Owners y Scrum Masters el 2026-09-30: nombres, alcance y
  existencia de los dos repositorios, la excepción de Python para Chatbot y el
  plan de creación y despliegue.
- Team propietario asignado el 2026-09-30: **Chatbot → Team Alfa**;
  **Tournament → Team Beta y Team Gama** (propiedad compartida en `CODEOWNERS`).

## Estado de despliegue

| Estado | Vigente desde |
| --- | --- |
| **Accepted** | 2026-09-30 |
| Repositorios creados con CI verde, imagen publicada y `main`/`develop` protegidas | Pendiente |
| Bases y usuarios creados en el nodo `data` | Pendiente |
| Nodo `app` con los dos servicios | Pendiente |
