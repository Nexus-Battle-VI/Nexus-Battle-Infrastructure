# Propiedad de datos

Ver [ADR-005](../adr/ADR-005-data-strategy.md).

## La regla

Cada servicio posee su almacén **en exclusiva**. Ningún otro accede a él, ni directamente ni mediante claves foráneas.

## Reparto

| Servicio | Motor objetivo | Datos que posee | Referencias externas |
| --- | --- | --- | --- |
| Account | PostgreSQL | Cuenta, correo, nombre visible, estado, roles | — |
| Player / Inventory | MongoDB | Inventario, capacidad, ranuras | `PlayerId` (Account), `ItemId` (Catalog) |
| Catalog | MongoDB | Producto, nombre, categoría, precio, estado | — |
| Community | PostgreSQL | Hilo, título, estado, mensajes | `AuthorId` (Account) |
| Commerce | PostgreSQL | Pedido, líneas, estado | `CustomerId` (Account), `Sku` (Catalog) |
| Notifications | Sin base obligatoria | Registro de idempotencia de vida corta | — |

El criterio de motor no es preferencia: Player/Inventory y Catalog usan documentos porque sus agregados se leen y escriben enteros y tienen atributos variables; Account, Community y Commerce usan relacional porque sus consultas atraviesan relaciones claras y Commerce necesita integridad transaccional entre pedido y líneas.

## Cómo se cruza la frontera

Las referencias externas son **identificadores opacos**. Un servicio que necesita más que el identificador **pregunta por la API**:

```text
Commerce necesita el precio de un producto

  ProductPricingPort.priceOf(sku)      <- correcto
  SELECT ... JOIN productos ...        <- PROHIBIDO
```

Un `JOIN` entre pedidos y productos convertiría dos servicios en uno solo con dos procesos. La prohibición es lo que mantiene el límite.

## Por qué `Money` está duplicado

`Money` existe por separado en Catalog y en Commerce, con código prácticamente idéntico. **Es deliberado.**

Un paquete común de objetos de dominio acoplaría ambos servicios: cualquier cambio en el objeto obligaría a un despliegue coordinado, y el límite entre contextos dejaría de existir en la práctica aunque siguiera existiendo en el diagrama.

Treinta líneas duplicadas cuestan menos que ese acoplamiento. El plan lo prohíbe explícitamente y aquí se cumple.

## Estado real

**Los seis servicios operan con repositorios en memoria.**

No son simulaciones: implementan el contrato completo de su puerto y almacenan **instantáneas, no referencias vivas al agregado**.

Ese detalle importa más de lo que parece. Con referencias vivas, este código pasaría la prueba:

```ts
// caso de uso que OLVIDA guardar
const inventory = await inventories.findByOwner(ownerId)
inventory.add(itemId, quantity, now)
// falta: await inventories.save(inventory)
```

Con instantáneas, no. Hay **una prueba por servicio** que fija exactamente ese comportamiento: se muta el agregado sin volver a guardarlo y se comprueba que el almacén no cambió.

## Aunque compartan host

En la demo, PostgreSQL y MongoDB corren como contenedores en la misma instancia. Aun así:

- cada servicio conserva **base o esquema lógico propio**;
- cada servicio tiene **credenciales propias**;
- cada servicio tendrá **migraciones propias**.

Compartir host es una concesión de coste. Compartir esquema sería renunciar a la arquitectura.

### La regla tiene que aplicarla el motor, no la convención

Una versión anterior de la composición de referencia **incumplía este apartado en MongoDB**, y conviene dejarlo escrito porque el fallo es fácil de repetir:

| Motor | Antes | Ahora |
| --- | --- | --- |
| PostgreSQL | Usuario y base por servicio, con `REVOKE` sobre el esquema público | Igual |
| MongoDB | Base por servicio pero **sin autenticación**: `catalog` podía leer y escribir la base de `player-inventory` | Usuario por servicio con `readWrite` acotado a su propia base |

Las URI eran `mongodb://mongo:27017/catalog`, sin credenciales. Bases distintas, sí, pero **nada impedía cruzar la frontera**: bastaba cambiar el nombre de la base en la cadena de conexión.

La separación existía en el documento y en el nombre de la base, no en el motor. Eso no es propiedad de datos: es una convención que el primer error de programación se salta sin avisar.

`compose/init-mongo.js` es ahora el equivalente exacto de `init-postgres.sql`. **Definir `MONGO_INITDB_ROOT_USERNAME` es lo que activa la autenticación** en la imagen oficial; sin esa variable Mongo arranca abierto.

## Aislamiento de fallos entre servicios

Los seis servicios y las dos bases comparten instancia. Sin límites de recursos, **un solo servicio con una fuga de memoria agota la RAM del host y se lleva por delante a todos los demás, incluidas las bases de datos**.

Cada contenedor declara ahora `mem_limit` y `pids_limit`. El efecto es concreto: cuando un contenedor supera su techo, el núcleo mata **ese** contenedor, y `restart: unless-stopped` lo levanta de nuevo en segundos. El resto del sistema no se entera.

**La CPU no se limita a propósito.** La contención de CPU degrada el rendimiento pero no mata procesos, y poner un techo por contenedor en una instancia de núcleos compartidos provocaría estrangulamiento en ráfagas legítimas. El riesgo que hay que contener es la memoria, no el cómputo.

Suma de techos: 1 712 MiB, más unos 300 MiB de sistema y Docker. **No cabe en una instancia de 2 GiB** con margen razonable, y es el argumento técnico para dimensionar la instancia, por encima de cualquier preferencia.

## Lo que falta

La elección de ORM u ODM queda **deliberadamente abierta** ([ADR-005](../adr/ADR-005-data-strategy.md)). De ella dependen el esquema, las migraciones y los índices.

Configurar `PERSISTENCE_DRIVER=postgres` o `=mongo` valida la configuración y lo advierte en el registro, pero **no habilita un adaptador que no existe**. Fallar al arrancar ante una configuración incoherente es preferible a arrancar aparentando una persistencia que no hay.
