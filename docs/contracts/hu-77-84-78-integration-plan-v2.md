# Integración local de HU-77, HU-84 y HU-78 con HU-83

Versión común: `torneos-hu77-84-78-hu83-v2.0.0`.
Fecha de corte: 2026-10-05, America/Bogota. Autorización: preparación, contratos, commits e integración **locales**. Publicación y aceptación no están autorizadas por este trabajo.

## Problema, resultado y comprobación

Las copias originales contienen avance útil, pero partieron de bases anteriores a los cambios publicados. Una copia completa de `app.module.ts`, `database.ts`, `schema.ts` o `routes.tsx` elimina dependencias recientes; las migraciones y los GET de justas tienen colisiones concretas. El resultado esperado es un incremento implementable por cuatro responsables con una sola versión de contrato, sin perder el archivo de HU-83 ni trabajo ajeno.

Coordinación comprueba preservación, bases y ramas, reglas de contrato, grafo y compatibilidad propuesta. QA debe comprobar el código combinado y el recorrido real. El propio autor de los contratos no otorga aceptación de producto.

El acuerdo operativo está en `P2/Entregables/Coordinacion-Torneos-2026-10-05/acuerdo-integracion.json`. Contiene rutas **absolutas**, commits base, hashes de estos contratos, decisiones y estados pendientes. Es la autoridad para asignar checkout y rama; las rutas originales se conservan solo como fuentes del traslado selectivo.

## Bases verificadas

| Rol / repositorio | Rama propia | Base `develop` verificada |
| --- | --- | --- |
| Coordinación / Infrastructure | `codex/torneos-20261005/coordinacion` | `0adb5214e0902ac4bc99c67155f580fb7fb1e2fe` |
| Account | `codex/torneos-20261005/account` | `edbc67ff915d97d06b34273ddf05982c9ed7e669` |
| Wallet | `codex/torneos-20261005/wallet` | `cdf5a5d3328e3c21822f93a862e690727bd0e85e` |
| Tournament | `codex/torneos-20261005/tournament` | `21951787de52c47ba29891ada412ff187162f0b5` |
| Web | `codex/torneos-20261005/web` | `d83b35dd79ef9d3d47501f99caaa4f2418c1eb1b` |

Los cinco checkouts están bajo `P2/tmp/torneos-integracion-2026-10-05/<repositorio>`. Las bases reflejan la verificación de preparación, no una garantía de que `develop` no cambie más tarde. Se revalida antes de combinar o proponer publicación.

Coordinación conserva los originales, 172 archivos modificados/nuevos no ignorados, parches binarios de índice/árbol e historia completa de cada HEAD en `evidencia-coordinacion/preservacion`. Hay manifiestos y hashes. Los archivos ignorados permanecen en sus copias originales; no se trasladan `.env`, dependencias, bases o credenciales. El respaldo no es solo un `git diff`.

Infrastructure tiene cinco commits exclusivos anteriores a su `develop`; se conservan en el bundle y en la rama original. No se trasladan automáticamente al contrato nuevo ni se fusiona la antigua rama de infraestructura completa.

## Propiedad y trabajo habilitable

Solo Coordinación modifica el acuerdo común y `Infrastructure/docs/contracts`. Cada rol modifica su checkout y su propio `estado-<rol>.json`; nunca el estado de otro. Un cambio incompatible se propone en ese estado antes de implementarlo. No se envían mensajes a otros chats a partir de estos archivos.

| Responsable | Traslado e implementación local | Riesgo que debe resolver |
| --- | --- | --- |
| Account | Elegibilidad mínima, HMAC por ruta, pruebas y documentación de su servicio | Conservar `z20261003-hu90-sanction-reason-code`; no copiar la composición antigua; separar sujeto Cognito de ID interno |
| Wallet | Cobro/devolución en créditos, repositorios, errores y pruebas; migración `008` | Conservar migración `007`, devolución parcial de subastas y saldos con medios créditos; no reemplazar `InMemoryWalletStore`/schema/database con la copia anterior |
| Tournament | Registro, pago simulado local, cupos, reconciliación, bracket y fuente real compatible con HU-83 | Conservar controlador, dominio y migración publicados; unir providers/ports a la composición actual; una sola API de justas |
| Web | Recorridos HU-77/84/78 y consumo compatible de HU-83 | Conservar los 15 commits recientes, router/remaster/Cognito; resolver avisos desactualizados; no pegar el router antiguo ni atribuir aceptación a fixtures |

