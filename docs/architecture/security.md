# Seguridad

Ver [ADR-004](../adr/ADR-004-identity-directory.md).

## El estado que hay que conocer primero

**Ningún servicio verifica quién realiza la petición.**

No es un descuido: no existe un proveedor de identidad autorizado ni presupuesto aprobado para un directorio corporativo. Es un **BLOCKER declarado**.

| Servicio | Qué queda sin proteger |
| --- | --- |
| Account | El registro y la verificación no exigen credencial |
| Catalog | Crear, publicar, archivar y cambiar precios no exige rol de administrador |
| Community | El `moderatorId` llega sin verificar |
| Commerce | El `customerId` llega sin verificar |
| Web | `useSession` guarda una identidad no verificada |

**Ningún servicio debe desplegarse en un entorno accesible desde internet sin resolver este blocker.**

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
| Usuario sin privilegios | Sí (`node` o `caddy`) |
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
