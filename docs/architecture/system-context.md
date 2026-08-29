# Contexto del sistema

Diagrama en [system-context.puml](../diagrams/system-context.puml).

## Actores

| Actor | Interacción |
| --- | --- |
| **Jugador** | Usa la aplicación web: cuenta, inventario, catálogo, comunidad y pedidos |
| **Moderador** | Oculta mensajes y cierra hilos en Community |
| **Administrador** | Gestiona el catálogo y los roles de las cuentas |

Los tres roles existen en el dominio de Account (`PLAYER`, `MODERATOR`, `ADMINISTRATOR`), pero **hoy ninguno se verifica**: no hay proveedor de identidad autorizado. Ver [ADR-004](../adr/ADR-004-identity-directory.md).

## Sistemas externos

| Sistema | Relación | Estado |
| --- | --- | --- |
| Proveedor de identidad | Autentica a las personas usuarias, y da de alta las cuentas en su propia pantalla | **Amazon Cognito**, `us-east-1_HrEiSzzKW`, aprovisionado y en uso por los cinco servicios |
| Proveedor de correo | Entregaría las notificaciones | **No integrado.** Opera `FakeEmailSender`; en local, Mailpit por SMTP |
| Directorio corporativo | Censo de personas de la organización | **No provisionado** por coste |

## Frontera del sistema

```text
                    [ Jugador / Moderador / Administrador ]
                                    |
                                  HTTPS
                                    |
        +---------------------------v---------------------------+
        |                  Nexus Battles VI                      |
        |                                                        |
        |   Web  ->  Account · Player/Inventory · Catalog         |
        |            Community · Commerce · Notifications         |
        +--------------------------------------------------------+
              |                        |
      (pendiente ADR-004)      (pendiente aprobacion)
              |                        |
   [ Proveedor de identidad ]  [ Proveedor de correo ]
```

Las dos relaciones externas están **pendientes**, y ambas por el mismo motivo de fondo: requieren una aprobación que no depende del equipo técnico.

## Qué entra y qué sale hoy

| Flujo | Estado |
| --- | --- |
| Navegador → Web (HTTPS) | Operativo |
| Web → servicios (`/api` por proxy inverso) | Operativo para Catalog; el resto de pantallas son marcadores declarados |
| Servicios → proveedor de identidad | **No existe** |
| Notifications → proveedor de correo | **No integrado** |
| Servicio → servicio | **No implementado.** Ver [integration.md](integration.md) |

El sistema es hoy un conjunto de servicios que funcionan de forma aislada y verificable, no un sistema integrado. Esa distinción es deliberada y su motivo está en [ADR-006](../adr/ADR-006-messaging.md).
