# HU-57 — Consulta, búsqueda y filtros en la vitrina de E-commerce

| Campo | Valor |
| --- | --- |
| **Requisito** | `RF-57` |
| **Historia de usuario** | [#31](https://github.com/Nexus-Battle-VI/Nexus-Battle-Management/issues/31) — HU-57 |
| **Task de diseño** | [#217](https://github.com/Nexus-Battle-VI/Nexus-Battle-Management/issues/217) — HU-57.1 |
| **Épica** | [#5](https://github.com/Nexus-Battle-VI/Nexus-Battle-Management/issues/5) — [EPIC-05] Carro de Compras / E-commerce |
| **Team** | Gama (Catalog). Consumo desde Web (Alfa + Beta + Gama) |
| **Estado** | Diseño. **No cierra la implementación ni la HU-57.** |

Este documento es la especificación de diseño de la consulta, búsqueda y filtros de la vitrina:
caso de uso, actividad, secuencia, fragmento de dominio, contrato conceptual, decisiones
pendientes y trazabilidad con `CA-01`…`CA-12` y `CP-57-01`…`CP-57-03`.

> **Nota de honestidad documental.** Cuando este diseño se redactó, la capacidad **ya estaba
> implementada** en `develop` (Catalog y Web). Por eso cada criterio de aceptación lleva, además del
> diseño, el **estado observado** con su evidencia y las desviaciones encontradas. El diseño
> describe el comportamiento que la HU exige; no se ajusta la exigencia a lo que el código hace hoy.

---

## 1. Alcance

Un **Cliente** consulta la vitrina de E-commerce, busca productos por la información disponible
—incluido el precio— y reduce los resultados con los filtros documentados. La vitrina presenta un
banner, productos en páginas y una card por producto con nombre, imagen, descripción, habilidades y
precio; los productos en promoción muestran su porcentaje de descuento; el producto se resalta al
pasar el ratón y, al seleccionarlo, se abre su vista de detalle.

**Capacidad de dominio:** consultar el catálogo publicado con criterios de búsqueda y filtro,
paginado, sin efectos secundarios.

## 2. Frontera: lo que NO es de esta HU

| Fuera de alcance | Dueño | Frontera |
| --- | --- | --- |
| Incorporar a la lista de deseos | HU-56 (`#30`) | La vitrina puede **presentar** la acción; su comportamiento no se diseña aquí |
| Agregar al carrito | HU-58 | Igual: la acción se presenta, no se especifica |
| Pago simulado, transferencia, vaciado | HU-59 (`#33`) | No se modela pasarela ni transacción |
| Persistencia del carrito entre sesiones | HU-61 (`#35`) | No se modela carrito persistente |
| `RNF-23` | Documental | Se conserva **solo** por trazabilidad con el Product Backlog. **No** se convierte en obligación de caché para E-commerce: su definición SRS se refiere a otros módulos |

No se diseña un microservicio exclusivo para HU-57. La consulta de vitrina vive en el componente que
ya es responsable del catálogo publicado (Catalog), y la presentación en la vista de E-commerce (Web).

## 3. Caso de uso

### 3.1 Identificación

| Campo | Valor |
| --- | --- |
| **Identificador** | `CU-57 — Consultar, buscar y filtrar productos en la vitrina` |
| **Actor principal** | `Cliente` (visitante o autenticado; la consulta de vitrina es pública) |
| **Objetivo** | Explorar la oferta publicada y localizar productos que cumplan la información y los criterios de interés |
| **Precondiciones** | Existen productos **disponibles** en el catálogo (`RF-33`) — publicados y no archivados. La consulta no requiere sesión |
| **Postcondición de éxito** | Se devuelve la página solicitada con **hasta dieciséis** representaciones de producto que cumplen el término y **todos** los filtros activos |
| **Postcondición de fallo** | No se devuelve ningún producto que incumpla los criterios: o la página está vacía (ausencia de resultados) o se informa el error funcional correspondiente |

**Entrada:** página solicitada; término de búsqueda opcional; filtros opcionales (rango de precio,
tipo de producto, estado de promoción); moneda aplicable.

**Inclusiones documentadas:** `Consultar vitrina paginada`, `Buscar productos por información
disponible`, `Filtrar resultados`, `Abrir vista de detalle`.

### 3.2 Flujo principal

1. El Cliente accede a la vitrina.
2. El sistema comprueba que existen productos disponibles para E-commerce.
3. El sistema presenta el banner y la primera página, con hasta dieciséis ítems.
4. Cada card muestra nombre, imagen, descripción, habilidades y precio.
5. Si un producto está en promoción, su card incluye el marcador con el porcentaje de descuento.
6. El Cliente escribe un término de búsqueda y/o activa uno o varios filtros.
7. El sistema localiza los productos publicados que contienen el término en su información
   disponible —incluido el precio— **y** cumplen simultáneamente todos los filtros activos.
8. El sistema devuelve la página solicitada, con la moneda aplicable.
9. El Cliente pasa el ratón sobre un producto: la card se resalta.
10. El Cliente selecciona un producto: el sistema abre su vista de detalle.

### 3.3 Flujos alternativos

| # | Condición | Comportamiento |
| --- | --- | --- |
| A1 | Sin término ni filtros | Se devuelve la vitrina completa, paginada de dieciséis en dieciséis |
| A2 | Solo término de búsqueda | Se aplica únicamente la coincidencia textual |
| A3 | Solo filtros | Se aplican únicamente los filtros activos |
| A4 | Término **y** filtros | Conjunción: deben cumplirse el término y **todos** los filtros |
| A5 | Página posterior a la primera | Se respeta la paginación; el vacío de una página intermedia no reordena el resultado |
| A6 | El Cliente cambia cualquier criterio | La consulta se reejecuta desde la primera página |

### 3.4 Excepciones

| # | Situación | Resultado |
| --- | --- | --- |
| E1 | No hay coincidencias (`CA-12`) | Página vacía y representación explícita de ausencia de resultados. **Nunca** se muestran productos que incumplan |
| E2 | El catálogo no está disponible (`RF-33`) | Estado de error de la consulta; no se inventan productos ni se rellena con datos de demostración en producción |
| E3 | Página inválida (no entera, menor que 1 o fuera de rango seguro) | Error funcional de validación |
| E4 | Precio negativo o no entero, o `minPrice > maxPrice` | Error funcional de validación |
| E5 | Filtro de precio sin moneda | Error funcional: **no se convierten divisas** (ver §9) |
| E6 | Tipo de producto desconocido | Error funcional: el conjunto válido lo fija el catálogo canónico (`RF-33`) |

### 3.5 Reglas de negocio

- **RN-1.** La paginación presenta **dieciséis** ítems por página.
- **RN-2.** La card presenta nombre, imagen, descripción, habilidades y precio.
- **RN-3.** El precio se expresa en COP, dólar o euro según la **moneda aplicable** al Cliente.
- **RN-4.** Un producto en promoción muestra el **porcentaje de descuento**.
- **RN-5.** El producto se resalta al pasar el ratón (regla de **presentación**, no de dominio).
- **RN-6.** Seleccionar un producto abre su vista de detalle.
- **RN-7.** La búsqueda usa la información disponible del producto, **incluido el precio**.
- **RN-8.** La búsqueda usa mecanismos de indexación **sin** tecnología impuesta y **sin** mínimo de
  caracteres no documentado.
- **RN-9.** Filtros documentados: rango de precio, tipo de producto y estado de promoción.
- **RN-10.** Los filtros se combinan entre sí y con la búsqueda, en **conjunción**.
- **RN-11.** El resultado contiene únicamente productos que cumplen el término y los filtros.
- **RN-12.** La consulta **no** incorpora a deseos ni al carrito.

**Trazabilidad:** `RF-57` → `HU-57` (`#31`) → este diseño (`#217`).

## 4. Diagrama de actividades

Fuente editable: [`docs/diagrams/hu-57-activity.puml`](../diagrams/hu-57-activity.puml).

Recorre: recibir la solicitud → comprobar que hay productos disponibles → recibir término y/o
filtros → **decisión** ¿hay término? → localizar candidatos por información disponible (incluido
precio), sin fijar motor ni umbral de caracteres → **decisión** ¿hay filtros activos? → retener solo
los que cumplen **todos** → si coexisten búsqueda y filtros, exigir cumplimiento simultáneo →
**decisión** ¿resultado vacío? → representar ausencia de resultados **o** paginar de dieciséis →
componer la card con los campos documentados → aplicar la moneda aplicable **sin** cerrar el
mecanismo de ubicación → si está en promoción, asociar el marcador de porcentaje → devolver la
página → si el Cliente selecciona, abrir detalle → **no** ejecutar deseos ni carrito.

El resaltado al pasar el ratón (`CA-05`) es regla de presentación: se identifica para la tarea de
interfaz (`#221`) y **no** se detalla como interacción de dominio.

## 5. Diagrama de secuencia

Fuente editable: [`docs/diagrams/hu-57-sequence.puml`](../diagrams/hu-57-sequence.puml).

Participantes conceptuales: `Cliente`, `Vitrina` (vista de E-commerce), `Servicio de consulta de
catálogo en vitrina`, `Catálogo de productos` (dependencia `RF-33`) y `Regla de criterios de
búsqueda y filtro`.

Escenarios representados con fragmentos `alt`: consulta sin criterios; búsqueda con coincidencia;
búsqueda o filtro **sin** coincidencias; filtros combinados; apertura de detalle; y catálogo no
disponible. No se modelan pasarela, inventario, deseos ni carrito.

## 6. Fragmento del modelo de dominio

Fuente editable: [`docs/diagrams/hu-57-domain.puml`](../diagrams/hu-57-domain.puml).

| Concepto | Responsabilidad | Atributos (solo los de HU-57 / `RF-57`) |
| --- | --- | --- |
| `Producto` | Concepto de catálogo **consumido**, no rediseñado aquí | nombre, imagen, descripción, habilidades, tipo, precio, estado de promoción, porcentaje de descuento |
| `PaginaVitrina` | Una página de resultados y su posición | número de página, tamaño (16), ítems, total |
| `CriterioConsulta` | Conjunción de término y filtros activos | término de búsqueda; filtros activos |
| `FiltroRangoPrecio` | Acota por precio publicado | importe mínimo, importe máximo, moneda |
| `FiltroTipoProducto` | Acota por tipo | tipo |
| `FiltroEstadoPromocion` | Acota por estado de promoción | estado |
| `Precio` | Importe y su moneda | importe, moneda |
| `MonedaAplicable` | Moneda con la que se presenta el precio | código de moneda |
| `MarcadorPromocion` | Marca visual del descuento | porcentaje |

**Restricciones modeladas:** dieciséis ítems por página; conjunción de término y filtros; nunca se
devuelven productos que incumplan; el vacío es un resultado válido y representable.

**Prohibiciones explícitas:** no se crean entidades `ListaDeDeseos`, `Carrito`, `Transaccion` ni
`Correo`; no se inventa una entidad de caché por `RNF-23`; no se persisten páginas ni rankings
derivados si pueden obtenerse al consultar el catálogo.

## 7. Modelo de datos: qué NO se persiste

- **No** se persiste la página de vitrina ni el resultado de una búsqueda: es **derivado** de la
  consulta al catálogo y quedaría obsoleto en cuanto cambie un producto.
- **No** se persiste un ranking ni un índice propio de la vitrina como fuente de verdad: el catálogo
  publicado sigue siendo la única fuente.
- **No** se persiste nada de deseos, carrito, pago ni correo: pertenece a otras HU.
- **Sí** vive en el catálogo lo que ya es del catálogo: el producto publicado y los datos que la
  búsqueda necesita. La proyección de búsqueda es una **materialización derivada del propio
  catálogo** (se reconstruye desde el producto), no un agregado de esta HU.

## 8. Contrato conceptual de la operación de consulta

Detalle completo: [`docs/contracts/hu-57-storefront-query-v1.md`](../contracts/hu-57-storefront-query-v1.md).

**Propósito.** Devolver una página de productos publicados que cumplen un término de búsqueda y
todos los filtros activos.

**Entrada conceptual:** página; término de búsqueda opcional; filtros opcionales (rango de precio,
tipo, estado de promoción); moneda aplicable (**sin** fijar su origen).

**Salida conceptual:** página de hasta dieciséis representaciones de producto, con la posición y el
total; o ausencia de resultados explícita.

**Validaciones y errores funcionales:** página entera positiva; importes enteros no negativos en
unidades menores de una moneda; `minPrice ≤ maxPrice`; moneda obligatoria al filtrar por precio;
tipo dentro del conjunto vigente del catálogo.

**No** se fijan firmas de implementación, nombres de clase, DTOs de lenguaje, códigos de estado HTTP
ni nombres de colección. **No** se incluye agregar a deseos, mutar carrito ni resolver el detalle más
allá de «abrir la vista de detalle del producto seleccionado».

## 9. Impacto arquitectónico

- **Responsabilidad.** La consulta de vitrina pertenece al componente que ya sirve el catálogo
  publicado (Catalog, team Gama). La vista de vitrina pertenece a Web. **No** se crea un
  microservicio nuevo.
- **Dependencia.** `RF-33 — Creación de producto en el catálogo`: sin productos publicados no hay
  vitrina. Es una dependencia de datos, no de despliegue.
- **Consumidores previstos.** La UI de vitrina (HU-57). Puntos de extensión hacia HU-56 (deseos) y
  HU-58 (carrito) **sin** absorber su comportamiento.
- **`RNF-23`.** No impone caché en este módulo.
- **Separación.** Nada de carrito, pago, correo ni inventario entra en este límite.
- **ADD/SAD.** Este documento es la constancia de impacto conceptual; no se introduce un
  microservicio ni se altera el mapa de despliegues.

## 10. Decisiones funcionales pendientes (no inventadas)

Estas decisiones **no** las cierra el diseño ni la implementación. Quedan registradas para que no se
descubran por accidente:

| # | Decisión pendiente | Estado hoy | Quién decide |
| --- | --- | --- | --- |
| D-1 | **Ubicación geográfica → moneda aplicable** (`CA-03`). El issue exige COP/dólar/euro «conforme a la ubicación geográfica aplicable» y no define cómo se obtiene esa ubicación (perfil, detección, preferencia, parámetro) | Account ya admite `countryCode` ISO alpha-2 editable y **no** atribuye país por IP ni idioma. Falta acordar **conversión y fuente de tasas**, o **precios separados por moneda**. Hoy **no se convierten divisas** | Product Owner + arquitectura |
| D-2 | **Valores de «tipo de producto»** (`CA-09`) | Dependen del catálogo (`RF-33`). El conjunto vigente lo fija el catálogo canónico; este diseño **no** inventa tipos | Product Owner / Catalog |
| D-3 | **Valores de «estado de promoción»** (`CA-10`) | El caso oficial solo usa «en promoción». **No** se inventan estados adicionales | Product Owner |
| D-4 | **Regla comercial de promoción** (`CA-04`): porcentaje de descuento, vigencia y precio anterior | **No existe dato**. Se necesitan regla comercial y datos en Catalog antes de cerrar HU-57. **No se inventan porcentajes** | Product Owner + Catalog |
| D-5 | **Tecnología de indexación y mínimo de caracteres** | El issue **prohíbe** imponer tecnología concreta y **prohíbe** un mínimo no documentado. El diseño reconoce la necesidad de indexación y no la cierra | Arquitectura |
| D-6 | **Contenido de la vista de detalle** | HU-57 exige **dirigir** al detalle; no define campos extra respecto de la card, y no se replica el módulo de administración | Product Owner |
| D-7 | **Esquema físico del catálogo** | Dependencia `RF-33` sin issue inequívoco en esta HU. Se consume la definición aprobada; no se inventa el modelo de persistencia | Catalog |

## 11. Trazabilidad y estado observado

Estados: **Cumplido**, **Parcial**, **No cumplido**, **Pendiente de decisión**.

| CA | Qué exige | Estado observado en `develop` | Evidencia |
| --- | --- | --- | --- |
| `CA-01` | Vista responsive con banner y páginas de **hasta dieciséis** | ⚠️ **Parcial**: la vitrina pagina de **12 en 12** y adapta páginas de 16 del contrato de Catalog | `Nexus-Battle-Web/src/features/commerce/showcase/api.ts` → `SHOWCASE_PAGE_SIZE = 12`, `CATALOG_PAGE_SIZE = 16` |
| `CA-02` | Nombre, imagen, descripción, habilidades y precio en la card | ✅ Cumplido | `ShowcaseProduct` (name, imageUrl, description, attributes.values, creditsPrice / realMoneyPrice) |
| `CA-03` | Moneda según ubicación geográfica | ⛔ **Pendiente de decisión** (D-1): hoy la moneda es un **filtro explícito** y obligatoria al filtrar por precio; no hay conversión | `Nexus-Battle-Catalog/src/application/use-cases/ListCatalogStorefront.ts` |
| `CA-04` | Marcador con **porcentaje de descuento** | ⛔ **No cumplido**: no existe el dato. Catalog expone `premium: boolean`, no porcentaje ni precio anterior | `canonical-products.dto.ts`; ver D-4 |
| `CA-05` | Resaltado al pasar el ratón y apertura del detalle | ✅ Cumplido (presentación) | `ShowcaseGrid.tsx` (`hover:border-brand`, `onClick` de detalle) |
| `CA-06` | Búsqueda general por la información del producto | ✅ Cumplido | `Nexus-Battle-Catalog/src/domain/services/storefront-search.ts` |
| `CA-07` | Búsqueda por **precio publicado** | ✅ Cumplido: el texto indexado incluye `creditsPrice` y `realMoneyPrice` | idem |
| `CA-08` | Filtro por rango de precio | ✅ Cumplido | `storefront-search-projection.ts` (`$gte` / `$lte` sobre `realMoneyPrice`) |
| `CA-09` | Filtro por tipo de producto | ✅ Cumplido con el conjunto vigente | `catalog-storefront.dto.ts`; ver D-2 |
| `CA-10` | Filtro por **estado de promoción** | ⛔ **No cumplido**: no existe parámetro ni filtro de promoción | no aparece en el comando de consulta ni en la barra de filtros; ver D-3 |
| `CA-11` | Conjunción de término y **todos** los filtros | ✅ Cumplido: se construye **un solo** filtro con tipo, moneda, rango y la expresión de búsqueda | `storefrontMongoQuery` (`$expr` + `$indexOfCP` en el mismo filtro) |
| `CA-12` | Sin coincidencias: no mostrar incumplidores y representar el vacío | ✅ Cumplido | `Showcase` + `QueryState` con mensaje de ausencia |

| CP | Escenario | Trazabilidad real |
| --- | --- | --- |
| `CP-57-01` | Búsqueda por información **y** por precio | `CA-06` + `CA-07` (el issue los cita como `CA-01`/`CA-02`: los números del issue están desalineados, se mapea el **comportamiento**) |
| `CP-57-02` | Filtros combinados (rango + tipo + estado «en promoción») | `CA-08` + `CA-09` + `CA-10` + `CA-11`. **El estado de promoción no es filtrable hoy** (D-3/D-4) |
| `CP-57-03` | Presentación y paginación con diecisiete productos | `CA-01` + `CA-04` + `CA-05`. **Hoy son 12 ítems por página** y el marcador de porcentaje no tiene dato |

## 12. Escenarios dejados identificados para pruebas posteriores (`#223`)

No se automatizan aquí. Se dejan nombrados para la task de pruebas. El **registro de verificación**
de la implementación existente —qué pruebas lo cubren ya, con qué resultado y qué queda bloqueado—
está en [`docs/evidence/HU-57-verificacion-implementacion.md`](../evidence/HU-57-verificacion-implementacion.md).

1. Primera página con los ítems que exige `CA-01` y el resto paginado (`CP-57-03`).
2. Card con los cinco campos documentados (`CA-02`).
3. Producto en promoción con su porcentaje (`CA-04`) — **bloqueado por D-4**.
4. Búsqueda por información textual (`CP-57-01`).
5. Búsqueda por precio publicado (`CP-57-01`).
6. Tres filtros combinados (`CP-57-02`) — el de promoción **bloqueado por D-3/D-4**.
7. Búsqueda + filtros en conjunción (`CA-11`).
8. Consulta sin coincidencias (`CA-12`).
9. Apertura del detalle (`CA-05`).
10. Frontera: deseos y carrito **no** son criterios de esta HU.

## 13. Riesgos y criterios del diseño

| Riesgo | Cómo lo evita este diseño |
| --- | --- |
| Inventar motor de búsqueda, mínimo de caracteres o caché | D-5 y §2: se reconoce la indexación y **no** se impone tecnología ni umbral |
| Fijar geolocalización o catálogo de tipos no aprobados | D-1 y D-2: se modela «moneda aplicable» y «tipo vigente», no el mecanismo ni la lista |
| Absorber deseos o carrito en el modelo de vitrina | §2 y §6: declarados fuera de alcance y prohibidos como entidades |
| Persistir páginas o rankings derivados | §7 |
| Crear un microservicio exclusivo para HU-57 | §9 |
| Copiar los números de `CA` del issue a los `CP` sin mapear | §11: se mapea el **comportamiento** real, no el número |
| Tratar el hover o los tokens visuales como regla de dominio | §4: es presentación, y pertenece a `#221` |
| Dar por cerrada la HU porque el código existe | §11: se declaran `CA-01` parcial, `CA-04` y `CA-10` no cumplidos, y `CA-03` pendiente de decisión |
