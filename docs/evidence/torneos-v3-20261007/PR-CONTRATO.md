# docs(tournaments): [HU-85] fijar contrato v3 de modalidades, convocatoria y resolución

Destino previsto: develop, reconsultado en 4397e313050f5965539f00a8e49dbb4b8387d520. Borrador local preparado; no se ha publicado un PR.

Refs Nexus-Battle-VI/Nexus-Battle-Management#470, #467, #468, #469 y #465.

Cuando se registra un TRIO, Tournament debe proyectar tres integrantes por lado y traducir tournamentMode a mode al preparar Combat. Esta revisión fija el wire, las seis rondas UTC, aceptación individual de 120 segundos, resultados PLAYED/ABSENCE y el puente de compatibilidad de torneos v2. Permite que B/C/D implementen sobre una misma referencia y deja visible el bloqueo de premios por ausencia.

Incluye esquemas/fixtures, grafo G1 con E9/E10 cruzados y una Final, reserva de migraciones nuevas y matriz de integración con pendientes. No modifica los contratos v2, migraciones aplicadas ni implementaciones de otros servicios.

Revisión documental r4: intento privado distinto de recibo, ACCEPTANCE_PENDING temporal, error técnico confirmado separado de rechazo 4xx y de ausencia de ticks; reserva forward condicional si 007 preliminar ya está aplicada. Mantiene wire y reglas de r3. No modifica migraciones ni implementaciones de B/C/D.

Validación documental: 28 comprobaciones de schema/casos positivos y negativos, grafo/destinos, fechas UTC/deadline, enlaces internos y whitespace. Evidencia versionada del paquete: verificacion-contrato-A.json (r2), verificacion-contrato-A-r3.json (r3) y verificacion-contrato-A-r4.json. Parser C/adaptador B compatibles con marcador numérico 3 opcional, sin cambiar el string público ni v2. No acredita comportamiento integrado, cuentas reales o premios.

El registro conserva la evidencia histórica B-RECOVERY-01 y B-ATTEMPT-RACE-01. Sobre 98628f7, A comprueba siete escenarios de recuperación y la carrera de deadline: limpia rechazo normal, permite cierre 0–0 y conserva un único sorteo; el noveno caso muestra incompatibilidad de JSON preliminar, no prueba su upgrade SQL. B declara 323 unitarias/HTTP y 52 PostgreSQL, cero omitidas, con CI calidad/imagen SUCCESS. C0076458 tiene CI calidad/Python/imagen SUCCESS. Los recorridos B con Combat real usan persistencia memory; Mongo real está probado por separado en C, no como el mismo recorrido. Upgrade B desde 001–004 acreditado por dueño; variantes preliminares 007 y entorno integrado/cuentas/premios aún sin certificación.

PR de implementación separados, que cada dueño prepara sobre su base vigente:

1. Combat: cardinalidad de salas y motor/registro real 2/4/6 humanos; validación tamaño, replay histórico, Mongo y base develop vigente.
2. Tournament: modalidad/miembros/consentimiento y avance; DDL 006, ocho cupos, v2 preservado, PostgreSQL limpio/upgrade.
3. Tournament: ampliación HU-85; DDL 007, aceptación/calendario/worker/resolución y concurrencia por justa.
4. Web: formularios y árboles; fixtures demo rotulados, grafo recibido del servidor, desktop/móvil.
5. Web: aceptación y administración; JWT propio, deadline servidor, ausencia/bloqueo y pendiente de premios visibles.

No se usan Closes para la HU padre cerrada; las tareas de ampliación se publicarán solo con autorización de gobierno. La política de pago/premios permanece vigente.