HU-79/81/82/80/85/86, observación, premios y enlaces no están asignados a este incremento. Sus archivos originales se respaldaron, pero no se trasladan por inercia. HU-83 se adapta solo en lo necesario para consumir las identidades y metadatos del bracket real; preparar/iniciar o avanzar se coordina con su propietario. El contrato describe la frontera con Combat, sin implementar esos servicios desde Coordinación.

## Orden de migraciones y conservación

| Servicio | Migración | Acción |
| --- | --- | --- |
| Tournament | `001-tournament-encounters` | Conservar el nombre, registro Kysely y contenido exacto de `2195178`; crea las tablas de archivo de HU-83 |
| Tournament | `002-tournament-registration` | Crear tablas nuevas de torneos, equipos, pertenencias activas, operaciones/intenciones de pago y recibos; proteger calendario y cupos |
| Tournament | `003-tournament-bracket` | Extender los torneos con snapshot inmutable; validar ocho confirmados y materializar las 14 filas en las tablas existentes de HU-83 |
| Wallet | `001`–`007` publicados | Conservar nombres, contenido y orden; `007-wallet-auction-publication-fee-partial-refund` ya está en `develop` |
| Wallet | `008-wallet-tournament-entry-fees` | Agregar persistencia de tarifas/cobros/reembolsos sin recrear tablas de saldo/ledger |
| Account | Todas las migraciones publicadas | Conservar; la consulta de elegibilidad no necesita una migración nueva |

Tournament `002` puede reutilizar los nombres nuevos locales `tournaments`, `registration_teams`, `registration_members` y `registration_operations`. Añade la política de métodos/importes, operaciones administrativas idempotentes, intenciones y recibos necesarios para v2. Son tablas nuevas después de HU-83; no son un segundo esquema de `tournament_encounters`. Se mantienen restricciones transaccionales de pertenencias, cupos y calendario; no se confía solo en JSON o en el navegador.

Tournament `003` valida seeds/cupos/miembros, impide INSERT de un bracket ya publicado y reescrituras del snapshot. Materializa filas con la clave HU-83 en la misma transacción que publica. No aplica FK retroactiva que invalide justas históricas de HU-83 sin fila nueva en `tournaments`. Un choque de identidad se rechaza; no se pisa una justa archivada para hacer pasar el test.

La antigua `001-registration` no puede ordenarse antes de la `001` publicada ni conservar ese nombre en el proveedor integrado. La antigua `002-bracket` se adapta como `003`. La antigua `003-encounters` **no se integra**: intenta recrear tablas con `data jsonb`, `match_id` y otro modelo. Cualquier evolución posterior de preparación/archivo requiere una migración aditiva posterior coordinada con HU-83, nunca cambiar o recrear `001`.

El SHA-256 capturado del archivo publicado `001-tournament-encounters.ts` es `2ca854efa1393c48e583045aeaad1dcc6b4d7fe19d43a45b74765a9a7090d7ae`; también se compara su blob Git con el commit base para no confundir contenido con finales de línea.

Los bancos locales con migraciones antiguas `001-registration`/`003-encounters` no representan una actualización desde HU-83. Se mantienen intactos. No se borran entradas de `kysely_migration` ni tablas para ocultar el conflicto. QA crea bases aisladas: una limpia y otra con la migración publicada y datos históricos; documenta un procedimiento independiente si luego se decide importar datos de esos bancos de desarrollo.

## Integración de entregas y resolución de conflictos

1. Congelar esta versión técnica y sus hashes en el acuerdo. Cada responsable registra que la consume; ese acuse no equivale a aceptación funcional.
2. Account y Wallet entregan commits locales acotados y evidencias; Tournament consume sus APIs y conserva los cambios recientes de sus respectivos `develop`. Web desarrolla contra esta versión y después prueba los servicios combinados.
3. Coordinación recibe estados con ruta, rama, base, versión, commits y pruebas ejecutadas. Comprueba ancestralidad del `develop` asignado, alcance de archivos y ausencia de secretos. Sin commit/estado no se declara integrada una entrega.
4. Crear checkouts/ramas **de integración** separados por repositorio desde la base actual revalidada. Integrar únicamente los commits declarados mediante cherry-pick, conservando los checkouts de cada propietario. Registrar base, commits seleccionados y HEAD resultante por repositorio.
5. Si hay conflicto de contrato o comportamiento, devolverlo al propietario mediante `estado-coordinacion.json`/acuerdo y su registro pendiente. Coordinación no duplica la implementación. Una resolución rutinaria de composición que esté dentro de su autorización queda registrada con archivo, motivo, base y commits involucrados; no se acepta un conflicto funcional en silencio.
6. Actualizar `versionesCombinadas` en el acuerdo con los cinco HEAD exactos y pruebas del incremento combinado. QA prueba esas versiones; no los checkouts originales ni simplemente el HEAD de `develop`.
7. Recibir la evidencia de QA y revisión funcional. Emitir el veredicto de publicación con evidencia y límites. Todo push, PR, merge remoto, cierre o despliegue necesita autorización posterior del usuario.

