# ADR-025 — Aplicación de sanciones entre microservicios (HU-42)

- **Estado:** **Decidido el 2026-10-11** el contrato y el patrón de adopción. **No implementado todavía** en Combat, Catalog, Community, Missions, Player-Inventory, Commerce ni Tournament — ver «Lo que queda pendiente, con nombre y apellido».
- **Fecha:** 2026-10-11
- **Decide:** Arquitectura, en el cierre funcional de HU-42
- **Relacionado:** [ADR-004](ADR-004-identity-directory.md) (identidad y rol), `docs/contracts/hu-42-active-sanctions-v1.md`

## Contexto

Una auditoría dirigida de HU-42 (sanción progresiva) encontró que Account aplica y persiste sanciones correctamente, pero **ningún otro servicio de dominio verifica el estado de sanción de una cuenta**. Los ocho servicios que validan identidad (`JwtAuthGuard` + `CognitoTokenVerifier`) solo comprueban la firma, `exp`, `aud`/`iss` y los `cognito:groups` del testimonio — nunca el estado `SUSPENDED`/`BANNED` que vive exclusivamente en la base de datos de Account.

Consecuencia concreta: un testimonio emitido **antes** de una suspensión o un baneo sigue siendo aceptado por Combat, Catalog, Community, Missions, Player-Inventory, Commerce y Tournament hasta su `exp` (máximo 15 minutos, el mismo límite que ADR-004 ya documenta y acepta como riesgo residual — pero ese ADR lo acepta para cambios de **rol**, nunca lo extendió a sanciones de cuenta).

El único control real que existe hoy es **`Auction`**, que consulta a Account antes de que un vendedor publique una subasta (HU-62) o para cancelarla automáticamente por incumplimiento de términos (HU-90, CA-05). Es un buen diseño — síncrono, fail-closed, acotado — pero de alcance mínimo: no cubre pujar, ni ninguna acción en los otros siete servicios.

## Lo que YA existe y se reutiliza

`GET /internal/accounts/:subject/active-sanctions` (Account, `InternalSellerSanctionsController`), protegido por el contrato HMAC de `InternalServiceGuard` (`internal-signature.ts`). Formalizado ahora en `docs/contracts/hu-42-active-sanctions-v1.md` — hasta esta ADR no tenía contrato documentado, solo el docstring del código.

`INTERNAL_SERVICE_ALLOWED_SERVICES` en el compose de Infrastructure ya incluye `catalog,combat,auction,tournament`: **la autorización HMAC ya está abierta** para tres servicios que todavía no llaman al endpoint. `community`, `missions`, `player-inventory` y `commerce` no están ni siquiera en esa lista.

## Decisión

1. **El contrato de Account es la única fuente de verdad de sanción entre servicios.** Ningún servicio de dominio debe replicar el modelo de `Sanction`/`AccountStatus`; todos preguntan al mismo endpoint, igual que ya hace Auction.
2. **Patrón de adopción por servicio** (el que debe seguir cada PR futuro que implemente esto en Combat/Catalog/etc.): verificación **síncrona** antes de ejecutar una acción protegida que modifique estado (combate, compra, transferencia de inventario, puja, entrega de recompensa) — nunca en rutas de solo lectura públicas. **Fail-closed**: un timeout o error de Account bloquea la acción, igual que `UnavailableAuctionDependencies` ya hace en Auction. **Caché corta en memoria** (TTL de 30 a 60 segundos por `subject`) para no convertir cada petición mutante en una llamada de red nueva — se descartó consultar en cada petición sin caché, por el mismo motivo que ADR-004 ya descartó que los cuatro servicios preguntaran a Account el rol en cada petición: acopla el camino caliente y convierte una caída de Account en una caída de todo el sistema. La caché acota ese acoplamiento a, como mucho, el TTL elegido.
3. **No se generaliza el endpoint a nivel de lectura de testimonio** (es decir, `JwtAuthGuard` no pasa a llamar a Account en cada petición). La verificación vive en el caso de uso de la acción mutante concreta, no en el guard global — mismo razonamiento del punto 2.
4. **Riesgo residual aceptado, documentado explícitamente:** una acción ya en curso, o una lectura pública, puede seguir viendo a una cuenta recién sancionada durante el TTL de la caché más el tiempo que falte para que el testimonio expire. Es una extensión del riesgo de 15 minutos que ADR-004 ya acepta para rol, ahora también para sanción. No se intenta cerrar a cero: el costo de hacerlo (verificación síncrona sin caché en el camino caliente de ocho servicios) no se juzga proporcional al riesgo de una ventana acotada en minutos.
5. **`INTERNAL_SERVICE_ALLOWED_SERVICES` debe ampliarse** a `community,missions,player-inventory,commerce` en el mismo cambio que cada uno de esos servicios implemente el cliente — nunca antes: una autorización HMAC concedida sin un consumidor real es superficie abierta sin beneficio.

## Lo que queda pendiente, con nombre y apellido

Esta ADR decide el contrato y el patrón. **No implementa ningún cliente nuevo.** El trabajo que queda, servicio por servicio, es idéntico en forma al que ya existe en `Auction/src/adapters/outbound/http/HttpSellerSanctionClient.ts`:

| Servicio | Autorización HMAC hoy | Cliente implementado | Accion mutante que debería verificar |
| --- | --- | --- | --- |
| Auction | Sí | Sí (HU-62, HU-90) | Publicar subasta (hecho); **pujar (pendiente)** |
| Combat | Sí | No | Entrar a una sala de batalla |
| Catalog | Sí | No | Crear/publicar/archivar producto, cambiar precio |
| Tournament | Sí | No | Inscripción, validación de equipo |
| Community | No | No | Publicar comentario |
| Missions | No | No | Iniciar/completar misión |
| Player-Inventory | No | No | Equipar, desequipar, transferir |
| Commerce | No | No | Confirmar pedido |

Cada fila es un PR propio en su repositorio, fuera del alcance de esta ADR y de Infrastructure. Se deja registrado en vez de implementarlo sin la revisión de cada equipo dueño del servicio.

## Consecuencias

**Lo que se gana:** un contrato único, ya probado en producción por Auction, con un patrón de adopción explícito que no repite la discusión de ADR-004 sobre acoplamiento y disponibilidad.

**Lo que cuesta:** hasta que cada servicio implemente su cliente, el enunciado "una suspensión o un baneo bloquean el acceso a todos los servicios" sigue siendo falso para siete de los ocho. No se oculta: queda en esta tabla, no en una afirmación general sin matizar.
