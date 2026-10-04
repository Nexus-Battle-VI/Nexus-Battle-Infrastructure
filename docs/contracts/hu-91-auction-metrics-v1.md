# HU-91.1 — Refinement técnico: contrato de métricas, fórmulas y autorización

| Campo | Valor |
| --- | --- |
| Task | HU-91.1 — Definir contrato de métricas y fórmulas exactas (Nexus-Battle-Management#576) |
| HU padre | HU-91 — Consultar métricas operativas y comerciales de Subasta (#522) · EPIC-07 (#7) · Sprint 3 · Team Gamma |
| Estado del documento | **Borrador** — contrato propuesto para revisión; no aprobado por PO / dueños de Auction, Catalog y Wallet; no declara implementación ni aceptación de la HU |
| Versión de definiciones | `hu-91.v1` |
| Fecha de la investigación | 2026-10-04 |
| Alcance | Solo diseño. Sin cambios de código. |
| Decisiones resueltas (2026-10-04) | **D-1** subastas oficiales: solo volumen y precio de lista; `successRate`, `closingTime` y `finalSalePrice` son `UNAVAILABLE` de forma permanente (fuera de alcance de HU-91). **D-2** `playerId` = `sub` opaco tal cual, tras `@Roles(Role.Administrator)` + `@AuthenticationRequired()`; no se resuelve nombre en esta Task. |

> **Convención de citas.** Cada hecho técnico cita `repo:ruta` y la rama verificada. Salvo que se indique `main`, todo se verificó en **`origin/develop`** tras `git fetch origin --prune` (ver §1). Los repos se leyeron con `git show`/`git grep` contra las refs remotas; no se modificó ninguna rama de trabajo.

---

## 0. Resumen ejecutivo

1. **Las 3 fórmulas quedan cerradas** (§3) usando solo columnas que ya existen en Auction. No hace falta inventar campos para las fórmulas; sí hacen falta **índices** (R-06).
2. **Las subastas oficiales (dinero real) no tienen ciclo de cierre en el código actual**: no se liquidan, no reciben pujas, no tienen compra inmediata y quedan `ACTIVE` para siempre. Por eso **tasa de éxito, tiempo de cierre y precio de venta solo existen para subastas de jugador (créditos)**. Para oficiales solo hay volumen y precio de **publicación**. El contrato lo declara con un bloque `availability: "UNAVAILABLE"` (mismo patrón que HU-89 `view-statistics`), nunca con ceros.
3. **Hay tres huecos entre lo que HU-91 asume y lo que existe** que cambian el plan de las Tasks siguientes (§8):
   - **Wallet no tiene ningún endpoint de lectura de comisiones** y su `wallet_ledger` es el ledger de recompensas de batalla, no de comisiones. No existe "cuenta de sistema" en el código (solo en `docs/architecture.md` como *previsto*). La única "comisión" real es la **comisión de publicación** (1 crédito/24 h, 3 créditos/48 h) y se puede calcular hoy **solo desde Auction**.
   - **Catalog no tiene "marca"** y la "categoría" solo existe en el modelo legado. Además `GET /api/products/:sku` es el modelo **legado** y **no puede resolver** los `product_id` de Auction. **Ya existe** el endpoint en bloque que HU-91.3 necesita: `POST /api/v1/catalog/products/lookup`.
   - **Las compras inmediatas (`SOLD`) rompen las agregaciones ingenuas**: `finished_at`, `winner_id` y `final_amount_credits` quedan en `NULL` y `closes_at` se **sobrescribe** con el instante de la compra.
4. **Autorización (CA-06):** `@Roles(Role.Administrator)` en Auction (el `RolesGuard` ya admite a `SUPER_ADMINISTRATOR` por jerarquía) + `@AuthenticationRequired()`; en Web, `RequireAdministrator` + entrada en `ADMIN_NAVIGATION`. Es el mismo patrón de `features/admin/products` y `features/admin/roles`.

---

## 1. Estado de los repos al investigar

| Repo | `origin/main` | `origin/develop` | Base de la investigación |
| --- | --- | --- | --- |
| Nexus-Battle-Auction | `a225d04` (2026-09-30) | `5c0b781` (2026-10-03, HU-89 #83) | `develop` |
| Nexus-Battle-Catalog | `f92b458` (2026-09-27) | `2705b3d` (2026-10-03) | `develop` (lookup también en `main`) |
| Nexus-Battle-Wallet | `96bb79e` (2026-09-28) | `09694a7` (2026-10-03, reembolso parcial #25) | `develop` |
| Nexus-Battle-Web | `1114c49` (2026-10-01) | `09a451a` (2026-10-03, cancelación #201) | `develop` |
| Nexus-Battle-Management | — (sin clon local) | — | leído por `gh issue view` (solo lectura): #522, #520, #521, #576 |

**Divergencia main/develop** (relevante para despliegue, R-07): en Auction, la migración `017` (cancelación) y todo `CANCELLED`/`cancelled_at`/`GetMyAuctionActivity` existen **solo en `develop`**; `main` termina en la migración `016`. En Wallet, la migración `007` (reembolso parcial) **no está en `main`**.

---

## 2. Qué existe hoy en el código (evidencia)

### 2.1 Auction — modelo de datos real

Fuente de verdad del esquema: `Nexus-Battle-Auction:src/adapters/outbound/persistence/schema.ts` + migraciones `001`–`018`.

**Tabla `auctions`** (una sola tabla para ambos tipos, discriminada por `price_kind`; restricción `auctions_pricing_discriminated`, migración `016-persist-official-auction-publication.ts`):

| Columna | Jugador (`CREDITS`, `publisher_type='PLAYER'`) | Oficial (`REAL_MONEY`, `publisher_type='GAME_MASTER'`) |
| --- | --- | --- |
| `id`, `seller_id`, `product_id`, `duration_hours` (24/48) | sí | sí (`seller_id` = publicador GM) |
| `published_at`, `closes_at` | sí | sí |
| `status` ∈ `ACTIVE`,`FINISHED`,`SOLD`,`CANCELLED` (mig. `013`, `017`) | todos | **solo `ACTIVE`** en la práctica (R-01) |
| `publication_fee_credits` | 1 (24 h) / 3 (48 h) (`AuctionDuration.ts`) | 0 |
| `minimum_bid_credits`, `buy_now_credits` | sí | `NULL` |
| `currency`, `minimum_bid_amount_minor`, `buy_now_amount_minor`, `official_mark` | `NULL` | sí (`OFFICIAL`/`PREMIUM`; importes `integer` en unidad mínima) |
| `inventory_commitment_id`, `fee_charge_id` | no nulos | `NULL` |
| `finished_at`, `closing_result_type` (`WITH_WINNER`/`WITHOUT_BIDS`), `winning_bid_id`, `winner_id`, `final_amount_credits` | solo en `FINISHED` (mig. `007`) | nunca |
| `cancelled_at` | no nulo ⇔ `CANCELLED` (`auctions_cancelled_at_valid`, mig. `017`) | nunca |

**Tablas relacionadas usables para métricas:**

| Tabla | Aporta | Clave de idempotencia / unicidad |
| --- | --- | --- |
| `auction_bids` (`002`) | `bidder_id`, `amount_credits`, `placed_at`, `is_leader` | PK `id`; **sin columna que distinga puja manual de automática** |
| `auction_buy_now_operations` (`013`,`014`) | `buyer_id`, `price_credits`, `completed_at` | PK `operation_id`; **UNIQUE `auction_id`** (`auction_buy_now_operations_auction_uq`) |
| `auction_settlements` (`007`,`008`) | `status` (incl. `FAILED_TERMINAL`), `settled_at`, `seller_id`, `winner_id` | PK `auction_id` |
| `auction_pending_claims` (`008`,`012`) | `claim_status` `PENDING`/`CLAIMED`/`EXPIRED`, `settled_at`, `claimed_at` | PK `auction_id` |
| `auction_cancellations` (`017`) | `refund_amount_credits` ∈ {0.5, 1.5}, `wallet_refund_status`, `cancelled_at` | PK `auction_id` |
| `auction_publication_operations` (`001`) | `operation_id`, `completed_at` | UNIQUE `auction_id` |
| `auction_publication_failures` (`001`) | comisión cobrada y reembolsada tras fallo (`fee_refunded`) | PK `operation_id` |

Dominio relevante: `src/domain/entities/Auction.ts` (estados, `cancel()`), `AuctionClosingResult.ts`, `AuctionPendingClaim.ts` (`CLAIM_PERIOD_MS` = 7 días), `OfficialAuction.ts` (**no tiene** `finish()` ni resultado de cierre).

**Comportamientos del código que condicionan las fórmulas** (verificados):

- `PostgresAuctionRepository.closeByBuyNow` (`:1420`) hace `UPDATE auctions SET status='SOLD', closes_at = command.closedAt`; **no** escribe `finished_at`, `winner_id` ni `final_amount_credits`. El precio y el instante viven solo en `auction_buy_now_operations` (`price_credits`, `completed_at` = `closedAt`).
- `findSettlementCandidates` (`:1235`), `findActiveClosingBetween` (`:354`) y `persistBid` (`:966`) filtran `price_kind = 'CREDITS'`; comentario explícito: *«la liquidación en dinero real de una publicación oficial no existe todavía»*. `findAuction` devuelve `null` para filas `REAL_MONEY`, por lo que tampoco hay compra inmediata oficial.
- `ExpirePendingClaims.ts`: al vencer un reclamo (`EXPIRED`) **no** se devuelve el producto al vendedor ni se reembolsa al ganador («tal como exige CA-04» de HU-69). La venta ya está concluida y cobrada.
- `SettleAuction.ts`: `auction.finish()` fija `FINISHED`/`closing_result_type` antes de capturar créditos; la captura Wallet puede terminar en `TerminalError` y el settlement en `FAILED_TERMINAL` sin revertir `FINISHED`.
- `product_id` **es el `productId` canónico de Catalog**: `CatalogProductPolicyClient.ts:52` llama `/api/internal/v1/catalog/products/${productId}/premium-status` y exige `payload.productId === productId`.
- Precedente de contrato en HU-89: `AuctionActivityRepositoryPort`/`PostgresAuctionActivityRepository.ts` filtra `price_kind='CREDITS'`, devuelve valores como `{ amount, unit: 'CREDITS' }`, y `GET /v1/auctions/me/view-statistics` responde `{ availability: "UNAVAILABLE", reason: "AUTHORITATIVE_SOURCE_NOT_CONFIGURED", metrics: [] }` (`docs/tasks/TASK-89.3-auction-view-statistics.md`). **HU-91 reutiliza ese lenguaje de "indisponible explícito".**
- Cuerpo de error: `{ statusCode, code, message }` (`auction-error.mapper.ts`, función `body`).

### 2.2 Catalog

- **Modelo legado** — `products.controller.ts` (`@Controller('products')`): `GET /api/products/:sku` (`@Public()`), «Recupera un producto **publicado**» (404 si no está publicado). Respuesta `ProductResponse` (`products.dto.ts`): `sku, name, category, price{amount,currency}, isPremium, realMoneyPrice, status(DRAFT|PUBLISHED|ARCHIVED)`. **No tiene campo de marca.** La clave es el `sku` kebab-case, no un UUID.
- **Modelo canónico** — `canonical-products.controller.ts` (`@Controller('v1/catalog/products')`):
  - `GET /api/v1/catalog/products/:reference` (`@Public()`, `productId` UUID o `sku`).
  - **`POST /api/v1/catalog/products/lookup`** (`@Public()`): body `{ references: string[1..500], query?, type? }` → `{ items: CanonicalProductDto[] }`. Referencias inexistentes **se omiten** (no es error). Devuelve productos de **cualquier** `lifecycleStatus` (incl. `SUSPENDED`). Existe en `main` y `develop`.
  - `CanonicalProductDto` (`CanonicalProductDto.ts`): `productId, sku, name, imageUrl, description, type, attributes, printRun, printRunMode, availableUnits, lifecycleStatus, creditsPrice, premium, realMoneyPrice, averageRating, reviewCount, hasRealMoneyPurchase, createdAt, updatedAt, version`.
  - `type` ∈ `HEROE | HABILIDAD | ARMA | ARMADURA | ITEM | EPICA` (`canonical-product-values.ts`). **Es lo más parecido a "categoría" en el modelo canónico.**
- `git grep -i "brand|marca"` en `Nexus-Battle-Catalog/src` → solo coincidencias de la palabra "marca" como verbo (`marca una ruta…`). **No existe el concepto de marca de producto.**
- Auction ya consume este lookup (`CatalogProductLookupClient.ts`, trocea en bloques de 500, sin firma interna, tolera `items` ausentes).

### 2.3 Wallet

- `wallet_ledger` (`schema.ts`, migración `001`): columnas `battle_id`, `reason`, `credits_amount`, `victory_credits_amount`, `chest_earned`… → **ledger de recompensas de batalla (HU-22)**. No contiene comisiones de Subasta.
- Ledgers de Subasta: `wallet_auction_hold_ledger` (`kind` ∈ `AUCTION_HOLD_RESERVED/RELEASED/CAPTURED/EXPIRED`, `AUCTION_SETTLEMENT_CREDIT`) y `wallet_buy_now_transfer_ledger` (`BUY_NOW_DEBIT/CREDIT/REVERSAL_*`). La captura (`PostgresAuctionHoldRepository.capture`) acredita al vendedor **el monto completo**: **no hay comisión de venta**.
- **Comisión de Subasta = comisión de publicación**: tablas `wallet_auction_publication_fees` (`charge_id`=`operation_id`, `seller_id`, `amount`, `status` `CHARGED|REFUNDED`, `created_at`, `refunded_at`) y `wallet_auction_publication_fee_refunds` (`operation_id`, `charge_id`, `amount` — mig. `007`).
  - **No hay `auction_id` en Wallet**: el vínculo Auction↔Wallet es `auctions.fee_charge_id` = `charge_id`.
  - **No hay "cuenta de sistema"**: `docs/architecture.md` la menciona como *previsto* («Cuentas de sistema para comisiones»); el código descuenta del saldo del vendedor y no acredita a ninguna cuenta. No existe identificador de operación/cuenta que distinga "comisión de Subasta" en un ledger común; la distinción es **la tabla misma**.
  - Matices de `PostgresAuctionPublicationFeeRepository.refund`: un reembolso **parcial** deja `status='REFUNDED'` (no distingue parcial de total); una segunda solicitud con otro `operationId` **inserta fila en `…_refunds` pero no acredita** (`applied:false`). Sumar `…_refunds.amount` sobrecuenta (R-04).
- Rutas: todas internas (`/internal/v1/wallet/...`, `@InternalOnly('auction'|'combat'|'missions')`, HMAC) salvo `GET /v1/wallet/me`. **No hay ninguna ruta de lectura agregada de comisiones.**

### 2.4 Web — patrón de autorización por rol

- Guardas de presentación (`src/app/`): `RequireAdministrator.tsx`, `RequireSuperAdministrator.tsx`, `RequireModerator.tsx`, `RequireGameMaster.tsx`. Todas declaran «**NO AUTORIZA NADA**… el servicio valida el testimonio y responde 403».
- Criterio de roles centralizado en `src/shared/rbac.ts`: `canViewAdminUsers(roles)` ⇒ `primaryRole ∈ {ADMINISTRATOR, SUPER_ADMINISTRATOR}` (precedencia `SUPER_ADMINISTRATOR > ADMINISTRATOR > MODERATOR > GAME_MASTER > PLAYER`). `RequireAdministrator` usa `canViewAdminUsers`.
- Uso en rutas (`src/routes/routes.tsx`): `admin/products`, `admin/products/new`, `admin/products/:productId/inventory`, `admin/banners`, `admin/missions` → `<RequireAdministrator>`; `admin/roles` → `<RequireSuperAdministrator>`.
- Navegación: `ADMIN_NAVIGATION` con `requiredPrimaryRole: 'ADMINISTRATOR'` (jerarquía `ADMINISTRATIVE_RANK`: un Super Admin ve lo que exige `ADMINISTRATOR`).
- Backends: Catalog `admin-products.controller.ts` usa `@Roles(Role.Administrator)` en lecturas (`GET`) y **añade** `@RequiresMfaEvidence()` solo en mutaciones. Auction: `roles.guard.ts` — `satisface()` admite `SUPER_ADMINISTRATOR` donde se exige `ADMINISTRATOR` («Se resuelve AQUÍ y no añadiendo `Role.SuperAdministrator` a cada `@Roles`»).
- Auction **no tiene hoy ninguna ruta administrativa** ni infraestructura de MFA (`git grep -i mfa` en `src` → 0).

### 2.5 Management

- HU-91 (#522): fórmulas de «tasa de éxito», «usuario más activo» y «tiempo de cierre» **declaradas abiertas**; PO checklist con «Fórmulas exactas… confirmadas por PO/Developers» **sin marcar**.
- HU-89 (#520): se resolvió con contratos explícitos, `price_kind='CREDITS'` y "indisponible explícito" (§2.1). Aquí se replica esa disciplina antes de escribir código.
- Task #576: pide documento + contrato por endpoint (Tasks HU-91.2 a 91.6) + rol confirmado. **Condición de cierre incluye aprobación de PO y revisión de dueños de Auction, Catalog y Wallet** (pendiente: este documento es el insumo).

---

## 3. Fórmulas cerradas

**Reglas comunes a todas** (se repiten en cada respuesta como `definitionsVersion`):

- **Periodo:** semiabierto `[from, to)` en **UTC**, ISO-8601 con zona. Por defecto: `to = now`, `from = to − 30 días`. Máximo 366 días.
- **Ámbito de monedas:** "jugador" = `price_kind='CREDITS'`; "oficial" = `price_kind='REAL_MONEY'`. **Nunca se suman ni promedian entre sí.**
- **Solo lectura:** `GET`, transacción `READ ONLY`, sin escrituras. Las métricas históricas solo cambian si cambian los datos fuente (p. ej. un reembolso confirmado tarde).
- **Cada contador se ancla a su propio timestamp persistido** (indicado en cada fórmula); por eso "publicadas en el periodo" y "cerradas en el periodo" son cohortes distintas y se muestran separadas.

### 3.1 Tasa de éxito

**Definición.** Entre las subastas **de jugador** que **terminaron por el mercado** en el periodo, la proporción que terminó **con venta**.

```
cerrada(a)     = a.price_kind = 'CREDITS' AND a.status IN ('FINISHED','SOLD')
cerrada_en(a)  = a.finished_at                      si status = 'FINISHED'
                 n.completed_at (buy-now op)        si status = 'SOLD'
con_venta(a)   = (status = 'FINISHED' AND closing_result_type = 'WITH_WINNER') OR status = 'SOLD'

denominador = |{ a : cerrada(a) AND from ≤ cerrada_en(a) < to }|
numerador   = |{ a : ... AND con_venta(a) }|
tasa        = numerador / denominador          (NULL si denominador = 0; nunca 0)
```

SQL de referencia (verificable contra los datos):

```sql
select count(*) filter (where is_success) as numerator, count(*) as denominator
from (
  select (a.status = 'SOLD' or a.closing_result_type = 'WITH_WINNER') as is_success,
         case a.status when 'FINISHED' then a.finished_at else n.completed_at end as closed_at
  from auctions a
  left join auction_buy_now_operations n on n.auction_id = a.id   -- 1:1 por UNIQUE(auction_id)
  where a.price_kind = 'CREDITS' and a.status in ('FINISHED','SOLD')
) c
where closed_at >= :from and closed_at < :to;
```

**Justificación (campos reales).** `FINISHED` + `closing_result_type` es el resultado persistido por `Auction.finish()` (`AuctionClosingResult.ts`); `SOLD` es el cierre anticipado por compra inmediata (`closeByBuyNow`). HU-91 pide «venta/adjudicación frente a finalización elegible».

**Decisiones de casos borde:**

| Caso | Decisión | Por qué |
| --- | --- | --- |
| **Cancelada** (`CANCELLED`) | **Fuera del denominador.** Se reporta aparte (`cancelled`). | Es decisión del vendedor (HU-90, solo sin pujas y con > 6 h), no un desenlace del mercado. Incluirla castigaría la tasa por una acción que el comprador no vio. La regla futura de cancelación automática (HU-90 CA-05, «fuera de este PR» en `CancelAuction.ts`) caerá en el mismo `status='CANCELLED'` sin cambiar el contrato. |
| **Activa** (`ACTIVE`) | Fuera. Se reporta `active` y `awaitingClosure` (`ACTIVE` con `closes_at <= asOf`, pendiente del scheduler). | Aún no hay desenlace. |
| **Oficial (dinero real)** | **Fuera; la tasa es `UNAVAILABLE`** (`OFFICIAL_AUCTION_HAS_NO_CLOSING_FLOW`). Solo se reporta volumen. | No existe cierre/venta oficial en el código (R-01). Cualquier cifra sería inventada. |
| **Compra inmediata** (`SOLD`) | **Cuenta como éxito** y cierra en `completed_at`. | Es una venta real; `closes_at` está sobrescrito, `finished_at` es `NULL` (R-02). |
| **Reclamo vencido sin reclamar** (`EXPIRED`) | **Sigue siendo éxito.** Se reporta `claims.expired` aparte. | La venta y la captura de créditos ya ocurrieron; el reclamo es logística posterior y el producto no vuelve (`ExpirePendingClaims.ts`). |
| **`FINISHED` con captura fallida** (`auction_settlements.status='FAILED_TERMINAL'`) | **Sigue siendo éxito de adjudicación**; se expone `settlementFailedTerminal` para auditoría. | Definición de HU-91: «venta/adjudicación». El conteo separado evita ocultar un problema operativo. |

> **Fórmula reproducible para CP-01:** 10 cerradas, 6 `WITH_WINNER`/`SOLD`, 4 `WITHOUT_BIDS` ⇒ `6/10 = 0.6`.

### 3.2 Usuario activo

**Definición.** Un **usuario activo** en el periodo es una identidad (`sub` del token) que **realizó al menos una acción de mercado** en una subasta **de jugador** dentro del periodo. El **grado de actividad** es el número de **subastas distintas** en las que actuó:

```
Acciones de mercado (cada una con su timestamp persistido):
  SELLER : publicó una subasta        → auctions.seller_id,   auctions.published_at
  BIDDER : registró ≥ 1 puja          → auction_bids.bidder_id, auction_bids.placed_at
  BUYER  : ejecutó una compra inmediata → auction_buy_now_operations.buyer_id, .completed_at

actividad(u) = COUNT(DISTINCT auction_id) sobre la unión de las tres, con timestamp ∈ [from, to)
usuarios activos = |{ u : actividad(u) ≥ 1 }|
ranking = ORDER BY actividad DESC, playerId ASC   (desempate determinista)
```

```sql
with acts as (
  select seller_id as player_id, id as auction_id, 'SELLER' as role from auctions
   where price_kind='CREDITS' and published_at >= :from and published_at < :to
  union all
  select bidder_id, auction_id, 'BIDDER' from auction_bids
   where placed_at >= :from and placed_at < :to
  union all
  select buyer_id, auction_id, 'BUYER' from auction_buy_now_operations
   where completed_at >= :from and completed_at < :to
)
select player_id,
       count(distinct auction_id) as active_auctions,
       count(distinct auction_id) filter (where role='SELLER') as as_seller,
       count(distinct auction_id) filter (where role='BIDDER') as as_bidder,
       count(distinct auction_id) filter (where role='BUYER')  as as_buyer
from acts group by player_id
order by active_auctions desc, player_id asc limit :limit;
```

**Justificación.** Son las únicas acciones con identidad y timestamp persistidos. Se cuenta **subastas distintas** y no pujas porque `auction_bids` **no distingue pujas manuales de automáticas** (`ReactToRivalBid`): contar filas dejaría que una guerra de auto-pujas infle el ranking. Un vendedor no puede pujar en su subasta (`Bid.assertBidderIsNotSeller`), y un `BUYER` que antes pujó cuenta una sola vez esa subasta.

**Decisiones de casos borde:**

| Caso | Decisión |
| --- | --- |
| Seguir (watchlist), reclamar productos, consultar | **No son actividad** (pasivos o posteriores a la venta; no miden mercado). |
| Subasta publicada y luego **cancelada** | El vendedor **sí cuenta** (publicó en el periodo). |
| Publicador oficial (GM) y subastas oficiales | **Excluidos**: la cuenta GM es una identidad comercial (HU-66), no un usuario del mercado. |
| Identidad `anonymous` (modo `AUTH_MODE=disabled`) | No debe existir en producción (el binario no arranca así); no se filtra. |

### 3.3 Tiempo de cierre

**Definición.** Segundos transcurridos entre la **publicación** y el **cierre efectivo persistido**, sobre las subastas de jugador **cerradas en el periodo** (misma cohorte `cerrada` del §3.1):

```
cierre_segundos(a) = EXTRACT(EPOCH FROM (cerrada_en(a) − a.published_at))
```

Se reporta: `average`, `median` (`percentile_cont(0.5)`), `p90`, `sampleSize` y desglose por **motivo de cierre**: `EXPIRED_WITH_WINNER` (FINISHED+WITH_WINNER), `EXPIRED_WITHOUT_BIDS` (FINISHED+WITHOUT_BIDS), `BUY_NOW` (SOLD).

**Justificación.** `closes_at − published_at` es **siempre** 24 h o 48 h (`AuctionDuration.calculateClosingTime`): no informa nada. Lo informativo es el instante **real**: `finished_at` (liquidación) o `completed_at` (compra inmediata). Por eso la compra inmediata baja el promedio y es visible por motivo.

**Métrica complementaria (diagnóstico):** `settlementLagSeconds = finished_at − closes_at` (solo `FINISHED`). Mide retraso del scheduler; se publica **separada** para no contaminar el tiempo de cierre.

**Decisiones de casos borde:**

| Caso | Decisión |
| --- | --- |
| `CANCELLED` | Excluida (no hay "cierre" de mercado); se cuenta en tendencias. |
| `ACTIVE` | Excluida. |
| Oficial | `UNAVAILABLE` (`OFFICIAL_AUCTION_HAS_NO_CLOSING_FLOW`): quedan `ACTIVE` pasada su `closes_at`. |
| `SOLD` | Se usa `auction_buy_now_operations.completed_at` (autoritativo); `closes_at` coincide por construcción pero es un detalle de implementación que podría cambiar. |
| Muestra vacía | `average/median/p90 = null`, `sampleSize = 0`. |

### 3.4 Definiciones auxiliares (necesarias para los contratos)

- **Precio final (jugador, créditos):** `FINISHED+WITH_WINNER` → `auctions.final_amount_credits`; `SOLD` → `auction_buy_now_operations.price_credits`. **Nunca** `AVG(final_amount_credits)` a secas (excluye silenciosamente las compras inmediatas, R-02). Anclado a `cerrada_en`.
- **Precio de publicación (oficial, dinero real):** `minimum_bid_amount_minor` (y `buy_now_amount_minor` si existe), **por moneda** (`currency`). Es **precio de lista, no de transacción** (R-05). Anclado a `published_at`.
- **Comisión de Subasta:** únicamente la **comisión de publicación** en créditos.
  `neta = Σ publication_fee_credits (subastas de jugador publicadas en el periodo) − Σ refund_amount_credits (auction_cancellations con wallet_refund_status='CONFIRMED' y cancelled_at en el periodo)`.
  No existe comisión por venta ni comisión en dinero real. Puede ser negativa en un periodo si los reembolsos corresponden a publicaciones de periodos previos; se expone bruto, reembolsado y neto.
- **Ranking de productos:** *más subastados* = `COUNT(*)` de `auctions` por `product_id` publicadas en el periodo (jugador y oficial por separado + total); *más vendidos* = `COUNT(*)` de subastas de jugador con `con_venta` cerradas en el periodo. Sin `JOIN` a `auction_bids` (evita duplicados); el único `JOIN` es 1:1 (`UNIQUE auction_id`). Desempate: `count DESC, product_id ASC`.
- **Granularidad de tendencias:** `DAY` | `WEEK` (lunes, ISO) | `MONTH`, `date_trunc` en UTC; el servidor devuelve **todos** los buckets (con ceros/`null`) para que la serie sea continua y reproducible. Máx. 366 buckets.

---

## 4. Contrato de API

**Base:** `/api/v1/admin/auction-metrics` (prefijo global `api` — `main.ts:21`). Controlador **propio** (`@Controller('v1/admin/auction-metrics')`), **no** dentro de `v1/auctions`, porque `GET v1/auctions/:auctionId` (`auction.controller.ts:466`) capturaría rutas como `metrics`.

**Autorización común:** `@Roles(Role.Administrator)` + `@AuthenticationRequired()` (§6). Todos son `GET`.

**Parámetros comunes de consulta**

| Param | Tipo | Defecto | Validación |
| --- | --- | --- | --- |
| `from` | ISO-8601 con zona | `to − 30d` | `from < to`, span ≤ 366 d |
| `to` | ISO-8601 con zona | `now` | no futuro más allá de `now` + 1 min |

**Envoltorio común de toda respuesta 200**

```json
{
  "definitionsVersion": "hu-91.v1",
  "period": { "from": "2026-09-04T00:00:00.000Z", "to": "2026-10-04T00:00:00.000Z", "timezone": "UTC", "bounds": "[from,to)" },
  "asOf": "2026-10-04T15:20:11.000Z"
}
```

**Formas de valor (separación créditos / dinero real)**

```jsonc
{ "unit": "CREDITS", "amount": 12.5 }                                   // créditos (número, ≤ 2 decimales)
{ "unit": "REAL_MONEY", "currency": "COP", "amountMinor": 1500000 }     // dinero real: entero en unidad mínima
{ "availability": "UNAVAILABLE", "reason": "OFFICIAL_AUCTION_HAS_NO_CLOSING_FLOW" } // indisponible explícito (patrón HU-89)
```

**Errores comunes** (cuerpo `{ statusCode, code, message }`, igual que `auction-error.mapper.ts`):
`400 INVALID_PERIOD` · `400 INVALID_PARAMETER` · `401` (token ausente/ inválido, o `AUTH_MODE=disabled`) · `403` (rol insuficiente — **sin datos ni identificadores**, CA-06) · `503` (BD no disponible).

---

### 4.1 Volumen y tasa de éxito — `GET /api/v1/admin/auction-metrics/volume-and-success` *(Task HU-91.2)*

```json
{
  "definitionsVersion": "hu-91.v1",
  "period": { "from": "2026-09-04T00:00:00.000Z", "to": "2026-10-04T00:00:00.000Z", "timezone": "UTC", "bounds": "[from,to)" },
  "asOf": "2026-10-04T15:20:11.000Z",
  "playerAuctions": {
    "currencyUnit": "CREDITS",
    "published": 120,
    "closed": {
      "total": 100,
      "withWinner": 55,
      "soldByBuyNow": 8,
      "withoutBids": 37,
      "settlementFailedTerminal": 1
    },
    "cancelled": 12,
    "active": 8,
    "awaitingClosure": 2,
    "successRate": {
      "numerator": 63,
      "denominator": 100,
      "value": 0.63,
      "formula": "(withWinner + soldByBuyNow) / closed.total",
      "excludes": ["CANCELLED", "ACTIVE"]
    },
    "claims": { "createdInPeriod": 63, "pending": 5, "claimed": 52, "expired": 6 }
  },
  "officialAuctions": {
    "currencyUnit": "REAL_MONEY",
    "published": 14,
    "byMark": { "OFFICIAL": 9, "PREMIUM": 5 },
    "successRate": { "availability": "UNAVAILABLE", "reason": "OFFICIAL_AUCTION_HAS_NO_CLOSING_FLOW" }
  }
}
```

Reglas: `closed.total = withWinner + soldByBuyNow + withoutBids`. `successRate.value = null` (con `numerator:0, denominator:0`) si no hay subastas cerradas. `published` ancla a `published_at`; `closed.*` a `cerrada_en`; `cancelled` a `cancelled_at`; `claims.createdInPeriod` a `auction_pending_claims.settled_at` (incluye reclamos de compras inmediatas). `active` = `ACTIVE` y `closes_at > asOf`; `awaitingClosure` = `ACTIVE` y `closes_at <= asOf`. Para el CP-01 (10 → 6 adjudicadas, 4 sin venta) `value = 0.6`.

---

### 4.2 Ranking de productos — `GET /api/v1/admin/auction-metrics/product-rankings` *(Task HU-91.3)*

Parámetros extra: `limit` (1–50, defecto 10).

```json
{
  "definitionsVersion": "hu-91.v1",
  "period": { "from": "...", "to": "...", "timezone": "UTC", "bounds": "[from,to)" },
  "asOf": "2026-10-04T15:20:11.000Z",
  "limit": 10,
  "enrichment": { "source": "catalog:POST /api/v1/catalog/products/lookup", "status": "COMPLETE" },
  "mostAuctioned": [
    {
      "rank": 1,
      "productId": "7d6f0a9e-3c1b-4a55-9d31-0f2f6f6a1c11",
      "product": { "name": "Espada de hierro", "sku": "espada-de-hierro", "type": "ARMA", "imageUrl": "https://…" },
      "auctions": { "total": 14, "playerCredits": 11, "officialRealMoney": 3 }
    }
  ],
  "mostSold": [
    {
      "rank": 1,
      "productId": "7d6f0a9e-3c1b-4a55-9d31-0f2f6f6a1c11",
      "product": { "name": "Espada de hierro", "sku": "espada-de-hierro", "type": "ARMA", "imageUrl": "https://…" },
      "sales": { "total": 9, "byAuctionClose": 7, "byBuyNow": 2, "unit": "CREDITS" }
    }
  ]
}
```

Reglas: el **conteo es autoritativo de Auction**; el nombre es **enriquecimiento** de Catalog y **no puede hacer fallar** el endpoint. Si Catalog no responde: `enrichment.status = "UNAVAILABLE"` y `product: null`. Si Catalog responde pero omite un `productId`: `enrichment.status = "PARTIAL"` y ese ítem lleva `product: null` (el lookup omite inexistentes). Campos de `product` = **exactamente** los que existen en el DTO canónico (`name`, `sku`, `type`, `imageUrl`); **no hay `brand`**. `mostSold.sales` solo cuenta jugador (oficial nunca vende). Lookup en bloques ≤ 500 `references` (los `productId` UUID).

---

### 4.3 Precios promedio por moneda — `GET /api/v1/admin/auction-metrics/average-prices` *(Task HU-91.4)*

```json
{
  "definitionsVersion": "hu-91.v1",
  "period": { "from": "...", "to": "...", "timezone": "UTC", "bounds": "[from,to)" },
  "asOf": "2026-10-04T15:20:11.000Z",
  "credits": {
    "basis": "FINAL_SALE_PRICE",
    "salesCount": 63,
    "average": { "unit": "CREDITS", "amount": 142.38 },
    "median":  { "unit": "CREDITS", "amount": 120 },
    "min":     { "unit": "CREDITS", "amount": 5 },
    "max":     { "unit": "CREDITS", "amount": 900 },
    "byChannel": {
      "AUCTION_CLOSE": { "salesCount": 55, "average": { "unit": "CREDITS", "amount": 138.1 } },
      "BUY_NOW":       { "salesCount": 8,  "average": { "unit": "CREDITS", "amount": 171.75 } }
    },
    "listedMinimumBid": { "auctionsCount": 120, "average": { "unit": "CREDITS", "amount": 41.2 } }
  },
  "realMoney": {
    "basis": "LISTED_PRICE",
    "note": "Subasta oficial no tiene flujo de venta: se reporta precio de publicación, no de transacción.",
    "finalSalePrice": { "availability": "UNAVAILABLE", "reason": "OFFICIAL_AUCTION_HAS_NO_SALE_FLOW" },
    "byCurrency": [
      {
        "currency": "COP",
        "publishedCount": 9,
        "listedMinimumBid": {
          "average": { "unit": "REAL_MONEY", "currency": "COP", "amountMinor": 4500000 },
          "min":     { "unit": "REAL_MONEY", "currency": "COP", "amountMinor": 1000000 },
          "max":     { "unit": "REAL_MONEY", "currency": "COP", "amountMinor": 9000000 }
        },
        "listedBuyNow": { "count": 3, "average": { "unit": "REAL_MONEY", "currency": "COP", "amountMinor": 12000000 } }
      }
    ]
  }
}
```

Reglas: **no hay campo que combine** `credits` con `realMoney` ni entre monedas (CA-03). Redondeo: créditos a 2 decimales (half-up), dinero real a entero de unidad mínima. `salesCount=0` ⇒ promedios `null`. `byCurrency` solo incluye monedas con publicaciones; el orden es por `currency ASC`.

---

### 4.4 Usuarios activos y comisiones — `GET /api/v1/admin/auction-metrics/users-and-commissions` *(Task HU-91.5)*

Parámetros extra: `limit` (1–50, defecto 10).

```json
{
  "definitionsVersion": "hu-91.v1",
  "period": { "from": "...", "to": "...", "timezone": "UTC", "bounds": "[from,to)" },
  "asOf": "2026-10-04T15:20:11.000Z",
  "limit": 10,
  "activeUsers": {
    "definition": "DISTINCT_AUCTIONS_WITH_SELLER_BIDDER_OR_BUYER_ACTION",
    "totalActiveUsers": 87,
    "byRole": { "sellers": 31, "bidders": 70, "buyers": 12 },
    "top": [
      {
        "rank": 1,
        "playerId": "us-east-1:2f1c…",
        "activeAuctions": 18,
        "asSeller": 6,
        "asBidder": 11,
        "asBuyer": 1
      }
    ]
  },
  "commissions": {
    "scope": "PUBLICATION_FEE_ONLY",
    "unit": "CREDITS",
    "source": "AUCTION_LOCAL",
    "gross":    { "unit": "CREDITS", "amount": 210 },
    "refunded": { "unit": "CREDITS", "amount": 9 },
    "net":      { "unit": "CREDITS", "amount": 201 },
    "pendingRefunds": { "count": 1, "amount": { "unit": "CREDITS", "amount": 1.5 } },
    "byDuration": [
      { "durationHours": 24, "auctions": 80, "feePerAuction": 1, "gross": { "unit": "CREDITS", "amount": 80 } },
      { "durationHours": 48, "auctions": 40, "feePerAuction": 3, "gross": { "unit": "CREDITS", "amount": 120 } }
    ],
    "salesCommission": { "availability": "UNAVAILABLE", "reason": "NO_SALE_COMMISSION_DEFINED" },
    "realMoneyCommission": { "availability": "UNAVAILABLE", "reason": "OFFICIAL_AUCTION_HAS_NO_FEES" },
    "walletReconciliation": { "availability": "UNAVAILABLE", "reason": "WALLET_READ_ENDPOINT_NOT_AVAILABLE" }
  }
}
```

Reglas de privacidad: `playerId` es el identificador **opaco** (`sub`); **no** se devuelve correo, nombre ni saldo. Es un dato pseudónimo visible solo para admin (**decisión D-2 confirmada**, R-09); no se resuelve nombre en esta Task. `gross` ancla a `published_at`; `refunded` a `cancelled_at` con `wallet_refund_status='CONFIRMED'`; `pendingRefunds` = cancelaciones con estado `PENDING|RETRYABLE`. `net` puede ser negativo. `walletReconciliation` pasa a `AVAILABLE` solo si una Task posterior crea el endpoint de lectura en Wallet (R-03).

---

### 4.5 Tiempo de cierre y tendencias — `GET /api/v1/admin/auction-metrics/closing-time-and-trends` *(Task HU-91.6)*

Parámetro extra: `granularity` = `DAY` | `WEEK` | `MONTH` (defecto `DAY`; con span > 92 días y `DAY` ⇒ `400 INVALID_PARAMETER`).

```json
{
  "definitionsVersion": "hu-91.v1",
  "period": { "from": "...", "to": "...", "timezone": "UTC", "bounds": "[from,to)" },
  "asOf": "2026-10-04T15:20:11.000Z",
  "granularity": "WEEK",
  "closingTime": {
    "definition": "closed_at - published_at (playerAuctions CLOSED in period)",
    "unit": "SECONDS",
    "sampleSize": 100,
    "average": 118240,
    "median": 172800,
    "p90": 172800,
    "byCloseReason": {
      "EXPIRED_WITH_WINNER":   { "sampleSize": 55, "average": 172950 },
      "EXPIRED_WITHOUT_BIDS":  { "sampleSize": 37, "average": 172910 },
      "BUY_NOW":               { "sampleSize": 8,  "average": 9420 }
    },
    "settlementLagSeconds": { "sampleSize": 92, "average": 41, "p90": 118 },
    "officialAuctions": { "availability": "UNAVAILABLE", "reason": "OFFICIAL_AUCTION_HAS_NO_CLOSING_FLOW" }
  },
  "trends": {
    "bucketAnchors": {
      "published": "published_at",
      "closedWithWinner": "finished_at",
      "soldByBuyNow": "auction_buy_now_operations.completed_at",
      "closedWithoutBids": "finished_at",
      "cancelled": "cancelled_at"
    },
    "buckets": [
      {
        "bucketStart": "2026-09-28T00:00:00.000Z",
        "bucketEnd":   "2026-10-05T00:00:00.000Z",
        "playerAuctions": {
          "published": 28,
          "closedWithWinner": 12,
          "soldByBuyNow": 3,
          "closedWithoutBids": 9,
          "cancelled": 2,
          "successRate": 0.625,
          "averageClosingTimeSeconds": 121000
        },
        "officialAuctions": { "published": 3 }
      }
    ]
  }
}
```

Reglas: buckets contiguos y completos (con ceros y `successRate: null` / `averageClosingTimeSeconds: null` donde `closed = 0`). `WEEK` empieza lunes UTC. Un bucket parcial en los extremos se recorta al periodo pero conserva `bucketStart/End` completos. Cada conteo del bucket usa su ancla (`bucketAnchors`), de modo que `Σ buckets` coincide con los totales de §4.1 para el mismo periodo (invariante de prueba).

---

## 5. Cómo se garantiza CA-02 / CP-03 (no duplicar por joins o reintentos)

- Cada subasta es **una fila** en `auctions`; las operaciones idempotentes tienen unicidad por subasta (`auction_buy_now_operations_auction_uq`, `auction_publication_operations.auction_id` UNIQUE, `auction_cancellation_operations_auction_uq`) ⇒ un reintento con el mismo `operationId` **no crea otra fila** y no altera ningún conteo.
- Los rankings cuentan sobre `auctions` y solo se unen 1:1; **prohibido** `JOIN auction_bids` en agregados de subastas (multiplicaría filas). Las pujas solo entran por `COUNT(DISTINCT auction_id)` en actividad.
- Prueba de aceptación obligatoria para HU-91.2/91.5: insertar dos veces la misma operación (mismo `operation_id`) y verificar que el agregado no cambia.

---

## 6. Autorización (CA-06) — rol exacto

**Decisión:** se exige **`ADMINISTRATOR`**; `SUPER_ADMINISTRATOR` entra por jerarquía. **Denegados:** `PLAYER`, `MODERATOR`, `GAME_MASTER`, anónimo.

**Backend (Auction)** — mismo mecanismo ya implementado:

```ts
@AuthenticationRequired()                       // watchlist.controller.ts:35 — fail-closed aun con AUTH_MODE=disabled
@Roles(Role.Administrator)                      // roles.guard.ts: satisface() admite SUPER_ADMINISTRATOR
@Controller('v1/admin/auction-metrics')
export class AuctionMetricsController { /* GET … */ }
```

**Web** — mismo patrón de `features/admin/*` (y rutas de `routes.tsx`):

- Ruta `admin/auction-metrics` envuelta en `<RequireAdministrator>` (`src/app/RequireAdministrator.tsx` → `canViewAdminUsers` de `src/shared/rbac.ts`).
- Entrada en `ADMIN_NAVIGATION` con `requiredPrimaryRole: 'ADMINISTRATOR'`.
- Cliente `features/admin/auction-metrics/api.ts` con `httpClient.get`, mismo estilo que `features/admin/roles/api.ts`. La guarda de Web **no autoriza**: el 403 del backend manda.

**Por qué `ADMINISTRATOR` y no otro:**

| Opción | Evaluación |
| --- | --- |
| `MODERATOR` | Rol de Community para moderar comentarios (`COMMENT_MODERATION_PRIMARY_ROLES`); sin relación con métricas comerciales. |
| `GAME_MASTER` | Identidad comercial con *subject* configurado (`RolesGuard`, HU-66.1) y **fuera de la jerarquía administrativa**; permitiría ver métricas de toda la plataforma desde la cuenta que publica oficiales. |
| `SUPER_ADMINISTRATOR` solamente | Excesivo: `admin/roles` (gestión de cuentas) lo exige, pero las demás superficies de datos de negocio (`admin/products`, `admin/banners`) piden `ADMINISTRATOR`. |
| **`ADMINISTRATOR`** | Coincide con Catalog (`@Roles(Role.Administrator)` en `GET /v1/admin/products`) y con las rutas Web equivalentes. |

**MFA:** **no se exige** en estas lecturas, igual que los `GET` administrativos de Catalog (`@RequiresMfaEvidence()` solo en mutaciones). Auction **no tiene** verificador de MFA; exigirlo sería trabajo nuevo (R-10). Es una decisión a confirmar con PO/seguridad.

**Privacidad (CA-06):** respuesta `403` con cuerpo genérico `{ statusCode:403, code, message }` — sin conteos, sin ids. Solo agregados; el único identificador es `playerId` opaco (§4.4, D-2).

**Contraste con ADR-014 (leído completo, `Proposed`):** sin conflicto con D-2. El ADR gobierna consentimiento (Dec. 1), frontera exportable/no portable (Dec. 2), identidad del titular por `VerifiedIdentity.subject` (Dec. 3), portabilidad (Dec. 4) y derecho al olvido acotado a Account (Dec. 5-6). Esta superficie es una lectura administrativa que no acepta ningún id del cliente (cumple Dec. 3) y no crea una base de privacidad (Dec. 6). Matiz a vigilar, no contradicción: el requisito de Dec. 5 de que un `subject` fuera de Account no permita reconstruir la identidad "mediante el acceso ordinario" se mantiene porque el endpoint no devuelve nombre/correo y exige `ADMINISTRATOR`.

---

## 7. Plan de implementación sugerido (insumo para Tasks 91.2–91.6)

1. **Infra común (en 91.2):** `AuctionMetricsRepositoryPort` + adaptador Postgres de **solo lectura** (patrón `AuctionActivityRepositoryPort` de HU-89) + adaptador en memoria; transacción `READ ONLY`; DTOs con validación de periodo.
2. **Migración nueva `019`** (la última en `develop` es `018`): índices para los filtros por periodo — hoy **no existe ninguno** sobre `auctions(published_at)`, `auctions(finished_at)`, `auctions(cancelled_at)`, `auction_bids(placed_at)` ni `auction_buy_now_operations(completed_at)` (`createIndex` revisados en migraciones `001`–`018`). Parciales: `where price_kind='CREDITS'`.
3. **91.3:** reutilizar `CatalogProductLookupClient` (ya existe; **ampliar el parser** para `imageUrl`, hoy solo exige `productId/sku/name/type`). **No hay que crear endpoint en Catalog.**
4. **91.5:** calcular comisiones desde Auction. Cualquier endpoint de Wallet es una Task **aparte** y opcional (R-03).
5. **Web (tras 91.6):** pantalla `admin/auction-metrics` con `RequireAdministrator`; estados de carga/vacío/error; respetar `availability: "UNAVAILABLE"` mostrando "No disponible" (sin cifras).

---

## 8. Riesgos detectados (huecos entre lo que HU-91 asume y lo que el código soporta)

> Severidad: **A**lta = rompe el diseño si no se decide antes · **M**edia = produce cifras erróneas silenciosas · **B**aja = a vigilar.

| ID | Sev. | Hueco | Evidencia | Mitigación propuesta |
| --- | --- | --- | --- | --- |
| **R-01** | A | **HU-91 habla de tasa de éxito / precios / tiempo de cierre para "publicaciones oficiales en moneda real" (CA-03), pero las subastas oficiales no tienen cierre, pujas, venta ni compra inmediata**; quedan `ACTIVE` pasada su `closes_at`. | `OfficialAuction.ts` (sin `finish()`); `PostgresAuctionRepository.ts` `:354`, `:966`, `:1235` (todo filtra `price_kind='CREDITS'`); `findAuction` devuelve `null` para `REAL_MONEY`. | Contrato con `availability:"UNAVAILABLE"` (§4). **RESUELTO (D-1):** confirmado que oficiales solo reportan volumen y precio de lista; los `UNAVAILABLE` son permanentes. Un flujo de cierre oficial está **fuera de alcance de HU-91** y no se diseña aquí. |
| **R-02** | A | **`SOLD` (compra inmediata) rompe agregaciones ingenuas**: `finished_at`, `winner_id`, `final_amount_credits` son `NULL`; `closes_at` se sobrescribe con el instante de compra. `AVG(final_amount_credits)` ignora toda compra inmediata. | `closeByBuyNow` (`PostgresAuctionRepository.ts:1420-1560`): solo `status` y `closes_at`; datos en `auction_buy_now_operations`. | Fórmulas §3 ya usan `auction_buy_now_operations`. Pruebas con datos mixtos `FINISHED`+`SOLD` obligatorias. |
| **R-03** | A | **Wallet no expone ninguna lectura de comisiones**, `wallet_ledger` es de batallas, y la "cuenta de sistema para comisiones" **no existe** en el código (solo en `docs/architecture.md`, *previsto*). No hay `auction_id` en las tablas de comisión. HU-91.5 se planteó dependiendo de Wallet. | `Nexus-Battle-Wallet:schema.ts`, migraciones `001`/`005`/`007`; controladores solo `POST` internos + `GET balance` + `GET /v1/wallet/me`. | Comisiones calculadas **solo desde Auction** (§3.4). Wallet queda como reconciliación futura (`walletReconciliation: UNAVAILABLE`). No bloquear 91.5 por Wallet. |
| **R-04** | M | Si algún día se lee Wallet: `status='REFUNDED'` también tras reembolso **parcial**; solicitudes duplicadas con otro `operationId` insertan fila en `…_fee_refunds` **sin acreditar**. `SUM(refunds.amount)` sobrecuenta. | `PostgresAuctionPublicationFeeRepository.ts` (`refund`, rama `fee.status === 'REFUNDED'`). | Para conciliar, usar solo el primer refund por `charge_id` o `charged − saldo aplicado`; documentarlo en la Task de Wallet. |
| **R-05** | M | **Promedio "en dinero real" solo puede ser precio de lista**, no de transacción: Auction no registra ventas en dinero real. Importes `integer` (int4) en unidad mínima. | `schema.ts` `minimum_bid_amount_minor`/`buy_now_amount_minor`; sin flujo de venta oficial (R-01). | Etiquetar `basis:"LISTED_PRICE"`; agrupar por `currency`. **RESUELTO (D-1):** semántica confirmada. |
| **R-06** | M | **Sin índices** por columnas de periodo ⇒ escaneos completos al crecer el volumen. | `createIndex` en migraciones `001`–`018`: ninguno sobre `published_at`, `finished_at`, `cancelled_at`, `placed_at` de forma aislada, ni `completed_at` de buy-now. | Migración `019` (§7.2). Medir con `EXPLAIN` sobre datos de prueba en 91.2. |
| **R-07** | A | **`main` y `develop` divergen** y producción (`main`) **no tiene** `CANCELLED`/`cancelled_at`/migración `017` ni la migración `007` de Wallet. Un endpoint que consulte `cancelled_at` rompe en `main` si se promueve sin las migraciones. Es la misma clase de fallo que en el despliegue de HU-69. | `Auction origin/main` termina en migración `016`; `git grep CANCELLED origin/main` = 0 archivos; Wallet `origin/main` sin `007`. | Gate de despliegue: promover HU-89/HU-90 (con migraciones `017`/`018`) **antes** que HU-91.2; añadir prueba de arranque que verifique el esquema. |
| **R-08** | M | **Catalog: no existe "marca"; "categoría" solo existe en el modelo legado**; `GET /api/products/:sku` (legado, solo `PUBLISHED`, clave `sku` kebab) **no resuelve** los `product_id` de Auction (UUID canónico). Se asumía un endpoint "futuro" en bloque: **ya existe** el lookup público (≤500 refs). | `products.controller.ts`/`products.dto.ts`; `canonical-products.controller.ts`; `git grep -i marca` = 0 conceptos; `CatalogProductPolicyClient.ts:52`. | Usar `POST /api/v1/catalog/products/lookup`; mostrar `type` como "categoría"; **no** pedir `brand`. Documentar en 91.3 que el lookup es público y sin HMAC. |
| **R-09** | M | **Privacidad:** el ranking de usuarios necesita un identificador; `playerId` (`sub`) es pseudónimo pero identifica a una persona. | ADR-014 (`Nexus-Battle-Infrastructure/docs/adr/ADR-014-privacy-data-governance.md`, **leído completo**, estado `Proposed`): ninguna decisión prohíbe exponer el `sub` a un administrador autenticado. Matiz: Decisión 5 pide que un `subject` opaco fuera de Account "no debe permitir reconstruir directamente la identidad personal … mediante el acceso ordinario al sistema"; Decisión 3 prohíbe usar ids enviados por el cliente como fuente de autorización (aquí no se usa ninguno: `playerId` solo sale en la respuesta). `portability-contract-v1.md` clasifica el `sub` como no exportable **al titular** (HU-45), no como dato oculto al administrador. | **RESUELTO (D-2):** `sub` opaco tal cual, solo tras el guard de §6; sin nombre/correo/saldo. Si se necesita nombre a futuro, Task aparte con el patrón `fetchAccountDisplayName` (`features/admin/comments/api.ts`; hoy exige `MODERATOR`, verificar que un Administrador pasa). Nota residual: un administrador con acceso a Account podría cruzar el `sub` con una cuenta; ADR-014 sigue `Proposed` (ver §6). |
| **R-10** | B | **MFA:** Auction no tiene verificador de segundo factor; si PO lo exige para métricas, es trabajo nuevo. | `git grep -i mfa` en `Auction/src` = 0; Catalog tiene `AccountMfaEvidenceClient`. | Decisión explícita en la aprobación (propuesto: no exigir, como los `GET` admin de Catalog). |
| **R-11** | M | **`AUTH_MODE=disabled` concede todos los roles** (incl. `ADMINISTRATOR`) con subject `anonymous`; un endpoint admin sin `@AuthenticationRequired()` quedaría abierto en dev. Las rutas `me/*` de HU-89 **no** lo usan (solo `watchlist.controller.ts`). | `anonymous.guard.ts`; `git grep AuthenticationRequired` = solo watchlist. | Aplicar `@AuthenticationRequired()` al controlador de métricas (§6). *(Observación colateral: HU-89 `me/*` no lo aplica; fuera del alcance de HU-91.)* |
| **R-12** | B | **Colisión de rutas:** `GET v1/auctions/:auctionId` captura cualquier segmento. | `auction.controller.ts:466`. | Controlador propio `v1/admin/auction-metrics` (§4). |
| **R-13** | M | **Inconsistencia temporal:** estado `ACTIVE` con `closes_at` vencido hasta que el scheduler liquida; y tendencias cuyo cierre ocurre en bucket distinto al de publicación. | `findSettlementCandidates` (`closes_at <= now`, `status in ('ACTIVE','FINISHED')`). | `awaitingClosure` explícito; anclas por bucket documentadas (§4.5); lectura `READ ONLY` en un único snapshot. |
| **R-14** | B | **Pujas automáticas indistinguibles**: `auction_bids` no tiene bandera de origen. | `schema.ts` `AuctionBidTable`. | Actividad por **subastas distintas**, no por pujas (§3.2). |
| **R-15** | B | **Observación (no bloqueante):** el índice único `auctions_active_product_uq (product_id) WHERE status='ACTIVE'` implica **como máximo una subasta activa por `productId` de Catalog en toda la plataforma**. Si `product_id` es el id de catálogo (confirmado por `CatalogProductPolicyClient`), productos con tiraje > 1 no podrían estar en subasta a la vez por distintos jugadores. | `001-create-auction-publication.ts:36`. | Preguntar a dueños de Auction/Inventory si es intencional. Afecta cuán "grande" será el ranking `mostAuctioned`, no la corrección de las fórmulas. |
| **R-16** | B | **Observación colateral (HU-89, no HU-91):** `listBidParticipations` deriva `WON/LOST` de `winner_id`; en `SOLD` `winner_id` es `NULL`, así que un comprador por compra inmediata que antes pujó aparece como `LOST`. | `PostgresAuctionActivityRepository.ts` (`participationStatus`) + `closeByBuyNow`. | Reportar a HU-89; no se corrige aquí. |
| **R-17** | B | **Sin aprobación formal:** el checklist de HU-91 tiene sin marcar «Fórmulas exactas… confirmadas por PO/Developers» y Story Points. | #522. | Este documento es **propuesta**; la Task #576 exige aprobación de PO y revisión de los dueños de Auction, Catalog y Wallet. |

---

## 9. Checklist de verificación pendiente para el cierre de la Task

- [ ] PO aprueba §3 (fórmulas) y las decisiones de casos borde.
- [x] R-01/R-05 resuelto (D-1): oficial solo volumen y precio de lista; `successRate`, `closingTime` y `finalSalePrice` `UNAVAILABLE` permanentes; sin flujo de cierre oficial en HU-91.
- [ ] Dueño de Auction revisa §4 y migración de índices (R-06).
- [ ] Dueño de Catalog confirma que el lookup público es el contrato a usar y que no se agregará "marca" (R-08).
- [ ] Dueño de Wallet confirma que 91.5 no depende de Wallet y que la conciliación es opcional (R-03/R-04).
- [x] R-09 resuelto (D-2): `playerId` = `sub` opaco tras `@Roles(Role.Administrator)` + `@AuthenticationRequired()`; ADR-014 revisado sin conflicto.
- [ ] Plataforma/seguridad confirma rol `ADMINISTRATOR` y ausencia de MFA (§6, R-10).
- [ ] Plan de promoción `develop → main` con migraciones `017`/`018` antes de HU-91.2 (R-07).
- [ ] Documento enlazado en #576 *(solo cuando se autorice subirlo)*.
