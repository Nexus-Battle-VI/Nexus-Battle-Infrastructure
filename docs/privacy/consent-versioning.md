# Consentimiento y versionado de la Política

Analiza el gap entre lo que la [Política v0.3 §6](privacy-policy-v0.3.md#6-autorización-y-consentimiento)
exige como evidencia de consentimiento y lo que `Nexus-Battle-Account`
persiste hoy. **Esta rama no modifica Account** — documenta el requisito y el
gap para que HU-43/HU-45 o una Task futura lo resuelvan.

## Requisito funcional (Política v0.3 §6 y Anexo A)

> "La plataforma deberá mantener evidencia verificable de la aceptación,
> incluyendo como mínimo la **versión de la Política aceptada** y el
> **momento en que se produjo la manifestación**."

Tres elementos mínimos, explícitos en el texto:

1. **Titular/cuenta** — a quién pertenece la aceptación.
2. **Versión de la Política presentada** — cuál version del documento vio y
   aceptó.
3. **Fecha y hora de la aceptación** — cuándo ocurrió la manifestación.

La Política deja explícitamente abierta la forma técnica: *"El diseño físico
de tablas, eventos, logs o servicios utilizados para dicha evidencia
pertenece a la arquitectura técnica y no se fija mediante este documento"*
(Anexo A). Este documento separa esa decisión (arquitectónica) del requisito
(funcional) precisamente por esa instrucción.

## Estado actual verificado en código

`Nexus-Battle-Account` almacena un único campo:

```ts
// src/domain/entities/Account.ts — Account.register(...)
termsAccepted: boolean
```

Persistido como `accounts.terms_accepted boolean not null` en PostgreSQL
([schema real verificado](https://github.com/Nexus-Battle-VI/Nexus-Battle-Account/blob/main/src/adapters/outbound/persistence/schema.ts)).
`RegisterAccount.ts` lo exige `=== true` para completar el alta, pero no
acepta ni guarda ningún otro dato sobre el consentimiento — [verificado en
`RegisterAccount.ts`](https://github.com/Nexus-Battle-VI/Nexus-Battle-Account/blob/main/src/application/use-cases/RegisterAccount.ts).

También existen `accounts.created_at`/`updated_at`, pero **no están atados a
la aceptación de la Política** — son marcas de auditoría técnica del registro
de la fila, no evidencia de consentimiento. Usarlas como sustituto de "fecha
de aceptación" sería una inferencia, no un dato registrado con ese propósito.

## El gap

| Elemento exigido por la Política §6 | ¿Existe hoy? |
| --- | --- |
| Titular/cuenta de la aceptación | Sí, implícito — la fila de `accounts` pertenece a un titular |
| Versión de la Política aceptada | **No** — no hay columna ni registro que indique qué versión (`v0.1`, `v0.2`, `v0.3`...) vio el usuario |
| Fecha y hora de la manifestación | **No** — `terms_accepted` es un booleano sin marca de tiempo propia |

**Conclusión: el booleano actual NO es suficiente para demostrar qué versión
de la Política aceptó un usuario ni cuándo lo hizo.** Es apto para bloquear el
registro sin aceptación (lo hace hoy), pero no para producir evidencia
verificable si se cuestiona el consentimiento después.

## Requisito funcional (lo que debe existir, sin decidir cómo)

1. Cada aceptación debe quedar vinculada a: la cuenta, un identificador de
   versión de Política, y una marca de tiempo.
2. El identificador de versión debe ser estable y consultable — cuando la
   Política cambie de versión, debe poder distinguirse "aceptó v0.3" de
   "aceptó v0.4" sin ambigüedad.
3. Una modificación material de la Política (Política §16) debe poder exigir
   una nueva manifestación, lo que implica que el sistema pueda comparar la
   versión aceptada por una cuenta contra la versión vigente.
4. La evidencia debe sobrevivir independientemente de si luego se ejecuta
   HU-43 sobre el resto de la cuenta — ver la excepción de retención
   propuesta en [HU-43](hu-43-account-deletion-design.md#excepciones-de-retención).

## Decisión arquitectónica (NO se fija en este documento)

Cómo se persiste la evidencia — una tabla nueva en Account
(`account_consents`, por ejemplo), un evento de dominio append-only, o algún
otro mecanismo — es una decisión arquitectónica pendiente. Se propone como
candidato a [ADR-014](../adr/ADR-014-privacy-data-governance.md) (estado
`Proposed`, no `Accepted`), porque implica:

- ownership de la evidencia de consentimiento (¿la posee Account, como dueño
  de la cuenta, o un contexto transversal de privacidad?);
- si es mutable (un booleano que se sobrescribe) o append-only (un historial
  de aceptaciones, relevante si la Política cambia varias veces);
- si la versión de Política se referencia por string libre (`"0.3"`) o por un
  catálogo versionado que el propio repositorio de Infrastructure publique.

**Recomendación no vinculante para esa decisión futura:** dado que
`data-ownership.md` establece que cada bounded context posee su almacén en
exclusiva y que Account ya posee `terms_accepted`, el candidato más coherente
con la arquitectura actual es que Account también posea la evidencia de
consentimiento versionado, en lugar de crear un servicio nuevo solo para
esto. Esto es una recomendación para el ADR, no una decisión tomada aquí.

## Qué queda fuera de esta rama

- No se crea la tabla, columna ni migración.
- No se modifica `RegisterAccount`, `Account` ni ningún adaptador de Account.
- No se decide el formato del identificador de versión.

Queda para la implementación de HU-43/HU-45 o una Task de Account dedicada,
una vez el ADR-014 correspondiente sea revisado.
