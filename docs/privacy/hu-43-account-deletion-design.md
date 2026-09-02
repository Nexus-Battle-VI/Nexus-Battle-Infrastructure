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
   no es la confirmación de cierre todavía — la petición HTTP
   termina aquí, el proceso sigue de forma durable)
       |
       v
Proceso de eliminación durable
  (coordinado por Account, llamadas síncronas por contexto,
   progreso persistido, idempotente, con reintento — ver
   "Estrategia de orquestación" más abajo. NO depende de ADR-006)
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
verificado en código al momento de este PR. **Esto no bloquea HU-43 ni
EN-011**: si esas categorías no existen físicamente en ningún servicio, HU-43
simplemente no tiene hoy datos de ese tipo que eliminar — no hay nada que
excepcionar todavía. La regla de retención (Política §10 PARÁGRAFO, §11)
queda documentada en la [matriz](data-treatment-matrix-v0.3.md) para cuando
ese bounded context se implemente: en ese momento deberá cumplirla desde el
primer día, no añadirla después.

## Estrategia de orquestación entre bounded contexts

**No existe hoy una decisión de cómo Account coordina la eliminación en
Player/Inventory, Community y Commerce — esa es la pieza que falta, no un
transporte de mensajería.** [ADR-006](../adr/ADR-006-messaging.md) sigue
`Proposed`, pero su alcance cubre tres integraciones concretas
(Account/Commerce → Notifications, Commerce → Catalog, Commerce →
Player/Inventory en checkout) y **no define el derecho al olvido**. Que
ADR-006 no esté aceptado no implica que HU-43 esté bloqueada.

[ADR-014](../adr/ADR-014-privacy-data-governance.md) (Decisión 5) propone la
estrategia concreta: **proceso de eliminación durable, coordinado por
Account mediante llamadas síncronas por contexto** — no una petición HTTP
mantenida abierta hasta que todo el proceso termine —, sin necesitar el
transporte asíncrono de ADR-006. Resumen:

1. Account verifica identidad, registra la solicitud y responde de
   inmediato al titular con la confirmación de RECEPCIÓN. La petición HTTP
   del titular termina ahí.
2. A partir de ese punto, de forma durable y fuera de esa petición, Account
   invoca el endpoint de eliminación de cada bounded context por su API
   (mismo patrón síncrono que `Commerce -> Catalog` para precio), de forma
   **idempotente** (reintentar una llamada no debe producir un efecto
   distinto de aplicarla una vez).
3. Cada contexto aplica su propia fila de la matriz de tratamiento y
   responde éxito, fallo, o "aplicado con excepción de retención".
4. Account persiste el progreso por contexto (no en memoria), reintenta los
   fallos transitorios dentro del plazo de 30 días, y solo cuando todos los
   contextos relevantes confirman (o registran su excepción de retención)
   emite la confirmación de cierre y dispara la notificación final.
5. Si Account se reinicia o despliega una nueva versión con solicitudes en
   curso, el proceso debe poder reanudarse desde el progreso ya persistido.

Esto es posible porque, a diferencia del checkout, la eliminación no compite
por ningún recurso escaso — no hay condición de carrera que una saga con
compensación deba resolver; el problema de fiabilidad se resuelve con
progreso durable e idempotencia, no con compensación. El detalle completo de
esta decisión, incluidas las propiedades exigidas (idempotencia, progreso
durable, reintentos, estados parciales, timeout, reanudación segura) y las
alternativas descartadas, está en
[ADR-014](../adr/ADR-014-privacy-data-governance.md#5-estrategia-de-orquestación-para-el-derecho-al-olvido-hu-43-coordinación-síncrona-por-api-sin-esperar-a-adr-006).

## Verificación de identidad

Reutiliza el patrón ya implementado y verificado —
`VerifiedIdentity.subject -> findBySubject(...) -> Account` — descrito en
[portability-contract-v1.md](portability-contract-v1.md#verificado-en-código-la-identidad-del-titular-no-es-un-parámetro-de-la-petición).
No se introduce un mecanismo nuevo de verificación para HU-43.

## Qué NO define este documento

- el endpoint HTTP concreto de solicitud de eliminación, ni el de cada
  bounded context;
- el formato exacto del registro de progreso por contexto;
- el mecanismo exacto de "confirmación de recepción" vs. "confirmación de
  cierre" (¿correo vía Notifications? ¿estado consultable en el portal?);
- qué ocurre si el plazo de 30 días se agota sin que todos los contextos
  confirmen.

Estas decisiones pertenecen a la implementación de HU-43, sobre la
estrategia de orquestación ya fijada en
[ADR-014](../adr/ADR-014-privacy-data-governance.md).
