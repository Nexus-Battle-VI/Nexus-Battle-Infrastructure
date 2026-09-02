# ADR-016 — Almacenamiento y ownership de recursos visuales de Producto

- **Estado:** **Proposed** — requiere aprobación del Product Owner y del Tech Lead en [EN-027.3 #283](https://github.com/Nexus-Battle-VI/Nexus-Battle-Management/issues/283)
- **Fecha:** 2026-09-02
- **Decide:** Arquitectura, con aprobación funcional del Product Owner y técnica/económica del Tech Lead
- **Relacionado:** [HU-33 #41](https://github.com/Nexus-Battle-VI/Nexus-Battle-Management/issues/41), [HU-37 #45](https://github.com/Nexus-Battle-VI/Nexus-Battle-Management/issues/45), [ADR-007](ADR-007-aws-cost-optimized-platform.md), [ADR-013](ADR-013-canonical-product-contract.md), [ADR-015](ADR-015-catalog-atomicity-audit-outbox.md)

## Contexto

HU-33 exige una imagen principal y establece que una falla de carga no puede
dejar un producto parcialmente creado. HU-37 amplía el problema a iconos,
animaciones e historial de versiones. ADR-013 reservó `imageUrl` como
referencia obligatoria y decidió que Catalog no almacena el binario.

La infraestructura vigente no tiene almacenamiento de objetos para el producto.
ADR-007 descartó S3 + CloudFront para los estáticos de Web, que Caddy ya sirve,
y la política IAM deniega `s3:*` fuera del bucket de estado de Terraform. Esa
decisión no evaluó recursos dinámicos administrados durante la ejecución.

ADR-015 garantiza atomicidad únicamente entre `products`, `audit_log` y
`outbox` en MongoDB. Un objeto externo no participa en esa transacción. Esta
decisión debe impedir un Producto sin imagen sin afirmar una transacción
distribuida que S3 y MongoDB no ofrecen.

## Fuerzas de decisión

- durabilidad del recurso fuera del ciclo de vida de una instancia EC2;
- costo variable dentro del techo de USD 100;
- bucket privado y acceso mínimo;
- carga sin enviar credenciales AWS al navegador;
- validación real del contenido, no solo de la extensión;
- referencia estable en Producto, sin persistir URL firmadas que expiran;
- conservación de imágenes de productos suspendidos y versiones de HU-37;
- recuperación de objetos huérfanos sin borrar recursos referenciados;
- pruebas locales y CI sin credenciales AWS;
- ausencia de un nuevo microservicio sin ownership operativo.

## Decisión propuesta

### 1. Ownership

| Responsabilidad | Owner |
| --- | --- |
| Semántica del asset, referencia estable, asociación con Producto, reemplazo, conservación y autorización | **Catalog** |
| Validación de rol y consulta de evidencia TOTP por `jti` para carga/finalización administrativa | **Catalog**, consumiendo el contrato interno de Account |
| Bucket, cifrado, bloqueo público, lifecycle, IAM, presupuesto y alarmas | **Infrastructure** |
| Transferir el archivo mediante contrato y mostrar la referencia | **Web**, sin reglas de negocio ni credenciales AWS |
| Resolver Producto por `productId` | **Player / Inventory**; no copia binarios ni URL firmadas |
| Historial de versiones visuales | **Catalog/HU-37**, mediante referencias a assets inmutables |

No se crea un servicio de archivos independiente. Catalog es el único contexto
que decide si un recurso puede asociarse a un Producto. Infrastructure opera el
almacén, pero no conoce reglas de Producto.

### 2. Almacenamiento

Se propone un bucket S3 Standard privado, separado del bucket de Terraform, en
`us-east-1`, sin sitio web de S3 y sin CloudFront para la demo.

Controles obligatorios:

- Object Ownership `BucketOwnerEnforced` y ACL deshabilitadas;
- los cuatro controles de S3 Block Public Access;
- cifrado SSE-S3 (`AES256`) y rechazo de transporte sin TLS;
- versionado habilitado como defensa frente a sobrescrituras accidentales;
- claves generadas por Catalog, nunca nombres de archivo suministrados;
- prefijos `staging/` y `assets/`;
- caducidad de `staging/` al día siguiente y aborto de cargas multiparte
  incompletas al día siguiente;
- versiones no vigentes retenidas inicialmente 30 días, excepto cuando HU-37
  las mantenga referenciadas;
- etiquetas comunes de proyecto, entorno, owner y costo.

S3 es una excepción nueva y acotada de ADR-007 para recursos dinámicos de
Producto. No autoriza alojar Web en S3, añadir CloudFront, crear buckets
arbitrarios ni retirar GHCR para imágenes de contenedor.

### 3. Referencia estable y URLs temporales

Catalog persiste un identificador de asset y una clave opaca, no una URL firmada.
La proyección `imageUrl` usa una URL estable del propio servicio:

```text
https://<host>/api/v1/catalog/product-assets/<assetId>/content
```

Esa ruta devuelve `307 Temporary Redirect` hacia una URL S3 firmada de lectura
con máximo cinco minutos, o transmite el contenido si el adaptador futuro lo
requiere. Una URL firmada nunca se almacena en Producto, auditoría, outbox ni
inventario.

### 4. Flujo de carga

1. Un Administrador o Super Administrador con TOTP solicita una intención.
2. Catalog genera `assetId`, una clave única de `staging/` y un formulario
   `POST` firmado con vigencia máxima de diez minutos.
3. El navegador carga directamente un único objeto mediante los campos firmados.
   La política incluye `content-length-range`, tipo y checksum; el cliente no
   elige la clave ni recibe credenciales AWS.
4. Catalog finaliza la intención: comprueba existencia, longitud y SHA-256,
   inspecciona magic bytes, decodifica la imagen y valida dimensiones.
5. Catalog elimina metadatos no necesarios y produce/promueve un objeto
   inmutable bajo `assets/<assetId>/<sha256>.<ext>`.
6. Solo entonces devuelve la `imageUrl` canónica que puede usarse al crear el
   Producto.
7. `POST /api/v1/catalog/products` rechaza referencias externas, expiradas,
   inexistentes, no finalizadas o que no pertenezcan al contrato de assets.

El formulario y las URLs firmadas son bearer tokens temporales. Deben limitar
método, bucket, clave, longitud, checksum, tipo de contenido y antigüedad de
firma. El endpoint de S3 puede ser visible al navegador por tratarse de carga
directa, pero no se exponen ARN, claves AWS ni credenciales permanentes. Firmas,
políticas y URLs temporales no se registran completas en logs.

### 5. Atomicidad y compensación

No se afirma atomicidad entre S3 y MongoDB.

- La carga y validación ocurren antes de iniciar la creación del Producto.
- Si la carga o promoción falla, la transacción de Producto no comienza.
- La clave final es inmutable y existe antes del commit MongoDB.
- La creación confirma internamente Producto, auditoría y outbox conforme a
  ADR-015.
- Si el commit MongoDB falla **de forma conocida** después de promover el objeto,
  Catalog intenta eliminarlo, y un reconciliador idempotente elimina además los
  assets finales no referenciados con más de 24 horas.
- Si el resultado del commit es **desconocido** —un tiempo de espera agotado, una
  conexión perdida—, Catalog **no compensa**. Deja el objeto y lo entrega al
  reconciliador, que comprueba referencias antes de borrar nada.
- El lifecycle elimina staging abandonado aunque Catalog no vuelva a ejecutarse.
- El reconciliador nunca elimina una clave referenciada por Producto o por el
  historial de diseño.

**La distinción entre «falló» y «no se sabe» no es una sutileza.** Un tiempo de
espera agotado no dice que la transacción no ocurriera: puede haberse confirmado
en el servidor y haberse perdido la respuesta. Compensar ahí borraría la imagen
de un Producto vigente, y el resultado sería peor que el huérfano que se quería
evitar: un Producto que existe apuntando a una clave que ya no. Ante la duda, el
diseño prefiere el huérfano, porque es recuperable y el reconciliador lo resuelve
comprobando referencias.

Así se evita un Producto parcial. Puede existir temporalmente un objeto huérfano
recuperable y acotado, que es una consecuencia explícita de no usar una
transacción distribuida.

### 6. Validación mínima de HU-33

| Regla | Valor propuesto |
| --- | --- |
| Uso | `PRIMARY_IMAGE` |
| MIME | `image/jpeg`, `image/png`, `image/webp` |
| Tamaño | máximo 5 MiB |
| Dimensiones | entre 256 y 4096 píxeles por lado |
| Píxeles totales | 20 megapíxeles, como defensa en profundidad |
| Integridad | SHA-256 obligatorio |
| Contenido | magic bytes + decodificación; extensión y MIME declarados no bastan |
| Metadatos | se eliminan EXIF y metadatos no requeridos |
| SVG/BMP | rechazados; SVG puede contener contenido activo |
| Animación | rechazada; se detecta inspeccionando la estructura del archivo, no el MIME |

Estos límites son operativos y versionables. Cambiarlos exige actualizar el
contrato y sus pruebas, no modificar silenciosamente una constante.

**El tope de píxeles no puede dispararse hoy, y conviene decirlo.** Con 4096 px
por lado el área máxima posible es 4096 × 4096 = 16,8 MP, por debajo del tope.
El control que realmente ataja una bomba de descompresión es el límite de lado;
los 20 MP se conservan por si ese límite se relaja en el futuro. Presentarlo como
la protección principal sería atribuirle un efecto que no tiene.

**«Sin animación» no se puede hacer cumplir con el MIME ni con los magic bytes.**
Un WebP animado se declara `image/webp` y empieza por `RIFF....WEBP`, igual que
uno fijo: la animación vive en el chunk `VP8X` con el bit `ANIM` y en los `ANMF`
que le siguen. Un APNG se sirve como `image/png` y arranca con la firma PNG: lo
que lo hace animado es el chunk `acTL`. Un archivo así supera la lista cerrada de
MIME, los magic bytes y la decodificación. Por tanto la finalización debe
**inspeccionar la estructura** y rechazar `ANIM`/`ANMF` en WebP y `acTL` en PNG,
con una prueba por formato construida sobre un archivo animado real. Sin esa
comprobación la regla existe en este documento y no en el sistema.

HU-37 decidirá si admite animación y bajo qué formato y límites; esta decisión no
se lo concede por omisión.

### 7. Relación con HU-37

Cada versión visual referencia assets inmutables. Aplicar o revertir una versión
cambia referencias en Catalog; no reescribe cada inventario. Suspender un
producto no elimina sus assets. Un asset solo puede purgarse cuando no esté
referenciado por el Producto vigente ni por ninguna versión conservada.

La política concreta para iconos y animaciones se refina en HU-37 después de
aceptar esta decisión. ADR-016 no convierte GIF o spritesheets en requisitos de
HU-33.

### 8. Seguridad y limitación de la demo

El rol EC2 del nodo `app` es compartido por sus contenedores. Con la topología
actual no es posible conceder credenciales S3 a Catalog y ocultarlas a los demás
contenedores mediante IAM de instancia.

Conviene enunciar la consecuencia entera, no solo la parte nueva: ese rol **ya**
concede `cognito-idp:AdminSetUserPassword` y `ses:SendEmail`. Añadirle S3
significa que cualquier contenedor del nodo podrá además leer y escribir en el
bucket de assets. La demo acepta esta limitación, ya documentada en ADR-011:

- el rol solo accede al bucket y prefijos de assets;
- se conceden acciones concretas, nunca `s3:*`;
- las mutaciones se autorizan además en la API de Catalog;
- CloudTrail/observabilidad debe identificar acciones sobre el bucket;
- la arquitectura objetivo asignará identidad de workload exclusiva a Catalog.

Esto es mínimo privilegio a nivel de nodo, no aislamiento real por servicio. No
se presenta de otra forma.

### 9. Threat model básico

| Amenaza | Control exigido |
| --- | --- |
| Archivo disfrazado o contenido activo | Lista cerrada de MIME, magic bytes, decodificación real y rechazo de SVG/BMP |
| Animación colada bajo un MIME admitido | Inspección de estructura: `ANIM`/`ANMF` en WebP y `acTL` en PNG. El MIME y los magic bytes NO la distinguen |
| Archivo excesivo o bomba de imagen | `content-length-range`, máximo 5 MiB, límites de dimensiones/píxeles y decodificación acotada |
| Sustitución o corrupción en tránsito | HTTPS, checksum SHA-256 firmado y verificado antes de promover |
| Escritura en otra clave o reutilización de autorización | Clave generada por Catalog, política POST exacta, expiración <= 10 min y una intención de un solo uso |
| Acceso público accidental | Bucket privado, Block Public Access, ACL deshabilitadas y URL GET <= 5 min |
| Elevación administrativa | JWT válido, rol administrativo y evidencia TOTP vigente consultada en Account por `jti` |
| Fuga por logs | Redacción de firmas, políticas, URL temporal, JWT y cabeceras de autorización |
| Objeto huérfano o borrado de una versión vigente | Lifecycle de staging, reconciliación conservadora y comprobación de referencias vigentes/históricas |
| Abuso de costo o almacenamiento | cuotas, métricas, alarmas, límites por archivo y revisión mensual |
| Acceso lateral desde otro contenedor del nodo | Permisos IAM acotados al bucket/prefijos; riesgo residual aceptado y workload identity como arquitectura objetivo |

El contrato de evidencia TOTP no depende de un claim inexistente en Cognito: para
cada mutación sensible Catalog consulta la evidencia vigente asociada al `jti`
del access token según el contrato interno aprobado con Account.

### 10. Coste

La estimación detallada está en
[product-assets-s3-estimate.md](../costs/product-assets-s3-estimate.md).

Para el escenario de demo —5 GB, 10 000 escrituras y 100 000 lecturas al mes—,
almacenamiento y solicitudes se estiman en **USD 0,21/mes** antes de impuestos.
Con 10 GB de salida, el total sigue siendo USD 0,21 mientras quede dentro de los
100 GB mensuales de salida sin cargo agregados por AWS. Como sensibilidad
conservadora, si esa franquicia ya estuviera consumida, 10 GB a USD 0,09/GB
llevarían el total a **USD 1,11/mes**.

No se asume capa gratuita de almacenamiento. El costo debe medirse y alertarse;
la transferencia es la variable dominante.

### 11. Observabilidad

Métricas mínimas:

- intenciones creadas/finalizadas/expiradas;
- fallos de carga, checksum, decodificación y promoción;
- bytes almacenados y transferidos;
- objetos en staging con edad mayor a la esperada;
- assets finales huérfanos y resultado del reconciliador;
- respuestas 4xx/5xx del adaptador S3;
- costo real mensual del bucket.

Los logs usan `assetId`, `productId` y correlation ID. No incluyen URL
firmada, firma, cabeceras de autorización ni contenido binario.

## Alternativas consideradas

| Alternativa | Resultado | Motivo |
| --- | --- | --- |
| S3 privado, URL firmada y Catalog como owner | **Recomendada** | Durabilidad, costo variable, acceso controlado y desacoplamiento del host |
| Disco EBS del nodo app + Caddy | Rechazada | El asset queda ligado a una instancia reemplazable y complica backup/ownership |
| MongoDB/GridFS | Rechazada | Mezcla binarios con el agregado, presiona el nodo de datos y contradice ADR-013 |
| Bucket S3 público | Rechazada | Expone recursos y elimina control de acceso/revocación |
| S3 + CloudFront | Pospuesta | Mejora distribución, pero añade servicio y coste sin necesidad para la demo |
| Nuevo microservicio de assets | Rechazada | No existe owner/equipo y agrega despliegue, API y operación innecesarios |
| URL externa arbitraria | Rechazada | No garantiza disponibilidad, validación, borrado ni seguridad |

## Despliegue y rollback

EN-027.3 no provisiona recursos. Una Task posterior deberá aplicar en este orden:

1. actualizar **dos** políticas IAM, que están en módulos distintos y es fácil
   descubrir la segunda a mitad de camino:
   - la denegación del grupo de operación (`infra/modules/iam`, sentencia
     `S3SoloParaElEstado`), que hoy deniega `s3:*` sobre todo lo que no sea el
     bucket de estado y por tanto impide crear el bucket de assets;
   - una concesión nueva y acotada al rol del nodo `app` (`infra/modules/compute`),
     que hoy no declara ninguna acción de S3: solo `cognito-idp:AdminSetUserPassword`
     y `ses:SendEmail`;
2. crear el bucket privado y sus controles;
3. desplegar el adaptador de assets con la funcionalidad deshabilitada;
4. ejecutar pruebas de carga, validación, referencia y reconciliación;
5. habilitar por configuración las intenciones de carga;
6. observar costo y errores antes de usarlo en la creación de Producto.

Para revertir: deshabilitar nuevas intenciones, conservar lectura de referencias
existentes, restaurar la versión anterior de Catalog y no destruir el bucket
mientras haya referencias. Los objetos solo se exportan/eliminan después de
inventariar referencias y verificar backup. Nunca se ejecuta `terraform
destroy` sobre el bucket como rollback rutinario.

## Condiciones para pasar a Accepted

Revisión del Tech Lead del 2026-09-02: las once decisiones quedan aprobadas, y
las condiciones técnicas que traía esa revisión están incorporadas en este
documento —detección de animación por estructura, tope de píxeles descrito como
lo que es, prohibición de compensar ante resultado desconocido, las dos políticas
IAM y el alcance real del rol compartido. Lo que resta es el registro de las
aprobaciones humanas.

- aprobación del Product Owner sobre ownership y visibilidad;
- aprobación del Tech Lead sobre S3 privado, límites y compensación;
- aceptación explícita de la limitación IAM del rol EC2 compartido;
- aprobación de la excepción acotada de ADR-007;
- validación del contrato y del diagrama;
- coste revisado dentro del techo;
- Tasks separadas para IaC, adaptador de Catalog, reconciliación y pruebas;
- ningún `terraform apply` como parte de esta decisión.

## Consecuencias

**Lo que se gana**

- referencia durable y estable para HU-33;
- flujo que no crea Producto si la imagen falla;
- base extensible para versiones visuales de HU-37;
- costo bajo y medible;
- bucket privado sin credenciales AWS en el navegador.

**Lo que cuesta**

- coordinación con un sistema externo sin transacción distribuida;
- reconciliación de huérfanos;
- dependencia runtime de S3 para nuevas cargas y lecturas no cacheadas;
- una excepción adicional a ADR-007;
- aislamiento IAM solo a nivel de nodo en la demo.
