# Contrato interno — Estado de sanción activa (HU-42)

- **Versión:** v1
- **Propietario:** `Nexus-Battle-Account` (autoridad única del modelo de sanciones)
- **Relacionado:** [ADR-025](../adr/ADR-025-cross-service-sanction-enforcement.md)

Este documento formaliza un endpoint que ya existe desde HU-62/HU-90
(`InternalSellerSanctionsController`) y que hasta ahora solo tenía el
docstring del código como contrato. No cambia su forma: la deja escrita para
que cualquier servicio nuevo que lo consuma (ver ADR-025) lo haga contra una
referencia estable, no contra el código fuente de otro repositorio.

## Endpoint

```
GET /internal/accounts/:subject/active-sanctions
```

- `:subject` es el sujeto del proveedor de identidad (el `sub` del testimonio
  Cognito), **no** el `id` de la cuenta en Account.
- Protegido por el contrato HMAC de `InternalServiceGuard`
  (`x-internal-service`, `x-internal-timestamp`, `x-internal-signature`).
  El servicio llamante debe estar en `INTERNAL_SERVICE_ALLOWED_SERVICES` de
  Account.
- Es una **consulta pura**: a diferencia de iniciar sesión, nunca reincorpora
  una cuenta cuya suspensión ya venció. Quien consume este endpoint ve el
  estado persistido tal cual, sin efectos secundarios.

## Respuesta — `200 OK`

```json
{
  "hasActiveSanctions": true,
  "sanctions": [
    {
      "id": "sancion-123",
      "type": "TEMPORARY_SUSPENSION",
      "reasonCode": "HARASSMENT",
      "expiresAt": "2026-10-20T15:30:00.000Z"
    }
  ]
}
```

- `hasActiveSanctions`: `true` si la cuenta tiene un `PERMANENT_BAN` o un
  `TEMPORARY_SUSPENSION` vigente. Las advertencias (`WARNING`) **nunca**
  aparecen aquí: no restringen acceso (§7.3.2 del documento funcional).
- `sanctions`: las restricciones activas, más reciente primero. Puede venir
  vacía aunque `hasActiveSanctions` sea `true` (cuenta `BANNED` sin fila de
  sanción, caso legado).
- `type`: `PERMANENT_BAN` o `TEMPORARY_SUSPENSION` únicamente.
- `reasonCode`: texto libre a propósito — un código que el consumidor no
  reconoce simplemente no dispara ningún comportamiento especial suyo. Hoy
  incluye el catálogo oficial de HU-42 más `OTHER`/`AUCTION_TERMS_VIOLATION`
  (compatibilidad histórica, HU-90); el catálogo puede crecer sin romper este
  contrato.
- `expiresAt`: fin de una suspensión temporal, `null` en un veto permanente.

## Otras respuestas

| Código | Significado | Qué debe hacer quien llama |
| --- | --- | --- |
| `401` | Firma HMAC inválida, servicio no autorizado, o sello de tiempo fuera de ventana | Tratarlo como fallo de configuración propio, nunca como "cuenta sin sanción" |
| `404` | El sujeto no tiene cuenta en Account | **No** tratarlo como sancionado — un sujeto no reconocido no es evidencia de sanción. Auction ya distingue este caso en `SellerActiveSanctionsPort.getActiveSanctions` |
| `503` | El contrato interno no está configurado (`INTERNAL_SERVICE_AUTH_SECRET` vacío) | Fail-closed en la acción protegida: un despliegue incompleto nunca debe interpretarse como "sin sanciones" |

## Patrón de consumo recomendado (ADR-025)

1. Verificación síncrona antes de ejecutar la acción mutante, nunca en rutas
   de solo lectura.
2. Caché en memoria de 30–60 segundos por `subject`, para no convertir cada
   petición mutante en una llamada de red nueva.
3. Fail-closed ante timeout o error — igual que
   `UnavailableAuctionDependencies` en Auction.

No es responsabilidad de este contrato decidir el TTL exacto ni el catálogo
de acciones protegidas de cada servicio: eso lo decide el PR que implemente
el cliente en ese repositorio.
