# Ampliación de HU-85 cerrada — borrador trazable

Estado: redacción preparada, **sin publicar issues/comentarios ni cambiar asignaciones**.
Refs Nexus-Battle-VI/Nexus-Battle-Management#470; cierre previo conservado.

Problema: el torneo publicado opera con parejas y preparación/inicio manuales. El usuario necesita ocho cupos en SOLO/DUO/TRIO, una convocatoria individual por justa y avance verificable, incluso por ausencia, mientras puede entender el recorrido en árboles conectados.

Resultado esperado: ocho tríos equivalen a 24 identidades distintas; las justas usan seis humanos reales cuando ambos lados aceptan, o un resultado propio de Tournament con motivo y resolución durable. El horario y los retrasos son visibles.

Contrato: [torneos-v3.0.0](../contracts/torneos-v3.0.0.md). No se atribuyen los PR anteriores a nuevos autores ni se afirma aceptación nueva por el cierre histórico de #470.

| ID local | dueño | tarea de ampliación | criterio que acredita |
| --- | --- | --- | --- |
| HU85-A01 | A | Contrato, calendario UTC, reserva de migraciones y evidencia | formas exactas v3 y consumidores v2 preservados |
| HU85-B01 | B | Modalidad, integrantes y consentimiento; ocho cupos | 8/16/24 distintos; tamaño y consentimiento exigidos en servidor |
| HU85-B02 | B | Proyección HU-80 y consulta HU-83 | E9/E10/Final correctos; ganadores/perdedores nuevos con roster exacto |
| HU85-B03 | B | Calendario, aceptación JWT, worker y resolución | 120s, deadline estricto, independencia, bloqueo visible, ausencia/sorteo durable |
| HU85-C01 | C | Creación/inicio/registro de 2/4/6 humanos | cardinalidad válida, motor real y una sala por justa con retry/concurrencia |
| HU85-D01 | D | Formularios por modalidad y árboles | grafo del servidor legible en desktop/móvil, detalle por justa |
| HU85-D02 | D | Aceptación y administración conectadas | identidad propia, hora prevista/real, ausencias/bloqueos/premios pendientes visibles |
| HU85-DEP01 | Wallet/Inventory, dueño pendiente | Consumidor de premios basado en fuente/resolutionId | final ABSENCE sin sala ficticia, política/importes vigentes, una entrega por derecho |
| HU85-DEP02 | Inventory, dueño pendiente | Fuente de héroe receptor autorizada para Tournament | caller propio autorizado; PENDING/PRIZE_RECIPIENT_CONTRACT_REQUIRED hasta disponer de fuente; sin impersonar Combat |
| HU85-QA01 | A con cada dueño | Matriz integrada, instalación limpia y upgrade | SHAs finales, PostgreSQL/Mongo reales, auth y dobles explicitados |
| HU85-UAT01 | usuario/PO | Recorrido con cuentas/héroes reales | resultado del usuario acreditado; tests/capturas solos no lo sustituyen |

No se solicita permiso al antiguo responsable para asumir HU-85; la instrucción del usuario ya decide esa responsabilidad. La asignación de GitHub xocamacho se conserva hasta una acción de gobierno expresamente autorizada.

Los premios por ausencia pueden estar pendientes con motivo verificable. Eso permite revisar avance/estadísticas pero impide declarar el torneo íntegramente validado con premios. Reprogramación, ventana tardía, PixelLab y OBS/YouTube siguen en sus paquetes independientes.
