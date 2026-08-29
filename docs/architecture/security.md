# Seguridad

Ver [ADR-004](../adr/ADR-004-identity-directory.md).

## El estado que hay que conocer primero

**Los cinco servicios verifican quién realiza la petición.** Al 2026-08-29, con
`AUTH_MODE=jwt` y comprobado de extremo a extremo contra el pool real.

Este documento decía lo contrario hasta esa fecha, y el **BLOCKER de ADR-004**
que describía está resuelto en lo técnico:

| Paso | Estado |
| --- | --- |
| Elegir proveedor y presupuesto | **Hecho**: Cognito, plan Essentials |
| ~~Adaptador del alta de sujetos~~ | **Retirado**: el producto no da de alta identidades; el alta ocurre en la pantalla del proveedor |
| Validar el JWT contra el JWKS | **Hecho** |
| Validar el testimonio en cada servicio | **Hecho**: los cinco servicios NestJS |
| Activar RBAC en operaciones sensibles | **Hecho** |
| Reflejar el rol en el proveedor | **Hecho**: Account decide, el pool recoge |

La comprobación, contra el sistema desplegado:

| Ruta | Sin testimonio | Con testimonio |
| --- | --- | --- |
| `/`, `/api/products`, `/api/threads` | 200 | — |
| `GET /api/inventories/:id` | **401** | 404 |
| `GET /api/orders` | **401** | **200** |
| `POST /api/threads` | **401** | — |

Que `/api/orders` pase de 401 a 200 con el mismo testimonio prueba que la
verificación **no vive solo en Account**: la hace cada servicio.

## Lo que sigue abierto

- **Segundo factor de los roles administrativos.** ADR-004 lo previó por correo;
  el correo exige SES, que no está aprobado. `LoginAccount` **falla cerrado**
  mientras tanto: un rol administrativo con testimonio pero sin reto devuelve
  `providerUnavailable`. No se rebajó la regla para que el flujo pasara.
- **Exposición a internet, que son dos cambios acoplados.**
  `public_ingress_cidrs` está vacío, y la única URL de retorno registrada en
  Cognito es la de desarrollo local. Abrir lo primero sin añadir el origen
  desplegado a `callback_urls` rompe el inicio de sesión en cuanto alguien lo
  use.
- **Una sola identidad de AWS para todo el nodo `app`.** Cualquier contenedor de
  ese nodo puede obtener las mismas credenciales que Account. Es una limitación
  aceptada de la topología de ADR-011, no un descuido, y aislarla exige cambiar
  de topología.

## Lo que este documento describía y ya no ocurre

Se deja escrito en lugar de borrarlo: quien haya leído una versión anterior
necesita saber qué cambió, y un blocker que desaparece sin rastro parece que
nunca existió.

La tabla que sigue describe lo que ocurriría si el sistema se desplegara **sin** ese pool, con `AUTH_MODE=disabled`. **No es el estado actual**: el despliegue corre con `AUTH_MODE=jwt`. Se conserva porque `disabled` sigue siendo una configuración posible en desarrollo local, y conviene saber qué implica. En ese caso el sujeto registrado es literalmente `anonymous`: los datos dicen que nadie fue verificado, en lugar de aparentar personas concretas.

Y con `NODE_ENV=production`, esa configuración **impide arrancar el servicio**.

| Servicio | Qué queda sin proteger |
| --- | --- |
| Account | El registro y la verificación no exigen credencial |
| Catalog | Crear, publicar, archivar y cambiar precios no exige rol de administrador |
| Community | El `moderatorId` llega sin verificar |
| Commerce | El `customerId` llega sin verificar |
| Web | `useSession` guarda una identidad no verificada |

**Con `AUTH_MODE=disabled`, ningún servicio debe desplegarse en un entorno accesible desde internet.** Con `NODE_ENV=production` esa configuración además impide arrancar, de modo que la regla no depende de que alguien la recuerde.

## La decisión de no añadir seguridad aparente

Se decidió **no implementar comprobaciones de rol sobre identificadores no verificados**.

Un `if (rol === 'ADMINISTRATOR')` sobre un valor que el cliente envía sin firmar no es un control de seguridad. Es peor que su ausencia, porque induce a creer que existe una protección donde no la hay, y esa creencia sobrevive a la revisión.

Lo que sí se implementó es todo lo que **no** depende del proveedor:

- El modelo de roles completo en el dominio de Account.
- La regla de que el rol base no puede retirarse.
- La regla de que solo un administrador gestiona roles.

