# Registro de ejecución A — 7 de octubre de 2026

Estado: **contrato disponible; integración pendiente de entregas certificadas**. Refs Nexus-Battle-VI/Nexus-Battle-Management#470.

## Último corte de entregas B/C — controles finales y límites

B entregó [Tournament #12](https://github.com/Nexus-Battle-VI/Nexus-Battle-Tournament/pull/12) en borrador, develop 2679af4, head/testedSHA be54b0a108e676ec79dadbfb593dff9c0ceb435c. Su estado y `evidencia/chat-B-verificacion-final.json` informan lint/format/typecheck/build, 318 unitarias/HTTP y 50 PostgreSQL (cero omitidas), cobertura ramas 88.66%/85.52%. A revisó ese reporte y verificó el SHA/base/head del PR; no reejecutó sus suites. CI 37656818640 sigue en curso al corte consultado. Los resultados generales anteriores 316/fixtures dirigidos quedan sustituidos por esta entrega final.

C entregó head/testedSHA 00764585d24cc973fdd24768e8d2503b4cc04b90 en [Combat #86](https://github.com/Nexus-Battle-VI/Nexus-Battle-Combat/pull/86), base dd67d47. A revisó logs locales finales: 3526 pruebas, 68 Mongo seleccionadas; CI [37655450014](https://github.com/Nexus-Battle-VI/Nexus-Battle-Combat/actions/runs/37655450014) confirma Calidad y pruebas/Python SUCCESS sobre 0076458, con 248 Mongo de suite completa declaradas por C y presentes en su log CI. Imagen en curso al consultar; no declarar workflow/despliegue íntegros aprobados. El fallo de 317726d se conserva como historia corregida, no fallo actual de calidad sobre 0076458.

Los recorridos B prueban Tournament/HTTP/PostgreSQL real con motor/HMAC Combat real **en memoria** y Account/Inventory/JWT/pagos controlados; Mongo real se verifica por separado en C. No hay todavía un único recorrido Web→Tournament→Combat/Mongo con cuentas/premios reales. La reproducción dirigida A de siete casos sobre be54b0a corrige 3–3/aceptación; el criterio de cierres incompletos sin tick reciente sigue no certificado. Se conserva r3 y los dos blockers de premios, sin atribuir aprobación PO.

## Actualización r3 — corte anterior de marcador interno

Este apartado actualiza el corte inicial conservado más abajo. Versión documental `torneos-v3.0.0+r3`; contrato público y rutas sin cambio.

B entregó `fc7a95ebc1af4779755a1cfc037c560d470cdd56` (registro/modalidad/avance), inspeccionado; HU-85/convocatoria del working tree sigue pendiente de su commit final. El adaptador ya traduce tournamentMode→mode. C actual está en `tmp/torneos-modalidades-arboles-20261007/Nexus-Battle-Combat`, limpio en `317726d36e9aa7775c6920a2d7782fb713cc7a75`, con develop dd67d47 como ancestro. La entrega 7df51d8 queda como historia, no base integrada actual.

Inicialmente C 5d247e0 exigía el marcador numérico contractVersion:3, incompatible con el wire r2 de B. Durante la verificación publicó 317726d, que lo hace opcional. A comprobó que ambos cuerpos nuevos —con y sin marcador 3— pasan su parser y generan la misma intención normalizada v2. El string público torneos-v3.0.0 no se envía como marcador interno. Peticiones históricas siguen con huella original v1. C añade metadatos tournament y migración forward 026; 018/025 se conservan.

A ejecutó `evidencia/verificar-wire-combat-r3.cjs`: parser/política C reales y adaptador B real con **fetch doble**, 3 modalidades, marcador opcional, rechazo string, duplicado, orden de lados y hash histórico. El cuerpo actual B pasa C; hashes de fuentes capturados sin cambios durante esa comprobación. No crea/inicia salas ni accede a DB/Account/Inventory. Evidencia machine-readable en `evidencia/conformidad-wire-r3.json` del paquete.

C entregó logs finales sobre 317726d: typecheck/lint/format, 165 suites y 3526 pruebas con cobertura; 3 suites y 47 pruebas seleccionadas sobre MongoDB 8.0.24 real. A leyó los logs y el estado del dueño, no repitió esas suites. Account/Inventory/compromisos/JWT siguen siendo dobles de C: no es aceptación integrada. B declara 5 pruebas nuevas de aceptación/reinicio/final por ausencia sobre PostgreSQL real, todavía sin SHA HU85 entregado.

C creó el PR borrador [Combat #86](https://github.com/Nexus-Battle-VI/Nexus-Battle-Combat/pull/86), develop←317726d. El [CI 37654858884](https://github.com/Nexus-Battle-VI/Nexus-Battle-Combat/actions/runs/37654858884) falló: suite Mongo completa con 2 assertions históricas que suponían que 024/025 eran las últimas migraciones (246 pruebas pasan / 2 fallan). La migración nueva 026 invalida esas posiciones; no se elimina ni reordena la historia para satisfacer el test. Al corte se observa el commit local 00764585d24cc973fdd24768e8d2503b4cc04b90, que modifica esos dos archivos de pruebas; falta certificar su CI. Los resultados verdes sobre 317726d no se atribuyen a 0076458 automáticamente.

### Desajuste de Web: índice, archivos visibles y checkout aislado

La revisión original 3294cac conserva 218 archivos preparados en Git, 15 con diferencias posteriores frente al índice y 27 no rastreados (los grupos se solapan). Por ejemplo, CreateTournamentPanel/RegisterTeamForm tienen imports de TournamentVisuals en los archivos visibles y de Button/Card genéricos en el índice. La revisión visual y una prueba del índice no bastan para certificar una copia completa ni un contrato API. A conserva ambos estados: no resetea, confirma ni copia en bloque esa revisión.

El checkout de D `tmp/torneos-modalidades-arboles-20261007/Nexus-Battle-Web` ya contiene bde49b8d68ca25276b32d84da1818bebf5c090ec (modalidades/árbol/diseño), más cambios posteriores de calendario/aceptación todavía sin commit. A ejecutó `npm run typecheck` allí a las 16:52 UTC, con salida 0. El bloqueo citado por el usuario **no se reproduce en ese working tree actual**; no se ha reejecutado la prueba en una exportación del índice original ni certificado el SHA bde49b8 con sus cambios posteriores. La continuación corresponde a D: adaptar selectivamente al contrato común, conservar v2 y entregar commit final con tipos, pruebas y QA de navegador sobre ese mismo estado. Evidencia adicional en `evidencia/reconciliacion-web-A.json` del paquete.

Nuevo bloqueo **PRIZE-RECIPIENT-01**: reconsultada la ruta Inventory `GET /api/internal/v1/players/:playerId/equipped-hero` en develop 7c76dda, blob `9e3ccd938c4096ff14a1241f66cbd61fb90a7ce6`. Permite commerce/notifications/combat, no tournament. El working tree B usa `UnavailableTournamentPrizeRecipients` y devuelve PRIZE_RECIPIENT_CONTRACT_REQUIRED sin petición indebida. Conservar derecho/destinatario PENDING, responsable PRIZE_OPERATIONS. La fuente heroId de una Final jugada puede ser su registro oficial; no se inventa héroe para ausencia. Este bloqueo es independiente de PRIZE_RESOLUTION_CONTRACT_REQUIRED por sala ausente y de publicar consumidores de premio.

[Contrato normativo](../../contracts/torneos-v3.0.0.md), [corte machine-readable](corte.json), [matriz completa](matriz.json), [borrador de tareas HU-85](../../tasks/hu-85-ampliacion-20261007.md).

## Corrección B be54b0a — núcleo corregido, criterio incompleto pendiente

B sustituyó el commit 7910079 por `be54b0a108e676ec79dadbfb593dff9c0ceb435c`. A verificó checkout B limpio, fuentes src/test/support sin diferencias frente a ese commit y siete escenarios dirigidos (`evidencia/verificar-recuperacion-ventana-r2.cjs`): 3–3 produce intención COMBAT tras pausa de 10 s y tras pausa larga; primera aceptación a +42 s pasa pese a falta de ticks; GET muestra CLOSED/RESOLUTION_PENDING al deadline, sin mutar la decisión. Los recibos y el deadline se conservan. Estos dos defectos del corte anterior quedan **corregidos en componente**, no se mantiene su dictamen como si describiera be54b0a. A no inicia Combat ni accede a bases en este chequeo.

Permanece **B-RECOVERY-01C**: cierre incompleto 3–0 con gap de observación >=10 s queda BLOCKED sin ganador, mientras con observación reciente produce ausencia. El umbral todavía decide el resultado sin probar que la aceptación estuvo indisponible. Se registra como criterio operativo/producto no certificado, separado de los bugs ya corregidos. No se aprueba una regla nueva ni se modifica el contrato normativo; diferenciar pausa del observador de fallo real sigue pendiente del dueño/validación.

B entregó después los controles finales be54b0a (318 unitarias/HTTP y 50 PostgreSQL, reporte del dueño revisado por A) descritos en el último corte. A no repitió esas suites. Evidencia de componente exacta, 31 hashes de fuentes y casos en `evidencia/recuperacion-ventana-A-r2.json`. La evidencia anterior se conserva para explicar la corrección.

## Corte anterior B 7910079 — guard reproducido, histórico

B informa seis pruebas PostgreSQL de aceptación/reinicio/ausencia y tres de modalidades HTTP/Tournament/PostgreSQL con Combat real, más 23 unitarias/HTTP nuevas. Se observa el commit HU-85 `79100793d9095c12ad8f41fccb9f184bf7aecf0d`, todavía con cambios posteriores y controles finales a cargo de B. A inspeccionó la prueba y su harness: Combat ejecuta motor/HTTP/HMAC reales, pero persistencia memory y AUTH_MODE disabled; Account/Inventory y JWT son controlados. Es evidencia distinta de Mongo real en las suites de C y no se suman ambos como un único recorrido con todos los servicios reales. No se han recibido logs ni testedSHA final de las nueve pruebas.

**B-RECOVERY-01 (P1):** un intervalo >=10000 ms sin lastObservedAt convierte OPEN en WINDOW_INTERRUPTED antes del cierre. A lo reprodujo con cinco escenarios sobre los casos de uso/dominio reales y puertos/reloj en memoria (`evidencia/verificar-recuperacion-ventana.cjs`). Con 3–3 recibos durables, lastObservedAt a +110 s y reanudación al deadline +120 s, no existe intención de Combat: queda BLOCKED. Con 3–0 tampoco resuelve. A +42 s, tras pausa del observador de 12 s, la consulta muestra OPEN pero una primera aceptación devuelve 409 ACCEPTANCE_CLOSED dentro del horario. Con observación a +115 s, el cierre 3–3 sí produce COMBAT. Recibos y deadline se conservan en todos esos casos.

No se ha demostrado que falten ticks porque el canal de aceptación fuera inaccesible. Con ambos equipos completos tampoco hay ausencia que inferir: las seis intenciones están confirmadas. El umbral es una decisión técnica de B, **no una regla nueva aprobada por el usuario**. Los criterios vigentes siguen siendo ambos completos juegan, retomar cierres tras reinicio y no inventar una derrota ante una incidencia comprobada. Se pide a B separar disponibilidad de observación, reconciliar cierre/consulta/primera aceptación y añadir regresiones; revisar el guard SQL coherentemente sin reescribir historia ya aplicada. A no modifica Tournament ni elimina protecciones ante caídas reales.

Hashes de las 31 fuentes cargadas sin cambios durante la reproducción en `evidencia/recuperacion-ventana-A.json`. Este chequeo acredita el efecto del guard, no HTTP/PostgreSQL, caída real, disponibilidad medida ni controles finales del SHA. La matriz A4-07/A4-08/A4-17 queda sin conformidad de componente hasta resolver este hallazgo. Contrato normativo r3 sin cambios; comunicación solamente por archivos.

## Corte inicial r2 (histórico)

Se reconsultaron develop y los PR fusionados de la base HU-85 mediante git fetch/GitHub API. Se encontró c9446f8 limpio en un repositorio independiente, no como rama del original. No se debe reconstruir desde el original sucio. B está aislado desde 2679af4 y recupera avance/premios selectivamente.

| repo | develop reconsultado | checkout de escritura de la ejecución |
| --- | --- | --- |
| Infrastructure | 4397e313050f5965539f00a8e49dbb4b8387d520 | tmp/infrastructure-torneos-v3-20261007, rama docs/torneos-v3-hu85-20261007 |
| Tournament | 2679af41c47519578bbb21fbd82ebb4521b3869d | tmp/tournament-modes-hu85-20261007, B |
| Combat | dd67d471af403097333b15d84cb1a00d0a41e0ec | tmp/hu85-combat, C |
| Web | 59df33012bf5d6153d5075b0b96e4f9929c00f15 | tmp/torneos-modalidades-arboles-20261007/Nexus-Battle-Web, D |

A conserva los originales: Tournament df2c544 (86 rutas cambiadas), Web a487eb2 (391), Infrastructure 0df09dd (8, incluyendo dos borradores de A), y Combat review ef10577 limpio. La copia Tournament c9446f8 está limpia; Web revisión 3294cac tiene 251 rutas cambiadas. Estos conteos son del corte **actual**, no resultados de planes viejos. El inventario completo de hashes queda en el paquete compartido; no incluye contenidos/credenciales ni sustituye un respaldo de archivos sin commit.

La comparación develop→c9446f8 incluye 71 archivos (4189 adiciones / 2269 eliminaciones): además de avance/premios incorpora observación/enlaces y elimina la administración HU-85 publicada. Por eso **no es una base que se pueda copiar completa** ni progreso/premios ya publicados.

Se generó y verificó un bundle recuperable de la rama c9446f8 en el paquete compartido (`evidencia/tournament-c9446f8.bundle`, historial completo). No reemplaza archivos sin commit de otros checkouts. En Web revisión se observaron 218 archivos con cambios en el índice y 15 con diferencias del working tree frente al índice; hay además no rastreados. El HEAD y una prueba del índice no identifican por sí solos la interfaz visible. D debe reconciliar esas diferencias selectivamente en su checkout aislado; el original conserva ambos estados.

El checkout aislado de A se creó con git worktree porque el chat está asociado a P2, que no es por sí un repositorio. Las otras worktrees encontradas pertenecen a entregas previas; sus archivos permanecen intactos. CONTRIBUTING conserva texto antiguo trunk/main, mientras la base y los PR reales del encargo usan develop; el borrador de PR sigue el destino develop vigente solicitado.

## Migraciones y DDL aplicada

| reserva Tournament | contenido | estado |
| --- | --- | --- |
| 001–003 | archivo/registro/bracket publicados | hashes idénticos entre develop y checkout B |
| 004-tournament-admin-actions | administración HU-85 publicada | hash idéntico; conservar |
| 005-tournament-external-links | adaptación selectiva de enlaces si se recupera | reservado, no obligatorio |
| 006-tournament-mode-members-progression | modalidad/miembros/proyección recuperada | archivo B observado; no commit entregado |
| 007-tournament-round-acceptance-resolution | calendario/aceptaciones/resoluciones | reservado a B; implementación pendiente |

También existen 006-tournament-results-prizes y 007-tournament-broadcast **locales** en c9446f8. Esos nombres no se portan como sustitutos de 006/007 de esta base. Si la DDL local de enlaces/prizes/broadcast ya fue aplicada en un entorno reutilizado, se requiere puente incremental adaptado a su historial, no borrar/renombrar entradas de kysely_migration ni ejecutar CREATE repetido.

**MIGRATION-ORDER-01:** Kysely, con la configuración publicada de Migrator, exige nombres nuevos posteriores al último aplicado. Reservar 005 no permite instalarla después de 006. Si 006 ya está aplicada cuando se recuperen enlaces, se asigna a enlaces el siguiente ordinal libre posterior; no se cambia el historial ni se habilita desorden para ocultar el conflicto. La reserva 005 solo es utilizable antes de aplicar 006 y después de revisar la base concreta.

Auditoría read-only de A en PostgreSQL 18.4 aislado, 127.0.0.1:25407, database postgres: no había tablas persistentes de historial/administración/enlaces al consultar. Esa instancia sirve pruebas con schemas temporales; **no permite afirmar qué DDL se aplicó en producción o en otras bases locales**. Hace falta reportar SELECT name,timestamp FROM kysely_migration por cada entorno de upgrade. Se verificaron los cuatro hashes de fuentes publicadas, no la instalación/upgrade completos. No se detectó proceso Mongo activo en el corte; no se probó persistencia Mongo.

## Entregas recibidas y defectos de coordinación

- C: commit local 7df51d81a249335c67f0a7ce0845a0f5747d2339, inspeccionado y limpio. Su estado declara types/lint/format y 24 pruebas unitarias; A **no repitió** esas suites. No acredita inicio real de seis humanos, Mongo, servicios reales ni contrato v3 final. Base d0a9cc4, seis commits detrás de develop dd67d47.
- B: todavía sin commit entregado. Su archivo de estado declara types/build/lint, 280 pruebas unitarias/integración y 39 PostgreSQL; 12 casos Combat real omitidos. Son **resultados declarados por B sobre working tree**, no testedSHA certificado ni pruebas ejecutadas por A.
- D: checkout aislado en 59df330, sin commit/testedSHA entregado; diseño/formularios/árbol en curso.

Hallazgos pendientes del dueño, accesibles también en estado/contrato-comun.json:

1. **B-WIRE-01:** HttpCombatRoomCommandAdapter envía input sin traducción. tournamentMode de B no es mode de C; TRIO llega como modalidad omitida y C deriva DUO. El adaptador debe construir el wire canónico, con el roster original en retries.
2. **C-CONTRACT-01:** 7df51d8 parsea mode, no valida teamSize. Debe comprobar concordancia y conservar huellas históricas. No se requiere inventar una migración si capacidad/roster existentes bastan; C decide DDL tras verificar persistencia.
3. **C-BASE-01:** reconciliar con develop vigente y certificar el motor/persistencia, porque los seis commits posteriores afectan el servicio.
4. **PRIZE-ABSENCE-01:** consumidores locales de Wallet/Inventory exigen diez campos, finalRoomId y heroId. En develop reconsultado (47f9799 / 7c76dda) no están las rutas de premios preparadas. Guardar derechos PENDING/PRIZE_RESOLUTION_CONTRACT_REQUIRED; requiere consumidor versionado propio del dueño.
5. **D-CONTRACT-01:** el borrador inicial A mencionaba /api/v3 y mode; B mantiene /api/v1 y tournamentMode. El contrato actual fija rutas v1, traducción interna y encounterId opaco. El borrador genérico previo queda sustituido.

No se enviaron mensajes a chats externos: la coordinación se publica en archivos compartidos. No se modificaron estados B/C/D, asignaciones, comentarios ni la HU cerrada.

## Evidencia, dictamen y próxima condición comprobable

La matriz contiene los 23 recorridos requeridos con evidencia integrada **NO_EJECUTADO_POR_A**. A valida formas/schema/fixtures, calendario UTC, grafo y enlaces documentales; eso no acredita que el código ya aplique las reglas.

Los tres objetivos siguen pendientes de integración: 3v3 exige motor y seis humanos reales, árboles requieren QA desktop/móvil, HU-85 ampliada requiere worker/aceptación/ausencias durable y su avance. Las pruebas con dobles del dueño quedan separadas de pruebas de servicios reales y de aceptación humana.

Condición de siguiente corte: commits B/C/D con contrato compatible y comandos/evidencia exactos; entonces ejecutar matriz y clean/upgrade en PostgreSQL/Mongo aislados. Para Wallet histórico, las versiones actuales fueron reconsultadas; WALLET-PRECISION-01/02 no se reabren ni se declaran corregidos sin reproducción sobre el SHA actual.

[PR documental preparado](PR-CONTRATO.md). No hay PR de implementación creado por A ni merge/despliegue. PixelLab, OBS/YouTube y plan 7 permanecen fuera de este paquete.
