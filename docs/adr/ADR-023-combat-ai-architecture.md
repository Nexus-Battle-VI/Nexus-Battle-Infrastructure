# ADR-023 — Arquitectura de inteligencia artificial de combate

- **Estado:** Proposed — no existe todavía evidencia registrada de aprobación formal bajo EN-025 (ver «Evidencia de aceptación»)
- **Fecha:** 2026-10-03
- **Decide:** Arquitectura, pendiente de validación de Product Owner/Scrum Master conforme a la gobernanza de [ADR-001](ADR-001-repository-strategy.md) y a `EN-025` #204
- **Relacionado:** [ADR-001](ADR-001-repository-strategy.md), [ADR-002](ADR-002-backend-stack.md), [ADR-005](ADR-005-data-strategy.md), [ADR-007](ADR-007-aws-cost-optimized-platform.md), [ADR-011](ADR-011-deployment-topology.md), [ADR-019](ADR-019-sprint-2-bounded-contexts.md), [ADR-020](ADR-020-realtime-combat.md), [ADR-021](ADR-021-combat-randomness-and-effect-table.md), [ADR-022](ADR-022-sprint-3-bounded-contexts.md), [EN-025 #204](https://github.com/Nexus-Battle-VI/Nexus-Battle-Management/issues/204), [EN-035 #554](https://github.com/Nexus-Battle-VI/Nexus-Battle-Management/issues/554), [EN-036 #555](https://github.com/Nexus-Battle-VI/Nexus-Battle-Management/issues/555), [EN-037 #556](https://github.com/Nexus-Battle-VI/Nexus-Battle-Management/issues/556), [HU-93 #553](https://github.com/Nexus-Battle-VI/Nexus-Battle-Management/issues/553), [HU-71 #56](https://github.com/Nexus-Battle-VI/Nexus-Battle-Management/issues/56), [HU-72 #57](https://github.com/Nexus-Battle-VI/Nexus-Battle-Management/issues/57), [EPIC-09 #9](https://github.com/Nexus-Battle-VI/Nexus-Battle-Management/issues/9), [TASK EN-035.1 #561](https://github.com/Nexus-Battle-VI/Nexus-Battle-Management/issues/561)

## Contexto

`Nexus-Battle-Combat` ya modela participantes `HUMAN`/`AI` (`ParticipantKind`,
`Participant.ts`) y exige al menos un participante `AI` en toda sala `PVE`
(`BattleRoom.validateModeComposition`), pero **ningún participante `AI` actúa
todavía**: la validación es solo estructural. [ADR-022](ADR-022-sprint-3-bounded-contexts.md)
ya dejó escrito que «las salas JcE se crean, pero la IA no actúa: los
participantes `AI` no tienen perfil y su turno se cierra sin acción» y que
«JcE de Jugar Online queda dentro de Combat» cuando exista la HU — esa HU ya
existe (`HU-93 #553`).

El comportamiento de decisión automática que existe hoy **no es uno solo**.
Dentro de `src/application/services/MissionSimulation.ts` conviven dos
mecanismos distintos, ninguno extraído a una interfaz reusable:

- `chooseAction()` (línea 268), que decide la acción del **héroe** del
  jugador evaluando las tres rotaciones priorizadas de HU-71 y cayendo a
  ataque básico sin Poder si ninguna es viable (CA-03 de HU-71).
- Reglas simples del **enemigo**, condicionadas por su campo `ai`
  (`AGGRESSIVE`/`GUARDED`/`BOSS`): un `GUARDED` se defiende cada tercer turno
  (`if (base.ai === 'GUARDED' && turns % 3 === 0) { guard = 4; ... }`) y un
  `BOSS` cambia a modo enfurecido según su salud restante
  (`base.ai === 'BOSS' && enemyHealth * 100 <= enemy.maxHealth * (base.enrageBelowPercent ?? 50)`),
  mientras que `AGGRESSIVE`/el comportamiento por defecto ataca sin condición
  especial.

Ambos mecanismos están **acoplados** a `MissionSimulation.ts`: ninguno es una
clase independiente, ninguno implementa todavía `AiDecisionPort` y ninguno lo
consume JcE porque JcE todavía no tiene IA. El motor de aleatoriedad
autoritativo ya existe y está separado
(`Mt19937BoxMullerRandomSequenceFactory`, `RandomIndex`, `RandomSeed`,
[ADR-021](ADR-021-combat-randomness-and-effect-table.md)); ninguna política de
IA debe introducir una fuente paralela.

`EN-035 #554` pide congelar, antes de implementar nada, el contrato de
decisión (`BattleDecisionState → legalActions → ActionIntent` vía
`AiDecisionPort`) y las políticas intercambiables (`RandomPolicy`,
`RuleBasedPolicy`, y más adelante `MctsPolicy`/`NeuralPolicy` de
`EN-036 #555`/`EN-037 #556`). Esta Task (`EN-035.1 #561`) es exclusivamente
documental: congela la arquitectura para que `#562`, `#563`, `#564` y los
Enablers `#555`/`#556` tengan una base común antes de escribir código.

**Verificado en el código actual** (auditoría del 2026-10-03, rama `develop`):

| Elemento | Estado |
| --- | --- |
| `package.json` de Combat | Node `>=24 <25`, `@nestjs/core` `11.2.1`, `typescript` `5.9.3`, `mongodb` `6.21.0` |
| `BattleDecisionState`, `LegalAction`, `ActionIntent`, `AiDecisionPort` | No existen en `src/` |
| `RandomPolicy`, `RuleBasedPolicy`, `MctsPolicy`, `NeuralPolicy` | No existen en `src/` |
| `CombatDecisionEvent` | No existe en `src/` |
| `chooseAction()` (héroe) | Existe, acoplado a `MissionSimulation.ts`, no extraído |
| Reglas de enemigo `AGGRESSIVE`/`GUARDED`/`BOSS` | Existen, acopladas a `MissionSimulation.ts`, no extraídas |
| Participante `AI` (JcE) | Modelado estructuralmente (`ParticipantKind.Ai`); sin turno autónomo |
| RNG autoritativo | Existe y está centralizado (`Mt19937BoxMullerRandomSequenceFactory`) |

## Fuerzas / restricciones

- `RNF-12` (microservicios) y [ADR-019](ADR-019-sprint-2-bounded-contexts.md)/[ADR-022](ADR-022-sprint-3-bounded-contexts.md): un bounded context se crea por propiedad de datos, no por capacidad técnica.
- [ADR-007](ADR-007-aws-cost-optimized-platform.md): techo de **USD 100/mes**, sin RDS/DocumentDB/ECS/Fargate/EKS nuevos, S3 ya cerrado salvo la excepción de [ADR-016](ADR-016-product-asset-storage.md).
- [ADR-021](ADR-021-combat-randomness-and-effect-table.md): el RNG autoritativo de Combat es único; ninguna política de decisión puede introducir una fuente paralela ni observar el valor futuro real (semántica de stream vivo vs. stream de simulación detallada en «Políticas»).
- `HU-93 #553`: alcance productivo actual es **Humano vs IA 1v1**, sin tocar `Nexus-Battle-Tournament`.
- `EN-025 #204`: toda tecnología no impuesta por un requisito explícito debe pasar por comparación de alternativas antes de aprobarse como línea base.
- `RF-14 / §7.6` (citado textualmente en `HU-93 #553`): «Jugar Online con participante controlado por IA y estrategias aprendidas a partir de partidas almacenadas» — el requisito de aprender de partidas, no solo de ejecutar reglas fijas, es funcional y no una preferencia técnica.
- `EN-036 #555`: «El documento exige aprendizaje profundo» — el Enabler registra la exigencia de Deep Learning como motivación explícita para `MctsPolicy`/`NeuralPolicy`; no se localizó en los documentos de Infrastructure auditados un número de sección específico del curso para esa frase, así que aquí se cita la fuente verificada (el Enabler), no un `§` inventado.
- `docs/architecture/hu-72-simulacion-mision.md` (fuente funcional: documento del curso §7.8.1/§7.8.5/§7.8.6/§7.8.8/§7.8.12, CA-03 de HU-72): «se aplican las mismas mecánicas de combate y el mismo motor de aleatoriedad que en las batallas en línea» — ya reflejado en «Combat manda» y en el RNG único de este ADR.

## Decisión

### Frontera del bounded context

**La IA de juego no constituye un bounded context ni un microservicio
separado.** Vive dentro de `Nexus-Battle-Combat`, el mismo servicio que ya es
dueño de la batalla, sus reglas, su RNG autoritativo y su persistencia
([ADR-019](ADR-019-sprint-2-bounded-contexts.md), [ADR-020](ADR-020-realtime-combat.md),
[ADR-021](ADR-021-combat-randomness-and-effect-table.md)). Esto extiende
literalmente la decisión ya tomada en [ADR-022](ADR-022-sprint-3-bounded-contexts.md)
(«JcE de Jugar Online queda dentro de Combat»); este ADR no la reabre, la
desarrolla.

```text
                    Nexus-Battle-Combat
                            |
                 BattleDecisionState
                            |
                    LegalAction[]
                            |
                     AiDecisionPort
                            |
      +----------------+----------------+----------------+
      |                |                |                |
 RandomPolicy    RuleBasedPolicy    MctsPolicy       NeuralPolicy
      |                |                |                |
      +----------------+----------------+----------------+
                            |
                       ActionIntent
                            |
                     Combat valida de nuevo
                            |
                        Combat ejecuta
                            |
                           RNG
                            |
                       transición
```

Las cuatro políticas son implementaciones **hermanas** de `AiDecisionPort`: en
runtime productivo, `NeuralPolicy` nunca invoca a `MctsPolicy` turno a turno
— cada política resuelve `BattleDecisionState + legalActions → ActionIntent`
de forma independiente, y Combat vuelve a validar el resultado sin importar
cuál la produjo. `MctsPolicy` participa en runtime como una política más
intercambiable (p. ej. para evaluación comparativa de `EN-036.5 #569`), no
como un paso obligatorio antes de `NeuralPolicy`.

La relación entre MCTS y la red neuronal es **offline, de entrenamiento**, no
de ejecución en el turno: MCTS actúa como teacher que genera las etiquetas
que luego entrena la MLP en PyTorch, que se exporta a ONNX para convertirse
en `NeuralPolicy`:

```text
BattleDecisionState
        |
        v
    MctsPolicy (teacher, offline)
        |
        v
  etiquetas/distribuciones
        |
        v
    entrenamiento PyTorch
        |
        v
    exportación ONNX
        |
        v
      NeuralPolicy (runtime productivo)
```

**Combat manda.** La IA decide únicamente qué acción intentar entre acciones
ya validadas como legales. La IA no calcula ni redefine daño, defensa, Poder,
cooldown, críticos, tablas RNG, drop, experiencia, recompensas, targets
legales, condiciones de victoria ni persistencia de inventario — todo eso
sigue siendo autoridad exclusiva del motor de Combat.

### Contrato de decisión

Semántica conceptual (sin DTOs de código todavía, conforme al alcance
documental de esta Task):

- **`BattleDecisionState`**: estado observable necesario para decidir. Excluye
  explícitamente JWT, correo, cualquier dato personal, la semilla futura del
  RNG y el próximo valor aleatorio real (CA-06 de `EN-035`).
- **`LegalAction`**: una acción que Combat ya determinó ejecutable, incluido
  su target válido. La genera y la garantiza Combat, nunca una política.
- **`ActionIntent`**: la intención única que produce cualquier política,
  independiente de su implementación.
- **`AiDecisionPort`**: la frontera que permite intercambiar la política sin
  tocar el motor.

```text
Combat state
   ↓
BattleDecisionState
   ↓
LegalActionGenerator
   ↓
AiDecisionPort
   ↓
ActionIntent
   ↓
Combat valida nuevamente
   ↓
Combat ejecuta
```

Defensa doble: la política solo puntúa `legalActions` ya calculadas por
Combat; Combat vuelve a validar el `ActionIntent` recibido antes de
ejecutarlo. Ninguna política puede mutar el agregado directamente.

### Políticas

**Semántica única del RNG, antes de describir cada política:** Combat sigue
siendo dueño de **toda** la aleatoriedad ([ADR-021](ADR-021-combat-randomness-and-effect-table.md)).
Eso no significa que exista un solo stream físico para todo: el **stream
vivo** de resolución (crítico, daño, efectos de la batalla productiva,
`RandomIndex`/`RandomSeed` avanzando turno a turno) es distinto de cualquier
**stream de simulación** que una búsqueda, un rollout o `RandomPolicy`
necesiten consumir para explorar alternativas. Un stream de simulación nace
de una semilla propia, aislada y explícita (nunca comparte cursor con la
batalla real), y consumirlo jamás adelanta ni observa el próximo valor real
que Combat vaya a usar para resolver la batalla en curso. Ambos stream siguen
siendo responsabilidad de Combat — ninguna política implementa su propio
generador paralelo; lo que cambia es cuál semilla/cursor consume cada uno.

**`RandomPolicy`** — piso experimental. Elige exclusivamente entre
`legalActions` usando un stream de simulación aislado del escenario de
prueba/simulación, nunca el stream vivo de resolución de las reglas de
combate (crítico, daño, efectos), que sigue siendo exclusivo de
[ADR-021](ADR-021-combat-randomness-and-effect-table.md).

**`RuleBasedPolicy`** — preserva el comportamiento determinista existente de
`chooseAction()`/`MissionSimulation`. Actúa como baseline, como fallback
productivo, y como rollout policy inicial de MCTS. **Todavía no existe como
clase separada**; este ADR no afirma que la extracción ya ocurrió, solo la
decide para `EN-035.3 #563`.

**`MctsPolicy`** — teacher offline para generación/evaluación de decisiones,
no la política productiva principal inicial. Debe operar sobre el motor/
simulador real de Combat, muestreando futuros mediante su propio stream de
simulación aislado; no debe conocer el próximo RNG real, la semilla futura
ni el cursor del stream vivo de resolución de la batalla productiva.

**`NeuralPolicy`** — inferencia rápida en runtime, implementación de
`AiDecisionPort`. Recibe `BattleDecisionState + CandidateAction` y produce un
`score`; no tiene una salida global fija por `abilityId`. La acción final se
obtiene por `argmax` sobre los candidatos legales.

```text
State + CandidateAction
        ↓
      score
        ↓
argmax sobre candidatos legales
```

### Search teacher: MCTS frente a Minimax/Expectiminimax

| Alternativa | Evaluación |
| --- | --- |
| Minimax + alpha-beta | Encaja con juegos adversariales deterministas; Nexus tiene azar (críticos, efectos, tabla de efectos) y no modela nodos `CHANCE` de forma natural |
| Expectiminimax | Sí representa `MAX`/`MIN`/`CHANCE`, conceptualmente válido; pero el árbol crece rápido con habilidades, targets, RNG y la futura composición multipersonaje, y alpha-beta pierde parte de su ventaja con muchos nodos de azar |
| **MCTS (seleccionada)** | No necesita expandir todo el árbol, aprovecha el simulador acelerado existente, permite rollouts y es apropiado como teacher offline reutilizando `RuleBasedPolicy` en los rollouts |

Expectiminimax queda registrado como alternativa académica válida, no como
requisito de implementación v1.

### Deep Learning: PyTorch frente a TensorFlow/Keras

| Criterio | PyTorch | TensorFlow/Keras |
| --- | --- | --- |
| Compatibilidad con Deep Learning académico | Sí | Sí |
| Facilidad de experimentación/depuración | Alta (modo eager por defecto) | Requiere más andamiaje para el mismo flujo |
| Imitation/supervised learning pequeño | Directo | Directo, más verboso |
| Exportación a ONNX | Soportada de forma nativa (`torch.onnx`) | Soportada, con una ruta de conversión adicional |
| No obliga runtime Python en el request path de Combat | Sí (entrenamiento offline, inferencia por ONNX Runtime Node) | Sí, misma condición |
| Mantenibilidad académica/comunidad | Alta | Alta |
| Licencia | BSD-3-Clause | Apache-2.0 |

**Decisión: PyTorch para entrenamiento.** Razones: red neuronal pequeña,
experimentación académica sencilla, buen ecosistema, facilidad para
evolucionar a policy/value networks más adelante, exportación ONNX directa, y
no obliga a ejecutar Python dentro del camino de petición de Combat. **No se
fija todavía una versión exacta** — se fija en `uv.lock` cuando el spike de
`EN-036.2 #566` confirme compatibilidad real con Python 3.13, CPU, y la
arquitectura del contenedor de despliegue.

### Modelo neuronal v1 (configuración experimental, no requisito funcional)

```text
input
  ↓
Linear(64)
  ↓
ReLU
  ↓
Linear(32)
  ↓
ReLU
  ↓
Linear(1 score)
```

Entrenamiento inicial: optimizer `AdamW`, learning rate `0.001`, batch size
`256`, máximo `30` epochs, early stopping a `5` epochs sin mejora. Estos
valores son hiperparámetros configurables y versionados — **no son reglas de
negocio** y pueden cambiar con evidencia de `EN-036.3 #567`.

### ONNX

```text
PyTorch
   ↓
export
   ↓
ONNX model
   ↓
ONNX Runtime Node
   ↓
NeuralPolicy dentro de Combat
```

No hay microservicio de model-serving: la inferencia corre dentro del proceso
de Combat. **ONNX Runtime Node queda seleccionado arquitectónicamente,
condicionado a un spike de compatibilidad** con el Node/arquitectura real de
Combat, trazado a `EN-036.4 #568`. Esta Task no instala ni afirma que la
dependencia ya funciona con la imagen productiva actual.

### Pipeline de entrenamiento y dataset

**No se usa base vectorial.** El problema es decisión sobre estado
estructurado (features numéricas/categóricas de un estado de combate), no
búsqueda semántica sobre texto/embeddings — son dos cosas distintas aunque
ambas usen la palabra «vector».

```text
CombatDecisionEvent
      ↓
MongoDB propio de Combat (append-only, versionado, sin PII)
      ↓
training manifest / cutoff reproducible
      ↓
feature encoder
      ↓
PyTorch
```

Fuentes: JcJ, JcE, Misiones, y Torneos/cualquier modalidad futura **cuando**
ejecuten el mismo flujo de Combat — esta arquitectura no implementa IA de
Torneos ahora, solo no le cierra la puerta (ver «JcE, Misiones y Torneos»).

Cada training run registra: data cutoff, cantidad de batallas, cantidad de
decisiones, `featureSchemaVersion`, `teacherVersion`, `utilityVersion`,
`sourceCommit`, `seed`. Split determinista por hash estable de `battleId`
(0–79 `TRAIN`, 80–89 `VALIDATION`, 90–99 `TEST`) para que ninguna decisión de
una misma batalla cruce entre splits. Parquet queda opcional para analítica
futura, no es dependencia del MVP; JSON/JSONL sirve para debugging/fixtures;
Mongo es la fuente raw de la demo.

No se interpreta «cada partida alimenta el aprendizaje» como «copiar el
dataset completo tras cada partida» — no existe un «dataset N+1» físico por
batalla, solo el raw append-only más el manifiesto de corte.

### Persistencia y model lifecycle

```text
TRAINING → CANDIDATE → EVALUATING → ACTIVE | REJECTED
```

Metadata mínima por versión: `modelVersion`, `featureSchemaVersion`,
`teacherVersion`, `utilityVersion`, `trainingRunId`, `sourceCommit`,
`trainingSeed`, métricas, hash del artefacto, `createdAt`, estado.

**No se adopta S3 nuevo**; [ADR-007](ADR-007-aws-cost-optimized-platform.md)
y [ADR-016](ADR-016-product-asset-storage.md) no lo autorizan para esta
capacidad. Para el MVP, la metadata y el model registry viven en la
persistencia propia de Combat (MongoDB). El mecanismo exacto para el binario
ONNX dentro de Mongo (BSON Binary frente a GridFS u otra alternativa) **no
está validado todavía** y queda como detalle técnico pendiente de
`EN-037.1 #570` — este ADR no lo decide por adelantado.

### Entrenamiento continuo

```text
BattleCompleted
      ↓
persistir decision events
      ↓
training requested
      ↓
worker observa pendiente
      ↓
TRAIN → CANDIDATE → EVALUATE → ACTIVE / REJECTED
```

Máximo un training concurrente. Si llegan partidas nuevas mientras entrena:
`trainingRunning = true`, `newDataPending = true`; al terminar, si
`newDataPending`, se ejecuta otra iteración (coalescing). El worker **no** es
un bounded context nuevo, no tiene API pública, no necesita puerto propio y
pertenece técnicamente a Combat (paquete `Combat/ai`, Python aislado del
runtime Node).

### Promoción y fallback

- **Gate de seguridad:** 0 acciones ejecutadas fuera de `legalActions`; 0
  crashes; 0 `NaN`; 0 decisiones vacías.
- **Gate de paridad:** PyTorch ≈ ONNX dentro de la tolerancia numérica
  validada sobre fixtures fijos.
- **Gate frente a Random:** `NeuralPolicy` ≥ 60 % de victorias frente a
  `RandomPolicy`.
- **Gate frente a RuleBased:** `NeuralPolicy` ≥ 45 % de victorias frente a
  `RuleBasedPolicy`.

Estos umbrales son línea base técnica v1, versionada junto con la política de
promoción, y revisable con evidencia — no son requisitos funcionales fijos
del producto.

```text
CANDIDATE
   ↓ gates
PASS → ACTIVE
FAIL → REJECTED
```

Una candidata nunca sustituye al modelo `ACTIVE` sin pasar los gates.
Fallback: si `NeuralPolicy` falla o no existe un `ACTIVE` compatible, Combat
usa `RuleBasedPolicy`. Una batalla nunca se bloquea por indisponibilidad del
modelo neuronal.

### Función de utilidad (JcE/Misiones)

`pve-utility-v1`:

```text
U = 0.60·W + 0.15·H + 0.10·P + 0.15·D
```

- `W`: probabilidad/resultado de victoria o éxito del encuentro.
- `H`: proporción de salud propia conservada.
- `P`: proporción de Poder conservado.
- `D`: progreso de daño sobre el enemigo.

La dificultad de Misiones modifica estadísticas, nunca esta función, ni el
modelo, ni sus pesos, ni la policy.

**Regla de salud:** `healthRatio = currentHealth / maxHealth`. Una acción cuyo
efecto principal sea curación solo se considera candidata estratégica cuando
`healthRatio < 0.90` del objetivo; no obliga a curar, solo evita premiar
curación casi completa. Curación efectiva para la utilidad:
`effectiveHealing = min(healingAmount, missingHealth)`.

### JcE, Misiones y Torneos

**Rotaciones (HU-71/HU-72) como restricción del espacio de decisión:**

```text
rotaciones del jugador
       ↓
Combat determina acciones permitidas/viables
       ↓
legalActions
       ↓
AiDecisionPort
       ↓
la política decide estratégicamente dentro de ese conjunto
```

El modelo no puede ignorar una restricción funcional de rotaciones; las
rotaciones tampoco reducen necesariamente el futuro modelo a un `if/else`
determinista — dentro del conjunto viable, la política sigue decidiendo
estratégicamente. Si ninguna rotación es viable, fallback a ataque básico
conforme HU-71 (comportamiento ya implementado hoy en `chooseAction()`).

**Épica del bot (HU-93):** `P(con épica) = 0.05`, `P(sin épica) = 0.95`. Si el
sorteo es positivo: como máximo una épica, compatible con el héroe, definida
en Catalog, sin requerir ownership real. El sorteo usa la fuente de RNG
autoritativa — nunca `Math.random()` disperso.

**JcE Online v1 — alcance actual:** Humano vs IA, 1v1 únicamente. El bot no
tiene cuenta, no tiene `playerId` real, no tiene inventario real; usa
definiciones válidas de Catalog y actúa automáticamente vía `AiDecisionPort`
cuando llega su turno; Combat valida todo. Economía: si la IA gana, no recibe
créditos/experiencia/objetos/drop; si el humano pierde, su equipo no se
transfiere al bot; si el humano gana, el equipo del bot no se transfiere al
humano. Nada de esto está implementado todavía — es el alcance que `HU-93`
construirá sobre este contrato.

**Torneos — delimitación obligatoria:** esta Task y los Enablers `EN-035`/
`EN-036`/`EN-037` **no implementan IA de Torneo**. `EPIC-09` sí contempla
equipos de IA para completar el bracket, pero esa integración requerirá su
propia HU/Task en `Nexus-Battle-Tournament`. Lo único que esta arquitectura
garantiza es que `AiDecisionPort` es suficientemente genérico para que
Tournament, en el futuro, pueda pedir «necesito un participante AI» y
reutilizar el mismo motor:

```text
Tournament
    ↓
crea/solicita justa con participantes AI
    ↓
Combat
    ↓
BotParticipantFactory
    ↓
AiDecisionPort
```

No se implementan ahora equipos completos de bots ni 2v2/3v3 de IA. Ningún
archivo de `Nexus-Battle-Tournament` cambia en esta Task.

### Responsabilidades por repositorio

| Repositorio | Responsabilidad |
| --- | --- |
| `Nexus-Battle-Combat` | Participant AI; `BattleDecisionState`; `LegalAction`; `ActionIntent`; `AiDecisionPort`; `RandomPolicy`; `RuleBasedPolicy`; `MctsPolicy`; `NeuralPolicy`; `CombatDecisionEvent`; RNG autoritativo; persistencia raw/model registry; runtime ONNX |
| `Nexus-Battle-Combat/ai` (paquete Python aislado) | Python, PyTorch, feature encoding para training, entrenamiento, evaluación, exportación ONNX, worker de entrenamiento |
| `Nexus-Battle-Missions` | Orquestación de Misiones; configuración congelada de misión; invocación/integración con Combat |
| `Nexus-Battle-Web` | UI; configuración de rotaciones; experiencia JcE si requiere cambios |
| `Nexus-Battle-Catalog` | Definiciones de héroes, armas, armaduras, épicas, compatibilidades, stats/configuración de producto |
| `Nexus-Battle-Player-Inventory` | Ownership e inventario de jugadores humanos; **no** inventario de bots |
| `Nexus-Battle-Infrastructure` | ADR, topología, despliegue posterior del worker/runtime, documentación |
| `Nexus-Battle-Management` | HU, Enablers, Tasks, trazabilidad |
| `Nexus-Battle-Tournament` | Consumidor **futuro**; sin cambios en esta Task |
| `Nexus-Battle-Chatbot` | Sin cambios; IA independiente (ver «Deslinde con Chatbot») |
| `Nexus-Battle-Commerce` / `Nexus-Battle-Auction` | Sin responsabilidad sobre la decisión del bot |

### Deslinde con Chatbot

Según [ADR-022](ADR-022-sprint-3-bounded-contexts.md), Chatbot es **Python
3.13 + FastAPI + scikit-learn**: `TfidfVectorizer` (n-gramas de caracteres) +
`LogisticRegression` para clasificación de intención conversacional. La IA de
combate **no reutiliza scikit-learn como motor neuronal** — son problemas
distintos (clasificación de texto frente a scoring de acciones de combate
sobre estado estructurado). Lo único que comparten ambos es:

- Python 3.13;
- `uv` como gestor de paquetes/lockfile;
- prácticas de versionado de modelo (`CANDIDATE`/`ACTIVE`);
- la idea general de reproducibilidad.

No comparten modelo, dataset, bounded context, ni framework de ML obligatorio
— Chatbot sigue con scikit-learn, la IA de combate usa PyTorch + ONNX.

### Despliegue de demo y costo

Respeta [ADR-007](ADR-007-aws-cost-optimized-platform.md): no se introduce
SageMaker, GPU gestionada, Bedrock, OpenSearch, base vectorial, Redis, otra
instancia EC2, ECS, S3 adicional, ni ningún otro servicio de AWS nuevo. La
propuesta de demo es: el runtime de Combat existente, más un worker técnico
de entrenamiento en CPU, sujeto a medición posterior — no se afirma que la
capacidad actual del nodo alcance hasta que `EN-037.4 #573` mida recursos
reales (mismo criterio de medición que usó [ADR-022](ADR-022-sprint-3-bounded-contexts.md)
con SSM antes de afirmar capacidad disponible).

### Matriz de decisión tecnológica

| Decisión | Alternativas | Seleccionada | Estado |
| --- | --- | --- | --- |
| Framework de Deep Learning | PyTorch / TensorFlow-Keras | PyTorch | Proposed, versión exacta condicionada a spike `EN-036.2` |
| Search teacher | Minimax+AlphaBeta / Expectiminimax / MCTS | MCTS | Proposed |
| Runtime de inferencia | Python service / TF.js / ONNX Runtime Node | ONNX Runtime Node | Proposed, condicionada a spike `EN-036.4 #568` |
| Persistencia dataset/model registry | Mongo de Combat / base vectorial / S3 | Mongo de Combat (MVP) | Proposed — S3 no autorizado actualmente; base vectorial no necesaria |
| Ubicación del servicio | Microservicio de IA / in-process en Combat | In-process en Combat | Proposed, consistente con ADR-022 |

## Estado actual vs capacidad futura

**Ya existe (verificado en `develop` el 2026-10-03):**

- `Nexus-Battle-Combat` como bounded context autoritativo de batalla.
- Participantes `HUMAN`/`AI` estructurales (`Participant.ts`, `ParticipantKind`) y validación de composición `PVE`/`PVP` (`BattleRoom.validateModeComposition`).
- `chooseAction()` rule-based acoplado a `MissionSimulation.ts` (rotaciones HU-71, fallback a ataque básico).
- RNG centralizado y autoritativo (`Mt19937BoxMullerRandomSequenceFactory`, `RandomIndex`, `RandomSeed`), [ADR-021](ADR-021-combat-randomness-and-effect-table.md).
- MongoDB como persistencia de Combat.
- Línea base Node `>=24 <25` / NestJS `11.2.1` / TypeScript `5.9.3` (`package.json` de Combat).
- Decisiones previas de [ADR-019](ADR-019-sprint-2-bounded-contexts.md), [ADR-020](ADR-020-realtime-combat.md), [ADR-021](ADR-021-combat-randomness-and-effect-table.md), [ADR-022](ADR-022-sprint-3-bounded-contexts.md).

**Todavía no existe:**

- `AiDecisionPort`, `BattleDecisionState`, `LegalAction`, `ActionIntent`.
- `CombatDecisionEvent` (ni su persistencia).
- `RandomPolicy` y `RuleBasedPolicy` como clases independientes (hoy es una función cerrada).
- `MctsPolicy`, `BattleUtilityEvaluator`.
- Pipeline PyTorch, paquete `Combat/ai`, dataset/feature encoder.
- `NeuralPolicy` y la integración de ONNX Runtime Node.
- Trainer worker, model registry, gates de promoción automática.
- Bot JcE autónomo completo (`HU-93`).

## Alternativas consideradas

| Alternativa | Por qué se descartó |
| --- | --- |
| Microservicio de IA separado | Rompe la autoridad única de reglas/RNG de Combat ([ADR-020](ADR-020-realtime-combat.md)/[ADR-021](ADR-021-combat-randomness-and-effect-table.md)); añade latencia de red al turno; sin justificación de propiedad de datos distinta, contradice el criterio de [ADR-019](ADR-019-sprint-2-bounded-contexts.md) |
| Base vectorial para telemetría/dataset | El problema es estado estructurado versionado, no búsqueda semántica; Mongo ya cubre append-only con índices |
| TensorFlow/Keras | Viable, pero mayor fricción de experimentación para una red pequeña y exportación ONNX menos directa que PyTorch |
| Model-serving en un servicio Python aparte | Introduce un salto de red en el camino crítico del turno; ONNX Runtime Node permite inferencia in-process sin ese costo |
| S3 para artefactos de modelo | [ADR-007](ADR-007-aws-cost-optimized-platform.md)/[ADR-016](ADR-016-product-asset-storage.md) no lo autorizan para esta capacidad; Mongo de Combat basta para el volumen del MVP |
| Implementar IA de Torneo ahora junto con HU-93 | `HU-93` delimita expresamente el alcance a Humano vs IA 1v1; mezclar el bracket de `EPIC-09` aquí comprometería alcance no pedido por el Product Owner |

## Consecuencias

### Se gana

- Un contrato único (`AiDecisionPort`) que permite sustituir la política sin tocar el motor de Combat.
- Reutilización total del RNG autoritativo existente; ninguna fuente de aleatoriedad paralela.
- Telemetría reusable entre JcJ, JcE y Misiones desde el primer día del contrato.
- Camino incremental: `RandomPolicy`/`RuleBasedPolicy` dan una JcE funcional «aunque tonta» sin esperar a que la red neuronal exista.
- Ningún servicio de AWS nuevo; coste incremental de infraestructura 0 USD en esta Task.

### Cuesta

- Dos lenguajes dentro de Combat: TypeScript/Node para el motor y Python aislado (`Combat/ai`) para entrenamiento — mismo patrón de costo ya aceptado para Chatbot en [ADR-022](ADR-022-sprint-3-bounded-contexts.md), ahora dentro de un único repositorio en vez de entre dos.
- Memoria/CPU del worker de entrenamiento todavía no medida; `EN-037.4` debe medirla antes de afirmar que el nodo `app` la soporta.
- La extracción de `chooseAction()` a `RuleBasedPolicy` debe demostrar cero regresión sobre los escenarios de Misiones ya aprobados (`EN-035.3 #563`).

### Queda prohibido/no adoptado

- Microservicio de IA independiente.
- Base de datos vectorial.
- S3 nuevo para artefactos de modelo o dataset.
- GPU como requisito.
- Reinforcement Learning en esta fase.
- IA de Torneo dentro de `HU-93`/`EN-035`/`EN-036`/`EN-037`.
- Cambios a reglas de daño, Poder, cooldown, RNG o balance para beneficiar al modelo.

## Riesgos

- **Diseñar el dataset antes de estabilizar el contrato de decisión** produciría datasets atados a una representación accidental del código. Mitigación: `EN-035.2`/`EN-035.3` antes que cualquier captura de telemetría de producción.
- **Duplicar reglas dentro de una política** (por ejemplo, que `MctsPolicy` reimplemente validación de daño). Mitigación: `LegalActionGenerator` y la validación final permanecen exclusivamente en Combat; ninguna política calcula resultados de combate.
- **Spike de ONNX Runtime Node sin resultado favorable** retrasaría `NeuralPolicy`. Mitigación: `RuleBasedPolicy` sigue siendo la política productiva válida mientras tanto; el fallback no es un caso de error, es la ruta normal hasta que el spike concluya.
- **Umbrales de promoción (60 %/45 %) mal calibrados** podrían bloquear o permitir promociones indebidas. Mitigación: están versionados (`utilityVersion`) y revisables con evidencia, no son constantes mágicas dispersas en código.

## Evidencia / validaciones pendientes

- Spike de compatibilidad PyTorch + Python 3.13 + arquitectura de despliegue (`EN-036.2 #566`).
- Spike de compatibilidad ONNX Runtime Node con el Node/arquitectura real de Combat (`EN-036.4 #568`).
- Medición de recursos reales del worker de entrenamiento en el nodo `app` (`EN-037.4 #573`), con el mismo método SSM que usó [ADR-022](ADR-022-sprint-3-bounded-contexts.md).
- Validación de paridad numérica PyTorch ↔ ONNX sobre fixtures fijos (`EN-036.3`/`EN-036.5`).
- Decisión técnica pendiente sobre el mecanismo exacto de almacenamiento del binario ONNX dentro de Mongo (`EN-037.1 #570`).

## Trazabilidad

Refs Nexus-Battle-VI/Nexus-Battle-Management#561
Refs Nexus-Battle-VI/Nexus-Battle-Management#554
Refs Nexus-Battle-VI/Nexus-Battle-Management#204
Refs Nexus-Battle-VI/Nexus-Battle-Management#555
Refs Nexus-Battle-VI/Nexus-Battle-Management#556
Refs Nexus-Battle-VI/Nexus-Battle-Management#553

## Evidencia de aceptación

Ninguna todavía. Esta Task (`EN-035.1 #561`) deja el ADR listo para revisión;
la existencia de la Task por sí sola **no autoriza** marcarlo `Accepted`. El
estado pasa a `Accepted` únicamente cuando exista evidencia registrada de
aprobación del Product Owner/Scrum Master bajo `EN-025 #204`, siguiendo el
mismo criterio que [ADR-022](ADR-022-sprint-3-bounded-contexts.md) aplicó el
2026-09-30.