Cuando exista identidad verificable, activar el control será conectar el testimonio con reglas que ya están escritas y probadas.

## Lo que sí protege el sistema hoy

### El producto no custodia credenciales

Account **no almacena** contraseñas, hashes, sales, tokens de sesión ni secretos de segundo factor. El agregado modela cuenta y roles, no credenciales. Es la clase de dato con mayor consecuencia en caso de filtración, y el sistema simplemente no la tiene.

### Validación estricta en el borde

Los cinco servicios NestJS descartan propiedades no declaradas y **rechazan la petición si llegan campos desconocidos**. Consecuencias verificadas por prueba de integración:

| Intento | Resultado |
| --- | --- |
| Enviar `roles: ["ADMINISTRATOR"]` al registrar una cuenta | `400` |
| Enviar `status: "PUBLISHED"` al crear un producto | `400` |
| Enviar `unitPrice` al añadir una línea de pedido | `400` |
| Enviar `capacity` al añadir un objeto al inventario | `400` |

Sin esa configuración, un cliente podría fijar el precio de su propio pedido.

### Las reglas viven en el dominio

Una comprobación en el controlador puede saltarse llegando por otro adaptador. Por eso las reglas están en el dominio:

- `Quantity` impide por construcción un saldo negativo o fraccionario.
- `Money` impide importes fraccionarios y mezclar monedas.
- La capacidad del inventario se aplica en el agregado.
- La longitud del contenido de un mensaje se acota en el objeto de valor.

### Datos personales

| Dato | Tratamiento |
| --- | --- |
| Correo electrónico | Account lo almacena. La observabilidad registra **solo el dominio** |
| Nombre visible | Account lo almacena |
| Contenido de mensajes | Community lo almacena. **No se registra ni viaja en eventos** |
| Identificadores entre servicios | Opacos: ningún servicio conoce datos personales de otro contexto |

`community.post.published` transporta la **longitud** del mensaje, no el texto. Hay una prueba que verifica que el texto no aparece en el evento serializado.

## Seguridad de la cadena de suministro

| Control | Estado |
| --- | --- |
| Acciones de terceros fijadas por **SHA de commit completo** | Aplicado en los 8 repositorios, resuelto desde GitHub y verificado |
| `permissions: contents: read` en los workflows | Aplicado |
| Aprobación requerida para workflows de contribuciones externas | `all_external_contributors` |
| Creación y aprobación de PR por el token del workflow | Deshabilitadas |
| Retención de artefactos | 60 días |
| Dependabot agrupado, semanal | Configurado; los cambios de versión mayor requieren revisión humana |
| Escaneo de secretos y protección de subida | Ver `docs/governance` |
| CodeQL | Ver `docs/governance` |

Ningún repositorio contiene secretos. `.env` está ignorado y `.env.example` documenta las variables sin valores reales.

## Contenedores

| Control | Aplicado |
| --- | --- |
| Multi-etapa | Sí, en los siete |
| Usuario sin privilegios | Sí. `node` en los servicios; en Web se **crea** el usuario `web`, porque la imagen de Caddy corre como root y no trae uno |
| Solo dependencias de producción | Sí |
| Sin ficheros de entorno en la imagen | Sí, vía `.dockerignore` |
| Healthcheck | Sí |

La imagen de Web **no incluye runtime de Node**: es Caddy sirviendo estáticos, lo que elimina el intérprete de JavaScript de la superficie de ataque.

## Cabeceras del frontend

```text
X-Content-Type-Options: nosniff
Referrer-Policy: strict-origin-when-cross-origin
X-Frame-Options: DENY
```

La cabecera `Server` se retira: solo informa a quien busca vulnerabilidades conocidas.

## Sobre el frontend

**Todo lo que se envía al navegador es público.** Cualquier variable con prefijo `VITE_` acaba en el paquete servido al cliente. No se declara ningún secreto en `Nexus-Battle-Web`.

`useSession` mantiene la identidad **en memoria y no en `localStorage`**, de forma deliberada: persistir una identidad no verificada daría apariencia de una sesión que no existe.

## Credenciales de despliegue

No se usan claves de acceso de larga duración de AWS. Cuando se habilite el despliegue, la autenticación usará **OIDC con credenciales de corta duración**. Los *subjects* inmutables por repositorio están documentados en [developer-workflow.md](developer-workflow.md).

## Reporte de vulnerabilidades

Mediante el **reporte privado de vulnerabilidades** de GitHub, no por Issues públicas ni Pull Requests. Cada repositorio tiene su `SECURITY.md`.
