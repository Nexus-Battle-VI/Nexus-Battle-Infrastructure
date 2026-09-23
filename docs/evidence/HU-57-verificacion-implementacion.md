# HU-57 — Verificación de la implementación (evidencia para #219, #221 y #223)

| Campo | Valor |
| --- | --- |
| **Requisito** | `RF-57` |
| **Historia** | [#31](https://github.com/Nexus-Battle-VI/Nexus-Battle-Management/issues/31) — HU-57 |
| **Tasks cubiertas** | [#219](https://github.com/Nexus-Battle-VI/Nexus-Battle-Management/issues/219) (lógica), [#221](https://github.com/Nexus-Battle-VI/Nexus-Battle-Management/issues/221) (UI), [#223](https://github.com/Nexus-Battle-VI/Nexus-Battle-Management/issues/223) (pruebas) |
| **Diseño asociado** | [`docs/architecture/hu-57-busqueda-filtros-vitrina.md`](../architecture/hu-57-busqueda-filtros-vitrina.md) |
| **Commits verificados** | Catalog `1fe838b` · Web `f6b55ec` (ambos `develop`) |
| **Estado** | La capacidad **ya estaba implementada** antes de este diseño. Este documento es el registro de verificación, no una implementación nueva |

Este anexo existe porque las tasks de implementación de HU-57 están abiertas pero su contenido
**ya está en `develop`**. En lugar de reimplementarlo (lo que duplicaría la regla y crearía una
segunda fuente de verdad), se verificó contra el código y las pruebas, se ejecutaron las suites y se
registra el resultado con evidencia reproducible: es lo que `#223` pide como «Test + log» y lo que
`#219`/`#221` necesitan para poder cerrarse.

---

## 1. Qué se ejecutó (evidencia reproducible)

```bash
cd Nexus-Battle-Catalog
npx jest --selectProjects unit          # 24 suites · 465 pruebas · 38,6 s
npx jest --config jest.db.config.ts --coverage=false test/db/catalog-storefront-reservations.spec.ts
                                        # 1 suite · 8 pruebas · 52,3 s (Mongo real por Testcontainers)
npx jest --selectProjects integration   # 13 suites · 136 pruebas (1 omitida) · 58,1 s
```

Resultado: **todo en verde, 0 fallos**. Los contenedores son reales (Docker en la máquina de
desarrollo), no dobles.

## 2. Matriz de `#223` (`P1`…`P4`, `N1`)

| # | Caso | Esperado | Estado | Evidencia |
| --- | --- | --- | --- | --- |
| `P1` | `page 1` | ≤ 16 ítems | ✅ | `test/unit/catalog-storefront-reservations.spec.ts` — 17 productos activos: página 1 con **16**, página 2 con **1**, página 3 vacía |
| `P2` | `query` coincide | subconjunto | ✅ | Mismo spec: `'999'` → 2 (coincide por **precio**), `'fuego'` → 3 (atributo anidado), `'.*'` → 0 (**literal**, no expresión regular) |
| `P3` | filtro | subconjunto | ✅ | Unit: conjunción de `type` + `currency` + rango de precio. DB: «storefront excludes suspended and **combines all filters**» |
| `P4` | paginación estable | página determinista | ✅ | DB: «preserves one-character literal search and transfers only a **16-item facet**». Integración: «**stable 16-item pages**» (orden `normalizedName, _id`) |
| `N1` | `productId` inválido | error | ✅ | DB e integración: «rejects suspended finite/infinite and **missing products**» |

## 3. Validaciones de `#219`

Todas implementadas en `ListCatalogStorefront` y **todas ejercitadas** (el texto entre paréntesis es
lo que asevera la prueba, no una palabra clave del mensaje):

| Validación | Estado | Evidencia |
| --- | --- | --- |
| Página entera ≥ 1 y desplazamiento representable | ✅ | `page: 0` → error (`'page'`) |
| Precios enteros no negativos | ✅ | `maxPrice: 0.5` → error (`'enteros'`) |
| Rango coherente (`minPrice ≤ maxPrice`) | ✅ | `minPrice: 10, maxPrice: 1` → error (`'minPrice'`) |
| Moneda obligatoria al filtrar por precio | ✅ | `minPrice: 1` sin moneda → error (`'currency'`) |
| Moneda dentro de `{COP, USD, EUR}` | ✅ | `currency: 'BTC'` → error (`'currency'`) |
| Tipo dentro del conjunto del catálogo | ✅ | `type: 'ITEM'` sin coincidencias + rechazo de tipo desconocido en el adaptador HTTP |
| Sin mínimo de caracteres | ✅ | Búsqueda de **un solo carácter** preservada (spec de DB) |

## 4. Condiciones de `#221` (UI)

| Condición | Estado | Evidencia |
| --- | --- | --- |
| Banner + grid | ⚠️ **Parcial** | Banner presente en `CommercePage.tsx`. El grid muestra **12** productos, no 16 (ver §5) |
| Hover y promo visibles | ⚠️ **Hover sí, promo no** | `ShowcaseGrid.tsx` → `hover:border-brand`. El *badge* de promoción no tiene dato (§6) |
| Click → detalle | ✅ | `ShowcaseGrid.tsx` navega al detalle; el detalle consume `GET /api/v1/catalog/products/:reference` |
| 1360×768 OK | ✅ | `docs/frontend/ecommerce-compacto.md` §Verificación: documento 1360×768, 12 imágenes cargadas, **ninguna tarjeta desbordada**; y 390×844 sin desplazamiento horizontal |
| Estados (llena, vacía, loading, error) | ✅ | `Showcase.tsx` + `QueryState` (mensaje de ausencia de resultados) |
| Evidencia (Figma + capturas) | ⚠️ Parcial | Capturas en `docs/evidence/ecommerce-vitrina-local.png` y `ecommerce-pago-local.png`. **Figma no se aporta desde aquí** |

## 5. El punto que necesita decisión humana: 12 frente a 16

Hay un conflicto real entre tres fuentes, y **no se resuelve por cuenta propia** en este PR:

| Fuente | Dice |
| --- | --- |
| `CA-01` del issue `#31` | «páginas de **hasta** dieciséis elementos» |
| Regla de negocio del issue | «La paginación debe presentar **dieciséis (16)** ítems por página» |
| Condición de `#221` | «Banner + **grid 16**» |
| Contrato de Catalog | `pageSize: 16` — **cumplido** |
| Vitrina (Web) | **12** visibles y el adaptador pide páginas de 16 para completarlas |
| `Web/docs/frontend/ecommerce-compacto.md` | Decisión **deliberada y verificada**: 12 visibles para que ninguna tarjeta desborde en 1360 × 768, conservando la paginación de 16 de Catalog |
| `ShowcaseFiltersBar.tsx` | La interfaz lo declara: «Hasta 12 productos por página» |
| `api.test.ts` | `describe('Paginacion visible de 12 sobre el contrato HTTP de 16')` — probado |

**Lectura técnica:** el requisito «hasta dieciséis» se cumple en el contrato y en el backend; el
requisito literal «16 ítems por página» **no** se cumple en la pantalla. La reducción a 12 está
justificada por el otro requisito de `#221` (1360 × 768 sin desbordes), así que no es un descuido:
es un compromiso entre dos condiciones de la misma task.

**Por qué no se cambia aquí:** revertir una decisión de presentación ya verificada y declarada en la
interfaz es una decisión de producto/UX, no una corrección técnica. Queda como pregunta explícita:
¿prevalece «grid 16» de `#221` sobre el «sin desbordes en 1360 × 768» que motivó las 12?

## 6. Lo que sigue bloqueado (y por qué no se inventa)

| CA | Falta | Motivo |
| --- | --- | --- |
| `CA-04` | Marcador con **porcentaje de descuento** | El catálogo canónico expone `premium: boolean` (producto de pago en moneda real, HU-36), **no** un estado ni un porcentaje de promoción. `#219` manda: «si el catálogo aún no expone un campo documentado por HU-57, se declara impedimento; no se inventa el esquema» |
| `CA-10` | Filtro por **estado de promoción** | Misma causa. `#219` admite limitarlo al estado documentado «en promoción» y su complemento **si el catálogo lo expone**: hoy no lo expone |
| `CA-03` | Moneda según **ubicación geográfica** | Decisión del PO (`D-1`): falta el mecanismo de ubicación y la política de conversión. Hoy la moneda llega como filtro explícito y **no se convierten divisas** |

Ninguno de los tres se cierra inventando la regla. Son dependencia o condición, y así se declaran.

## 7. Conclusión

- **`#219` (lógica):** implementada y probada. No hay trabajo pendiente salvo la parte de promoción,
  bloqueada por datos que el catálogo no publica.
- **`#223` (pruebas):** la matriz `P1`…`P4`/`N1` y las validaciones están cubiertas por pruebas
  automatizadas que pasan con contenedores reales.
- **`#221` (UI):** implementada en todo salvo el *badge* de promoción (bloqueado) y la decisión
  12/16, que necesita confirmación del Product Owner.
- **`#217` (diseño):** entregado en el mismo PR que este anexo.
