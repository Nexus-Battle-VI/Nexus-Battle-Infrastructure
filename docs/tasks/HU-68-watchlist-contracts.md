# HU-68 — Contratos de lista de seguimiento de subastas

Referencia: `Refs Nexus-Battle-VI/Nexus-Battle-Management#53`.

## Alcance documentado

Infrastructure conserva los contratos que conectan las tareas de HU-68:

- `docs/contracts/auction-watchlist-v1.md`: alta, consulta y baja autenticadas de TASK 68.2.
- `docs/contracts/auction-watchlist-events-v1.md`: eventos, firma HMAC, respuestas e idempotencia de TASK 68.3–68.4.

## Decisiones

- Auction es propietario de la watchlist y deriva el jugador desde el JWT.
- Notifications recibe únicamente eventos internos firmados.
- Los contratos están versionados mediante el campo `eventType`.
- Los reintentos se resuelven con un `eventId` estable.
- Web consume la API pública y el historial existente de Notifications.

## Changelog / Registro de cambios

- Añadido el contrato HTTP de seguimiento.
- Añadido el contrato de eventos de cambios y cierre próximo.
- Documentados autenticación, errores, destinatarios y semántica de replay.

PR: https://github.com/Nexus-Battle-VI/Nexus-Battle-Infrastructure/pull/130
