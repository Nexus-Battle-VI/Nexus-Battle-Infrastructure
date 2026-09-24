# Misiones jugables — diseño P-J1 a P-J11

**Estado de este documento:** diseño contrastado con el código de las ramas `feat/misiones-jugabilidad` de Missions, Combat, Web e Infrastructure (2026-09-24). Nada de esto está en `develop` todavía. Las cifras de balance salen del motor real de Combat. Incluye las decisiones que el PO tomó el 2026-09-24 (ver «Decisiones del PO»); lo que sigue marcado como **pendiente del PO** son propuestas del equipo.

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
| Frío concentrado | Hechicera del Sello | Mago Hielo | La Cámara Sellada |
| Golpe de defensa | Coloso de Obsidiana | Guerrero Tanque | La Cámara Sellada |
| Segundo impulso | Campeón Carmesí | Guerrero Armas | La Arena de los Caídos |
| Intimidación sangrienta | Filo Errante | Pícaro Machete | La Arena de los Caídos |
| Luz cegadora | Llama Salvaje | Mago Fuego | Travesía por el Bosque Sombrío |
| Té changua | Chamán de la Niebla | Chamán | Travesía por el Bosque Sombrío |
| Reanimador 3000 | Cirujano Silente | Médico | Travesía por el Bosque Sombrío |

- **Un Máster aparece en el 15 % de las misiones, igual para cualquier héroe** (decisión del PO).
  - Cada misión tiene un solo punto de evaluación y como mucho una aparición, así que la cifra que ve el jugador en cada Máster es la real.
  - Templo: 15 %, como el ejemplo del curso (7.8.14). Cámara y Arena: 7,8 % por Máster. Travesía: 5,275 % por Máster. En Combat, que tira con resolución de 1/8000, dan entre 14,99 % y 15,01 %.
  - El Coloso pasó del Templo a la Cámara para que el Templo quede como en el curso.
  - `GET /missions/{id}` publica en `masterEncounter.probability` la probabilidad de que aparezca algún Máster en la misión, calculada por Missions: `1 − ((1 − p₁)(1 − p₂)…)^puntos`, la mayor según el tipo de héroe. Antes era la mayor probabilidad configurada de un candidato. Web la muestra en el detalle.
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

| Nivel | Estadísticas | Enemigos de más por encuentro regular | Ataque de más del jefe furioso | Botín |
| --- | --- | --- | --- | --- |
| Normal | ×1 | 0 | 0 | +0 % |
| Heroico | ×1,5 | 1 | 0 | +25 % |
| Legendario | ×2 | 1 | 2 | +50 % |
| Mítico | ×2,5 | 2 | 4 | +100 % |

- La probabilidad de botín mejorada tiene tope en el 100 %.
- La del Máster no cambia con el nivel: el PO la fijó en el 15 % por misión.
- Los enemigos de más se suman al primer grupo de cada encuentro regular; el jefe nunca se duplica.
- Más enemigos también dan más experiencia (HU-09).
- `GET .../difficulties` publica `extraEnemiesPerEncounter`, `bossEnrageBonus` y `lootBonusPercent`.

### P-J9 — Contenido v2 y balance medido

- Nuevas misiones:
  - **Camino al Templo:** historia, 10 min, sin requisitos ni Máster y con botín seguro.
  - **La Arena de los Caídos:** desafío, 1 h, requiere el Camino.
  - **Travesía por el Bosque Sombrío:** exploración, 24 h, tres Máster posibles (como mucho uno por misión), requiere el Camino.
- El Templo y la Cámara suben a 300 turnos por encuentro: la pelea con el jefe se decide por la vida de alguno, no por agotar el tiempo.
- La migración 012 inserta lo nuevo y mejora el Templo y la Cámara campo a campo, solo donde conservan lo sembrado en v1: lo que un administrador editó o enlazó no se toca.

Balance medido con el banco (`simulateMission` de Combat sobre `buildSimulationRequest` de Missions, 100 corridas por celda), con los Máster al 15 % por misión. Porcentaje de victorias con estrategia de dos mejoras de daño:

| Misión | Héroe | Normal | Heroico | Legendario | Mítico |
| --- | --- | --- | --- | --- | --- |
| Camino al Templo | Guerrero Armas equipado | 100 | 100 | 86 | 3 |
| Camino al Templo | Pícaro Veneno nivel 1 | 100 | 98 | 30 | 0 |
| El Templo Olvidado | Guerrero Armas equipado | 100 | 100 | 87 | 0 |
| El Templo Olvidado | Pícaro Veneno nivel 1 | 100 | 79 | 0 | 0 |
| La Cámara Sellada | Guerrero Armas equipado | 100 | 100 | 93 | 0 |
| La Arena de los Caídos | Guerrero Armas equipado | 100 | 95 | 2 | 0 |
| La Arena de los Caídos | Pícaro Veneno nivel 1 | 98 | 17 | 0 | 0 |
| Travesía por el Bosque Sombrío | Guerrero Armas equipado | 100 | 93 | 1 | 0 |
| Travesía por el Bosque Sombrío | Médico nivel 1 | 61 | 3 | 0 | 0 |

- Guerrero Armas equipado: el héroe del stack local, con ataque 12, defensa 14, vida 40 y daño 1d4. Pícaro Veneno y Médico de nivel 1: Tabla 6.
- Sin estrategia, las cifras bajan. Por ejemplo, el Médico cae del 61 % al 30 % en la Travesía: la estrategia importa.
- Mítico queda para héroes más fuertes. El curso dice que el nivel multiplica las estadísticas (nivel 3 → ataque 30), pero Player/Inventory aún no lo aplica: con héroes de nivel alto el balance cambiará y habrá que medirlo de nuevo.

