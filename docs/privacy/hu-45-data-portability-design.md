# Diseño de alto nivel — HU-45, portal de privacidad y portabilidad

Fija el contrato que HU-45 deberá implementar. **No implementa endpoints,
exportadores JSON/XML, generador PDF ni UI de Portal.**

## Fuente normativa

Política v0.3 §8 (derechos del titular y Portal de privacidad) y §9 (acceso y
portabilidad). Ver texto completo en
[privacy-policy-v0.3.md](privacy-policy-v0.3.md#9-acceso-y-portabilidad-de-datos).

## Flujo de alto nivel

```text
JWT (emitido por Cognito, verificado contra JWKS — AUTH_MODE=jwt)
       |
       v
Identidad verificada
  (JwtAuthGuard dentro de cada servicio NestJS, patrón ya
   desplegado en los cinco servicios — ver security.md)
       |
       v
Titular
  (VerifiedIdentity.subject -> findBySubject(...) -> Account,
   mismo patrón verificado en GetOwnAccount.ts/UpdateOwnAccount.ts
   — NUNCA un accountId enviado arbitrariamente por Web)
       |
       v
Agregación autorizada de datos
  (por bounded context, cada uno resuelve SU parte del titular;
   ningún servicio consulta la base de otro — data-ownership.md)
       |
       v
JSON / XML / PDF
  (PDF exige explícitamente: inventario, estadísticas,
   comentarios, historial de transacciones — Política §9)
```

Ver también el diagrama de secuencia:
[`hu-45-sequence-portability.puml`](../diagrams/hu-45-sequence-portability.puml).

## La autoridad del titular NO es un parámetro enviado por Web

Verificado en código, no asumido: `GetOwnAccount.execute(subject: string)`
llama a `this.accounts.findBySubject(subject)`, donde `subject` es el claim
del JWT ya verificado, nunca un identificador que el cliente controle
([`GetOwnAccount.ts`](https://github.com/Nexus-Battle-VI/Nexus-Battle-Account/blob/main/src/application/use-cases/GetOwnAccount.ts)).
`UpdateOwnAccount` replica el mismo patrón. HU-45 debe seguir exactamente
esta forma en cada bounded context que agregue: el `subject` verificado viaja
hasta cada servicio (o hasta el agregador, según la decisión de arquitectura
de abajo), y cada servicio resuelve su propio dato **a partir del subject**,
no a partir de un ID que otro servicio le pase sin verificar.

## Alcance mínimo exigido por la Política (§9)

| Formato | Contenido mínimo |
| --- | --- |
| JSON | Datos personales definidos para el Portal — ver [matriz](data-treatment-matrix-v0.3.md) columna Exportable |
| XML | Mismo contenido que JSON |
| PDF | Inventario, estadísticas, comentarios, historial de transacciones (mínimo explícito de la Política) |

El detalle completo, categoría por categoría, y qué se excluye por defecto
(contraseñas, tokens, secretos MFA, hashes de respuestas de seguridad,
credenciales AWS, claims internos, datos internos de Cognito,
identificadores técnicos sin valor funcional, datos de terceros) está en
[portability-contract-v1.md](portability-contract-v1.md).

## Aislamiento entre titulares

Política §8: *"El portal deberá impedir que un titular visualice o exporte
datos pertenecientes a otra persona."* Consecuencia directa para el diseño:
ningún bounded context puede resolver "los comentarios del hilo X" y devolver
comentarios de otros autores solo porque comparten hilo — debe filtrar por
`author_id`/`customer_id`/equivalente igual al `subject` verificado del
titular, en cada contexto que agregue.

## Bloqueo real: agregación entre bounded contexts

Igual que HU-43, HU-45 necesita reunir datos de **varios** bounded contexts
(Account, Player/Inventory, Community, Commerce, y los pendientes de owner
—héroes/estadísticas, auditoría—) para producir un solo reporte por titular.
[ADR-006](../adr/ADR-006-messaging.md) sigue `Proposed`; no existe transporte
entre servicios todavía ([integration.md](../architecture/integration.md)).

A diferencia de HU-43 (que puede requerir consistencia transaccional para
garantizar que un dato no sobrevive donde no debería), la agregación de
lectura para exportar es más tolerante: **puede resolverse con llamadas
síncronas de solo lectura** desde un agregador hacia cada servicio (patrón ya
usado por `Commerce -> Catalog` para precio, ver
[integration.md](../architecture/integration.md)), sin depender
necesariamente de que ADR-006 (mensajería asíncrona) esté resuelto primero.
Esa es una vía de desbloqueo distinta a la de HU-43 y debe evaluarse en el
ADR correspondiente.

## Qué NO define este documento

- si el agregador vive en Account, en Web (llamando a cada servicio por
  separado), o en un servicio nuevo — decisión arquitectónica, candidato a
  [ADR-014](../adr/ADR-014-privacy-data-governance.md);
- el generador de PDF ni su plantilla;
- si el avatar se exporta como binario o como referencia;
- rate limiting o control de abuso sobre la generación de exportaciones.

Estas decisiones pertenecen a la implementación de HU-45.
