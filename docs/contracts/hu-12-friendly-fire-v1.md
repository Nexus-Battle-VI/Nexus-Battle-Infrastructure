# Contrato HU-12 — Prevención de daño entre aliados (v1)

- **Estado:** cierre formal de una validación que HU-18 y HU-19 ya implementaron y dejaron documentada como «HU-12, abierta». Este contrato no introduce mensajes nuevos ni cambia el comportamiento observable: traza cada restricción de HU-12 contra el código y las pruebas que ya existen, cubre el hueco de pruebas que faltaba (3 contra 3) y decide, con motivo, qué queda fuera.
- **Historia:** [HU-12 #21](https://github.com/Nexus-Battle-VI/Nexus-Battle-Management/issues/21) · **RF-12** · [EPIC-06 #6](https://github.com/Nexus-Battle-VI/Nexus-Battle-Management/issues/6) · Team Alfa · módulo Jugar Online / Combat.
- **Bloqueada por:** HU-14 (#23, crear sala de batalla), HU-17 (#26, orden de turnos) y HU-20 (#64, Ataque vs. Defensa), las tres cerradas.
- **Contratos de los que parte:** [HU-18](hu-18-basic-attack-v1.md) (§3, tabla de rechazos, `SAME_TEAM_TARGET`) y [HU-19](hu-19-skills-v1.md) (§3, misma tabla, reutilizada). Ambos citan a HU-12 explícitamente como la historia que cierra esta validación.

## 1. Qué exige la HU y qué ya está hecho

RF-12 (Issue #21) pide: bloquear por defecto el daño a un aliado, validarlo **antes** de resolver daño/crítico/evasión, no producir ningún efecto secundario en una acción bloqueada, aplicarlo a 2 y a 3 participantes por bando, y no asumir la excepción por tipo de ataque, héroe o modalidad — solo una habilidad puede autorizarla de forma explícita.

**Ya implementado desde HU-18 (`applyBasicAttack`/`ExecuteBasicAttack`) y reutilizado sin cambios por HU-19 (`applySkill`/`UseSkill`):** ambos flujos comparten `BattleRoom.requireCombatContext` (`src/domain/entities/BattleRoom.ts`), que resuelve, **en este orden y antes de cualquier otra cosa**:

1. la batalla está `IN_BATTLE`;
2. es el turno del solicitante;
3. el objetivo existe en la sala (`InvalidTargetError` si no);
4. **el objetivo no es del mismo equipo que el actor, incluido el propio actor** (`SameTeamTargetError` si lo es) — **esta es la regla de HU-12**;
5. recién después: perfiles de combate, Vida de ambos.

Solo si las cinco pasan continúa la resolución de Ataque/Defensa (HU-20), el sorteo de efecto (HU-25) y el cálculo de daño. `SameTeamTargetError` se traduce en el rechazo `SAME_TEAM_TARGET` en ambos manejadores de tiempo real (`BasicAttackRealtimeHandler`, `SkillRealtimeHandler`), con el mismo código que ya usa Web para mostrar «no puedes atacar a tu propio equipo».

## 2. Restricción → dónde se cumple (trazabilidad)

| Restricción del Issue #21 | Se cumple en | Prueba |
| --- | --- | --- |
| Identificar si atacante y objetivo son del mismo equipo antes de la acción ofensiva | `requireCombatContext`, paso 4, antes de leer perfiles/Vida | `basic-attack-room.domain.spec.ts`, `skill-room.domain.spec.ts` |
| Bloquear si es aliado y ninguna habilidad lo autoriza | `SameTeamTargetError` (ver §4: hoy ninguna habilidad autoriza nada) | ídem |
| No modificar Vida ni estado en una acción bloqueada | El agregado lanza antes de calcular nada; el caso de uso no persiste | `execute-basic-attack.spec.ts` / `use-skill.spec.ts`: snapshot de la sala **idéntico** antes y después, **0 sorteos** consumidos |
| Continuar con las reglas normales si el objetivo no es aliado | Mismo `requireCombatContext`: sigue con HU-20/HU-25 sin cambios | Suites de HU-18/HU-19/HU-20/HU-25, sin tocar |
| Validar antes de daño, crítico, evasión o cualquier efecto ofensivo | Orden fijo de `requireCombatContext`: el motor de efectos aleatorios (HU-25) ni se invoca | mismas pruebas de «0 sorteos» |
| No asumir la excepción por tipo de ataque, héroe o modalidad | La validación es única y compartida (`requireCombatContext`); ni el ataque básico ni ninguna habilidad tienen una ruta distinta | — |
| Aplicar en 2 y en 3 participantes por bando | `Team.capacity` admite 1 a 3; la validación no depende del tamaño del equipo | **Hueco cerrado en esta HU** (§5): antes solo había prueba de 2 contra 2 |
| La configuración de la sala no puede desactivar la protección | No hay bandera de sala, variable de entorno ni parámetro que la condicione | Guarda estática de HU-13/17/18/19 (`sin variables de entorno para reglas de combate`) sigue vigente |
| Sin efectos secundarios de una acción bloqueada | El caso de uso no llama a `rooms.save`; `commandId` no queda registrado como manejado | `execute-basic-attack.spec.ts`: repetir el mismo `commandId` tras el rechazo vuelve a lanzar (no fue un replay) |

CA-01 y CA-02 quedan cubiertos por la tabla anterior. CA-03 (100 % de los casos) se cierra con la prueba de 3 contra 3 de §5: antes de esta HU esa combinación no tenía prueba explícita, aunque la regla ya no dependía del tamaño del equipo.

## 3. Alcance de «objetivo aliado» y de «acción ofensiva»

- **Aliado:** cualquier combatiente del mismo `teamLabel` que el actor, **incluido el propio actor** (un héroe no puede atacarse a sí mismo). No distingue vivo/muerto: un aliado sin Vida también se rechaza como `SAME_TEAM_TARGET`, no como `TargetUnavailableError` (el chequeo de equipo va primero).
- **Acción ofensiva:** `attack` (HU-18) y `useSkill` para toda habilidad que hoy resuelve un golpe (HU-19: solo modificadores `SELF`, que igual usan `requireCombatContext` con un objetivo enemigo — HU-19 §16 documenta que los efectos sobre el oponente y los objetivos de grupo no están soportados aún).
- Las épicas (HU-11/Tabla 20) no están implementadas todavía: cuando lo estén, si son ofensivas deberán entrar por el mismo `requireCombatContext` — queda anotado como pendiente de esa HU, no de HU-12.

## 4. La excepción de habilidad: decisión y motivo (no se implementa aquí)

El Issue #21 exige que el sistema pueda permitir daño a un aliado **cuando una habilidad lo autorice de forma explícita**. Contrasté esto con el documento oficial (Tabla 5, Tabla 6, Tabla 7): **sí existen habilidades reales que target­ean a un aliado** — Chamán («Toque de la Vida», «Vínculo Natural», «Canto del Bosque») y Médico («Curación Directa», «Neutralización de Efectos», «Reanimación»), ambos sanadores con la columna «Sanar» de la Tabla 6 (Chamán `6 + 1d6`, Médico `4 + 1d8`) y sin Ataque ni Daño.

**Por qué no se construye la excepción en esta HU:**

- `CombatAbility` (perfil congelado de HU-19) no tiene ningún campo que indique «esta habilidad puede apuntar a un aliado»: el único campo de audiencia hoy es `CombatAbilityEffect.target` (`SELF`/`OPPONENT`), y describe **a quién modifica el efecto dentro de la resolución del golpe**, no a quién puede dirigirse el comando `useSkill`. No es el mismo concepto: reutilizarlo sería inventar una semántica que Catalog no publica.
- `evaluateSkill` (`SkillEffectPolicy`) hoy solo soporta efectos `SELF`; cualquier otro (`OPPONENT` u otro) se rechaza como `UnsupportedSkillEffectError`. Sanar es un efecto que ni siquiera tiene tipo en el vocabulario de dominio (`RandomEffectType` solo tiene `DAMAGE`, `CRITICAL_DAMAGE`, `EVADE`, `RESIST`, `ESCAPE`, `NO_DAMAGE` — Tabla 21). No hay «acción base» del sanador todavía.
- Construir un interruptor que ninguna habilidad real puede encender hoy sería código muerto: no hay caso positivo verificable sin inventar una habilidad de prueba que no corresponde a ningún dato publicado por Catalog. Es la misma regla de este proyecto que ya se aplicó en HU-19 §16 con los efectos condicionados y temporales: se documenta como pendiente, no se simula.

**Decisión (autor, a confirmar por el PO):** el bloqueo de HU-12 se mantiene **incondicional** — ninguna habilidad autoriza hoy un objetivo aliado — hasta que exista una historia que defina la acción base de los sanadores y publique en el contrato de habilidades (`hu-19-skills-v1`, ampliación aditiva) un campo de audiencia explícito (p. ej. `CombatAbility.targetAudience: 'ENEMY' | 'ALLY'`). Cuando esa historia exista, `requireCombatContext` deberá recibir la habilidad **antes** de decidir el rechazo por equipo (hoy la resuelve sin conocerla: `planSkill` llama a `requireCombatContext` antes de buscar la habilidad) — queda anotado como el punto de extensión conocido, no como algo pendiente de adivinar.

## 5. Lo que sí se añade en esta HU

- **Pruebas de 3 contra 3** (`Team.capacity = 3` en ambos equipos) para `SameTeamTargetError`, en ataque básico y en habilidad, en el agregado y en el caso de uso (0 sorteos, sala sin cambios): mismo resultado que 2 contra 2, con un tercer aliado y con los dos rivales como objetivos válidos.
- Este contrato, trazando CA-01/CA-02/CA-03 contra el código y las pruebas existentes (§2).

No hay cambios de código en Web: ya muestra `SAME_TEAM_TARGET` con un mensaje propio desde HU-18 (`presentation.ts`) y HU-19 (`skillPresentation.ts`); no hay nada nuevo que exponer.

## 6. Errores

Sin códigos nuevos: se reutiliza `SAME_TEAM_TARGET`, ya definido en `hu-18-basic-attack-v1.md` §3 y `hu-19-skills-v1.md` §3.

## 7. Seguridad

Sin cambios: el actor y el objetivo salen siempre del servidor (`sub` autenticado, `battle.turnOrder`); ningún campo del cliente puede declarar que un objetivo es rival cuando no lo es. Regla ya vigente desde HU-18/19, sin condicionar por rol ni por dato del cliente (regla del repo: nunca `if (rol === ...)` sobre algo no verificado; aquí ni siquiera aplica porque el `teamLabel` del objetivo lo calcula el servidor a partir de la sala, no del comando).

## 8. Pendientes (para el PO)

| Punto | Estado |
| --- | --- |
| Excepción de habilidad para daño/efecto a un aliado (Chamán/Médico) | **pendiente de una historia futura** que defina la acción base de los sanadores y amplíe `hu-19-skills-v1` con un campo de audiencia explícito |
| Épicas ofensivas de grupo (Tabla 20) | fuera de alcance: las épicas no están implementadas |
| Objetivo aliado sin Vida: se rechaza como `SAME_TEAM_TARGET`, no como `TargetUnavailableError` | decisión técnica del autor, coherente con el orden ya fijado en HU-18/19; a confirmar si el PO prefiere distinguir el mensaje |

## 9. Compatibilidad y despliegue

Aditivo en el sentido más fuerte posible: no cambia ningún mensaje, código de error ni comportamiento observable. Es documentación y pruebas sobre código que ya está desplegado (HU-18/19 en producción desde HU-19). No requiere orden de despliegue especial ni migración.
