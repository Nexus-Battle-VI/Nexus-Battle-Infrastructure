# Aceptación manual de HU-18 con dos sesiones reales

Complementa la validación automatizada de **protocolo** y **contrato**:

- Combat, `test/db/basic-attack.e2e.spec.ts`: MongoDB real (Testcontainers), servidor Nest real y
  **dos clientes `ws` reales**, con la secuencia aleatoria (HU-24) guionizada para que cada caso
  sea reproducible.
- Web, `combatWire.test.tsx`: la pantalla de batalla (guardas, reductor por `seq` y presentación)
  consume **bytes reales** capturados de esa suite de Combat, no fixtures escritas a mano.

Esas pruebas **no** demuestran lo que ven **dos navegadores reales**; este procedimiento sí, y es lo
que falta para cerrar la Task #412 (Management #412) y la HU-18 (#62). Contrato:
[`hu-18-basic-attack-v1.md`](https://github.com/Nexus-Battle-VI/Nexus-Battle-Infrastructure/blob/develop/docs/contracts/hu-18-basic-attack-v1.md).

**No es una automatización de navegador** (el proyecto no incluye Playwright ni Cypress y esta Task
no lo instala). Es un procedimiento reproducible con evidencia documentada. Si el proyecto decide
exigir E2E de navegador automatizado, este mismo guion es su especificación.

## Condiciones previas

| Condición | Comprobación |
| --- | --- |
| Infrastructure #119, Combat #29 y el PR de Web de HU-18 **mergeados** y desplegados en el entorno de prueba, **en ese orden** | Combat con `npm run migrate` ejecutado **antes** de arrancar (migración `007`) |
| Combat con **una sola réplica** | La serialización por sala, el almacén de tickets y la retención de `resume` viven en memoria del proceso (ADR-020) |
| Dos cuentas de jugador **reales y distintas** (cuenta A y cuenta B), cada una con un héroe equipado elegible para 1 contra 1 **que pueda atacar** | Un héroe ofensivo con Ataque y Daño (no Chamán ni Médico: el documento oficial no les da Ataque ni Daño y Combat rechaza su ataque básico). Ver HU-07 y HU-16 |
| Dos sesiones aisladas | Chrome normal → cuenta A; ventana de incógnito **o** otro perfil → cuenta B. Nunca la misma sesión dos veces |
| Una batalla **nueva** iniciada con Combat ya desplegado | Una batalla iniciada antes de HU-18 **no tiene Vida** y no admite ataque: Web lo dice en pantalla, pero no sirve para este procedimiento |

**No se guardan en la evidencia** contraseñas, códigos TOTP, tokens, tickets ni cabeceras
`Authorization`. Las capturas se recortan o se difuminan si los muestran.

## Procedimiento

| # | Acción | Resultado esperado | Criterio | Evidencia |
| --- | --- | --- | --- | --- |
| 1 | Cuenta A crea una sala **PVP 1 contra 1**; cuenta B se une (como en el paso 1 y 2 de [HU-17](hu-17-aceptacion-manual.md)) | Con la sala llena, ambas pantallas pasan solas a `/play/rooms/:roomId/battle` | HU-17 | Captura de las dos pantallas |
| 2 | Comparar las dos pantallas de batalla | Cada tarjeta muestra la **Vida** como texto `actual / máxima` y una barra; ambos jugadores ven **los mismos dos héroes**, la misma cola y el mismo turno | CA-01 | Captura lado a lado |
| 3 | En la pantalla de **quien NO tiene el turno** | **No** hay botón «Ataque básico»; se lee «Podrás atacar cuando sea tu turno.» | CA-01, RF-18 | Captura |
| 4 | En la pantalla de **quien tiene el turno** | Aparece «Ataque básico» **habilitado**, con el único rival ya elegido como objetivo y su Vida. **No hay ninguna referencia al Poder**: el botón está disponible sin importar el Poder del héroe | CA-02, CA-03, CA-04 | Captura |
| 5 | Pulsar **una vez** «Ataque básico» y observar **las dos** pantallas | El botón pasa a «Atacando…» y en ambas pantallas aparece **el mismo** texto de resultado (efecto o «sin efecto», con el Ataque y la Defensa comparados). La Vida del objetivo queda **igual en las dos pantallas**; si el golpe tuvo efecto, bajó | CA-01, CA-05, CA-06 | Captura de las dos, antes y después |
| 6 | Comprobar el turno tras el ataque | El turno **pasó al rival en ambas pantallas** y el botón aparece en la pantalla del rival | CA-07 | Captura de las dos |
| 7 | Con DevTools → *Network* → *WS* del jugador que atacó, revisar los *frames* | El comando enviado tiene **exactamente** `type`, `commandId`, `roomId` y `target` (`teamLabel`, `seat`): ni Ataque, ni daño, ni Vida. El evento recibido no contiene semilla, índices, estadísticas ni `activeEffects` | Seguridad | Captura de los *frames* (sin el ticket) |
| 8 | **Doble clic rápido** en «Ataque básico» en el turno siguiente | Se envía **un solo** `attack` (un solo *frame*) y la Vida del objetivo cambia **una sola vez** | Idempotencia | Captura de los *frames* y de la Vida |
| 9 | Repetir ataques alternando los jugadores (unos pocos: cada héroe tiene decenas de puntos de Vida) hasta ver **al menos un «sin efecto»** y **al menos un golpe con efecto** | Con «sin efecto», la Vida **no** cambia y el turno **sí** avanza. El resultado es aleatorio (HU-24): no se puede forzar; se anotan todos los golpes observados | CA-05, CA-06, CA-07 | Tabla de golpes observados |
| 10 | Un jugador corta la conexión (DevTools → *Network* → *Offline*) **mientras el rival ataca**, y la restaura | Aparece «Reconectando en tiempo real…» y, al volver, la **Vida y el turno coinciden** con la otra sesión (sin doble golpe ni retroceso) | Reconexión | Captura durante y después |
| 11 | Un jugador con el turno pulsa «Ataque básico» y **de inmediato** corta la conexión (*Offline*), luego la restaura | «No se pudo confirmar tu ataque…». Al volver, **o** llega el resultado guardado y el aviso desaparece, **o** «Reintentar ataque» devuelve **el mismo** resultado. En ambos casos la Vida del objetivo bajó **una sola vez** y **no** se envió nada solo | Idempotencia, sin reenvío automático | Captura y comparación de la Vida |
| 12 | Recargar la página (`F5`) en una sesión | Vuelven la **Vida y el turno vigentes** desde el `snapshot`. **No** se muestra el detalle del último golpe: el `snapshot` no trae acciones (comportamiento esperado, no un fallo) | Recarga | Captura tras recargar |
| 13 | (Opcional) Reiniciar Combat con las dos sesiones abiertas | Ambas reconectan solas con un ticket nuevo y conservan la Vida y el turno | Persistencia | Captura tras reiniciar |
| 14 | Con una tercera cuenta (no participante), abrir la URL de la batalla | No ve la batalla: «No participas en esta batalla.» | HU-17 | Captura |
| 15 | Revisar la accesibilidad básica de la pantalla de batalla | Teclado: el objetivo y el botón se alcanzan con `Tab`; el resultado se anuncia (región viva); 320 px sin desbordamiento; con «reducir movimiento» del sistema la barra no se anima | Accesibilidad | Captura a 320 px |

## Qué NO se valida aquí (y por qué)

- **Que un ataque se haga fuera de turno o con un objetivo inválido**: la interfaz no ofrece esas
  acciones, así que un navegador real no las produce. Combat las rechaza y lo demuestran sus
  pruebas de protocolo (`NOT_YOUR_TURN`, `INVALID_TARGET`, `SAME_TEAM_TARGET`,
  `TARGET_UNAVAILABLE`, sin sorteos ni cambios de estado).
- **El fin de la batalla**: una Vida en 0 no finaliza la batalla ni declara ganador (HU-21). **No
  lleves el procedimiento hasta la Vida 0**: la batalla quedaría sin más acciones válidas del caído.
- **El Poder**: Combat todavía no modela un Poder de batalla y el ataque básico no lo lee ni lo
  escribe. CA-03 y CA-04 se cumplen **por construcción** (no hay puerta de Poder), y el paso 4 lo
  comprueba desde la interfaz: el botón está disponible sin ninguna condición de Poder.
- **Participantes `AI` (JcE)**: sin perfil de combate autoritativo, Combat rechaza su ataque; la
  validación es **JcJ 1 contra 1 con dos humanos**.

## Plantilla de evidencia (para el comentario de cierre de #412)

```text
Entorno: <URL / commit de Infrastructure, Combat y Web>
Fecha y hora:
Cuenta A / Cuenta B: <identificadores no sensibles>, sesiones aisladas: sí
Pasos 1 a 15: PASS / FAIL (con enlace a la captura de cada paso)
Golpes observados en el paso 9: <n golpes: efecto, porcentaje, Vida antes → después>
Observaciones y desviaciones:
```

Si algún paso falla, la Task **no** se cierra: se documenta el fallo con su captura y se corrige en
el PR que corresponda (Web, Combat #29 o el que lo haya sustituido). La HU-18 **no** se cierra hasta
que CA-01 a CA-08 tengan evidencia; el cierre de la HU lo hace quien tenga autoridad sobre ella, con
la matriz consolidada, y nunca un `Closes` en un PR.
