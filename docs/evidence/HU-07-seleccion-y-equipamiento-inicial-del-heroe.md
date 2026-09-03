# HU-07 — Evidencia de selección y equipamiento inicial del héroe

- **Issue central:** [Nexus-Battle-VI/Nexus-Battle-Management#16](https://github.com/Nexus-Battle-VI/Nexus-Battle-Management/issues/16)
- **Tasks:** [#114](https://github.com/Nexus-Battle-VI/Nexus-Battle-Management/issues/114) (backend), [#115](https://github.com/Nexus-Battle-VI/Nexus-Battle-Management/issues/115) (interfaz), [#116](https://github.com/Nexus-Battle-VI/Nexus-Battle-Management/issues/116) (pruebas)
- **Fecha:** 2026-09-03
- **Pull Requests:** `Nexus-Battle-VI/Nexus-Battle-Player-Inventory#19`, `Nexus-Battle-VI/Nexus-Battle-Web#73`
- **Requisito trazado:** `RF-07`

## Estado de la verificación: qué se comprobó y qué NO

Este documento **no declara la HU aceptada**. Lo comprobado hasta aquí es la
suite automatizada y la pantalla en el navegador con datos de ejemplo. En este
proyecto eso no basta y hay precedente: cuatro fallos de HU-02 aparecieron al
usar el producto y ninguna prueba los encontró.

| Nivel | Estado |
| --- | --- |
| Pruebas unitarias y de integración | **Ejecutadas y en verde** |
| Pruebas contra MongoDB real (`test:db`) | **Pendientes de CI.** Docker Desktop no estaba arrancado en la máquina de desarrollo; la suite existe y CI la ejecuta |
| Revisión visual del diseño | **Hecha** en tema claro, tema oscuro y móvil, sobre el componente de producción |
| Uso del producto desplegado, con una persona delante | **PENDIENTE.** Requiere desplegar los dos PR y ejecutar la migración `004-hero-selections` |

## Criterios de aceptación

| Criterio | Estado | Cómo se comprobó |
| --- | --- | --- |
| CA-01 — Héroe configurado y listo, con estadísticas modificadas por el equipamiento | Cubierto | `hero-selection-http.spec.ts`: se equipa por la ruta de HU-28 y la vista de HU-07 pasa de ataque efectivo 10 a 13 |
| CA-02 — Selección sobre los prototipos definidos | Cubierto | La lista sale del catálogo cruzado con el inventario; `hero-selection-use-cases.spec.ts` comprueba los ocho |
| CA-03 — Máximo dos armas | **Reutilizado de HU-28** | `HeroLoadout` es la autoridad. HU-07 expone `capacity.weapons = {used, max: 2}` leyendo `EQUIPMENT_CAPACITY`, no revalidando |
| CA-04 — Máximo seis piezas de armadura | **Reutilizado de HU-28** | Ídem, `capacity.armor.max = 6` |
| CA-05 — Máximo dos ítems | **Reutilizado de HU-28** | Ídem, `capacity.items.max = 2` |
| CA-06 — Solo productos del inventario del jugador | Cubierto | `resolveOwnedHero` (el helper de HU-28) + `EQUIPPED_PRODUCT_NOT_OWNED` para la deriva posterior |
| CA-07 — Impedir configuraciones que excedan la capacidad | **Reutilizado de HU-28** | El agregado lo impide al escribir. HU-07 no añade una segunda comprobación |
| CA-08 — El equipamiento modifica las estadísticas | Cubierto | `configuration` es literalmente `assembleEquipmentView`; HU-07 no recalcula |
| CA-09 — El equipamiento no cambia durante el combate | **FUERA DE ALCANCE** | Ver la sección siguiente |
| CA-10 — Listo solo cuando la configuración es válida | Cubierto | `HeroReadinessPolicy` + `readiness` en la respuesta |
| CA-11 — Catálogo vigente, sin codificar los ocho como límite | Cubierto **con control** | Prueba con un noveno héroe; ver más abajo |
| CA-12 — Todos los criterios obligatorios aprobados | **Pendiente** de la aceptación del PO tras el despliegue |

## CA-09 queda fuera, y es deliberado

La TASK HU-07.4 lo dice textualmente:

> Tampoco deben convertir en prueba de HU-07 la regla de modificación durante
> combate, ya que pertenece a HU-29 y actualmente existe una inconsistencia
> documental que debe ser resuelta antes de automatizar dicho comportamiento
> como requisito definitivo.

No se ha automatizado ninguna prueba que fije ese comportamiento. Cuando HU-29
resuelva la inconsistencia, el guard de estado de batalla se antepone al
controlador de equipamiento de HU-28 —que es el **único** punto de escritura—
sin tocar HU-07.

## El control de CA-11: el noveno héroe

CA-11 exige que los ocho prototipos no se codifiquen como límite permanente.
Afirmarlo no basta; hay un control en los dos lados que **fallaría si la
afirmación fuera falsa**:

- **Backend** (`hero-selection-use-cases.spec.ts`): se añade `Druida del Bosque`
  al catálogo y al inventario, y la ruta devuelve nueve héroes. Si quedara una
  lista de ocho en algún sitio, devolvería ocho.
- **Web** (`HeroSelectionPage.test.tsx`): el mismo héroe se presenta con su
  etiqueta de rol derivada del subtipo, y el encabezado dice «(2)». Si la
  pantalla codificara los ocho, el héroe no aparecería o aparecería sin rol.

El prototipo de Figma rotula «CATÁLOGO DE HÉROES (8)». **Ese ocho no se
implementó**: el recuento se deriva de la respuesta. Se dibujó con los ocho
prototipos en el inventario, no porque ocho sea un límite.

## Aislamiento entre jugadores

Ninguna de las tres rutas acepta `ownerId` —ni en URL, ni en query, ni en
cuerpo—. El control no es «no lo usamos»: hay una prueba que **cuela `ownerId`
en el cuerpo del `PUT`** y comprueba que la petición se rechaza con 400 en lugar
de obedecerse. Sin ella, añadir el campo al DTO en el futuro pasaría
inadvertido.

## Lo que HU-07 NO reimplementa

La TASK HU-07.2 prohíbe expresamente una segunda implementación de las reglas de
HU-28. Cómo se cumple:

| Regla | Dónde vive | Qué hace HU-07 |
| --- | --- | --- |
| Pertenencia del héroe | `resolveOwnedHero` (HU-28) | Lo invoca. No lo reescribe |
| Capacidades 2/6/2 | `HeroLoadout` (HU-28) | Lee `filledCount` y `EQUIPMENT_CAPACITY` para presentarlas |
| Compatibilidad ranura/familia | `HeroLoadout` (HU-28) | No la toca |
| Estadísticas efectivas | `computeEffectiveStats` (HU-28) | Devuelve su resultado tal cual |
| Equipar / retirar | `HeroEquipmentController` (HU-28) | No expone una segunda ruta. La interfaz enlaza a `/inventory` |

Lo único propio de HU-07 es la **selección persistida** y la **disponibilidad**,
que cubre lo que HU-28 no puede garantizar: la deriva posterior a equipar.

## Divergencias respecto al prototipo de Figma, dichas enteras

Los tres diseños (`87:22`, `262:26`, `262:181`) son la **misma pantalla con otro
héroe elegido**, y así se implementó. Lo que se apartó del prototipo:

1. **El recuento del encabezado se deriva**, no es «(8)». Ver arriba.
2. **`Nivel` se muestra como `PENDIENTE`.** El contrato canónico del héroe
   publica `heroSubtype`, `basePower`, `baseHealth`, `baseDefense`, opcionalmente
   `baseAttack`/`baseDamage`/`baseHealing`, y `abilities`. **No publica nivel.**
   El prototipo escribe «1» en los tres frames; escribirlo aquí sería mostrar una
   estadística que nadie calculó. Se usa la misma palabra que el propio prototipo
   emplea para sus huecos.
3. **Las habilidades se resuelven de verdad.** El héroe publica tres referencias
   a productos `HABILIDAD`; se resuelven en Catalog en una sola llamada. Cuando
   Catalog no devuelve una, se dice `PENDIENTE` en vez de inventar un nombre.
4. **El modelo 3D solo se usa cuando existe.** Un héroe fuera de la biblioteca
   visual se presenta con la imagen del catálogo. El tinte del escenario se
   deriva del acento del héroe, no de una tabla de colores paralela.
5. **La pantalla entra en la navegación.** El prototipo no la enumera en su
   barra, pero esa barra es anterior a la que HU-02 dejó acordada. Sin acceso
   propio solo se llegaría escribiendo la URL.
6. **Colores por tokens, no por hex.** El prototipo está fijado a un tema
   oscuro; la pantalla funciona en los dos temas del producto.

**Las divergencias 1, 2 y 5 conviene que las mire el Product Owner** antes de
dar la HU por aceptada. Ninguna cambia el flujo; las tres son decisiones sobre
qué se le dice a quien juega.

## Contrato entregado

| Ruta | Respuesta |
| --- | --- |
| `GET /api/inventories/me/heroes` | Héroes que el jugador puede preparar, con estadísticas base, habilidades y cuál está preparado |
| `PUT /api/inventories/me/heroes/selection` | Prepara un héroe propio. Idempotente sobre el mismo héroe |
| `GET /api/inventories/me/heroes/selection` | Configuración: héroe, equipamiento, estadísticas base y efectivas, disponibilidad y ocupación 2/6/2 |

Códigos: `401` sin testimonio, `404` héroe no propio o sin selección, `409` héroe
suspendido o conflicto de concurrencia, `503` Catalog no responde.

## Resultado de la ejecución

| Suite | Resultado |
| --- | --- |
| Player/Inventory `npm run test:coverage` | 333 pruebas, 23 suites, en verde. 94,3 % sentencias / 83,95 % ramas |
| Player/Inventory `npm run test:db` | **No ejecutada en local** (Docker Desktop parado). 7 casos nuevos; los ejecuta CI |
| Web `npm run test:coverage` | 674 pruebas, 86 ficheros, en verde. 88,97 % sentencias / 82,23 % ramas |
| `lint`, `typecheck`, `format:check` en ambos | Limpios |

## Lo que falta para cerrar la HU

1. Revisar y fusionar los dos PR.
2. Promover `develop` a `main` en los dos repositorios y esperar a que se
   publiquen las imágenes.
3. **Ejecutar `inventory-migrate` en el nodo `app`.** `004-hero-selections` es una
   migración nueva: recrear solo el contenedor del servicio no la aplica, y sin
   ella la colección no existe. Es exactamente el fallo que produjo el 500 de
   HU-34.
4. Comprobar el digest que corre contra el publicado. Un contenedor «Up,
   healthy» no dice nada sobre qué versión ejecuta.
5. **Usar el producto con una persona delante**: elegir un héroe, equiparlo desde
   `/inventory`, volver a `/heroes` y comprobar que las estadísticas efectivas
   cambiaron y que el resumen refleja la pieza. Sin este paso la HU no está
   verificada, solo probada.
