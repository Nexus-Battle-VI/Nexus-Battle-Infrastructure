# ADR-005 — Estrategia de datos y persistencia

- **Estado:** Proposed
- **Fecha:** 2026-08-21
- **Decide:** Arquitectura
- **Relacionado:** [ADR-001](ADR-001-repository-strategy.md), [ADR-007](ADR-007-aws-cost-optimized-platform.md)

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

### La elección de ORM u ODM queda abierta

Este ADR **no** selecciona ORM ni ODM. El plan lo exige de forma explícita, y la razón es sólida: elegir un ORM determina el modelo de persistencia, la estrategia de migraciones y la forma de las consultas durante años, y esa decisión merece su propio análisis con criterios y alternativas.

Consecuencia práctica: **los seis servicios operan hoy con repositorios en memoria**.

No son simulaciones. Cada uno implementa el contrato completo de su puerto y almacena **instantáneas, no referencias vivas al agregado**. Ese detalle importa: con referencias, una prueba pasaría aunque el caso de uso olvidara guardar. Hay una prueba por servicio que fija exactamente ese comportamiento.

Configurar `PERSISTENCE_DRIVER=postgres` o `=mongo` valida la configuración y lo advierte en el registro, pero **no habilita un adaptador que no existe**. Fallar al arrancar ante una configuración incoherente es preferible a arrancar aparentando una persistencia que no hay.

## Consecuencias

**Lo que se gana**

- La frontera de datos es real y verificable, no una convención.
- Sustituir el repositorio en memoria por uno real toca un solo archivo por servicio: el adaptador. Ni el dominio ni los casos de uso cambian.
- Los seis servicios se ejecutan y se verifican de extremo a extremo sin base de datos, lo que hace el CI rápido y sin dependencias externas.

**Lo que cuesta**

- **El estado se pierde al reiniciar.** Es aceptable en la demo y no lo sería en ningún entorno con usuarios reales. Está declarado en el README de cada servicio.
- La decisión de ORM sigue pendiente y bloquea el esquema, las migraciones y los índices.

## Camino de resolución

```text
1. ADR de ORM/ODM con criterios y alternativas   -> pendiente
2. Esquema y migraciones por servicio            -> depende de 1
3. Adaptador real por servicio                   -> depende de 2
4. Pruebas de integracion con Testcontainers     -> depende de 3
```

Testcontainers es el mecanismo previsto para el paso 4: permite ejercitar el adaptador contra el motor real sin depender de una base de datos compartida ni de AWS.

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
- Ningún repositorio contiene esquema, migración ni dependencia de ORM.
