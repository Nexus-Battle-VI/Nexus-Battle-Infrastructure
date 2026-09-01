# Diseño de alto nivel — HU-43, eliminación de cuenta y datos asociados

Fija el contrato que HU-43 deberá implementar. **No implementa el
orquestador, la saga ni ningún endpoint** — ver [EN-011 §6](https://github.com/Nexus-Battle-VI/Nexus-Battle-Management/issues/197)
y el alcance declarado en el PR.

## Fuente normativa

Política v0.3 §10 (derecho de eliminación) y §11 (conservación y retención).
Ver el texto completo en [privacy-policy-v0.3.md](privacy-policy-v0.3.md#10-derecho-de-eliminación-de-cuenta-y-datos-asociados).

## Flujo de alto nivel

```text
Titular autenticado
       |
       v
Verificación de identidad
  (VerifiedIdentity.subject -> findBySubject -> Account,
   mismo patrón que GetOwnAccount/UpdateOwnAccount — ver
   portability-contract-v1.md)
       |
       v
Solicitud de eliminación
  (el sistema emite confirmación de RECEPCIÓN, Política §10;
   no es la confirmación de cierre todavía)
       |
       v
Orquestación por bounded contexts
  (mecanismo de transporte: PENDIENTE — depende de ADR-006,
   ver "Bloqueo real" más abajo)
       |
       v
Por cada bounded context, según la matriz de tratamiento:
  eliminar  -> dato sin excepción de retención
  anonimizar -> dato que pierde vínculo con el titular pero
                se conserva para agregados/estadística
  retener   -> dato con excepción de retención vigente
  (auditoría administrativa, registros financieros mientras
   dure la obligación aplicable, sanciones definitivas)
       |
       v
Confirmación de cierre
  (Política §10: "una vez finalizado el proceso, el usuario
   deberá recibir la notificación de cierre correspondiente")
```

Ver también el diagrama de secuencia:
[`hu-43-sequence-deletion.puml`](../diagrams/hu-43-sequence-deletion.puml).

## Plazo

**Máximo 30 días** desde la solicitud válida hasta el cierre (Política §10).
No se propone un plazo interno más corto en este documento: 30 días es el
límite normativo, no un objetivo de diseño a optimizar dentro de esta rama.

## Qué se elimina, qué se anonimiza, qué se retiene

Detalle categoría por categoría en la
[matriz de tratamiento](data-treatment-matrix-v0.3.md). Resumen de las
excepciones de retención que la Política **sí** fija explícitamente:

### Excepciones de retención

| Categoría | Excepción | Fuente |
| --- | --- | --- |
| Auditoría administrativa | Inmutable, mínimo **5 años**, sujeta a régimen propio | Política §11 |
| Sanciones definitivas | Régimen de conservación propio; la eliminación de cuenta no puede alterar la bitácora de auditoría asociada | Política §10, PARÁGRAFO |
| Información financiera/transaccional | Se conserva "durante el periodo exigido por las obligaciones aplicables" | Política §10, §11 — **periodo concreto no fijado; no se inventa un número en este documento** |

**No se agrega ninguna excepción adicional que las fuentes no establezcan.**
En particular, no se fija un periodo específico para información financiera
más allá de "el periodo exigido por las obligaciones aplicables" — ese
periodo concreto depende de una obligación legal/contable externa a este
repositorio, y afirmar un número aquí sería inventar un requisito.

### Registros sin owner asignado todavía

Como documenta la matriz, "sanciones definitivas" y "auditoría
administrativa" no tienen implementación ni owner de bounded context
verificado en código al momento de este PR. HU-43 no puede aplicar estas
excepciones sobre datos que no existen; su implementación real depende de
que esas piezas se construyan primero, o de que el alcance de HU-43 se acote
explícitamente a lo que sí existe (cuenta, inventario, comentarios,
transacciones).

## Bloqueo real: no existe orquestación entre bounded contexts

[ADR-006](../adr/ADR-006-messaging.md) sigue en estado `Proposed`. Verificado
en [integration.md](../architecture/integration.md): *"Los servicios no se
comunican entre sí todavía"*, y la saga de checkout (un caso más simple que
la eliminación, porque involucra menos contextos) está explícitamente
declarada como *"No implementado"*.

**HU-43 necesita coordinar como mínimo:** Account, Player/Inventory,
Community, Commerce, y cualquier owner futuro de auditoría/sanciones. Ninguno
de esos servicios tiene hoy un mecanismo de comunicación entre sí más allá de
puertos con implementación local (`InMemoryMessageQueue`,
`LocalCatalogPricing`, etc.).

**Consecuencia para el alcance de HU-43:** su implementación real depende de
que ADR-006 se acepte y se implemente el transporte (SQS es el candidato, ver
ADR-006). Hasta entonces, HU-43 puede avanzar en: verificación de identidad,
recepción de solicitud, confirmación, y la eliminación **dentro** de Account
(un solo bounded context, sin coordinación). La eliminación **entre**
contextos queda bloqueada por la misma razón que la saga de checkout.

## Verificación de identidad

Reutiliza el patrón ya implementado y verificado —
`VerifiedIdentity.subject -> findBySubject(...) -> Account` — descrito en
[portability-contract-v1.md](portability-contract-v1.md#verificado-en-código-la-identidad-del-titular-no-es-un-parámetro-de-la-petición).
No se introduce un mecanismo nuevo de verificación para HU-43.

## Qué NO define este documento

- el orquestador o saga concreta (SQS, Step Functions, u otro) — depende de
  ADR-006;
- el endpoint HTTP de solicitud de eliminación;
- el mecanismo exacto de "confirmación de recepción" vs. "confirmación de
  cierre" (¿correo vía Notifications? ¿estado consultable en el portal?);
- compensaciones si un bounded context falla a mitad de la eliminación.

Estas decisiones pertenecen a la implementación de HU-43, después de que
ADR-006 desbloquee el transporte entre contextos.
