# Integración de E-commerce con Catalog canónico

Implementación propuesta para HU-56–61 en las ramas `codex/ecommerce-*`.
Este documento describe sus contratos; no declara despliegue ni aceptación del Product Owner.
Se mantiene la propiedad de datos de ADR-005, los puertos HTTP de ADR-006 y las fronteras de ADR-013.

## Lecturas públicas y autenticadas

`GET /api/v1/catalog/products` devuelve `{items, page, pageSize:16, total}`.
Admite `query`, `type`, `minPrice`, `maxPrice`, `currency` y `page`.
Los filtros se combinan con AND; la búsqueda literal no distingue mayúsculas
y cubre nombre/descripción. Los importes son unidades menores y un intervalo
de precio requiere `currency`. Los parámetros inválidos producen 400.
Solo aparecen productos ACTIVE; stock cero sigue visible y `availableUnits:null`
representa disponibilidad infinita. `GET /api/v1/catalog/products/:reference`
admite UUID canónico o SKU comercial. El UUID identifica carrito y compras;
el SKU y nombre se conservan como presentación.

Las imágenes pueden requerir JWT en Catalog y redirigir a una URL S3 temporal.
Web descarga el recurso autenticado y muestra un object URL; S3 permite GET/HEAD
desde el origen configurado mediante CORS, y POST para la carga firmada del
Web administrativo (catalog-product-assets-v1). El bucket sigue siendo privado.

`POST /api/orders/cart` obtiene o crea el único carrito DRAFT/PROCESSING del titular.
Las rutas `/api/orders`, `/api/wishlist` y `/api/saved-cart` usan la identidad del JWT.
Una petición nunca decide el propietario enviando otro identificador.
La restauración del carrito guardado valida el conjunto antes de sustituir el activo.
Los precios ya pactados se conservan; para modificar/restaurar una línea cuyo
precio vigente cambió se pide retirarla y añadirla nuevamente.

`POST /api/orders/:id/payment` recibe los cuatro campos no vacíos del formulario
de pago simulado y opcionalmente `expectedVersion`. Devuelve `status: COMPLETED`
o `PROCESSING`, pedido, referencia simulada, tarjeta enmascarada y
`realMoneyMoved:false`. No hay cargos financieros. No se guardan tarjeta, CVV,
fecha, nombre del titular ni token. `GET /api/orders/:id/payment` consulta el
resultado; no vuelve a ejecutar el pago. La confirmación directa del pedido
responde 409 para impedir saltarse la entrega.

## Elegibilidad de comercialización premium

Fuente funcional: PDF §7.2.2 (productos premium) y aclaración del PO (2026-09-24): `ITEM` y `EPICA` quedan
fuera de E-commerce (siguen existiendo en Catalog/Player-Inventory/Missions; la épica se obtiene por
Misiones/Máster, no por compra). Un producto es elegible para el flujo de compra premium cuando, todo junto:

```text
premium == true
type in {HEROE, HABILIDAD, ARMA, ARMADURA}     // nunca ITEM ni EPICA
lifecycleStatus == ACTIVE
realMoneyPrice existe y realMoneyPrice.amount > 0
availableUnits es null (infinito) o > 0
```

**La autoridad de esta regla vive en Commerce, no en Catalog ni en Web.** Commerce ya recibe `type` en la
misma respuesta de `productOf()`/`priceOf()` que usa para fijar el precio — no hace falta un campo derivado
nuevo (`ecommerceEligible` o similar) en Catalog, ni un endpoint adicional: sería una segunda fuente de
verdad de la misma regla. Commerce aplica esta política al agregar/modificar líneas de carrito, al pagar y
al restaurar un carrito guardado; rechaza `ITEM`/`EPICA`, no-premium, suspendido y agotado aunque se invoque
la API directamente, sin depender de que Web los oculte.

Web consume la oferta ya elegible — puede pedir el listado con los filtros que `GET /api/v1/catalog/products`
ya admite (`type`, `currency`), y si ese endpoint no filtra por `premium`, Web omite del catálogo comercial
(no solo deshabilita) los productos que el propio listado ya le indica como no premium/no disponibles,
usando los campos que ya recibe por producto. Esto es presentación sobre datos ya autoritativos, no una
segunda implementación de la regla de negocio: la autoridad de compra sigue siendo exclusivamente Commerce.

