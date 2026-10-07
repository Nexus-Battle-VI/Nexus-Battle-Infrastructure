# docs(tournaments): [HU-85] fijar contrato v3 de modalidades, convocatoria y resolución

Destino previsto: develop, reconsultado en 4397e313050f5965539f00a8e49dbb4b8387d520. Borrador local preparado; no se ha publicado un PR.

Refs Nexus-Battle-VI/Nexus-Battle-Management#470, #467, #468, #469 y #465.

Cuando se registra un TRIO, Tournament debe proyectar tres integrantes por lado y traducir tournamentMode a mode al preparar Combat. Esta revisión fija el wire, las seis rondas UTC, aceptación individual de 120 segundos, resultados PLAYED/ABSENCE y el puente de compatibilidad de torneos v2. Permite que B/C/D implementen sobre una misma referencia y deja visible el bloqueo de premios por ausencia.

Incluye esquemas/fixtures, grafo G1 con E9/E10 cruzados y una Final, reserva de migraciones nuevas y matriz de integración con pendientes. No modifica los contratos v2, migraciones aplicadas ni implementaciones de otros servicios.

Validación documental: schema/casos positivos y negativos, grafo/destinos, fechas UTC/deadline, enlaces internos y whitespace. Los resultados exactos se registran en el archivo verificacion-contrato.json del paquete compartido al ejecutar. No acredita todavía comportamiento integrado, Mongo, cuentas reales o premios.

PR de implementación separados, que cada dueño prepara sobre su base vigente:

1. Combat: cardinalidad de salas y motor/registro real 2/4/6 humanos; validación tamaño, replay histórico, Mongo y base develop vigente.
2. Tournament: modalidad/miembros/consentimiento y avance; DDL 006, ocho cupos, v2 preservado, PostgreSQL limpio/upgrade.
3. Tournament: ampliación HU-85; DDL 007, aceptación/calendario/worker/resolución y concurrencia por justa.
4. Web: formularios y árboles; fixtures demo rotulados, grafo recibido del servidor, desktop/móvil.
5. Web: aceptación y administración; JWT propio, deadline servidor, ausencia/bloqueo y pendiente de premios visibles.

No se usan Closes para la HU padre cerrada; las tareas de ampliación se publicarán solo con autorización de gobierno. La política de pago/premios permanece vigente.
