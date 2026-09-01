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
2. **Versión de la Política presentada** — qué versión del documento vio y
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

## Decisión arquitectónica (fijada en ADR-014, `Proposed`)

[ADR-014, Decisión 1](../adr/ADR-014-privacy-data-governance.md#1-ownership-y-evidencia-mínima-de-consentimiento-versionado)
ya fija, como `Proposed` (no `Accepted`):

- **Ownership:** la evidencia de consentimiento la posee **Account**, no un
  contexto transversal de privacidad nuevo — mismo razonamiento que
  `data-ownership.md`: Account ya posee `terms_accepted` y es dueño de la
  cuenta.
- **Requisito mínimo de evidencia:** cuenta/titular, versión de la Política
  aceptada, y fecha/hora de aceptación generada por el backend (nunca un
  valor enviado por Web).
- **Debe conservar historial:** una aceptación de una versión anterior
  (v0.3) no puede quedar destruida ni sobrescrita cuando el titular acepte
  una versión futura (v0.4, ...) — necesario porque [HU-43](hu-43-account-deletion-design.md#excepciones-de-retención)
  puede necesitar conservar esa evidencia incluso tras eliminar el resto de
  la cuenta.

Lo que ADR-014 **no fija** — y sigue siendo una decisión de implementación
pendiente de la Task que resuelva este gap — es la forma física concreta:
una tabla nueva en Account (`account_consents`, por ejemplo, append-only), un
evento de dominio, o algún otro mecanismo que satisfaga el requisito de
historial de arriba. ADR-014 fija el requisito, no el diseño de tabla.

## Qué queda fuera de esta rama

- No se crea la tabla, columna ni migración.
- No se modifica `RegisterAccount`, `Account` ni ningún adaptador de Account.
- No se decide el formato del identificador de versión.

Queda para la implementación de HU-43/HU-45 o una Task de Account dedicada,
una vez el ADR-014 correspondiente sea revisado.
