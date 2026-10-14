# Pilotos gratuitos de torneo — extensión de torneos-v3.0.0

Revisión 1, 13 de octubre de 2026. Refs Nexus-Battle-VI/Nexus-Battle-Management#470.
Complementa [torneos-v3.0.0](torneos-v3.0.0.md); disponible en los PR de implementación,
pendiente de integración y despliegue. La evidencia local no acredita producción.

## Creación y calendario

`POST /api/v1/tournaments/admin` permite el booleano opcional `isTest`.
Omitirlo o enviar `false` conserva un torneo oficial y la intención idempotente
histórica. Solo un administrador puede crear un piloto. `true` exige modalidad
explícita SOLO/DUO/TRIO, contrato v3 con aceptación personal e inscripción gratuita
(`entryPolicy: {version: 1, free: true, methods: []}` o `entryFee: 0`).
Un valor de otro tipo o una entrada de pago se rechaza antes de efectos.

`PublicTournament` expone `isTest: boolean`; la ausencia en datos históricos
equivale a `false`. El bracket del piloto conserva `isTest: true` en su snapshot
inmutable. El modo de prueba queda fijado al crear: una repetición con otro modo
bajo el mismo `operationId` es un conflicto; no se convierte un torneo existente.

Los pilotos no participan en la exclusión de 91 días entre torneos oficiales.
Los torneos oficiales conservan esa exclusión entre sí. Se mantienen ocho equipos,
dos minutos de aceptación individual, seis ventanas de ronda y una sola final.
No se alteran las fechas ni se extienden ventanas al conectar tarde.

## Propagación Tournament → Combat

El cuerpo firmado de `POST /api/internal/v1/combat/tournament-rooms` añade
`isTest: true` exclusivamente para un piloto. Se mantienen `operationId`,
`tournamentId`, `encounterId`, `mode`, `teamSize` y el roster completo de `teams`.
HMAC firma el cuerpo íntegro, con sus validaciones y permisos existentes.

Combat valida el booleano, conserva el marcador en `BattleRoom.tournament.isTest`
y lo devuelve en `BattleRoomDto.tournament.isTest` y el record. No cambia el modo
PVP de la raíz ni la versión interna 3. Tournament exige confirmación explícita
del marcador antes de vincular/iniciar una sala de prueba. Un Combat anterior
que lo omita deja la operación pendiente con `SERVICE_UNAVAILABLE`, sin arrancarla.

`true` forma parte de la huella idempotente de la sala. Omitido y `false` conservan
la huella anterior; cambiar un piloto por oficial bajo una operación usada genera
conflicto. Los cuerpos históricos sin modalidad ni marcador permanecen intactos.

## Sin efectos económicos

En un piloto, Combat no crea derechos de créditos, progreso de cofre, experiencia
ni entregas de objetos. Tampoco crea un workflow de pérdida/transferencia de equipo,
aunque el inventario del participante contenga objetos con probabilidad de caída.
La reconciliación al reiniciar conserva la exclusión: el marcador se lee de MongoDB.
El compromiso del héroe sí se adquiere y libera normalmente para permitir otra ronda.

Tournament rechaza aprobar y entregar premios del piloto; PostgreSQL también impide
guardar premios/deliveries en su lifecycle. El torneo puede cerrar con campeón y
estadísticas, sin generar pagos ni productos. Wallet e Inventory mantienen sus contratos.

## Entrada personal y resultados en Web

Cada jugador acepta desde su sesión. Web consulta su convocatoria, valida sujeto,
torneo, equipo y encuentro del recibo, y anuncia la entrada automática a **su** sala
dos segundos después de estar disponible. La consulta continúa en otras secciones
del torneo. Una sesión ajena no recibe acceso ni acepta en nombre de otro participante.

Se mantienen los límites existentes de Combat: turno de 30 segundos, batalla de
seis minutos y desconexión de 30 segundos desde el inicio. Esta entrega no incorpora
una barrera que espere a que lleguen ambos navegadores. La pantalla avisa que hay
que llegar a la arena y permanecer conectado; aceptar por sí solo no conecta al socket.
Un navegador lento o cerrado todavía puede perder por desconexión. Debe comprobarse
el recorrido con Cognito, proxy, WebSocket y redes reales después del despliegue.

Web usa nombres de participantes en el marcador, muestra el siguiente encuentro,
ofrece **Volver al torneo** y oculta recompensas en el piloto. Las llaves principales
son ganadores y perdedores, con una final accesible desde ganadores.

## Migraciones y entrega

1. Combat: migración forward `033-battle-rooms-test-tournament`, que amplía solamente
   el metadato del torneo y conserva el resto del validador y expresiones de MongoDB.
2. Tournament: `010-tournament-combat-result-projection` compara los campos de resultado
   usados por Tournament con el evento terminal rico de Combat; conserva los controles
   de secuencia, sala y archivo. `011-test-tournaments` añade `is_test`, restringe la
   exclusión de calendario a oficiales y guarda las restricciones del piloto.
3. Web: interfaz y creación administrativa del piloto, después de ambos servicios.

No se reescribe ninguna migración aplicada. Después de crear un piloto, conservar
una versión de Combat que entienda el marcador: una versión antigua podría reconstruir
recompensas desde salas terminadas al reconciliar. La retirada de la interfaz no borra
el historial ni permite retroceder el backend a una versión sin esta protección.

## Evidencia local

El [registro del torneo completo](../evidence/tournament-pilot-20261013/registro.md)
identifica los límites de la simulación, resultados y capturas. No sustituye el piloto
con compañeros reales ni supone aprobación funcional del producto.
