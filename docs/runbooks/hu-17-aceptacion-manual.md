# Aceptación manual de HU-17 con dos sesiones reales

Complementa la validación automatizada de protocolo de Combat
(`test/db/battle-realtime.e2e.spec.ts`: MongoDB real, servidor Nest real y dos clientes `ws`
reales). Esa suite **no** demuestra lo que ven dos navegadores reales; este procedimiento sí,
y es lo que falta para cerrar la Task #408 (Management #408) y la HU-17 (#26).

**No es una automatización de navegador.** Es un procedimiento reproducible con evidencia
documentada. Si el proyecto decide exigir E2E de navegador automatizado, este mismo guion es su
especificación.

## Condiciones previas

| Condición | Comprobación |
| --- | --- |
| Infrastructure #116, Combat #26 y Web #112 **mergeados** y desplegados en el entorno de prueba, en ese orden | Combat con `npm run migrate` ejecutado (migración `005`) |
| Combat con **una sola réplica** | El almacén de tickets y la retención de `resume` viven en memoria del proceso |
| Dos cuentas de jugador **reales y distintas** (cuenta A y cuenta B), cada una con un héroe equipado elegible para 1 contra 1 | Ver HU-07 y HU-16 |
| Dos sesiones aisladas | Chrome normal → cuenta A; ventana de incógnito **o** otro perfil → cuenta B. Nunca la misma sesión dos veces |

**No se guardan en la evidencia** contraseñas, códigos TOTP, tokens, tickets ni cabeceras
`Authorization`. Las capturas se recortan o se difuminan si los muestran.

## Procedimiento

| # | Acción | Resultado esperado | Evidencia |
| --- | --- | --- | --- |
| 1 | Cuenta A: `Jugar Online` → crear una sala **PVP 1 contra 1** | La sala aparece en el listado y en el lobby | Captura del lobby de A |
| 2 | Cuenta B: `Jugar Online` → unirse a esa sala | HU-15: entra; HU-16: se valida el héroe y, si no es elegible, se explica el motivo | Captura del lobby de B |
| 3 | Con la sala llena, observar **ambas** pantallas | Ambas pasan solas a `/play/rooms/:roomId/battle` (nadie pulsa «Empezar») | Captura de las dos pantallas |
| 4 | Comparar las dos pantallas de batalla | **Los mismos dos héroes**, la **misma cola de dos** entradas, el **mismo turno actual** y la misma ronda. En una dice «Tu turno» y en la otra «Turno de \<nombre\>» | Captura lado a lado |
| 5 | Comprobar la cola durante varios minutos | No cambia: el orden es fijo y no se vuelve a sortear | Captura antes y después |
| 6 | Sin acciones de combate todavía (HU-18/HU-19): avance del turno **desde el servidor** (ver «Avance de turno») | Ambas pantallas cambian de turno a la vez, sin recargar | Captura de ambas tras el avance |
| 7 | En una sesión, cortar la conexión (DevTools → *Network* → *Offline* unos segundos) y restaurarla | Aparece «Reconectando en tiempo real…» y, al volver, el estado es el mismo que en la otra sesión (sin doble avance ni retroceso) | Captura durante y después |
| 8 | En una sesión, recargar la página (`F5`) | La pantalla vuelve al mismo estado desde el `snapshot` | Captura tras recargar |
| 9 | (Opcional) Reiniciar Combat mientras las dos sesiones están abiertas | Ambas reconectan solas con un ticket nuevo y conservan la misma cola y el mismo turno | Captura tras reiniciar |
| 10 | Con una tercera cuenta (no participante), abrir la URL de la batalla | No ve la batalla: «No participas en esta batalla.» / sala no disponible | Captura |

## Avance de turno (paso 6)

En esta HU **no existe ninguna ruta pública** que avance el turno: lo hace el servidor y solo
lo necesitarán HU-18/HU-19 (ataque, habilidades). Para el paso 6 hay dos opciones honestas, y
la evidencia debe decir cuál se usó:

1. **Si HU-18/HU-19 ya están integradas**: jugar una acción real y comprobar el avance.
2. **Si no**: ejecutar `CompleteBattleTurn` desde el proceso de Combat con el `sub` del
   participante activo (por ejemplo desde una consola de pruebas del entorno). Esto valida la
   sincronización de las pantallas, **no** una acción de juego.

## Plantilla de evidencia (para el comentario de cierre de #408)

```text
Entorno: <URL / commit de Infrastructure, Combat y Web>
Fecha y hora:
Cuenta A / Cuenta B: <identificadores no sensibles>, sesiones aisladas: sí
Pasos 1 a 10: PASS / FAIL (con enlace a la captura de cada paso)
Opción de avance de turno usada (paso 6): 1 / 2
Observaciones y desviaciones:
```

Si algún paso falla, la Task **no** se cierra: se documenta el fallo con su captura y se
corrige en el PR que corresponda (Web #112, Combat #26 o el que lo haya sustituido).
