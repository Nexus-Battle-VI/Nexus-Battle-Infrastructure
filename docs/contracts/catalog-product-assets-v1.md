# Contrato propuesto — Recursos visuales de Producto v1

- **Estado:** Proposed; depende de ADR-016 y EN-027.3 #283.
- **Owner:** Catalog.
- **Consumidor de carga:** Web administrativo.
- **Almacén:** S3 privado operado por Infrastructure.
- **Autenticación:** JWT + rol `ADMINISTRATOR|SUPER_ADMINISTRATOR` + evidencia
  TOTP vigente consultada en Account por el `jti` del access token.

Este contrato complementa `catalog-product-v1.openapi.yaml`. No reemplaza
`imageUrl`: define cómo se obtiene una referencia canónica antes de crear un
Producto.

## Invariantes

- El cliente nunca elige `productId` ni la clave S3; reenvía únicamente los
  campos opacos firmados por Catalog y nunca recibe credenciales AWS permanentes.
- `assetId` es UUID generado por Catalog.
- `imageUrl` es una URL estable del mismo origen; nunca es una URL S3 firmada.
- Una intención solo sirve para una clave, tamaño, MIME y checksum.
- Las URL firmadas vencen en diez minutos para escritura y cinco para lectura.
- Las claves finales son inmutables y contienen un hash.
- Una referencia externa o no finalizada se rechaza.
- La respuesta temporal puede revelar el endpoint S3 requerido para la carga
  directa; nunca expone ARN, claves AWS ni secretos permanentes. Política, firma
  y credenciales temporales se tratan como secretos efímeros y no se registran.

## 1. Crear intención de carga

```http
POST /api/v1/admin/product-assets/uploads
Authorization: Bearer <access-token>
Content-Type: application/json
```

```json
{
  "purpose": "PRIMARY_IMAGE",
  "contentType": "image/webp",
  "contentLength": 245760,
  "checksumSha256": "b64:ZHVtbXktc2hhMjU2LWVqZW1wbG8="
}
```

Respuesta `201 Created`:

```json
{
  "assetId": "f293ce6b-98e9-41da-99ef-0ad4e3a95120",
  "upload": {
    "method": "POST",
    "url": "https://<bucket-endpoint-redacted>",
    "fields": {
      "key": "staging/f293ce6b-98e9-41da-99ef-0ad4e3a95120",
      "Content-Type": "image/webp",
      "x-amz-checksum-sha256": "ZHVtbXktc2hhMjU2LWVqZW1wbG8=",
      "policy": "<redacted>",
      "x-amz-algorithm": "AWS4-HMAC-SHA256",
      "x-amz-credential": "<redacted>",
      "x-amz-date": "20260902T200000Z",
      "x-amz-signature": "<redacted>"
    },
    "expiresAt": "2026-09-02T20:10:00Z"
  }
}
```

El formulario firmado es una autorización temporal. Su endpoint puede ser
visible para permitir la carga directa, pero la política, firma y campos de
autorización no deben registrarse ni enviarse a observabilidad. La política
incluye `content-length-range` de 1 byte a 5 MiB y coincidencia exacta de clave,
MIME y checksum.

Respuestas:

| Código | Condición |
| --- | --- |
| `400` | forma básica o campo desconocido |
| `401` | JWT ausente/inválido |
| `403` | rol o TOTP insuficiente |
| `422` | MIME, tamaño o checksum no admitido |
| `503` | no puede generarse la intención o comprobarse MFA |

## 2. Cargar directamente

El navegador construye un `multipart/form-data` contra `upload.url`, añade cada
par de `upload.fields` sin alterarlo y agrega el archivo en el campo `file`.
S3 rechaza una clave, MIME, checksum o tamaño fuera de la política firmada.

```text
POST <upload.url>
Content-Type: multipart/form-data

<upload.fields>
file=<bytes>
```

El cliente no fija manualmente `Content-Length`: el navegador calcula el tamaño
del formulario y S3 aplica `content-length-range`. La carga no crea un Producto.

## 3. Finalizar y validar

```http
POST /api/v1/admin/product-assets/f293ce6b-98e9-41da-99ef-0ad4e3a95120/finalization
Authorization: Bearer <access-token>
Idempotency-Key: 78165793-acde-47a1-8ad4-acde0f4b3659
```

Respuesta `200 OK`:

```json
{
  "assetId": "f293ce6b-98e9-41da-99ef-0ad4e3a95120",
  "purpose": "PRIMARY_IMAGE",
  "status": "READY",
  "contentType": "image/webp",
  "contentLength": 245760,
  "width": 1024,
  "height": 1024,
  "checksumSha256": "b64:ZHVtbXktc2hhMjU2LWVqZW1wbG8=",
  "imageUrl": "https://api.example.test/api/v1/catalog/product-assets/f293ce6b-98e9-41da-99ef-0ad4e3a95120/content"
}
```

Catalog verifica checksum, magic bytes, decodificación, dimensiones y **ausencia
de animación**, y elimina metadatos no requeridos antes de promover a una clave
final inmutable. Finalizar dos veces la misma intención devuelve el mismo recurso
`READY`.

La comprobación de animación mira la estructura del archivo, no el MIME: un WebP
animado (`VP8X` con el bit `ANIM`, chunks `ANMF`) y un APNG (chunk `acTL`) se
declaran con los mismos tipos y las mismas firmas que sus equivalentes fijos, así
que pasarían el resto de validaciones. Un archivo animado devuelve `422`.

| Código | Condición |
| --- | --- |
| `404` | intención inexistente |
| `409` | intención vencida, ya asociada de forma incompatible o conflicto idempotente |
| `422` | contenido inválido, checksum distinto o dimensiones fuera de política |
| `503` | S3 indisponible; no se crea Producto |

## 4. Crear Producto

El cliente utiliza únicamente la `imageUrl` devuelta:

```json
{
  "name": "Espada de Fuego",
  "imageUrl": "https://api.example.test/api/v1/catalog/product-assets/f293ce6b-98e9-41da-99ef-0ad4e3a95120/content",
  "description": "Espada de dos manos con daño de fuego.",
  "type": "ARMA",
  "attributes": {
    "schemaVersion": "1",
    "values": {
      "kind": "ARMA",
      "compatibilityScope": "ALL_HEROES",
      "effects": [
        {
          "kind": "DAMAGE",
          "target": "OPPONENT",
          "magnitude": { "mode": "FIXED", "value": 5 }
        }
      ]
    }
  },
  "printRun": 100,
  "creditsPrice": 2500,
  "premium": false
}
```

Antes de abrir la transacción de ADR-015, Catalog comprueba que el asset final
existe y está listo. Si no lo está, devuelve `422` y no persiste Producto,
auditoría ni outbox.

Si el objeto ya fue promovido y la transacción falla, puede quedar un asset
huérfano; la compensación inmediata y el reconciliador de 24 horas lo eliminan.
No queda un Producto parcial.

## 5. Leer contenido

```http
GET /api/v1/catalog/product-assets/{assetId}/content
Authorization: Bearer <access-token>
```

Respuesta normal:

```http
HTTP/1.1 307 Temporary Redirect
Location: <presigned-get-url-redacted>
Cache-Control: private, max-age=240
```

La firma de lectura vence en máximo cinco minutos. El `max-age` de 240 segundos
es deliberado: cachea la redirección por menos de lo que dura la firma, de modo
que el navegador nunca reutiliza una URL ya vencida. Un asset de Producto
suspendido continúa disponible para quienes puedan consultar la instancia
adquirida.

**Riesgo residual asumido.** Si el `307` se sigue como navegación de primer nivel,
la URL firmada queda en el historial del navegador. No hay cabecera que lo
impida; lo acota el vencimiento de cinco minutos. La fuga por `Referer` sí está
cubierta, y no por este contrato: el proxy inverso ya aplica
`Referrer-Policy: strict-origin-when-cross-origin` a todo el sitio (ADR-010), que
recorta ruta y consulta en cualquier salto entre orígenes.

## 6. Reemplazo

El reemplazo repite intención, carga y finalización. La nueva clave existe antes
de que una transacción MongoDB cambie la referencia, escriba auditoría y outbox.
Si la transacción falla, la referencia anterior permanece. El asset anterior no
se elimina mientras HU-37 o un Producto lo referencien.

## Compatibilidad

Durante la adopción, Catalog puede conservar lectura de `imageUrl` heredadas,
pero la ruta canónica solo admite referencias emitidas por este contrato cuando
el feature flag de assets esté activo. El retiro de URL externas requiere
telemetría y decisión explícita; no se infiere de este documento.
