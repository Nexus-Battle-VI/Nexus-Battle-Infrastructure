# Smoke local de ecommerce entre servicios

`ecommerce-smoke.cjs` ejecuta Catalog, Commerce, Player-Inventory y la entrada de compras de Notifications sobre HTTP local. Usa MongoDB replica set y PostgreSQL reales; crea una base aislada por servicio con sufijo UUID y las elimina al terminar. No altera los datos de las aplicaciones ni detiene los motores compartidos.

El script espera clones hermanos:

```text
directorio/
  Nexus-Battle-Catalog/
  Nexus-Battle-Commerce/
  Nexus-Battle-Player-Inventory/
  Nexus-Battle-Notifications/
  Nexus-Battle-Infrastructure/
```

Preparar dependencias con `npm ci` en los cuatro servicios y compilar Notifications con `npm run build`. Los otros tres servicios se cargan desde sus fuentes TypeScript mediante el compilador ya instalado en Commerce; esto permite ejecutar el ensayo durante desarrollo. No sustituye los gates de tipos, compilacion, lint ni CI de cada repositorio.

## Ejecucion

Requiere Node24, Mongo8 en replica set y PostgreSQL con permiso para crear bases de prueba. Todas las conexiones de motores deben apuntar a loopback; el script rechaza hosts externos.

Desde Infrastructure, en PowerShell:

```powershell
$env:MONGO_TEST_URI = 'mongodb://127.0.0.1:27028/?replicaSet=nexus-test-rs'
$env:PG_TEST_URL = 'postgresql://nexus_test:nexus_test_only@127.0.0.1:55432/postgres'
node scripts/ecommerce-smoke.cjs
```

Esas credenciales son exclusivamente las del motor local de pruebas. Si los clones estan en otro directorio, definir `ECOMMERCE_REPOS_ROOT`. `SMOKE_OUTPUT` permite elegir el archivo JSON de resultados; por defecto se guarda `ecommerce-smoke-results.json` en el directorio que contiene los clones. Cada etapa aprobada imprime PASS; cualquier fallo o error de limpieza termina con codigo1.

## Recorrido

1. Ejecuta migraciones en bases nuevas y crea dos productos premium mediante el caso de uso canonico de Catalog, incluyendo su transaccion, auditoria y outbox.
2. Comprueba vitrina publica y busqueda por `query`, identidad requerida en Commerce y aislamiento del pedido entre dos sujetos.
3. Agrega productos por UUID, guarda el carrito, modifica el borrador, recrea Commerce y restaura los productos, metadatos, cantidades y precio desde PostgreSQL.
4. Paga una compra simulada: reserva el lote en Catalog, entrega todo a Inventory, confirma stock y pedido, y crea el outbox de correo. Comprueba cantidades e inventario enriquecido desde Catalog.
5. Envia el correo mediante el servidor HMAC real de Notifications y su inbox Mongo. El adaptador final captura el mensaje en memoria; comprueba destinatario registrado, productos y total.
6. Repite pago y correo tras recrear Notifications y comprueba ausencia de duplicados. Abre una segunda compra y comprueba un identificador nuevo y unidades acumuladas.
7. Un proxy local pierde la respuesta de Inventory despues del commit real. Commerce conserva RESERVED; GETpayment no produce efectos. Tras recrear Commerce, recupera la misma operacion sin volver a entregar. Una caida local de Notifications conserva el outbox hasta su recuperacion.
8. Un inventario lleno rechaza el lote duraderamente. Commerce libera la reserva y devuelve DRAFT. Aun despues de liberar espacio, repetir el grant rechazado conserva422; un nuevo intento de compra puede completarse.

Las rutas internas usan el contrato HMAC real, con secreto aleatorio por ejecucion. Los proxies de fallo conservan metodo, ruta, cuerpo y cabeceras para que cada servicio verifique la firma original. El scheduler automatico de Commerce se sustituye solo en el modulo de prueba para fijar los puntos de interrupcion; se ejecuta su coordinador real con `recover()`.

## Limites de la evidencia

- El puerto verificador JWT se sustituye por un mapa explicito de tokens de prueba. Se ejercitan guards, permisos y ownership, pero no la criptografia de Cognito ni una sesion real.
- El receptor local de Account exige el Bearer de esa identidad y devuelve un correo fixture. No consulta una cuenta de produccion.
- El alta usa el caso de uso canonico real; el navegador administrativo y la evidencia MFA no forman parte de este ensayo.
- Se verifican referencias y metadatos de imagen. No se descargan imagenes ni se prueba S3/CDN.
- El correo se captura localmente: no se contacta SMTP, SES ni destinatarios externos. No se verifica entregabilidad real ni se elimina la ventana de duplicado entre envio del proveedor y confirmacion SENT.
- Los servicios se ejecutan desde los clones. El ensayo no arranca imagenes Docker ni valida los permisos de las credenciales de cada servicio en un despliegue.
- El JSON registra SHAs, si los clones tienen cambios locales y huellas SHA256 de las fuentes cargadas (o `dist` en Notifications) al inicio y al final. Para evidencia de un release, ejecutar cuando los clones ya esten en los commits definitivos y comprobar que no cambiaron durante el ensayo.

La limpieza recorre solo bases `test_smoke_*_<UUID>` creadas por esa ejecucion. Los motores, las otras bases y los repositorios permanecen disponibles.
