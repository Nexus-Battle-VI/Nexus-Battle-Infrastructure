# Política de seguridad

## Alcance

Esta política cubre el código de `Nexus-Battle-Infrastructure`. Nexus Battles VI es un producto académico en desarrollo: no existe todavía una versión en producción con datos reales de usuarios.

## Versiones soportadas

| Versión | Estado                                                 |
| ------- | ------------------------------------------------------ |
| `0.1.x` | En desarrollo activo. Recibe correcciones de seguridad |

## Reporte de vulnerabilidades

Las vulnerabilidades **no se reportan mediante Issues públicas ni Pull Requests**.

Se utiliza el reporte privado de vulnerabilidades de GitHub, disponible en la pestaña _Security_ de este repositorio. Un reporte útil incluye:

- Componente afectado y versión o commit.
- Descripción del problema y su impacto.
- Pasos reproducibles.
- Configuración necesaria para reproducirlo.

El equipo propietario acusa recibo y coordina la corrección junto con los Scrum Masters. La divulgación se realiza después de que la corrección esté integrada.

## Controles activos en el repositorio

- Grafo de dependencias y alertas de Dependabot.
- Actualizaciones de seguridad de dependencias agrupadas y programadas.
- Escaneo de secretos con protección de subida.
- Análisis estático de código con CodeQL.
- Revisión obligatoria del Code Owner antes de integrar en `main`.
- Historial lineal y prohibición de forzar la subida o eliminar `main`.
- Permisos de solo lectura por defecto para el token de los workflows.
- Acciones de terceros fijadas por SHA de commit completo.
- Aprobación requerida para ejecutar workflows de contribuciones externas.

## Manejo de secretos

- No se incorporan secretos, credenciales, tokens ni claves al repositorio.
- La configuración sensible se entrega por variables de entorno. `.env` está ignorado por Git; `.env.example` documenta las variables sin valores reales.
- La imagen de contenedor no incluye archivos de entorno ni credenciales.
- No se utilizan claves de acceso de larga duración de AWS. Cuando se habilite el despliegue, la autenticación usará OIDC con credenciales de corta duración.
- La evidencia enlazada desde las Issues no debe contener secretos.

## Consideraciones específicas de este repositorio

Este repositorio **no contiene código ejecutable**. Su riesgo de seguridad es distinto al de un servicio, y también real:

- **La documentación no debe contener secretos.** Ni credenciales de ejemplo que parezcan reales, ni identificadores de cuenta, ni URLs internas con token. CI verifica automáticamente su ausencia.
- Las credenciales de la composición de referencia son **explícitamente de ejemplo**, están acompañadas de la instrucción de sustituirlas y solo sirven para desarrollo local.
- **Describir mal el estado de la seguridad es un riesgo en sí mismo.** Afirmar que existe un control que no existe induce a desplegar un sistema desprotegido. Por eso la ausencia de control de acceso está declarada de forma prominente en el README, en el SAD y en `docs/architecture/security.md`.
- La plantilla de ruleset conserva un placeholder deliberado. **Aplicarla sin sustituirlo bloquearía todas las integraciones de forma permanente**, y CI verifica que el placeholder sigue ahí.

## Identidad

La integración con un proveedor de identidad y con un directorio corporativo permanece pendiente de aprobación. Es un **BLOCKER activo** del proyecto: ningún servicio verifica quién realiza la petición.

**Ningún servicio del producto debe desplegarse en un entorno accesible desde internet sin resolverlo.**

Detalle completo en [ADR-004](docs/adr/ADR-004-identity-directory.md).
