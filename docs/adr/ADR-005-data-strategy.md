# ADR-005 — Estrategia de datos y persistencia

- **Estado:** **Accepted** el 2026-08-26 — camino recorrido: los cinco servicios con almacen tienen adaptador real y pruebas contra motor. **Notifications sigue sin almacen**, a proposito
- **Fecha:** 2026-08-21
- **Decide:** Arquitectura
- **Relacionado:** [ADR-001](ADR-001-repository-strategy.md), [ADR-007](ADR-007-aws-cost-optimized-platform.md), [ADR-012](ADR-012-orm-odm.md)

## Contexto

Seis servicios necesitan persistencia. El plan fija *Database per Service* y *Polyglot Persistence*, con un techo de coste de USD 100 mensuales que excluye RDS, DocumentDB, DynamoDB y ElastiCache.

Queda una decisión abierta que este ADR **no cierra deliberadamente**: qué ORM u ODM usar.

## Decisión

### Propiedad de datos

Cada servicio posee su almacén en exclusiva.

| Servicio | Motor objetivo | Por qué |
| --- | --- | --- |
| Account | PostgreSQL | Relaciones entre cuenta y roles; consultas por correo con unicidad |
| Player / Inventory | MongoDB | El inventario es un documento con ranuras heterogéneas que se lee y escribe entero |
| Catalog | MongoDB | Producto con atributos variables por categoría; lectura dominante |
| Community | PostgreSQL | Hilos y mensajes con relación clara y consultas por hilo |
| Commerce | PostgreSQL | Integridad transaccional del pedido y sus líneas |
| Notifications | Ninguno obligatorio | Solo requiere un registro de idempotencia de vida corta |

**Prohibiciones que no admiten excepción:**

- Acceso directo a la base de datos de otro servicio.
- Claves foráneas entre servicios.
- Entidades de dominio compartidas mediante un paquete común.

Aunque en la demo todos los motores vivan en el mismo host, **cada servicio conserva base o esquema lógico propio, credenciales propias y migraciones propias**. Compartir host es una concesión de coste; compartir esquema sería renunciar a la arquitectura.

### La elección de ORM u ODM se dejó abierta, y ya está cerrada

Este ADR **no** seleccionó ORM ni ODM. El plan lo exigía de forma explícita, y la razón era sólida: elegir un ORM determina el modelo de persistencia, la estrategia de migraciones y la forma de las consultas durante años, y esa decisión merecía su propio análisis con criterios y alternativas.

La tomó [ADR-012](ADR-012-orm-odm.md): **Kysely para PostgreSQL, driver oficial para MongoDB.**

Mientras estuvo abierta, los servicios operaron con repositorios en memoria. No eran simulaciones: cada uno implementaba el contrato completo de su puerto y almacenaba **instantáneas, no referencias vivas al agregado**. Ese detalle importaba, y sigue importando: con referencias, una prueba pasaría aunque el caso de uso olvidara guardar. Hay una prueba por servicio que fija exactamente ese comportamiento, y **el adaptador real cumple el mismo contrato**, con su propia prueba contra el motor.

Los repositorios en memoria **no se han retirado**, y no es descuido. `PERSISTENCE_DRIVER` elige cuál opera, y el de memoria es lo que permite que las pruebas del dominio y de los casos de uso corran sin Docker.

## Consecuencias

**Lo que se gana**

- La frontera de datos es real y verificable, no una convención.
- Sustituir el repositorio en memoria por uno real toca un solo archivo por servicio: el adaptador. Ni el dominio ni los casos de uso cambian.
- Los seis servicios se ejecutan y se verifican de extremo a extremo sin base de datos, lo que hace el CI rápido y sin dependencias externas.

**Lo que cuesta**

- ~~**El estado se pierde al reiniciar.**~~ Resuelto en los cinco servicios con almacén. Sigue siendo cierto en **Notifications**, cuyo registro de idempotencia es de vida corta y vive en memoria a propósito.
- ~~La decisión de ORM sigue pendiente y bloquea el esquema, las migraciones y los índices.~~ Resuelto por [ADR-012](ADR-012-orm-odm.md).
- Cada servicio con almacén arrastra ahora un esquema y unas migraciones que hay que desplegar. Es el coste real de tener persistencia, y se paga con un paso explícito de despliegue —`npm run migrate`— que no ocurre al arrancar el servicio.

## Camino de resolución: recorrido

```text
1. ADR de ORM/ODM con criterios y alternativas   -> hecho (ADR-012)
2. Esquema y migraciones por servicio            -> hecho (5 de 5)
3. Adaptador real por servicio                   -> hecho (5 de 5)
4. Pruebas de integracion con Testcontainers     -> hecho (5 de 5)
```

| Servicio | Motor | Adaptador |
| --- | --- | --- |
| Account | PostgreSQL | `PostgresAccountRepository` |
| Community | PostgreSQL | `PostgresThreadRepository` |
| Commerce | PostgreSQL | `PostgresOrderRepository` |
| Catalog | MongoDB | `MongoProductRepository` |
| Player / Inventory | MongoDB | `MongoInventoryRepository` |

Testcontainers era el mecanismo previsto para el paso 4, y es el que se usó: cada servicio tiene una suite propia que levanta su motor en un contenedor y ejercita el adaptador contra él. Vive **aparte** de la suite por defecto, para que quien trabaje en el dominio no necesite Docker, y el CI ejecuta ambas.

Aquí no se anota cuántas pruebas hay. Ese dato envejece con cada PR, y este documento ya estuvo desfasado una vez por afirmar cosas que dejaron de ser ciertas.

## Alternativas consideradas

| Alternativa | Por qué se descartó |
| --- | --- |
| Elegir el ORM ahora para desbloquear | Convertiría una decisión de años en un efecto colateral del bootstrap |
| Una única base de datos compartida | Elimina la propiedad de datos y con ella la independencia de los servicios |
| Persistencia en fichero para la demo | Añade un mecanismo que habría que retirar, sin acercar el adaptador real |
| PostgreSQL para todo | Simplifica operación, pero desatiende el requisito de Polyglot Persistence y el ajuste al modelo de cada contexto |

## Evidencia

- Los seis repositorios en memoria almacenan instantáneas; cada uno tiene una prueba que verifica que una mutación no persistida no se filtra al almacén.
- `Nexus-Battle-Commerce` consulta precios a Catalog mediante `ProductPricingPort`, nunca por acceso al almacén.
- Cinco repositorios contienen esquema, migraciones y adaptador; las restricciones del vocabulario del dominio viven **en el motor** —`CHECK` en PostgreSQL, `$jsonSchema` en MongoDB— y hay pruebas que fallan si el dominio y la migración divergen.
- Ninguna migración importa el dominio: queda congelada en el tiempo y debe seguir siendo ejecutable tal y como se escribió.
