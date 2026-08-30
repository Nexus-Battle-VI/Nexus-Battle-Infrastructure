# ADR-013 — Contrato canónico de Producto y compatibilidad de API

- **Estado:** **Proposed** — pendiente de aprobación del Tech Lead en [EN-027.1](https://github.com/Nexus-Battle-VI/Nexus-Battle-Management/issues/281)
- **Fecha:** 2026-08-30
- **Decide:** Arquitectura, con validación funcional del Product Owner donde se indica
- **Relacionado:** [HU-33](https://github.com/Nexus-Battle-VI/Nexus-Battle-Management/issues/41), [EN-027](https://github.com/Nexus-Battle-VI/Nexus-Battle-Management/issues/280), [ADR-005](ADR-005-data-strategy.md), [ADR-012](ADR-012-orm-odm.md)

## Contexto

HU-33 exige crear un producto disponible inmediatamente mediante
`POST /api/v1/catalog/products`, con identidad generada, tipos cerrados,
descripción, imagen, atributos, tiraje y precios. El agregado implementado en
Catalog protege otro contrato: el cliente entrega el SKU, el SKU también es
`_id`, el producto nace en `DRAFT`, la categoría es libre y la ruta es
`/api/products`.

La suite de Catalog está verde porque verifica ese contrato heredado. No es
evidencia de cumplimiento de HU-33.

La revisión técnica de EN-027 aprobó estas decisiones antes de este ADR:

1. conservar los lineamientos y adaptar la implementación;
2. usar `productId` generado como identidad canónica;
3. conservar `sku` temporalmente como alias contractual;
4. separar ciclo de vida y modalidad de tiraje;
5. admitir precio en créditos igual a cero;
6. exigir precio real estrictamente positivo para productos premium;
7. entregar HU-33 en dos carriles;
8. omitir backfill: la colección desplegada `catalog.products` está vacía.

### Evidencia de consumidores actuales

| Consumidor | Contrato implementado | Acoplamiento que debe retirarse |
| --- | --- | --- |
| Web | `GET /api/products`, `GET /api/products/:sku`; usa `sku` como key de React | ruta heredada, categoría libre y estado `PUBLISHED` |
| Commerce | `ProductPricingPort.priceOf(sku)` y líneas de pedido por SKU | SKU como referencia de producto; precio local mientras no exista integración |
| Player / Inventory | persiste `itemId` como texto | no distingue todavía `productId` de otras referencias de ítem |

Commerce conserva el precio acordado dentro de la línea del pedido. Adoptar
`productId` no cambia esa regla: cambia la referencia, no convierte el precio
en una consulta viva.

## Decisión propuesta

### 1. Identidad

`productId` es la única identidad canónica del agregado y se genera en Catalog
mediante el puerto existente `IdGeneratorPort`. El contrato usa UUID y no
permite que el cliente proporcione `productId`.

`sku` es un alias comercial estable y único durante la compatibilidad:

- siempre aparece en las respuestas mientras exista un consumidor heredado;
- puede recibirse opcionalmente en la ruta nueva para conservar integraciones;
- si se omite, Catalog genera un alias kebab-case único;
- nunca se usa como `_id`, aggregate ID ni relación canónica nueva;
- no tiene fecha de retiro hasta disponer de telemetría y confirmación de los
  consumidores.

Permitir un SKU opcional no crea una segunda identidad: buscar por SKU resuelve
primero el alias y toda operación interna continúa con `productId`.

### 2. Ciclo de vida y tiraje

El modelo canónico mantiene dos dimensiones independientes:

```text
lifecycleStatus = ACTIVE | SUSPENDED
printRunMode     = UNIQUE | LIMITED | INFINITE
```

La modalidad se deriva del entero `printRun`:

| `printRun` | `printRunMode` | Estado funcional inicial |
| ---: | --- | --- |
| `1` | `UNIQUE` | `único` |
| `>= 2` | `LIMITED` | `activo` |
| `-1` | `INFINITE` | `activo` |

`0`, decimales y negativos distintos de `-1` son inválidos. Toda creación
empieza con `lifecycleStatus=ACTIVE`; crear directamente en `SUSPENDED` está
prohibido.

La proyección funcional se calcula así:

```text
SUSPENDED                         -> suspendido
ACTIVE + UNIQUE                   -> único
ACTIVE + LIMITED o INFINITE       -> activo
```

La modalidad no se pierde al suspender. Reactivar restaura `ACTIVE` y vuelve a
proyectar `único` cuando corresponda.

### 3. Tipo y atributos

El tipo es un enum propiedad de Catalog:

```text
HEROE | HABILIDAD | ARMA | ARMADURA | ITEM | EPICA
```

No existe un bounded context de categorías del que dependa la creación. El
contrato reserva un sobre versionado:

```json
{
  "attributes": {
    "schemaVersion": "1",
    "values": {}
  }
}
```

El sobre permite evolucionar la matriz sin cambiar la forma raíz de Producto,
pero **no autoriza valores arbitrarios**. La matriz exacta de campos permitidos
y obligatorios por tipo continúa pendiente de decisión funcional.

HU-33 remite a «HU-012» como fuente del esquema, pero la HU-12 real del backlog
es «Prevención de daño entre aliados». Esa referencia no puede usarse como
fuente de verdad. El Product Owner debe corregir la referencia o aprobar una
matriz dentro de HU-33 antes de aceptar la validación de atributos.

#### Decisión funcional requerida: PO-ATTR-01

El Product Owner debe aprobar la fuente de verdad y la matriz funcional de
atributos para `HEROE`, `HABILIDAD`, `ARMA`, `ARMADURA`, `ITEM` y `EPICA`. La
decisión debe responder, como mínimo:

1. qué documento o ítem de backlog reemplaza la referencia inválida a HU-012,
   o si la matriz quedará definida directamente en HU-33;
2. para cada tipo, qué atributos son obligatorios, cuáles son opcionales y si
   se permite un conjunto vacío;
3. para cada atributo, su significado funcional, tipo de dato, unidad, valores
   permitidos, rango y cardinalidad cuando correspondan;
4. para `HEROE`, `HABILIDAD` y `EPICA`, qué significan `habilidades` y
   `efectos`, cuáles son obligatorios, su cantidad mínima y si referencian
   conceptos existentes o se crean en línea;
5. si un atributo desconocido debe rechazarse y cuál es el comportamiento
   esperado cuando falta uno obligatorio;
6. un ejemplo válido y uno inválido por cada tipo; y
7. si una matriz aún no aprobada bloquea todos los tipos o solo el tipo
   afectado durante una liberación incremental.

El resultado aceptable es una matriz aprobada y enlazada desde HU-33, EN-027 y
EN-027.1, junto con la corrección de la referencia funcional. El PO decide el
significado y las reglas de negocio; el Tech Lead y el equipo deciden la forma
JSON, el versionado del esquema, el almacenamiento y la implementación de las
validaciones.

Hasta entonces, OpenAPI marca `attributes.values` como extensión pendiente y
la ruta no puede declararse funcionalmente completa. El resto del contrato
(identidad, estados, tiraje y precios) puede avanzar, pero EN-027.1 no puede
cerrarse ni HU-33 declararse conforme mientras PO-ATTR-01 siga pendiente.

### 4. Precios

- `creditsPrice` es un entero mayor o igual a cero.
- `premium=false` exige `realMoneyPrice=null` o ausencia del campo.
- `premium=true` exige `realMoneyPrice` con importe entero mayor que cero en la
  unidad mínima de `COP`, `USD` o `EUR`.
- los importes reales no usan punto flotante: USD 9,99 se representa como
  `{ "amount": 999, "currency": "USD" }`.

La elegibilidad para Auction no forma parte de este contrato. La frontera entre
publicación premium oficial y reventa de jugadores sigue siendo decisión del
Product Owner en EN-027.

### 5. Imagen y descripción

`description` e `imageUrl` forman parte obligatoria del contrato final de
creación. Catalog guarda una referencia, no el binario.

Este ADR no elige proveedor, bucket, ciclo de vida ni propietario del archivo.
Esa decisión pertenece a
[EN-027.3](https://github.com/Nexus-Battle-VI/Nexus-Battle-Management/issues/283).
Modelar `imageUrl` puede avanzar en el Carril A; habilitar el alta completa en
un entorno compartido requiere una referencia producida por el mecanismo que
apruebe EN-027.3.

### 6. Contrato HTTP versionado

El contrato objetivo está en
[`catalog-product-v1.openapi.yaml`](../contracts/catalog-product-v1.openapi.yaml).
Su estado es `Proposed`: documenta el destino aprobado para implementación, no
una ruta ya desplegada.

El flujo entre la superficie heredada, el adaptador y el núcleo canónico se
representa en
[`catalog-product-contract-compatibility.puml`](../diagrams/catalog-product-contract-compatibility.puml).

La ruta canónica es:

```text
POST /api/v1/catalog/products
```

Reglas de protocolo:

- `201`: producto creado y disponible;
- `400`: JSON o forma básica inválida, incluidos campos no declarados;
- `401`: testimonio ausente o inválido;
- `403`: rol no autorizado o contexto administrativo sin segundo factor;
- `409`: alias SKU ocupado o nombre normalizado + tipo ya activo;
- `422`: regla de negocio válida sintácticamente pero imposible, como tiraje
  `-5` o configuración premium incoherente.

El OpenAPI mantenido aquí se compara con el documento generado por
`@nestjs/swagger` durante la implementación. Mientras la ruta no exista en
Catalog, este archivo se identifica como contrato objetivo y no sustituye la
evidencia del código.

### 7. ProductRef entre contextos

Los consumidores no comparten el agregado. La referencia mínima es:

| Campo | Obligatorio durante transición | Uso |
| --- | --- | --- |
| `productId` | sí | referencia canónica |
| `sku` | sí, temporal | correlación con contratos heredados |
| `name` | según proyección | presentación, nunca identidad |
| `type` | según caso de uso | filtro o validación funcional |

Cada contexto conserva solo lo que necesita:

- Web usa `productId` como key y mantiene SKU como dato visible temporal;
- Commerce solicita por `productId`, recibe precio/disponibilidad y congela el
  precio en la línea; conserva SKU solo para mostrar o conciliar legado;
- Player / Inventory persiste `productId` en lugar de un `itemId` ambiguo.

Ningún consumidor accede a la colección de Catalog.

### 8. Compatibilidad de rutas y semántica

La transición es aditiva. La ruta heredada permanece como adaptador hacia los
mismos casos de uso canónicos:

| Contrato heredado | Traducción durante compatibilidad |
| --- | --- |
| `POST /api/products` | crea por el caso canónico y proyecta respuesta heredada |
| `GET /api/products` | lista `ACTIVE` y proyecta campos heredados |
| `GET /api/products/:sku` | resuelve alias y consulta por `productId` |
| `POST /api/products/:sku/publication` | operación idempotente para un producto ya `ACTIVE` |
| `POST /api/products/:sku/archival` | traduce a suspensión |
| `POST /api/products/:sku/price` | cambia `creditsPrice` |

Proyección para clientes que todavía leen `status`:

```text
ACTIVE    -> PUBLISHED
SUSPENDED -> ARCHIVED
```

`DRAFT` no existe en el modelo canónico. No hay documentos desplegados que
requieran convertirlo. La semántica de publicación explícita queda deprecada
porque contradice la disponibilidad inmediata de HU-33.

Las respuestas heredadas deben incluir cabecera `Deprecation: true` y un enlace
al sucesor. `Sunset` solo se añade cuando el Product Owner apruebe una fecha.

## Secuencia de adopción

1. Aprobar este ADR, corregir la fuente de atributos y validar OpenAPI.
2. Implementar identidad y agregado canónicos en Catalog sin retirar rutas.
3. Exponer la ruta versionada y el adaptador heredado sobre los mismos casos de
   uso.
4. Actualizar Web, Commerce y Player / Inventory en Tasks independientes.
5. Medir uso de rutas y búsquedas por SKU.
6. Proponer retiro únicamente cuando no existan consumidores observados y el
   Product Owner lo apruebe.

No hay fase de backfill: la colección de productos desplegada está vacía.

## Consecuencias

### Lo que se gana

- una identidad estable que no depende de una referencia comercial;
- estados sin combinaciones imposibles;
- un contrato versionado y verificable antes de tocar consumidores;
- migración aditiva y observable;
- independencia entre el agregado y las proyecciones heredadas.

### Lo que cuesta

- durante la transición existen dos superficies HTTP y dos DTO de salida;
- Catalog debe mantener un índice único adicional para SKU;
- Web, Commerce y Player / Inventory requieren cambios coordinados;
- la publicación explícita heredada cambia a una operación compatible sin
  significado canónico.

### Lo que permanece bloqueado

- la matriz exacta de atributos por tipo, por referencia funcional inválida;
- el almacenamiento y ownership de imágenes, por EN-027.3;
- auditoría, outbox y `catalog.product.created`, por EN-027.2 y EN-027.4;
- ownership de Vitrine, Auction y notificaciones in-app, por decisión del PO.

## Alternativas consideradas

| Alternativa | Resultado |
| --- | --- |
| Mantener SKU como identidad | descartada: acopla identidad interna a una referencia comercial y contradice HU-33 |
| Sustituir SKU y `/api/products` en un solo despliegue | descartada: rompe Web y los contratos de Commerce sin una ventana observable |
| Conservar `DRAFT/PUBLISHED/ARCHIVED` junto con estados funcionales | descartada: crea dos máquinas de estados y combinaciones contradictorias |
| Modelar `activo/único/suspendido` como un único enum | descartada: suspender perdería la modalidad de tiraje |
| Inventar la matriz de atributos en Arquitectura | descartada: es una decisión funcional sin fuente válida |
| Mantener OpenAPI solo generado desde el código | insuficiente para esta fase: impediría revisar el contrato antes de implementar; se mantiene la comparación obligatoria con el generado |

## Evidencia y aceptación

Para pasar este ADR a `Accepted` se requiere:

- aprobación registrada del Tech Lead en #281;
- confirmación del Product Owner sobre la matriz de atributos o corrección de
  la referencia funcional;
- OpenAPI válido y ejemplos de `201`, `403`, `409` y `422`;
- revisión de Catalog y al menos un consumidor;
- diagrama de compatibilidad renderizado;
- confirmación de que el contrato objetivo no se presenta como desplegado.

## Reversión

Antes de implementar, revertir consiste en retirar el contrato propuesto sin
afectar runtime. Durante la adopción, la ruta heredada permanece disponible y
la nueva se despliega de forma aditiva. Si falla una prueba de consumidor, se
deshabilita la ruta/versionado nuevo, se conserva el contrato heredado y no se
retira ningún alias ni índice.
