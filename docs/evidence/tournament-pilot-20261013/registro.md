# Torneo completo con ocho sesiones simuladas — 13 de octubre de 2026

Resultado: **PASSED**. [Datos y controles ejecutados](torneo-completo.json).
Campeón: Jeffryepsteingo. Se jugaron las 14 batallas de seis rondas, incluida una
sola final. Los ocho participantes de la primera ronda recibieron su segunda batalla:
cuatro por ganadores y cuatro por perdedores. Siete equipos terminaron su participación.

Ambas personas conectaron y enviaron ataques en cada batalla. El motor resolvió 567
ataques y todos los resultados fueron WIN/ELIMINATION. En E1, Carlos y GABO pelearon
44 acciones durante 36,748 segundos; el resultado se produjo al quedar GABO sin vida.
No se insertaron ganadores, resultados ni avances manualmente en las bases.

## Componentes y límites

Se ejecutaron el bundle de producción de Web y los módulos Nest compilados de
Tournament/Combat, PostgreSQL nativo, MongoDB nativo, WebSocket y el motor de combate.
La prueba usó cuatro salas independientes al inicio y dos clientes humanos simulados
por sala; Carlos recibió 403 al consultar una sala ajena. El navegador recorrió la
interfaz real con Carlos y entró automáticamente en su sala contra GABO.

Los JWT de ocho identidades, Account, Wallet e Inventory fueron dependencias de QA
locales. El inventario de prueba devolvió objetos con probabilidad de caída del 100 %
y mantuvo compromisos del héroe para impedir otra pelea simultánea. Todas las llamadas
internas conservaron HMAC y su ventana de seguridad de reloj de pared. Solo el reloj
de negocio saltó entre ventanas de ronda; durante las batallas siguió transcurriendo
normalmente. Esto acredita el grafo y sus ventanas, pero no una espera real de 52 minutos.

Los SHA de los tres repositorios están en el JSON. El último commit de Combat solo
añade el await del cierre del planificador en una prueba; su código productivo coincide
con el bundle compilado usado. Las bases y puertos eran locales y aislados de producción.

## Persistencia y economía

PostgreSQL archivó 14 battleStarted, 567 basicAttackResolved y 14 battleFinished;
el lifecycle contiene 14 resultados. MongoDB conserva 14 salas FINISHED con isTest.
Se adquirieron 28 compromisos de héroe y se liberaron antes de avanzar a la siguiente
ronda. Las llamadas repetidas de liberación fueron idempotentes.

Antes y después de reiniciar Combat: cero workflows de recompensa y cero workflows
de transferencia de objetos. Las dependencias de QA registraron cero llamadas
económicas y cero transferencias, con todos los compromisos liberados. La reconciliación
de inicio mantuvo esas propiedades. La prueba no realizó cobros, premios ni cambios
en cuentas de producción.

## Capturas del recorrido

1. [Mi batalla con aceptación personal](01-aceptacion.jpg).
2. [Arena con Carlos y GABO, turnos y daño](02-batalla-real.jpg).
3. [Resultado con nombres, siguiente encuentro y Volver al torneo](03-resultado-y-avance.jpg).
4. [Ganadores con todos los resultados confirmados](04-ganadores-campeon.jpg).
5. [Perdedores y campeón confirmado](05-perdedores.jpg).

La captura de ganadores está desplazada al árbol; el campeón aparece en la de
perdedores. Los IDs del JSON son identidades de prueba, conservadas para correlacionar
salas y encuentros. No contiene tokens, contraseñas, firmas ni secretos del entorno.

## Pendiente con personas reales

Esta simulación no acredita Cognito, proxy desplegado, red doméstica ni ocho navegadores
humanos simultáneos. La regla de desconexión continúa en 30 segundos desde el inicio;
no existe una barrera que espere a ambos navegadores. El piloto real debe comprobar
entrada personal, demora/reconexión y que nadie termine por desconexión inesperada.
Los PR y CI son validación técnica; no sustituyen esa comprobación del producto.
