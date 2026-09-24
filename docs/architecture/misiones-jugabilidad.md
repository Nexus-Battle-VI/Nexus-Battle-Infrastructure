# Misiones jugables — diseño P-J1 a P-J11

**Estado de este documento:** diseño contrastado con el código de las ramas `feat/misiones-jugabilidad` de Missions, Combat, Web e Infrastructure (2026-09-24). Nada de esto está en `develop` todavía. Las cifras de balance salen del motor real de Combat; las decisiones marcadas como **pendientes del PO** son propuestas del equipo.

## Trazabilidad

- **Épica:** [EPIC-08 — Misiones](https://github.com/Nexus-Battle-VI/Nexus-Battle-Management/issues/8)
- **Historias:** HU-70 (tablón y matrícula), HU-71 (rotaciones), HU-72 (simulación), HU-73 (Máster), HU-74 (reporte e historial), HU-75 (dificultad), HU-76 (logros), HU-09 (experiencia)
- **Fuente funcional:** documento del curso, sección 7.8 (misiones), Tabla 6 (estadísticas de nivel 1) y Tabla 20 (épicas)
- **Contratos que se extienden:** [HU-70](../contracts/hu-70-mission-enrollment-v1.md), [HU-71](../contracts/hu-71-mission-strategy-v1.md), [HU-72](../contracts/hu-72-mission-simulation-v1.md), [HU-73](../contracts/hu-73-master-encounter-v1.md), [HU-74](../contracts/hu-74-mission-report-v1.md), [HU-75](../contracts/hu-75-mission-difficulty-v1.md), [HU-76](../contracts/hu-76-mission-achievements-v1.md)
- **Runbook de productos:** [misiones-productos-de-recompensa.md](../runbooks/misiones-productos-de-recompensa.md)

## Por qué

La prueba de punta a punta sobre `develop` (2026-09-24) mostró un módulo que funciona pero que el jugador no puede vivir:

| Hallazgo | Consecuencia para el jugador |
| --- | --- |
| El botín del jefe nunca llegaba al inventario: no existía un puerto de entrega. | El reporte promete objetos que no aparecen. |
| Combat solo aceptaba mejoras propias de Ataque o Daño: 10 de 24 habilidades de producción servían. | La estrategia casi no cambia nada. |
| El Templo en Normal (12 h) terminó con 6 de daño sobre 40 de vida; en Heroico o más, las derrotas eran por tiempo agotado. | Perder era imposible o arbitrario. |
| No había panel de misiones en curso ni forma de ver la misión mientras ocurre. | Se matricula y se espera 12 horas a ciegas. |
| Créditos, cofres y títulos se mostraban, pero HU-10 no los entrega. | Promesas vacías. |
| El catálogo de logros está vacío. | Una sección sin nada. |
| La interfaz mostraba `APPEARED_DEFEATED`, `sombra-del-olvido`, `msn_…` y «Sombras Corrompidas × 43» (eran 43 XP). | Textos técnicos. |

## Decisiones

| ID | Decisión | Servicios |
| --- | --- | --- |
| P-J1 | El botín del jefe se entrega al inventario, con el mismo patrón que la épica del Máster. | Missions |
| P-J2 | Solo se promete lo que se entrega: experiencia, botín enlazado a un producto y épicas enlazadas. | Missions, Web |
| P-J3 | Meta a largo plazo: cada épica oficial de la Tabla 20 la entrega exactamente un Máster, y el historial muestra el álbum. Sin catálogo de logros, la sección no promete nada. | Missions, Web |
| P-J4 | Las habilidades tienen semántica de misión en Combat: daño directo, curación, inmunidad, reflejo y penalizaciones al enemigo. | Combat, Web |
| P-J5 | El reporte resume qué hizo la estrategia: cuántas veces se usó cada habilidad y por qué se saltó. | Missions, Web |
| P-J6 | Misiones en curso visibles: panel con progreso y cuenta regresiva, bitácora revelada según el tiempo real y aviso al terminar. | Missions, Web |
| P-J7 | Probabilidad de éxito antes de enviar al héroe, calculada por Combat. | Combat, Missions, Web |
| P-J8 | La dificultad cambia qué se enfrenta y qué se gana, no solo las estadísticas. | Missions, Web |
| P-J9 | Contenido v2 medido con el motor real: primera misión de 10 minutos, desafío de 1 hora, exploración de 24 horas. | Missions |
| P-J10 | Nombres en lugar de identificadores en todo lo que ve el jugador. | Missions, Web |
| P-J11 | Una ilustración por misión, con la de su categoría como respaldo. | Missions, Web |

### P-J1 — Botín entregado

- Al cerrar la matrícula, cada botín ganado se convierte en una línea `PRODUCT` del reporte con origen `HU-72` y en una fila de `mission_loot_grants` (migración 011). Ambas se escriben en la transacción del cierre.
- `GrantMissionLoot` corre en el planificador después de las épicas y usa `POST /api/internal/v1/inventory/grants` de Player/Inventory: idempotente, con cantidad y `operationId = uuidV5(enrollmentId:loot:label)`.
- El producto se congela antes de enviar. Un botín sin `productId` espera con `LOOT_PRODUCT_MISSING` hasta que se enlace; nunca se inventa una entrega.
- El estado de la línea del reporte cambia junto con la entrega (`PENDING` → `CREDITED` o `FAILED`).

### P-J2 — Solo lo que se entrega

- Detalle: `rewards` pasa a `{ experience: true, guaranteed: [], potential, objectiveBonuses: [], firstTime: [] }`. `potential` solo trae los botines con producto enlazado.
- Un candidato a Máster cuya épica no tiene producto se muestra con `epic: null`.
- Tarjeta del tablón: `highlightedRewards` = experiencia, épicas posibles y los dos botines más probables.
- Créditos, cofres y títulos siguen en el contenido para cuando HU-10 los entregue, pero no se muestran.

### P-J3 — Una épica por Máster y el álbum

- Las 8 épicas oficiales de la Tabla 20, cada una en un Máster de su tipo de héroe:

| Épica | Máster | Tipo | Misión |
| --- | --- | --- | --- |
| Toma y lleva | Sombra del Olvido | Pícaro Veneno | El Templo Olvidado |
| Golpe de defensa | Coloso de Obsidiana | Guerrero Tanque | El Templo Olvidado |
| Frío concentrado | Hechicera del Sello | Mago Hielo | La Cámara Sellada |
| Segundo impulso | Campeón Carmesí | Guerrero Armas | La Arena de los Caídos |
| Intimidación sangrienta | Filo Errante | Pícaro Machete | La Arena de los Caídos |
| Luz cegadora | Llama Salvaje | Mago Fuego | Travesía por el Bosque Sombrío |
| Té changua | Chamán de la Niebla | Chamán | Travesía por el Bosque Sombrío |
| Reanimador 3000 | Cirujano Silente | Médico | Travesía por el Bosque Sombrío |

- Cada Máster aparece más para su propio tipo de héroe (`probabilityByHeroType`), así que cada tipo tiene su Máster que perseguir (7.8.4).
- El resumen del historial añade `epicAlbum`: cada épica entregable, con su Máster, su misión y si el jugador ya la tiene. Una entrega en camino cuenta como obtenida; una fallida no.
- Logros (HU-76): Missions lista todo su catálogo, conseguido o no. Con el catálogo vacío, Web muestra «Aún no disponible» y no «Aún no tienes logros».

### P-J4 — Habilidades con semántica de misión

- `evaluateMissionAbility` de Combat es propio de misiones. No cambia `evaluateSkill`, que comparte con JcJ.
- Soporta mejoras propias con duración, penalizaciones al enemigo, daño directo, curación (fija, por dados y porcentual), inmunidad y reflejo de daño.
- De las 24 habilidades de producción, 23 sirven en misiones. «Pare de fuego» no, porque su condición de activación llega a Combat solo como un booleano.
- El orden del generador aleatorio no cambia para las habilidades que ya se soportaban: se verificó con 50 corridas con semilla contra `develop`.
- Una habilidad que no sirve se salta con el motivo `UNSUPPORTED_EFFECT` y la estrategia sigue. Web marca esas habilidades en el editor de estrategia y dice por qué, con el texto que devuelve la estimación.

### P-J5 — La estrategia en el reporte

- El reporte añade `strategy: { abilities: [{ abilityId, name, used, skipped: { motivo: veces } }], basicAttacks, fallbackAttacks }`.
- Lo calcula el cierre desde la bitácora de Combat. Los reportes anteriores no lo tienen.
- `combatStats` añade `healingDone` y `abilityDamage`.

### P-J6 — Misiones en curso

- Combat simula la misión entera al empezar. Missions revela la bitácora poco a poco: cada evento se ve a partir de `startedAt + duración × turno / turnosTotales`, y el desenlace solo al final.
- `GET /api/v1/missions/me/active`: las misiones en curso del jugador, ordenadas por fin, con `progressPercent` y `remainingSeconds` calculados por Missions.
- `GET /api/v1/missions/me/progress/{enrollmentId}?after=`: lo revelado después de `after`, la vida del héroe, `lastSeq` y `nextRevealAt`. Web pide lo siguiente justo cuando se va a revelar.
- Web muestra el panel en el tablón, una página de seguimiento y un aviso en todo el marco de la aplicación cuando una misión deja de estar en curso.
- La cuenta regresiva vive en `src/shared/countdown.ts`, fuera de la feature: la guarda de HU-09.5 prohíbe el reloj en la carpeta de misiones, y ahí el reloj solo se muestra.

### P-J7 — Probabilidad de éxito

- Combat: `POST /api/internal/v1/combat/simulations/estimates`, firmada como la simulación.
  - Corre la misma simulación `runs` veces (30 por defecto, máximo 100) con las semillas `<operationId>:estimate:<n>` y no guarda nada.
  - Responde victorias, derrotas, tiempos agotados, turnos medios, vida mínima media, aparición de Máster y qué habilidades sirven.
- Missions: `GET /api/v1/missions/{missionId}/estimate?heroId=&difficulty=`.
  - Arma la solicitud real con el perfil actual del héroe, la estrategia guardada y la composición del nivel.
  - La operación es determinista por jugador, misión, héroe, nivel y versión de estrategia: la misma pregunta da la misma respuesta, y nunca coincide con la operación aleatoria de una matrícula, así que no adelanta el resultado real.
- Riesgo (pendiente del PO): Favorable desde 80 %, Pareja desde 50 %, Arriesgada desde 20 % y Muy arriesgada por debajo.
- Sin respuesta de Combat es `503 ESTIMATE_UNAVAILABLE` y la matrícula no se bloquea.

### P-J8 — Dificultad que cambia la misión

| Nivel | Estadísticas | Enemigos de más por encuentro regular | Ataque de más del jefe furioso | Botín y Máster |
| --- | --- | --- | --- | --- |
| Normal | ×1 | 0 | 0 | +0 % |
| Heroico | ×1,5 | 1 | 0 | +25 % |
| Legendario | ×2 | 1 | 2 | +50 % |
| Mítico | ×2,5 | 2 | 4 | +100 % |

- Las probabilidades mejoradas tienen tope en el 100 %.
- Los enemigos de más se suman al primer grupo de cada encuentro regular; el jefe nunca se duplica.
- Más enemigos también dan más experiencia (HU-09).
- `GET .../difficulties` publica `extraEnemiesPerEncounter`, `bossEnrageBonus`, `lootBonusPercent` y `masterBonusPercent`.

### P-J9 — Contenido v2 y balance medido

- Nuevas misiones:
  - **Camino al Templo:** historia, 10 min, sin requisitos ni Máster y con botín seguro.
  - **La Arena de los Caídos:** desafío, 1 h, requiere el Camino.
  - **Travesía por el Bosque Sombrío:** exploración, 24 h, hasta dos Máster, requiere el Camino.
- El Templo y la Cámara suben a 300 turnos por encuentro: la pelea con el jefe se decide por la vida de alguno, no por agotar el tiempo.
- La migración 012 inserta lo nuevo y mejora el Templo y la Cámara campo a campo, solo donde conservan lo sembrado en v1: lo que un administrador editó o enlazó no se toca.

Balance medido con el banco (`simulateMission` de Combat sobre `buildSimulationRequest` de Missions, 100 corridas por celda). Porcentaje de victorias con estrategia de dos mejoras de daño:

| Misión | Héroe | Normal | Heroico | Legendario | Mítico |
| --- | --- | --- | --- | --- | --- |
| Camino al Templo | Guerrero Armas equipado | 100 | 100 | 86 | 3 |
| Camino al Templo | Pícaro Veneno nivel 1 | 100 | 98 | 30 | 0 |
| El Templo Olvidado | Guerrero Armas equipado | 100 | 100 | 78 | 0 |
| El Templo Olvidado | Pícaro Veneno nivel 1 | 100 | 78 | 0 | 0 |
| La Cámara Sellada | Guerrero Armas equipado | 100 | 100 | 92 | 0 |
| La Arena de los Caídos | Guerrero Armas equipado | 100 | 93 | 2 | 0 |
| La Arena de los Caídos | Pícaro Veneno nivel 1 | 100 | 13 | 0 | 0 |
| Travesía por el Bosque Sombrío | Guerrero Armas equipado | 100 | 95 | 1 | 0 |
| Travesía por el Bosque Sombrío | Médico nivel 1 | 60 | 3 | 0 | 0 |

- Guerrero Armas equipado: el héroe del stack local, con ataque 12, defensa 14, vida 40 y daño 1d4. Pícaro Veneno y Médico de nivel 1: Tabla 6.
- Sin estrategia, las cifras bajan. Por ejemplo, el Médico cae del 60 % al 22 % en la Travesía: la estrategia importa.
- Mítico queda para héroes más fuertes. El curso dice que el nivel multiplica las estadísticas (nivel 3 → ataque 30), pero Player/Inventory aún no lo aplica: con héroes de nivel alto el balance cambiará y habrá que medirlo de nuevo.

### P-J10 — Nombres, no identificadores

- El detalle añade `prerequisiteMissions` con el nombre de cada misión previa.
- El resumen del historial añade `bestTimes[].missionName`, `epicCollection[].masterName` y `narrativeProgress[].missionNames`.
- Web traduce estados, tipos de héroe, estadísticas y motivos. La experiencia se muestra en su panel y no como «× N» en las recompensas.

### P-J11 — Ilustraciones

- Cada misión guarda `imageRef`: `mision-camino-templo`, `mision-templo-olvidado`, `mision-camara-sellada`, `mision-arena-caidos` y `mision-travesia-bosque`.
- Web dibuja una escena SVG propia por nombre, sin archivos externos. Un nombre desconocido usa la escena de su categoría.

## Cambios de contrato

Todos son compatibles: añaden campos o rutas y no quitan ni renombran nada.

| Contrato | Cambio |
| --- | --- |
| HU-70 | `GET /missions/{id}`: `imageRef`, `prerequisiteMissions`, `rewards` de P-J2 y `epic` anulable. Ruta nueva `GET /missions/{id}/estimate`. |
| HU-71 | Sin cambios de forma. La estimación dice qué habilidades de la estrategia sirven en misiones. |
| HU-72 | Combat: `POST /simulations/estimates`. La solicitud lleva la composición del nivel y las probabilidades mejoradas (P-J8). Las habilidades se evalúan con P-J4. |
| HU-73 | Una épica oficial por Máster; varios candidatos por misión (P-J3). |
| HU-74 | Reporte: `strategy`, `healingDone`, `abilityDamage` y líneas `PRODUCT` de origen `HU-72`. Resumen: nombres y `epicAlbum`. Rutas nuevas `GET /missions/me/active` y `GET /missions/me/progress/{id}`. |
| HU-75 | `GET /missions/{id}/difficulties`: `extraEnemiesPerEncounter`, `bossEnrageBonus`, `lootBonusPercent` y `masterBonusPercent`. |
| HU-76 | Sin cambios. Un catálogo vacío se lee como «sin logros definidos». |

Base de datos de Missions:
- **011:** tabla `mission_loot_grants` y el origen `HU-72` en las líneas del reporte.
- **012:** contenido v2.

## Pendiente del PO

1. **Probabilidad de los Máster.** La Tabla 20 da entre 0,01 % y 0,1 % por misión, lo que hace el álbum inalcanzable. El equipo propone entre 3 % y 20 %, con el 15 % del ejemplo del curso para la Sombra del Olvido.
2. **Composición de cada dificultad (P-J8)** y la escala de riesgo de la estimación (P-J7).
3. **Épicas repetidas.** Hoy una épica ya obtenida se acredita otra vez y se apila; se vio «Toma y lleva» ×2 en local. ¿Se acredita, se convierte en otra cosa o no se vuelve a entregar?
4. **Catálogo de logros (HU-76).** La base es la lista del curso (7.8.11): completar todas las misiones de una categoría, derrotar a todos los Máster, completar misiones sin recibir daño, terminar en tiempo récord y coleccionar todas las épicas. Mientras no se apruebe, la sección no promete nada.
5. **Créditos, cofres y títulos (HU-10).** No se entregan ni se muestran hasta que HU-10 los entregue.
6. **«Velo de Sombras».** La épica del ejemplo del curso no es un producto: se reemplazó por «Toma y lleva», la oficial de su tipo.
7. **Cancelar una misión (7.8.9).** No está en este alcance.
8. **Botín en la tienda.** Los productos nuevos quedan a la venta por créditos; si deben ser exclusivos de las misiones, hay que retirarlos de la venta (ver el runbook).

## Verificación

- **Missions:** 1070 pruebas unitarias y de integración, y 13 suites contra PostgreSQL real con Testcontainers. Incluyen la migración 012 sobre una base v1 enlazada y editada.
- **Combat:** pruebas unitarias de la política de habilidades (24 habilidades de producción) y de la simulación, y pruebas HTTP de `POST /estimates`.
- **Web:** 2483 pruebas, incluida la guarda `noClientAuthority` de HU-09.5, y el build de producción con su verificación de bundle.
- **Punta a punta local:** ver la sección de entorno local del runbook de productos.
