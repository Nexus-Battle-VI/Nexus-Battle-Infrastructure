# ADR-010 — Proxy inverso y entrada al sistema

- **Estado:** Proposed
- **Fecha:** 2026-08-21
- **Decide:** Arquitectura
- **Relacionado:** [ADR-003](ADR-003-frontend-stack.md), [ADR-007](ADR-007-aws-cost-optimized-platform.md)

## Contexto

En la arquitectura de demo, seis contenedores y un conjunto de ficheros estáticos deben ser accesibles desde internet por un único nombre de dominio y con TLS. El presupuesto excluye ALB y NLB por su coste fijo por hora.

Además, el plan plantea una pregunta explícita: **si API Gateway HTTP API aporta valor** o duplica la función del proxy inverso.

## Decisión

### Caddy como proxy inverso y servidor de estáticos

```text
Internet --HTTPS--> Caddy (en la propia EC2)
                      |
                      +-- /            -> estaticos de Web
                      +-- /api/accounts    -> :3000
                      +-- /api/inventories -> :3002
                      +-- /api/products    -> :3003
                      +-- /api/threads     -> :3004
                      +-- /api/orders      -> :3005
```

Motivos concretos:

| Criterio | Caddy | Nginx |
| --- | --- | --- |
| TLS automático | **Sí**, Let's Encrypt sin configuración ni renovación manual | Requiere certbot y su renovación |
| Configuración | Un fichero corto y legible | Más verbosa |
| Coste | Cero, corre en la instancia ya presupuestada | Cero |
| HTTP/2 y HTTP/3 | Por defecto | Configurable |

El TLS automático es lo que decide. Un certificado que caduca sin renovarse es un fallo recurrente y evitable, y en un equipo de 18 personas con rotación esa automatización vale más que la familiaridad con Nginx.

### Una consecuencia de diseño importante

Que todo pase por `/api` bajo el **mismo origen** significa que **la aplicación web no conoce la topología de los servicios**. No hay CORS que configurar, no hay lista de dominios que mantener y no hay ninguna URL de servicio incrustada en el frontend.

Esa indirección es lo que permite que la demo corra en una máquina y que la arquitectura objetivo viva detrás de un balanceador **sin cambiar una línea del frontend**. Es la razón de que `src/lib/http.ts` sea la única puerta de salida de la aplicación.

### API Gateway HTTP API: queda propuesto y no adoptado

API Gateway es *usage-based* y encajaría en el techo de coste. Se evaluó qué aportaría **por encima de lo que Caddy ya hace**:

| Capacidad de API Gateway | ¿Aporta hoy? |
| --- | --- |
| Enrutado por ruta | No: Caddy ya lo hace |
| TLS | No: Caddy ya lo automatiza |
| Limitación de tasa | Sí, sería útil — pero Caddy también puede |
| Autorización con JWT | **Sería valioso**, pero depende del proveedor de identidad ([ADR-004](ADR-004-identity-directory.md)), que está bloqueado |
| WAF y protección de borde | Sí, a coste adicional |
| Métricas por ruta | Sí, pero no hay tráfico que medir |

**Conclusión: en el alcance actual duplicaría el proxy inverso sin aportar valor.** Se deja en `Proposed`.

Se reconsiderará cuando se cumpla alguna de estas condiciones:

1. Exista un proveedor de identidad y se quiera validar el token **en el borde** en lugar de en cada servicio.
2. El tráfico justifique limitación de tasa gestionada.
3. La arquitectura objetivo introduzca un balanceador y convenga unificar la entrada.

### Cabeceras de seguridad

El Caddy que sirve los estáticos envía:

```text
X-Content-Type-Options: nosniff
Referrer-Policy: strict-origin-when-cross-origin
X-Frame-Options: DENY
```

Y retira la cabecera `Server`, que solo informa a quien busca vulnerabilidades conocidas.

### Enrutado en el cliente

Cualquier ruta desconocida devuelve `index.html` para que React Router la resuelva. Sin eso, recargar en `/catalog` produciría un `404`. **El job de Docker en CI verifica exactamente ese comportamiento.**

### Caché

| Recurso | Política | Por qué |
| --- | --- | --- |
| `/assets/*` | `max-age=31536000, immutable` | El nombre lleva huella: si cambia el contenido, cambia la URL |
| `index.html` | `no-cache` | Es el punto de entrada; debe revalidarse para que un despliegue nuevo llegue al navegador |

## Consecuencias

**Lo que se gana**

- Un único punto de entrada, con TLS automático y coste cero adicional.
- El frontend queda desacoplado de la topología de servicios.
- La imagen de Web no incluye runtime de Node: es Caddy sirviendo ficheros, lo que reduce su superficie de ataque.

**Lo que cuesta**

- Caddy corre **en la misma instancia** que los servicios: si la instancia cae, cae también la entrada. Es coherente con el punto único de fallo ya declarado en [ADR-007](ADR-007-aws-cost-optimized-platform.md), y no lo agrava.
- Sin API Gateway no hay WAF gestionado en el borde.

## Alternativas consideradas

| Alternativa | Por qué se descartó |
| --- | --- |
| ALB o NLB | Coste fijo por hora que consume parte significativa del techo |
| API Gateway HTTP API | Duplicaría el proxy sin aportar valor **hoy**. Queda propuesto |
| Nginx | Equivalente en función, pero exige gestionar la renovación de certificados |
| Traefik | Buen encaje con Docker, pero configuración más compleja para un caso estático |
| Exponer cada servicio en su puerto | Obligaría a CORS, a incrustar URLs en el frontend y a exponer seis puertos |

## Evidencia

- El `Caddyfile` de `Nexus-Battle-Web` está en el repositorio y el job `docker` de su CI verifica que el servidor responde y que una ruta desconocida devuelve el index.
- La aplicación web construye todas sus peticiones bajo `/api` desde un único cliente HTTP, verificado por prueba.
- El fichero de composición para la demo está en `compose/compose.example.yml`.
