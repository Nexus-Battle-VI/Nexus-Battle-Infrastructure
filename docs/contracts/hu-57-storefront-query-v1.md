# Contrato conceptual — Consulta de vitrina de E-commerce (HU-57)

| Campo | Valor |
| --- | --- |
| **Requisito** | `RF-57` |
| **Historia** | [#31](https://github.com/Nexus-Battle-VI/Nexus-Battle-Management/issues/31) — HU-57 |
| **Task de diseño** | [#217](https://github.com/Nexus-Battle-VI/Nexus-Battle-Management/issues/217) — HU-57.1 |
| **Diseño asociado** | [`docs/architecture/hu-57-busqueda-filtros-vitrina.md`](../architecture/hu-57-busqueda-filtros-vitrina.md) |
| **Estado** | Contrato **conceptual**. No fija firmas de implementación, ni HTTP, ni nombres de colección |

Este contrato describe **qué** debe poder pedirse y **qué** debe devolverse para consultar la vitrina.
Deliberadamente **no** prescribe tecnología de búsqueda, no fija un mínimo de caracteres y no
convierte divisas.

---

## 1. Propósito

Devolver una página de productos **publicados y disponibles** que cumplen un término de búsqueda
sobre su información disponible —incluido el precio— y **todos** los filtros activos, o declarar
explícitamente que no hay coincidencias.

Es una operación de **solo lectura**: no crea, modifica ni elimina nada, y no tiene efectos sobre
deseos, carrito, pago, inventario ni correo.

## 2. Entrada conceptual

| Entrada | Obligatoria | Semántica |
| --- | --- | --- |
| Página solicitada | No (por defecto, la primera) | Posición de la página dentro del resultado |
| Término de búsqueda | No | Texto que debe aparecer en la información disponible del producto, **incluido su precio**. Sin mínimo de caracteres impuesto |
| Filtro de rango de precio | No | Importe mínimo y/o máximo, **en unidades menores** de la moneda indicada |
| Filtro de tipo de producto | No | Uno de los tipos vigentes del catálogo (`RF-33`). El contrato **no** enumera la lista: la fija el catálogo |
| Filtro de estado de promoción | No | Estado de promoción del producto. Los valores oficiales están **pendientes** (ver §6) |
| Moneda aplicable | No, salvo al filtrar por precio | Moneda con la que se interpretan los importes y se presenta el precio. **El origen de esta moneda no se fija aquí** |

**Regla de conjunción.** Si llegan término y filtros, el resultado es la **intersección**: cada
producto devuelto cumple el término **y** todos los filtros. No hay semántica de unión.

## 3. Salida conceptual

| Salida | Semántica |
| --- | --- |
| Página de resultados | Hasta **dieciséis** representaciones de producto |
| Representación de producto | Nombre, imagen, descripción, habilidades, precio y, cuando corresponda, marcador de promoción |
| Posición | Número de la página devuelta |
| Tamaño de página | Dieciséis |
| Total | Número de productos que cumplen los criterios (permite saber si hay páginas siguientes) |
| Ausencia de resultados | Resultado **válido** y representable: ninguna representación y total cero. **Nunca** se devuelven productos que incumplan |

No se devuelve ningún dato que el catálogo no publique. En particular, no se inventan porcentajes de
descuento, precios anteriores, valoraciones ni disponibilidad.

## 4. Validaciones

| # | Validación | Motivo |
| --- | --- | --- |
| V-1 | La página es un entero positivo y su desplazamiento es representable | Evita páginas imposibles y desbordamientos |
| V-2 | Los importes son enteros no negativos en unidades menores de la moneda | El precio real es dinero; los créditos **no** son unidades menores de dinero |
| V-3 | El importe mínimo no supera el máximo | Un rango invertido no tiene semántica |
| V-4 | Si se filtra por precio, la moneda es obligatoria | **No se convierten divisas** |
| V-5 | El tipo de producto pertenece al conjunto vigente del catálogo | El catálogo de tipos no se inventa en esta HU |
| V-6 | El término de búsqueda es texto y tiene una longitud acotada | Evita consultas degeneradas; **no** impone un mínimo de caracteres |

## 5. Errores funcionales

| Error | Cuándo | Efecto |
| --- | --- | --- |
| Página inválida | V-1 | Se rechaza la consulta; no se devuelve una página arbitraria |
| Importe inválido | V-2 | Se rechaza |
| Rango invertido | V-3 | Se rechaza |
| Moneda ausente con filtro de precio | V-4 | Se rechaza. Convertir sería inventar una tasa |
| Tipo desconocido | V-5 | Se rechaza |
| Catálogo no disponible | Dependencia `RF-33` | Error de consulta. No se sustituye por datos de demostración |
| Sin coincidencias | No es un error | Resultado vacío explícito (`CA-12`) |

## 6. Decisiones que este contrato NO cierra

| # | Decisión | Consecuencia mientras siga abierta |
| --- | --- | --- |
| D-1 | Cómo se obtiene la **ubicación geográfica** y de dónde sale la moneda aplicable; si habrá conversión con tasas o precios separados por moneda | `CA-03` no puede darse por cumplido; hoy la moneda es un filtro explícito y **no** hay conversión |
| D-3 | Valores oficiales del **estado de promoción** | El filtro de promoción no puede exponerse de forma estable |
| D-4 | **Regla comercial de promoción**: porcentaje, vigencia y precio anterior | El marcador de descuento (`CA-04`) no tiene dato del que nutrirse |
| D-5 | **Tecnología de indexación y mínimo de caracteres** | Este contrato no los impone; la implementación los elige sin fijarlos aquí |

## 7. Ejemplos alineados con los casos de prueba del issue

### 7.1 `CP-57-01` — Búsqueda por información y por precio

- **Entrada:** página 1; en una ejecución un término presente en el nombre o la descripción del
  Producto A; en otra ejecución el **precio publicado** del Producto A.
- **Esperado:** el Producto A aparece en ambas ejecuciones; los productos sin coincidencia no
  aparecen.
- **Trazabilidad real:** `CA-06` (búsqueda general) y `CA-07` (búsqueda por precio). Los números de
  `CA` que el issue asocia a este caso están desalineados; se traza el comportamiento.

### 7.2 `CP-57-02` — Filtros combinados

- **Entrada:** página 1; rango de precio; un tipo de producto; estado «en promoción».
- **Esperado:** todos los resultados cumplen **simultáneamente** el rango, el tipo y el estado.
- **Trazabilidad real:** `CA-08`, `CA-09`, `CA-10` y `CA-11`. **El estado de promoción no es
  filtrable hoy** (D-3/D-4): el caso no puede ejecutarse completo.

### 7.3 `CP-57-03` — Presentación y paginación

- **Entrada:** diecisiete productos coincidentes, uno de ellos en promoción; página 1; interacción
  de ratón; selección del producto promocionado.
- **Esperado:** la primera página presenta los ítems que fija `CA-01`, el resto queda paginado, el
  producto promocionado muestra su porcentaje, se resalta y abre su detalle.
- **Trazabilidad real:** `CA-01`, `CA-04` y `CA-05`. **Hoy la vitrina muestra 12 ítems por página**
  y el porcentaje de descuento no tiene dato (D-4).

## 8. Frontera del contrato

- **No** incluye agregar a la lista de deseos (HU-56).
- **No** incluye agregar al carrito (HU-58).
- **No** incluye pago, transferencia ni vaciado (HU-59).
- **No** incluye persistencia del carrito entre sesiones (HU-61).
- **Sí** incluye «abrir la vista de detalle del producto seleccionado», y nada más sobre el detalle.

## 9. Trazabilidad de la implementación vigente

El contrato conceptual no fija HTTP; se deja constancia de dónde está materializado hoy para que la
verificación posterior (`#223`) tenga un punto de partida:

| Pieza | Ubicación |
| --- | --- |
| Caso de uso y validaciones | `Nexus-Battle-Catalog/src/application/use-cases/ListCatalogStorefront.ts` |
| Puerto de consulta y tamaño de página | `Nexus-Battle-Catalog/src/application/ports/CatalogStorefrontPort.ts` |
| Coincidencia textual (incluye precios) | `Nexus-Battle-Catalog/src/domain/services/storefront-search.ts` |
| Conjunción de criterios y paginación | `Nexus-Battle-Catalog/src/adapters/outbound/persistence/storefront-search-projection.ts` |
| Superficie HTTP | `Nexus-Battle-Catalog/src/adapters/inbound/http/canonical-products.controller.ts` (`GET /api/v1/catalog/products`) |
| Vitrina (presentación) | `Nexus-Battle-Web/src/features/commerce/showcase/` |
