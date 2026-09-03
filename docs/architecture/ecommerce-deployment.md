# Despliegue de la integración E-commerce

Este procedimiento acompaña las ramas de integración del 3 de septiembre de
2026. La ejecución local no implica que estas versiones estén en producción.
Este cambio sigue `codex/*` → PR a `develop` → revisión CodeOwner → promoción a
`main` y publicación GHCR, conforme al [workflow de ramas vigente](../../.github/workflows/flujo-de-ramas.yml).
La guía histórica `branching-and-release.md` todavía describe trunk-based y
requiere una actualización de gobierno separada.
No forzar las protecciones ni reemplazar volúmenes para aplicar migraciones.

## Preparación

1. Registrar SHA de cada imagen actual y copia verificable de las bases.
2. Comprobar Mongo 8 como replica set con primario disponible. Las reservas y
   entregas usan transacciones. El compose de referencia incluye keyfile y
   bootstrap de `rs0`; el nodo data existente conserva su configuración.
3. Provisionar `notifications` en Mongo si el volumen ya existía. El script de
   inicialización solo se ejecuta en volúmenes nuevos. Con sesión administrativa
   local y `DB_PASSWORD` ya definido, este JavaScript de mongosh crea únicamente
   el usuario ausente y no cambia credenciales existentes:

   ```javascript
   const target = db.getSiblingDB('notifications')
   if (!target.getUser('notifications')) {
     if (!process.env.DB_PASSWORD) throw new Error('Falta DB_PASSWORD')
     target.createUser({
       user: 'notifications', pwd: process.env.DB_PASSWORD,
       roles: [{ role: 'readWrite', db: 'notifications' }, { role: 'dbAdmin', db: 'notifications' }],
     })
   }
   ```

4. Configurar la misma clave `INTERNAL_SERVICE_AUTH_SECRET` en los cinco servicios
   que participan en los contratos internos. Conservarla fuera de Git y de logs.
   Para Web público mantener JWT/Cognito y los valores `VITE_` compilados del entorno.
5. Antes de la migración Commerce, revisar carritos antiguos duplicados:

   ```sql
   SELECT customer_id, count(*) AS live_carts, array_agg(id ORDER BY created_at) AS orders
   FROM orders WHERE status = 'DRAFT'
   GROUP BY customer_id HAVING count(*) > 1;
   ```

   La migración rechaza duplicados; no borra pedidos ni elige uno arbitrariamente.
   Resolver cada caso conservando su información y con una decisión explícita
   sobre cuál sigue activo. No ejecutar cancelaciones masivas automáticas.

## Orden de publicación

1. Parar las escrituras administrativas de Catalog durante el backfill e impedir
   que un binario viejo reemplace documentos ya indexados. Ejecutar sus migraciones
   hasta `011-storefront-search` y arrancar la imagen compatible. Verificar la
   colección canónica, búsqueda, reservas y readiness antes de seguir.
2. Ejecutar migraciones Inventory hasta `003-purchase-grants` (incluye
   `002-hero-loadouts`, ya presente en develop). Arrancar Inventory con clave HMAC.
3. Migrar Account (`hu57-profile-country`) y arrancar su imagen. Las cuentas
   existentes conservan país null hasta que su titular lo indique.
4. Arrancar Notifications con `PURCHASE_HTTP_ENABLED=true`, puerto 3003,
   `PURCHASE_INBOX_DRIVER=mongo`, `MONGO_URL`, `MONGO_DB_NAME=notifications` y clave
   interna. Los listeners anteriores de salud y recuperación de cuenta permanecen.
5. Detener Commerce antiguo, ejecutar `004-integrated-purchases`, arrancar
   Commerce con PostgreSQL y `COMMERCE_INTEGRATION_MODE=http`. URLs internas:
   Catalog 3003, Inventory 3002, Notifications 3003, Account 3000 por nombre del
   servicio. Verificar `/api/health/ready`; un 503 impide continuar el rollout.
6. Aplicar el cambio CORS del bucket de productos con el origen Web real mediante
   revisión del plan Terraform. `terraform validate` no ejecuta este cambio.
7. Instalar Caddy con rutas `/api/wishlist*`, `/api/saved-cart*`, `/api/orders*`
   y Catalog canónico; `/api/internal*` responde 404 desde el origen público.
   Publicar Web al final. Los endpoints internos no exigen puertos públicos.

Cambiar las plantillas Terraform no actualiza por sí solo un `.env`/compose de
una instancia existente. Copiar/aplicar el cambio por el mecanismo operativo
del entorno y confirmar las variables efectivamente cargadas. Conservar las
opciones existentes de S3, Cognito y notificaciones del despliegue.

## Verificación de aceptación

Ejecutar [el smoke](../../scripts/ecommerce-smoke.md) con servicios actuales y
bases aisladas. Después, en el entorno desplegado y con cuentas de prueba,
crear un producto canónico publicable, verificar imagen, búsqueda, detalle,
wishlist, persistencia del carrito al cambiar de sesión, compra simulada,
inventario y correo. Probar dos cuentas, agotamiento, carrito modificado en
otra pestaña y una segunda compra. Registrar SHA, resultados y evidencia sin
tarjetas, tokens ni credenciales. La UI requiere además revisión visual a
1360×768 y pruebas Chrome/Edge/Firefox de las Tasks; el smoke de API no las sustituye.

## Recuperación de un despliegue fallido

La migración Commerce 004 es forward-only: su `down` falla deliberadamente.
Un rollback destructivo perdería ledger, outbox y referencias UUID. Ante un
fallo, retirar temporalmente Web/checkout del tráfico, conservar bases y
ejecutar una corrección compatible hacia adelante. No volver al Commerce
antiguo sobre datos con compras integradas ni borrar operaciones pendientes.
Una restauración completa de copias necesita reconciliar también Catalog,
Inventory y Notifications; no restaurar solo una base tras entregar compras.

La cola conserva fallos temporales y reintenta. No marcar una compra como
fallida por timeout ni liberar su stock manualmente sin consultar el ledger
de entrega. Los correos pueden esperar sin impedir que termine una compra.

Moneda regional y promociones siguen pendientes de la decisión comercial
descrita en [el contrato](../contracts/ecommerce-integration-v1.md).
