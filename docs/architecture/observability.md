# Observabilidad

Ver [ADR-009](../adr/ADR-009-observability.md).

## Registro estructurado

Los siete deployables emiten **JSON por línea** con la misma forma:

```json
{
  "timestamp": "2026-08-21T10:00:00.000Z",
  "level": "info",
  "service": "nexus-battle-account",
  "version": "0.1.0",
  "message": "notification_requested",
  "notificationId": "acc-1",
  "recipientDomain": "nexus.test"
}
```

Tres decisiones deliberadas:

**1. El logger es el único punto autorizado para escribir en la salida estándar.** La regla `no-console` de ESLint lo hace cumplir en todo el código, con excepción únicamente en el propio módulo de observabilidad. Sin esa regla aparecen `console.log` sueltos que rompen el formato y hacen inútil la agregación.

**2. El sumidero es inyectable.** Permite verificar la salida en pruebas sin capturar la consola global. El logger está cubierto por pruebas en los siete repositorios.

**3. El mensaje es un identificador estable**, no una frase. Buscar por `message: "notification_requested"` funciona; buscar por texto libre traducible, no.

## Niveles

| Nivel | Uso |
| --- | --- |
| `debug` | Detalle de desarrollo |
| `info` | Hechos del negocio: cuenta registrada, mensaje enviado, lote procesado |
| `warn` | Situación recuperable: reencolado, driver no disponible |
| `error` | Fallo que requiere atención: mensaje descartado a la cola de fallidos |

Se configura con `LOG_LEVEL`. Por debajo del umbral, el registro se descarta sin construirse.

## Qué no se registra

| Dato | Motivo |
| --- | --- |
| Direcciones de correo completas | Dato personal. Account registra **el dominio**, no la dirección |
| Contenido de mensajes de Community | Texto escrito por personas usuarias |
| Cuerpos de correo renderizados | Pueden contener códigos de verificación |
| Credenciales del proveedor de correo | Evidente, y verificado por el escaneo de secretos |

## Sondas de salud

| Ruta | Semántica | Por qué así |
| --- | --- | --- |
| `/health/live` | El proceso responde | **No consulta dependencias**: reiniciar el servicio no repara una dependencia caída, y declararla aquí produciría reinicios inútiles |
| `/health/ready` | Evalúa dependencias reales | Responde `503` cuando alguna falla, para que el balanceador retire la instancia en lugar de enviarle tráfico |
| `/version` | Servicio, versión y entorno | Permite confirmar qué está desplegado |

Dos reglas verificadas por prueba en los siete deployables:

- **Una comprobación que lanza una excepción cuenta como fallo, nunca como éxito.**
- `ready` **nunca devuelve `ok` de forma incondicional**.

Ejemplos de comprobaciones reales:

| Servicio | Qué evalúa `ready` |
| --- | --- |
| Account | Repositorio de cuentas |
| Player / Inventory | Repositorio de inventarios |
| Catalog | Repositorio de productos |
| Community | Repositorio de hilos |
| Commerce | Repositorio de pedidos **y** catálogo de precios |
| Notifications | Consumidor **y** último sondeo de la cola |

Una readiness falsa es peor que no tenerla: hace que el orquestador envíe tráfico a una instancia que no puede atenderlo.

## Qué no está implementado, y por qué

| Capacidad | Motivo |
| --- | --- |
| **Trazas distribuidas** | Los servicios **no se llaman entre sí** todavía. Una traza sin salto entre servicios no aporta nada sobre el log |
| **Métricas** | Sin tráfico real no hay serie temporal que interpretar |
| **Agregación central** | En una sola instancia, `docker logs` cumple el papel |
| **Alertas de aplicación** | Alertar sobre un sistema sin tráfico produce ruido, no señal |

Estas ausencias **no son un olvido**. Implementar observabilidad para tráfico que no existe produce paneles vacíos que dan una falsa sensación de control.

## Lo que sí se activa antes de cualquier despliegue

| Elemento | Cuándo |
| --- | --- |
| **Alertas de coste de AWS Budgets** | **Antes** que cualquier recurso de cómputo |
| Retención de logs acotada | Al configurar el destino |

Un despliegue sin alerta de coste es un riesgo de presupuesto sin control, y el techo del proyecto es de USD 100 al mes.

## Evolución prevista

```text
Hoy          log estructurado + sondas de salud
Con SQS      metricas de profundidad de cola y edad del mensaje mas antiguo
Con saga     trazas distribuidas con OpenTelemetry
A escala     agregacion central, alertas por SLO, panel por servicio
```

**OpenTelemetry** es el candidato para las trazas: es estándar y permite cambiar el destino sin tocar el código instrumentado. No se adopta hoy porque no hay saltos entre servicios que trazar.

Las dos primeras métricas útiles cuando exista SQS son la **profundidad de la cola** y la **edad del mensaje más antiguo**: juntas indican si el worker sigue el ritmo de producción, que es la pregunta operativa relevante en un consumidor asíncrono.