No hay estados o entregas de otros roles en el corte inicial de esta coordinación. Las ramas de integración, versiones combinadas, pruebas integradas, aceptación funcional y veredicto favorable siguen pendientes. No se rellena su estado por ellos.

## Diferencias de fuentes y decisiones pendientes

| Evidencia | Diferencia | Tratamiento |
| --- | --- | --- |
| HU-78 vigente vs documento Sprint 3 §4/§5/§7 y ADR-022 | Ocho humanos sin IA frente a relleno IA/dependencia JcE | Rige #469; se registra la contradicción. No se modifica retrospectivamente el ADR Accepted desde este rol |
| HU-84 vigente vs contrato local v1 | Pago simulado requerido/configurable frente a «no se ofrece» | v2 define el método simulado; no se acepta HU-84 solo con créditos |
| Sprint 3: «Account no requiere cambio» | La consulta mínima de elegibilidad usada localmente aún no está publicada | Account es una dependencia de implementación explícita |
| Sprint 3: HU-59 abierta | Commerce `develop` tiene `SimulatedPaymentGateway` | Reutilizar política/formato, sin llamar al carrito; persistencia/idempotencia propias de Tournament |
| HU-83/puerto antiguo: Combat pendiente | Combat `d0a9cc4` ya expone creación/inicio/lectura | Adaptar el DTO real; no copiar el doble plano ni prometer integración por existir rutas |
| GET `/matches` | Array/`teams`/`IN_PROGRESS` publicado frente a objeto/`roster`/`IN_BATTLE` local | Conservar forma/enum publicados y añadir metadatos opcionales compatibles |
| `READY` | Héroes resueltos en HU-83 frente a solo equipos en bracket local | `TEAMS_RESOLVED` en bracket; HU-83 espera preparación hasta héroes reales |
| Wallet `007` | Ya ocupada por devolución parcial publicada | Inscripción se reserva como `008`; conservar comportamiento de medios créditos |
| HU-01/política de identidad vs prototipo | Nombres Account 3–32 y avatar de imagen vs 1–32 y emblemas | Decisión y alcance de identidad constan separados en el acuerdo; no atribuir a los emblemas cumplimiento HU-01 |

Pendientes reales: revisión entre responsables de tabla/contratos y del uso de la política de identidad de Account; importe y moneda concretos de cada torneo antes de operarlo; elección/preparación efectiva de héroes en HU-85; cancelación/devolución de inscripciones confirmadas fuera de este incremento; entrega, QA y aceptación funcional. No se inventan tarifas, monedas, héroes, salas, métricas, aprobaciones ni resultados.

## Evidencia de QA necesaria

- Registro válido, uno/tres/repetidos/inexistentes, identidad inválida, consentimiento ajeno, cancelación y replay del recibo de registro sin afirmar pago.
- Gratis sin Wallet/pasarela; créditos 100 con saldos de prueba 120/99; saldo reservado; pago simulado aprobado/rechazado; precios/métodos desde servidor, moneda/unidades explícitas y `realMoneyMoved:false`.
- Último cupo concurrente, consentimiento/registro concurrentes, cierre exacto, caída después del débito y después del reembolso, reconciliación/reinicio y replays sin duplicación. Los dos métodos compiten por las mismas ocho plazas.
- Ocho humanos y 14 nodos; cinco/siete y pendientes sin publicación ni IA; calendario en ambos sentidos, 90 días, 91 menos 1 ms, 91 exactos y creación concurrente en PostgreSQL.
- Actualización desde `001`: identidad, roster, resultados y eventos históricos conservados; orden Kysely y segundo arranque sin repetir migraciones. Ningún reset de tablas para conseguir una prueba verde.
- HU-83 publicado compatible, equipos reales sin héroes ficticios, paginación de más de 100 eventos, simultaneidad y archivo independiente de streaming. Las pruebas con Combat real se distinguen de dobles.
- Web con dos sesiones Cognito reales y administrador; aceptación/rechazo/cancelación, avisos actualizados, importe visible y recibos diferenciados, permisos y regreso tras reinicio. Suite de servicio y navegador controlado no prueban esta autenticación real.

Las suites históricas de la auditoría verifican las copias anteriores a esta combinación. Se conservan como antecedentes; no se reportan como pruebas del incremento integrado. Compilación, pruebas de contrato, integración de servicios y aceptación de usuario se reportan por separado.
