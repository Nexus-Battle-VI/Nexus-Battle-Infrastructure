# Registro de ejecución A — 7 de octubre de 2026

Estado: **contrato disponible; integración pendiente de entregas certificadas**. Refs Nexus-Battle-VI/Nexus-Battle-Management#470.

[Contrato normativo](../../contracts/torneos-v3.0.0.md), [corte machine-readable](corte.json), [matriz completa](matriz.json), [borrador de tareas HU-85](../../tasks/hu-85-ampliacion-20261007.md).

## Qué se comprobó ahora

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