### P-J10 — Nombres, no identificadores

- El detalle añade `prerequisiteMissions` con el nombre de cada misión previa.
- El resumen del historial añade `bestTimes[].missionName`, `epicCollection[].masterName` y `narrativeProgress[].missionNames`.
- Web traduce estados, tipos de héroe, estadísticas y motivos. La experiencia se muestra en su panel y no como «× N» en las recompensas.

### P-J11 — Ilustraciones

- Cada misión guarda `imageRef`: `mision-camino-templo`, `mision-templo-olvidado`, `mision-camara-sellada`, `mision-arena-caidos` y `mision-travesia-bosque`.
- Web dibuja una escena SVG propia por nombre, sin archivos externos. Un nombre desconocido usa la escena de su categoría.

## Cambios de contrato

Todos son compatibles: añaden campos o rutas y no quitan ni renombran nada. La única cifra que cambia de significado es `masterEncounter.probability` de HU-70; con un solo candidato vale lo mismo que antes.

| Contrato | Cambio |
| --- | --- |
| HU-70 | `GET /missions/{id}`: `imageRef`, `prerequisiteMissions`, `rewards` de P-J2, `epic` anulable y `masterEncounter.probability` como probabilidad de la misión (P-J3). Ruta nueva `GET /missions/{id}/estimate`. |
| HU-71 | Sin cambios de forma. La estimación dice qué habilidades de la estrategia sirven en misiones. |
| HU-72 | Combat: `POST /simulations/estimates`. La solicitud lleva la composición del nivel y la probabilidad de botín mejorada (P-J8). Las habilidades se evalúan con P-J4. |
| HU-73 | Una épica oficial por Máster, varios candidatos por misión y un 15 % por misión (P-J3). |
| HU-74 | Reporte: `strategy`, `healingDone`, `abilityDamage` y líneas `PRODUCT` de origen `HU-72`. Resumen: nombres y `epicAlbum`. Rutas nuevas `GET /missions/me/active` y `GET /missions/me/progress/{id}`. |
| HU-75 | `GET /missions/{id}/difficulties`: `extraEnemiesPerEncounter`, `bossEnrageBonus` y `lootBonusPercent`. |
| HU-76 | Sin cambios. Un catálogo vacío se lee como «sin logros definidos». |

Base de datos de Missions:
- **011:** tabla `mission_loot_grants` y el origen `HU-72` en las líneas del reporte.
- **012:** contenido v2.

## Decisiones del PO (2026-09-24)

El PO respondió las preguntas abiertas de los diseños de HU-70 a HU-76. Estas son las que tocan este diseño:

| Pregunta | Decisión | En este diseño |
| --- | --- | --- |
| Probabilidad de los Máster | 15 % por misión. Se consulta al profesor. | Aplicada en el contenido v2, el detalle y la estimación. La dificultad ya no la sube (P-J3, P-J8). |
| Épicas de los Máster | Las 8 oficiales de la Tabla 20. | Aplicada (P-J3). «Velo de Sombras», que no es un producto, queda reemplazada por «Toma y lleva». |
| Épica repetida | Se acumula. | Ya es así: Player/Inventory suma la cantidad y el álbum la cuenta una vez. |
| Créditos, cofres y títulos | HU-10 (#19) la hace Beta. | Siguen ocultos hasta que HU-10 los entregue (P-J2). Los créditos necesitan una ruta nueva en Wallet (Gama). |
| Nombres de la dificultad | Normal, Heroico, Legendario y Mítico, también en el filtro del tablón. Mítico se queda en ×2,5. | Los niveles ya usan esos nombres y el ×2,5. El tablón aún no tiene filtro por dificultad (pregunta 10 del diseño de HU-70): está fuera de este alcance. |
| Tiempo agotado sin el objetivo principal | Misión fallida. | Ya es así: `FAILED` con `TIME_LIMIT`. |
| Botín | Pasa al inventario al terminar y también se vende en la tienda. Solo las épicas son exclusivas de las misiones y no se venden. | El botín ya se entrega (P-J1) y sus productos quedan a la venta. Falta confirmar que las épicas de producción no se puedan comprar (ver el runbook). |
| Logros | Los 5 del curso (7.8.11). | Falta cargarlos en el catálogo de HU-76. Mientras esté vacío, Web muestra «Aún no disponible» (P-J3). |
| Cancelar una misión | El héroe queda cansado un tercio de la duración y no recibe recompensas. | Fuera de este diseño. |

**Sigue pendiente del PO:**

1. Los valores de P-J8 (enemigos de más, ataque de más del jefe y mejora del botín) y la escala de riesgo de la estimación (P-J7). Son propuestas del equipo.
2. La confirmación del profesor sobre el 15 %.

## Verificación

- **Missions:** 1075 pruebas unitarias y de integración, y 13 suites (217 pruebas) contra PostgreSQL real con Testcontainers. Incluyen la migración 012 sobre una base v1 enlazada y editada, y el 15 % de Máster por misión.
- **Combat:** pruebas unitarias de la política de habilidades (24 habilidades de producción) y de la simulación, y pruebas HTTP de `POST /estimates`.
- **Web:** 2484 pruebas, incluida la guarda `noClientAuthority` de HU-09.5, y el build de producción con su verificación de bundle.
- **Punta a punta local:** ver la sección de entorno local del runbook de productos.
