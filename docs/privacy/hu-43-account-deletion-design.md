# Diseño de alto nivel — HU-43, eliminación de cuenta y datos asociados

Fija el contrato que HU-43 deberá implementar. **No implementa el proceso de
tratamiento ni ningún endpoint** — ver la "Decisión de alcance para HU-43" en
[EN-011 (Management #197)](https://github.com/Nexus-Battle-VI/Nexus-Battle-Management/issues/197)
y el alcance declarado en el PR.

## Fuente normativa

Política v0.3 §10 (derecho de eliminación) y §11 (conservación y retención).
Ver el texto completo en [privacy-policy-v0.3.md](privacy-policy-v0.3.md#10-derecho-de-eliminación-de-cuenta-y-datos-asociados).

## Alcance (EN-011, Management #197)

`Nexus-Battle-Account` es el owner de la cuenta y de los datos personales que
administra. HU-43 elimina o trata, conforme a las excepciones de retención
formalmente aprobadas, los datos personales propiedad de Account. La mera
presencia de un `subject` opaco en Community, Commerce, Player/Inventory,
Catalog u otro bounded context **no** obliga a ese servicio a participar en
la eliminación: no se adopta una orquestación general de borrado sobre esos
servicios solo porque conserven un `subject`. Si en el futuro se identifica
en otro bounded context un dato formalmente clasificado como personal y
sujeto a eliminación, su tratamiento requerirá Refinement o decisión
arquitectónica explícita antes de incorporarse a HU-43. Ver la decisión
completa en [EN-011 §"Decisión de alcance para HU-43"](https://github.com/Nexus-Battle-VI/Nexus-Battle-Management/issues/197)
y en [ADR-014 Decisión 5](../adr/ADR-014-privacy-data-governance.md#5-alcance-y-proceso-del-derecho-al-olvido-hu-43-ownership-de-account-sin-orquestación-multi-contexto).

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
Cuenta propia
       |
       v
Registrar solicitud (estado: recibida, de forma durable)
       |
       v
Confirmar recepción
  (Política §10; no es la confirmación de cierre todavía —
   la petición HTTP del titular termina aquí)
       |
       v
Proceso de tratamiento dentro de Account
  (estado persistente, idempotente, con manejo de errores si
   no se completa de inmediato — ver "El proceso, dentro de
   Account" más abajo. No coordina otros bounded contexts)
       |
       v
Eliminar/tratar los datos personales propiedad de Account,
según la matriz de tratamiento:
  eliminar  -> dato de Account sin excepción de retención
  anonimizar -> dato de Account que pierde vínculo con el
                titular pero se conserva para agregados/estadística
  retener   -> dato de Account con excepción de retención
                formalmente aprobada vigente
       |
       v
Cerrar la solicitud
       |
       v
Solicitar notificación de cierre
  (Política §10: "una vez finalizado el proceso, el usuario
   deberá recibir la notificación de cierre correspondiente";
   Notifications solo materializa el envío, no participa del
   tratamiento — contrato pendiente de HU-43, ver más abajo)
```

Community, Commerce, Player/Inventory, Catalog y demás bounded contexts
pueden conservar referencias técnicas opacas (`subject`) según su propio
ownership; no participan automáticamente en este flujo.

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
excepcionar todavía. Si esas categorías terminan viviendo en un bounded
context distinto de Account, su tratamiento **no se incorpora
automáticamente a HU-43**: por alcance de EN-011 (Management #197), eso
requeriría Refinement o decisión arquitectónica explícita, igual que
cualquier otro dato personal fuera de Account. La regla de retención
(Política §10 PARÁGRAFO, §11) queda documentada en la
[matriz](data-treatment-matrix-v0.3.md) para cuando corresponda evaluarla.

## Alcance dentro de Account (no orquestación entre bounded contexts)

Por decisión de [EN-011 (Management #197)](https://github.com/Nexus-Battle-VI/Nexus-Battle-Management/issues/197),
HU-43 **no coordina** la eliminación en Player/Inventory, Community ni
Commerce: la mera presencia de un `subject` opaco en esos servicios no los
hace partícipes del derecho al olvido. Esto no es una limitación pendiente
de resolver — es el alcance vigente. [ADR-006](../adr/ADR-006-messaging.md)
(mensajería) es, por lo tanto, irrelevante para HU-43: no hay ninguna llamada
entre bounded contexts que dependa de su transporte.

[ADR-014](../adr/ADR-014-privacy-data-governance.md) (Decisión 5) fija el
proceso concreto, **enteramente dentro de Account**:

1. Account verifica identidad, registra la solicitud y responde de
   inmediato al titular con la confirmación de RECEPCIÓN. La petición HTTP
   del titular termina ahí.
2. A partir de ese punto, de forma durable y fuera de esa petición, Account
   trata sus propios datos personales del titular: elimina, anonimiza o
   retiene según la matriz de tratamiento, **sin invocar a ningún otro
   bounded context**.
3. Si el tratamiento no se completa de inmediato, el proceso mantiene estado
   persistente, es idempotente y maneja errores dentro del plazo de 30 días.
4. Cuando el tratamiento de los datos propiedad de Account concluye (o queda
   registrado con su excepción de retención), Account cierra la solicitud y
   solicita la notificación final de cierre.
5. Si Account se reinicia o despliega una nueva versión con solicitudes en
   curso, el proceso debe poder reanudarse desde el estado ya persistido.

Esto es posible sin saga ni compensación porque, a diferencia del checkout,
el tratamiento no compite por ningún recurso escaso ni coordina otros
servicios — no hay condición de carrera que resolver. El detalle completo de
esta decisión, incluidas las propiedades exigidas y las alternativas
descartadas (entre ellas, la orquestación multi-contexto que este documento
tenía antes), está en
[ADR-014 — Decisión 5](../adr/ADR-014-privacy-data-governance.md#5-alcance-y-proceso-del-derecho-al-olvido-hu-43-ownership-de-account-sin-orquestación-multi-contexto).

## Verificación de identidad

Reutiliza el patrón ya implementado y verificado —
`VerifiedIdentity.subject -> findBySubject(...) -> Account` — descrito en
[portability-contract-v1.md](portability-contract-v1.md#verificado-en-código-la-identidad-del-titular-no-es-un-parámetro-de-la-petición).
No se introduce un mecanismo nuevo de verificación para HU-43.

## Qué NO define este documento

- el endpoint HTTP concreto de la solicitud de eliminación;
- el formato exacto del registro de estado dentro de Account;
- el contrato concreto de la notificación de cierre con Notifications (no
  existe todavía en [event-catalog.md](../contracts/event-catalog.md) — se
  declara pendiente de la implementación de HU-43, no se inventa aquí);
- el mecanismo exacto de "confirmación de recepción" vs. "confirmación de
  cierre" (¿correo vía Notifications? ¿estado consultable en el portal?);
- qué ocurre si el plazo de 30 días se agota sin completar el tratamiento.

Estas decisiones pertenecen a la implementación de HU-43, sobre el alcance y
el proceso ya fijados en
[ADR-014](../adr/ADR-014-privacy-data-governance.md).
