# ADR-009 — Observabilidad

- **Estado:** Proposed
- **Fecha:** 2026-08-21
- **Decide:** Arquitectura
- **Relacionado:** [ADR-007](ADR-007-aws-cost-optimized-platform.md)

## Contexto

Seis servicios distribuidos necesitan ser observables. Al mismo tiempo, las plataformas de observabilidad gestionadas tienen coste por volumen ingerido, y el techo del Sprint es de USD 100 al mes.

La pregunta no es «qué herramienta», sino **qué se necesita observar de verdad en el alcance actual**.

## Decisión

### Registro estructurado, ya implementado

Los seis servicios y el worker emiten **JSON por línea** con la misma forma:

```json
{
  "timestamp": "2026-08-21T10:00:00.000Z",
  "level": "info",
  "service": "nexus-battle-account",
  "version": "0.1.0",
  "message": "notification_requested",
  "notificationId": "acc-1"
}
```

Tres decisiones deliberadas:

1. **El logger es el único punto autorizado para escribir en la salida estándar.** La regla `no-console` de ESLint lo hace cumplir en todo el código salvo en el propio módulo de observabilidad. Sin esa regla, aparecen `console.log` sueltos que rompen el formato y hacen inútil la agregación.
2. **El sumidero es inyectable.** Permite verificar la salida en pruebas sin capturar la consola global. El logger está cubierto por pruebas en los seis servicios.
3. **El mensaje es un identificador estable** (`notification_requested`), no una frase. Buscar por `message` funciona; buscar por texto libre traducido no.

### Qué no se registra

| Dato | Por qué |
| --- | --- |
| Direcciones de correo completas | Dato personal. Account registra **el dominio**, no la dirección |
| Contenido de mensajes de Community | Texto escrito por personas usuarias |
| Cuerpos de correo renderizados | Pueden contener códigos de verificación |
| Credenciales del proveedor de correo | Evidente, y verificado por el escaneo de secretos |

### Sondas de salud, ya implementadas

| Ruta | Semántica |
| --- | --- |
| `GET /health/live` | El proceso responde. **No consulta dependencias**: reiniciar el servicio no repara una dependencia caída, así que declararla aquí produciría reinicios inútiles |
| `GET /health/ready` | Evalúa las dependencias reales. Responde `503` cuando alguna falla, para que el balanceador retire la instancia en lugar de enviarle tráfico |
| `GET /version` | Servicio, versión y entorno |

Dos reglas que se verifican por prueba:

- **Una comprobación que lanza una excepción cuenta como fallo, nunca como éxito.**
- `ready` nunca devuelve `ok` de forma incondicional. Commerce, por ejemplo, evalúa **dos** dependencias: su repositorio y el catálogo de precios.

Una readiness falsa es peor que no tenerla: hace que el orquestador envíe tráfico a una instancia que no puede atenderlo.

### Qué no se implementa todavía, y por qué

| Capacidad | Estado | Motivo |
| --- | --- | --- |
| **Trazas distribuidas** | No implementadas | Los servicios **todavía no se llaman entre sí** ([ADR-006](ADR-006-messaging.md)). Una traza sin salto entre servicios no aporta nada sobre el log |
| **Métricas** | No implementadas | Sin tráfico real no hay serie temporal que interpretar |
| **Agregación central de logs** | No implementada | En una sola instancia, `docker logs` cumple el papel |
| **Alertas** | Solo de coste | Alertar sobre un sistema sin tráfico produce ruido, no señal |

Estas ausencias **no son un olvido**. Implementar observabilidad para tráfico que no existe produce paneles vacíos que dan una falsa sensación de control.

### Qué sí se activa antes de cualquier despliegue

| Elemento | Cuándo |
| --- | --- |
| **Alertas de coste de AWS Budgets** | Antes que cualquier recurso de cómputo |
| Retención de logs acotada | Al configurar el destino |

## Camino de evolución

```text
Hoy          log estructurado + sondas de salud
Con SQS      metricas de profundidad de cola y edad del mensaje mas antiguo
Con saga     trazas distribuidas con OpenTelemetry
A escala     agregacion central, alertas por SLO, panel de servicio
```

**OpenTelemetry** es el candidato para las trazas: es estándar y permite cambiar el destino sin tocar el código instrumentado. No se adopta hoy porque no hay saltos entre servicios que trazar.

## Consecuencias

**Lo que se gana**

- Los logs son consultables y agregables desde el primer día, sin coste.
- La regla `no-console` impide la erosión del formato con el tiempo.
- Las sondas dicen la verdad, verificada por prueba.

**Lo que cuesta**

- Sin trazas, diagnosticar un fallo que cruce servicios exigirá correlacionar logs a mano. Es aceptable mientras no haya llamadas entre servicios; dejará de serlo en cuanto las haya.
- Sin métricas, no hay base para definir un SLO.

## Alternativas consideradas

| Alternativa | Por qué se descartó |
| --- | --- |
| CloudWatch Logs desde el inicio | Coste por ingesta y retención sin beneficio a este volumen |
| Datadog, New Relic | Coste por host muy por encima del techo |
| Prometheus + Grafana autoalojados | Consumen recursos de la única instancia y requieren operación, sin métricas que recoger todavía |
| Logging sin estructura | Barato de escribir, imposible de agregar después |

## Evidencia

- Los seis servicios emiten JSON estructurado con umbral de nivel configurable, verificado por prueba.
- `no-console` está activa en los seis repositorios con excepción únicamente en `infrastructure/observability`.
- Las sondas responden correctamente en los binarios compilados: se verificó `/health/ready` en Account, Player-Inventory, Catalog, Community, Commerce y Notifications.
