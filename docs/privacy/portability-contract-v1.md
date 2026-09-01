# Contrato funcional de portabilidad — v1 (consumido por HU-45)

Define el alcance que HU-45 deberá exponer a través del Portal de privacidad.
No implementa endpoints; fija qué debe y qué no debe salir en una
exportación, para que la implementación no tenga que decidirlo sobre la
marcha.

## Regla general

> Ningún dato sale de un exportación por el solo hecho de existir
> técnicamente. Sale porque la [Política v0.3](privacy-policy-v0.3.md) o el
> SRS lo exigen como contenido mínimo, o porque una decisión funcional
> explícita lo añadió.

La Política (§9) exige, como mínimo:

- copia estructurada en **JSON o XML** de los datos personales definidos para
  el Portal de privacidad;
- un reporte completo en **PDF** que contemple explícitamente: **inventario,
  estadísticas, comentarios e historial de transacciones**.

## CONSULTABLE/EXPORTABLE (por defecto, sujeto a la matriz)

Datos cuya naturaleza es de presentación al propio titular — ver el detalle
categoría por categoría en la
[matriz de tratamiento](data-treatment-matrix-v0.3.md):

- identidad de cuenta (nombres, apellidos, correo, apodo, avatar);
- roles vigentes, como metadato descriptivo de la cuenta (no como mecanismo
  de autorización — el portal no debe usarse para verificar permisos, solo
  para informarlos);
- inventario y, cuando exista owner asignado, héroes/estadísticas/progreso;
- comentarios y mensajes propios (`author_id` = titular);
- historial de transacciones propio (`customer_id` = titular);
- evidencia de consentimiento propia (versión de Política aceptada, fecha) —
  sujeto a que [consent-versioning.md](consent-versioning.md) defina cómo se
  persiste.

## INTERNO/SECRETO/NO PORTABLE (excluido por defecto, sin excepción salvo ADR futuro)

Por instrucción explícita de este contrato, **no deben exponerse mediante el
portal únicamente por existir**:

| Categoría | Ejemplo concreto en el sistema actual |
| --- | --- |
| Contraseñas | No aplica — Account nunca las almacena |
| Tokens de acceso/refresco | Emitidos por Cognito, viven en el cliente, no en la base de ningún servicio |
| Secretos TOTP/MFA | Custodiados por Cognito |
| Hashes de respuestas de seguridad | `account_security_answers.answer_hash` |
| Credenciales de AWS | No pertenecen al titular en ningún caso |
| Claims internos del testimonio | `sub` técnico, `token_use`, `client_id`, metadatos JWT sin valor funcional para el titular |
| Datos internos de Cognito no reflejados como perfil | Atributos del pool que Account no proyecta a `accounts` |
| Identificadores técnicos sin valor funcional | Claves primarias internas (`id` de fila) cuando no coinciden con un identificador que el titular ya conoce; claves foráneas opacas hacia otro servicio |
| Datos de terceros | `author_id`/`customer_id` de otra cuenta; contenido de otros participantes de un hilo compartido |

Esta lista aplica **por defecto**. Ampliarla exige una decisión funcional
registrada (Product Owner) o un ADR si implica una decisión arquitectónica de
cómo se agrega o filtra la información — ver
[ADR-014](../adr/ADR-014-privacy-data-governance.md).

## Verificado en código: la identidad del titular no es un parámetro de la petición

La Política (§8) exige que "el portal deberá impedir que un titular visualice
o exporte datos pertenecientes a otra persona", y que las solicitudes se
sometan a "verificación de identidad" antes de operaciones sensibles.

El sistema **ya implementa** el patrón correcto para resolver "quién soy" sin
confiar en un identificador enviado por el cliente. Verificado en
`Nexus-Battle-Account`, no asumido:

```text
GetOwnAccount.execute(subject: string)
    -> this.accounts.findBySubject(subject)
```

— [`GetOwnAccount.ts`](https://github.com/Nexus-Battle-VI/Nexus-Battle-Account/blob/main/src/application/use-cases/GetOwnAccount.ts)

`subject` proviene del testimonio JWT ya verificado por `JwtAuthGuard`
contra el JWKS del pool (`AUTH_MODE=jwt`, ver
[security.md](../architecture/security.md)), nunca de un `accountId` que
Web envíe en el cuerpo o la URL de la petición. `UpdateOwnAccount` sigue el
mismo patrón
([`UpdateOwnAccount.ts`](https://github.com/Nexus-Battle-VI/Nexus-Battle-Account/blob/main/src/application/use-cases/UpdateOwnAccount.ts)).

HU-45 debe reutilizar este mismo patrón — `VerifiedIdentity.subject ->
findBySubject(...) -> Account` — como autoridad del titular en cada
bounded context que agregue datos para la exportación. **No** debe aceptar un
`accountId` arbitrario enviado por Web como fuente de autorización.

## Formatos

| Formato | Contenido mínimo exigido | Notas |
| --- | --- | --- |
| JSON | Datos personales definidos para el Portal (identidad, roles, evidencia de consentimiento, y lo demás que la matriz marque exportable) | Formato estructurado, Política §9 |
| XML | Igual contenido que JSON, forma alternativa | Política §9 exige explícitamente ambos formatos estructurados |
| PDF | Debe contemplar **inventario, estadísticas, comentarios e historial de transacciones** como mínimo (Política §9) | "Reporte completo" — no se limita a esas cuatro categorías si la matriz marca más contenido exportable, pero esas cuatro son obligatorias |

## Lo que este contrato NO decide

- el mecanismo de agregación entre bounded contexts (síncrono por servicio,
  vista materializada, u otro) — es una decisión arquitectónica, ver
  [ADR-014](../adr/ADR-014-privacy-data-governance.md);
- el endpoint HTTP, su ruta o su forma de autenticación más allá de reutilizar
  el patrón `VerifiedIdentity.subject`;
- el generador de PDF ni su plantilla;
- si el avatar se exporta como binario embebido o como referencia — pendiente
  en la [matriz](data-treatment-matrix-v0.3.md).

Estas decisiones pertenecen a la implementación de HU-45.