**Moneda:** esta regla no limita el sistema a COP. El PDF contempla COP/USD/EUR según contexto geográfico
(ver «Monedas y promociones pendientes» más abajo) y Commerce ya acepta las tres para el carrito. Este
trabajo garantiza que el flujo premium en COP funcione de extremo a extremo (añadir, pagar, total en COP,
precio siempre server-side); no restringe ni rompe USD/EUR donde ya funcionaban.

## Comandos internos

Todas estas rutas quedan fuera del proxy público y exigen HMAC del servicio
`commerce`. Cabeceras: `x-internal-service`, `x-internal-timestamp` en milisegundos
y `x-internal-signature`. Los adaptadores usan la misma serialización canónica
y firma que el contrato interno existente; el cuerpo completo queda firmado.

| Servicio / ruta POST | Cuerpo | Resultado |
| --- | --- | --- |
| Catalog `/api/internal/v1/catalog/reservations` | `reservationId`, `playerId`, `lines:[{productId,quantity}]` | Reserva atómica de todo el lote; stock finito se descuenta una vez |
| Catalog `/api/internal/v1/catalog/reservations/:id/confirmation` | `playerId` | Confirma la reserva; no descuenta nuevamente |
| Catalog `/api/internal/v1/catalog/reservations/:id/release` | `playerId` | Libera únicamente una reserva aún RESERVED |
| Inventory `/api/internal/v1/inventory/grants` | `operationId`, `playerId`, `items:[{productId,quantity}]` | Entrega atómica y durable; no modifica Catalog |
| Notifications `/api/internal/v1/notifications/purchases` | `notificationId`, `orderId`, `recipient`, `items:[{productId,name,quantity,unitPrice}]`, `currency`, `total` | Confirma SENT después del envío; conserva deduplicación en Mongo |

Los identificadores de operación son UUID; reutilizar uno con distinto contenido
produce conflicto. Un rechazo conocido de Catalog lleva `RESERVATION_REJECTED`
(404/409), y el de Inventory `INVENTORY_REJECTED` (422). Estos rechazos se guardan
antes de responder y permanecen iguales aunque después se reponga stock o se
libere espacio. Una compra nueva necesita un intento nuevo. Un timeout, 5xx o
un conflicto de huella no demuestra ausencia de efectos.

## Recuperación

Commerce guarda en PostgreSQL el intento y congela la versión del carrito.
Secuencia: reservar lote → entregar lote → confirmar reserva → confirmar pedido
y crear outbox en una transacción local. Se recupera desde el último estado
durable tras un reinicio. Una entrega incierta se reproduce con el mismo ID;
no se compensa a ciegas. Solo un rechazo definitivo de Inventory permite liberar
reserva y devolver el carrito a DRAFT. No se cancelan pedidos PROCESSING/CONFIRMED.

El trabajador consulta intentos y correos vencidos en lotes de 50 cada dos segundos.
Cada intento avanza su `next_attempt_at`, por lo que 50 fallos persistentes no
impiden procesar el número 51. Los errores de correo no repiten la compra.
El correo registrado se obtiene de Account `/api/accounts/me` reenviando el JWT
de la petición; se conserva solo el destinatario, no el testimonio.

Notifications deduplica envíos confirmados. Existe una ventana residual entre
la aceptación SMTP/SES y la persistencia de SENT: una caída en ese punto puede
repetir un correo. No se promete exactamente un envío con un proveedor sin
idempotencia. La entrega al inventario sí tiene ledger transaccional.

## Monedas y promociones pendientes

El usuario indicó que la moneda debe derivarse del país del perfil. Account
añade `countryCode` ISO alpha-2 nullable y Web permite editarlo, sin atribuir un
país por IP o idioma. Catalog todavía publica un precio con una moneda.
Falta acordar conversión y fuente de tasas o precios separados por moneda.
No se inventan tasas ni porcentajes: promociones, vigencia y precio anterior
necesitan una regla comercial y datos de Catalog antes de cerrar HU-57.

## Despliegue y comprobación

Ver [orden de despliegue](../architecture/ecommerce-deployment.md) y
[smoke reproducible](../../scripts/ecommerce-smoke.md). Cada PR referencia la
Task correspondiente de Management; las HU padre permanecen abiertas hasta
revisión, integración y aceptación completas.
