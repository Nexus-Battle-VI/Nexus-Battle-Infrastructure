# Contrato HU-19 — Habilidades especiales (v2)

- **Estado:** sucesor de [`hu-19-skills-v1`](hu-19-skills-v1.md), que queda congelado como registro histórico. Esta versión documenta la ampliación del motor de efectos para cubrir las habilidades de Tabla 7 que v1 dejaba `UNSUPPORTED`. Todo lo que v1 define y no se toca aquí (transporte `useSkill`, orden de validación §3, Poder/degradación §4.3, recarga §5.3, eventos §6, idempotencia §8, errores §9) **sigue vigente sin cambios**; este documento solo añade lo nuevo.
- **Motivo del cambio:** auditoría 2026-09-24 sobre `develop` real confirmó que **HU-12** (#21, prevención de daño entre aliados) y **HU-21** (#65, finalización de batalla) — que v1 citaba como bloqueos — **están cerradas** desde 2026-09-22. El propio código de Combat ya tenía, sin que v1 lo documentara, una excepción de curación para Reanimación (`kind: HEAL`, target `ALLY`) que hoy resuelve **sin pasar por el chequeo de Ataque** (`BattleRoom.planSkill`, rama `support.kind === 'HEAL'`). Esto prueba en código que el camino de ejecución para sanadores ya existe y no depende de una acción básica propia. **HU-31** (#78, épica equipada) sigue abierta y la épica permanece fuera de alcance.
- **Fuente funcional:** «Proyecto Integrador II», Tabla 7 (acciones), Tabla 6 (Poder/dados), §6.1.2. Ver también el PDF original página 27 para los dos marcadores sin definir (`(0dx)`, `(0d4)`) — confirmados visualmente, no son error de OCR.

## 1. Qué agrega v2 sobre v1

v1 solo soportaba `kind = STAT_MODIFIER · target = SELF · operation = INCREASE · statistic ∈ {ATTACK, DAMAGE} · magnitude ∈ {FIXED, DICE} · sin duración · sin condición`, más una excepción no documentada para `kind = HEAL · target = ALLY · REVIVE`.

v2 amplía el patrón declarativo (sin lógica `if ability == X`, mismo principio de v1 §10.2) a:

| Capacidad nueva | Alcance |
| --- | --- |
| `statistic = DEFENSE` en `STAT_MODIFIER` | Mano de piedra |
| `target = OPPONENT` en `STAT_MODIFIER`, `operation = DECREASE` | Cono de hielo, Bola de hielo |
| `kind = DAMAGE` (daño directo, sin resolución de Ataque/Defensa) | Agonía |
| `statistic = HEALING` en `STAT_MODIFIER`, `target ∈ {ALLY, ALLIED_GROUP}` | Toque de la Vida, Vínculo Natural, Canto del Bosque, Curación Directa, Neutralización de Efectos |
| Múltiples efectos por habilidad, cada uno soportado independientemente | Piquete, Neutralización de Efectos, Pare de fuego |
| `durationTurns` interpretado como estado real de batalla | Piquete, Cortada, Cono de hielo, Vínculo Natural, Canto del Bosque |
| `kind = IMMUNITY` (estructural: `immunityCode`, **sin** `magnitude`) | Ninguna habilidad de las 24 queda totalmente resuelta solo con esto — ver §5 |
| `kind = REFLECT_DAMAGE` con condición "daño recibido en el turno propio anterior" | Pare de fuego — ver nota de confianza de datos en §6 |
| Objetivo `ALLIED_GROUP` resuelto **server-side** desde el equipo del actor, sin cambiar el wire de `useSkill` | Canto del Bosque — ver §4 |

**No se toca:** el generador aleatorio sigue siendo el único de HU-24 (ningún efecto nuevo introduce un PRNG propio); el ataque básico no cambia; Poder y recarga no cambian de semántica; la épica sigue sin definirse (§11 de v1, sin cambios).

## 2. Estado de batalla: efectos temporales (ampliación estructural principal)

El snapshot de combate (v1 §5) se amplía, aditivamente, con una lista de **efectos temporales activos** por combatiente:

```jsonc
// interno, por combatiente, dentro de battle.combatants[].activeSkillEffects (nombre indicativo)
{
  "sourceAbilityId": "…",       // habilidad que lo originó
  "sourceCombatant": { "teamLabel": "A", "seat": 0 },
  "target": { "teamLabel": "B", "seat": 0 },
  "statistic": "ATTACK",        // o DAMAGE / DEFENSE / HEALING
  "operation": "DECREASE",      // o INCREASE
  "magnitude": { "mode": "DICE", "count": 1, "sides": 3 },
  "remainingOwnTurns": 2        // decrementa igual que `cooldownRemaining` (v1 §5.3)
}
```

- **Convención de duración:** se reutiliza literalmente la misma unidad que ya usa la recarga — «turnos propios» del combatiente **objetivo** del efecto (no del que lo lanzó), para que un efecto sobre el rival dure lo mismo en turnos reales sea cual sea el ritmo de turnos del lanzador. Se decrementa **una sola vez**, al cerrar cada turno propio del combatiente objetivo (mismo punto donde hoy se decrementa `cooldownRemaining`, `Combatant.closeOwnTurn()`), y expira exactamente al llegar a 0 (no se reaplica el efecto al expirar, simplemente deja de sumar).
- **Persistencia:** vive dentro del mismo documento `battle-rooms` que ya persiste Vida/Poder/recarga — no se crea una colección ni un reloj paralelo. Migración `$jsonSchema` aditiva siguiente libre tras la `015` existente.
- **Aplicación:** un efecto temporal se calcula sobre la estadística efectiva del combatiente en el momento de cada resolución que la consulte (p. ej. Ataque/Defensa al resolver un golpe), igual que hoy se aplican los modificadores de equipo (`activeEffects`), no se re-escribe el valor base.
- **Atomicidad:** aplicar/decrementar/expirar es parte de la **misma** transición de una sola escritura que ya usa `applySkill` (v1 §7) — nunca una escritura separada.
- **Idempotencia:** un `commandId` repetido (v1 §8) no vuelve a insertar el efecto temporal ni a reiniciar su duración — se sirve el mismo resultado persistido, igual que con Poder y recarga.
- **Recuperación:** `resume` (v1 escenario 17) reconstruye la lista de efectos activos y su `remainingOwnTurns` exacto desde el documento persistido; sobrevive refresh, reconexión y reinicio del proceso.

## 3. Múltiples efectos por habilidad

Una habilidad es **soportada** solo si **todos** sus efectos, individualmente, cumplen alguno de los patrones de §1/§5. Se mantiene sin cambios el principio de v1: no se aplica a medias (si un solo efecto no encaja en ningún patrón soportado, la habilidad entera se rechaza con `UNSUPPORTED_SKILL_EFFECT`, 0 mutaciones). Esto ya vale hoy para habilidades de 2 efectos (Pare de fuego, Cono de hielo en la tabla real de Catalog); v2 solo confirma que el mismo principio cubre also 2 efectos `HEALING` (Neutralización de Efectos) y `STAT_MODIFIER` con duraciones distintas por efecto (Piquete: +1 ataque 2 turnos, +2 daño 1 turno — cada efecto lleva su propio `durationTurns`).

## 4. `ALLIED_GROUP` — resolución server-side (Canto del Bosque)

**Decisión cerrada, no se reabre.** El wire de `useSkill` (v1 §2) no cambia: sigue siendo exactamente `{type, commandId, roomId, abilityId, target}` con un único `target`. Para una habilidad cuyo efecto declara `target: ALLIED_GROUP`:

1. Combat autentica al actor y localiza su `teamLabel` (ya lo tiene del turno vigente, v1 §3 paso 7).
2. El `target` del comando **no se usa como fuente del grupo** — puede seguir siendo cualquier combatiente válido (se recomienda que el cliente siga enviando su propio `{teamLabel, seat}` para no romper la validación de forma del mensaje, pero Combat lo ignora a efectos de alcance).
3. Combat obtiene los miembros elegibles del mismo equipo del actor (vivos, con perfil de combate) directamente del estado de la sala — mismo origen que ya usa para listar `combatants`.
4. Aplica el efecto a **cada** miembro elegible, individualmente, dentro de la **misma** transición atómica (una sola escritura, un solo `seq`).
5. El evento `skillUsed` (v1 §6.1) se amplía, aditivamente, con un campo `affected: [{teamLabel, seat}, …]` cuando el efecto es de grupo, para que Web sepa a quién pintar sin inferirlo.

Web **nunca** envía una lista de objetivos; el campo `targets: [...]` que no existe en v1 sigue sin existir en v2.

## 5. `IMMUNITY` — soporte estructural, no resuelve Defensa feroz por sí solo

Se implementa el patrón `kind: IMMUNITY · target: SELF · immunityCode: EffectCode` (el campo ya existe en `catalog-product-v1.openapi.yaml`, sin `magnitude` — no se amplía ese esquema). Esto es soporte de la **familia** de efecto, no una resolución de Defensa feroz: la habilidad tiene un segundo componente («(3d6) al daño mágico») que **no tiene kind ni campo alguno** en el contrato de Producto hoy, y el propio texto del PDF es ambiguo sobre qué representa ese `3d6` (¿mitigación con tope? ¿absorción? ¿daño que igual se recibe?). Por tanto:

- **`Defensa feroz` queda `PENDING_SOURCE_DEFINITION`.** No se declara soportada aunque el componente físico (inmunidad) sería trivial de representar hoy — la política de «no se aplica a medias» (§3) impide ejecutar solo la mitad de una habilidad.
- **No se agrega ningún campo nuevo** a `ImmunityEffect` ni se crea un `kind` nuevo tipo `DAMAGE_MITIGATION` para acomodar el componente mágico. Eso sería inventar semántica de negocio sin fuente confirmada.
- Cuando el PO/profesor aclare el significado de `(3d6) al daño mágico`, se documenta como **`hu-19-skills-v3`** (o adenda versionada) con el campo exacto que se decida, y recién entonces Catalog puede declarar el segundo efecto.

## 6. `REFLECT_DAMAGE` — soporte estructural genérico; dos habilidades quedan con nota de confianza de datos

Se implementa el patrón `kind: REFLECT_DAMAGE · target: OPPONENT · magnitude: PercentageMagnitude · hasActivationCondition: true`, con la condición «se activa si el actor recibió daño en su turno propio anterior» (requiere que Combat recuerde, por combatiente, el daño recibido en su último turno propio — mismo mecanismo de estado que §2, con `remainingOwnTurns` fijo en 1). Es un patrón **genérico**, sin lógica específica de «Pare de fuego»: cualquier producto HABILIDAD que declare este efecto lo ejecuta igual.

Igualmente, `target: OPPONENT` con `operation: DECREASE` (§1) es un patrón genérico ya cubierto por Cono de hielo y Bola de hielo por igual.

**Consecuencia honesta:** una vez implementados estos dos patrones genéricos, **Pare de fuego y Bola de hielo dejan de ser `UNSUPPORTED`** — porque sus efectos, tal como Catalog los tiene cargados hoy (100 % de reflejo; `1d4` de reducción), encajan estructuralmente en el patrón. Esto **no** es «convertir el valor histórico en requisito oficial»: es que el motor deja de rechazar por falta de capacidad, y ejecuta con el dato real que ya existía en Catalog desde antes de este trabajo, sin que Combat lo haya tocado ni inventado.

Por eso la tabla de cobertura (§7) usa un tercer estado para estos dos casos, distinto de `SUPPORTED` liso: **`SUPPORTED_UNCONFIRMED_MAGNITUDE`** — se ejecutan, pero su magnitud **no** está validada contra el documento oficial (que trae `(0dx)`/`(0d4)` sin definir) y por tanto **no cuentan** dentro del objetivo de «21/24 conforme al PDF». Ningún test de este trabajo afirma que `100%` o `1d4` sean el valor correcto de Tabla 7 — solo que el motor ejecuta correctamente lo que Catalog declara, sea lo que sea.

## 7. Cobertura — reemplaza la tabla «10 de 24» de v1

| # | Héroe | Habilidad | Estado v1 | Estado v2 |
| --- | --- | --- | --- | --- |
| 1 | G. Tanque | Golpe con escudo | SUPPORTED | SUPPORTED |
| 2 | G. Tanque | Mano de piedra | UNSUPPORTED | **SUPPORTED** |
| 3 | G. Tanque | Defensa feroz | UNSUPPORTED | **PENDING_SOURCE_DEFINITION** (§5) |
| 4 | G. Armas | Embate sangriento | SUPPORTED | SUPPORTED |
| 5 | G. Armas | Lanza de los dioses | SUPPORTED | SUPPORTED |
| 6 | G. Armas | Golpe de tormenta | SUPPORTED | SUPPORTED |
| 7 | Mago Fuego | Misiles de magma | SUPPORTED | SUPPORTED |
| 8 | Mago Fuego | Vulcano | SUPPORTED | SUPPORTED |
| 9 | Mago Fuego | Pare de fuego | UNSUPPORTED | **SUPPORTED_UNCONFIRMED_MAGNITUDE** (§6) |
| 10 | Mago Hielo | Lluvia de hielo | SUPPORTED | SUPPORTED |
| 11 | Mago Hielo | Cono de hielo | UNSUPPORTED | **SUPPORTED** |
| 12 | Mago Hielo | Bola de hielo | UNSUPPORTED | **SUPPORTED_UNCONFIRMED_MAGNITUDE** (§6) |
| 13 | Pícaro Veneno | Flor de loto | SUPPORTED | SUPPORTED |
| 14 | Pícaro Veneno | Agonía | UNSUPPORTED | **SUPPORTED** |
| 15 | Pícaro Veneno | Piquete | UNSUPPORTED | **SUPPORTED** |
| 16 | Pícaro Machete | Cortada | UNSUPPORTED | **SUPPORTED** |
| 17 | Pícaro Machete | Machetazo | SUPPORTED | SUPPORTED |
| 18 | Pícaro Machete | Planazo | SUPPORTED | SUPPORTED |
| 19 | Chamán | Toque de la Vida | UNSUPPORTED | **SUPPORTED** |
| 20 | Chamán | Vínculo Natural | UNSUPPORTED | **SUPPORTED** |
| 21 | Chamán | Canto del Bosque | UNSUPPORTED | **SUPPORTED** (§4) |
| 22 | Médico | Curación Directa | UNSUPPORTED | **SUPPORTED** |
| 23 | Médico | Neutralización de Efectos | UNSUPPORTED | **SUPPORTED** |
| 24 | Médico | Reanimación | SUPPORTED (excepción no documentada) | SUPPORTED (ahora formalizado; costo corregido a `ALL_AVAILABLE`, ver Catalog) |

**21/24 `SUPPORTED` conforme al PDF · 2/24 `SUPPORTED_UNCONFIRMED_MAGNITUDE` · 1/24 `PENDING_SOURCE_DEFINITION`.**

## 8. Pendientes legítimos (no son deuda técnica, son ambigüedad de la fuente)

| Punto | Estado |
| --- | --- |
| Defensa feroz — significado y campo del componente «(3d6) al daño mágico» | Bloqueado: requiere decisión del PO/profesor y, según lo que se decida, una `hu-19-skills-v3` |
| Pare de fuego — magnitud real de `(0dx)` | El PDF mismo no la define; el motor ya funciona con el valor histórico de Catalog, sin confirmar |
| Bola de hielo — magnitud real de `(0d4)` | Igual que arriba |
| Épica (HU-31) | Sigue bloqueada, sin cambios respecto a v1 §11 |

## 9. Compatibilidad

Aditivo sobre v1: ningún campo ni mensaje existente cambia de forma; `activeSkillEffects`/`affected` son nuevos y opcionales, un cliente que los ignore no se rompe. Migración de `battle-rooms` aditiva. Orden de despliegue igual que v1 §17 (Infrastructure → Player-Inventory si aplica → Combat → verificar → Web).
