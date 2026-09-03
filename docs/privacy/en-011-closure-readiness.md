# EN-011 — Estado de cierre

Analiza qué parte de [EN-011](https://github.com/Nexus-Battle-VI/Nexus-Battle-Management/issues/197)
queda satisfecha por este PR (puramente documental) y qué queda delegado a
HU-43/HU-45 o a una Task futura de Account, a partir de los criterios de
aceptación reales de EN-011. Corrige una imprecisión de la primera versión de
esta rama, que trataba el estado `Proposed` de ADR-006 como un bloqueo de
HU-43 sin que ningún documento lo sustentara.

## Criterios de aceptación de EN-011

| CA | Descripción | Estado tras este PR |
| --- | --- | --- |
| CA-01 | Política propia publicada y accesible | **No cubierto.** Requiere un mecanismo runtime para que el usuario consulte la Política aplicable desde el producto. Este PR versiona y gobierna la Política (v0.3), pero no la publica en ningún endpoint ni superficie de Web. |
| CA-02 | Consentimiento explícito y trazable (no solo un estado visual de frontend) | **No cubierto.** Requiere persistencia runtime del consentimiento versionado. Este PR fija la decisión arquitectónica (ADR-014, Decisión 1) y el requisito mínimo de evidencia (ver [consent-versioning.md](consent-versioning.md)), pero `Account` sigue persistiendo únicamente `terms_accepted: boolean`, sin versión ni fecha. |
| CA-03 | Minimización — justificación de cada dato obligatorio, sin campos adicionales por conveniencia técnica | **Cubierto documentalmente.** Ver [data-treatment-matrix-v0.3.md](data-treatment-matrix-v0.3.md): cada dato recolectado tiene finalidad y owner justificados; no se propone ningún campo nuevo. |
| CA-04 | Derecho al olvido — estrategia verificable compatible con HU-43, máximo 30 días, retención solo justificada | **Estrategia/documentación cubierta por este PR; implementación funcional ya completa.** [ADR-014 Decisión 5](../adr/ADR-014-privacy-data-governance.md#5-alcance-y-proceso-del-derecho-al-olvido-hu-43-ownership-de-account-sin-orquestación-multi-contexto) fija el alcance y el proceso durable dentro de Account. **Actualización:** Management #303–#307 ya están mergeados a `develop` en `Nexus-Battle-Account`, `Nexus-Battle-Notifications` y `Nexus-Battle-Web` — ver [hu-43-account-deletion-design.md](hu-43-account-deletion-design.md#qué-quedó-implementado-verificado-en-código-y-pr-mergeados-a-develop). Esto no cierra EN-011 por sí solo: EN-011 sigue bloqueada por CA-01/CA-02, no por CA-04. |
| CA-05 | Portabilidad — qué datos del titular se incluyen y cómo se excluyen terceros/secretos | **Contrato funcional/documental cubierto por este PR.** [portability-contract-v1.md](portability-contract-v1.md) fija exactamente esa frontera. La implementación (endpoints, exportadores) queda en HU-45. |
| CA-06 | Coherencia documental/técnica — la implementación real debe ser coherente con la política y las definiciones | **Solo verificable parcialmente.** Este PR no introduce ninguna incoherencia nueva (no toca código de microservicios), pero la coherencia completa solo puede confirmarse cuando exista implementación real (HU-43/HU-45/consentimiento) contra la cual contrastar. |

## Conclusión

**EN-011 NO debe cerrarse con este PR.** CA-01 y CA-02 exigen comportamiento
runtime — política publicada y accesible, consentimiento registrado de forma
verificable y no solo como estado visual de frontend — que un PR puramente
documental de `Nexus-Battle-Infrastructure` no puede satisfacer por
definición: este repositorio no contiene código ejecutable
(`CONTRIBUTING.md`).

Lo que este PR sí completa es la **definición documental, de gobierno y
arquitectura** que EN-011 necesitaba antes de que existiera ninguna
implementación:

- Política v0.3 versionada y gobernada.
- Matriz de tratamiento de datos (CA-03).
- Contrato de portabilidad (CA-05, base documental).
- Diseño de alto nivel y decisión de orquestación para HU-43 (CA-04, base
  documental).
- Decisión arquitectónica sobre ownership y evidencia mínima de
  consentimiento versionado (CA-02, base documental — ver
  [ADR-014 Decisión 1](../adr/ADR-014-privacy-data-governance.md#1-ownership-y-evidencia-mínima-de-consentimiento-versionado)).

## Qué falta para poder cerrar EN-011

Como mínimo, dos piezas de implementación runtime, fuera del alcance de esta
rama de `Infrastructure`:

1. **Publicación de la Política (CA-01):** un mecanismo accesible desde el
   producto (Web, o un endpoint servido por algún servicio) que muestre la
   versión vigente de la Política. No se decide en este PR quién lo
   implementa.
2. **Registro runtime del consentimiento versionado (CA-02):** que `Account`
   persista cuenta + versión de Política + fecha/hora de aceptación, en
   lugar del booleano actual. Candidata natural: una Task futura en
   `Nexus-Battle-Account` (rama futura sugerida:
   `feat/en-011-versioned-consent`), sobre la decisión ya fijada en
   [ADR-014](../adr/ADR-014-privacy-data-governance.md).

CA-04 y CA-05 no bloquean el cierre de EN-011 en el mismo sentido: su
implementación completa pertenece a HU-43/HU-45 respectivamente, que son
Historias de Usuario separadas con su propio ciclo de cierre — EN-011 fija su
base documental, no su ejecución.

## Aclaración sobre ADR-006 (motivo de la corrección de esta rama)

No existe un bloqueo de ADR-006 para nada de lo anterior: ADR-006 cubre tres
integraciones concretas (Notifications, precio de Catalog, reserva de
checkout) y no define el derecho al olvido en su alcance. La primera versión
de esta rama trató el estado `Proposed` de ADR-006 como si impidiera avanzar
con HU-43; eso era impreciso y se corrigió en
[ADR-014](../adr/ADR-014-privacy-data-governance.md#5-estrategia-de-orquestación-para-el-derecho-al-olvido-hu-43-coordinación-síncrona-por-api-sin-esperar-a-adr-006).
El bloqueo real de EN-011 nunca fue ADR-006: son CA-01 y CA-02, tal como se
documenta arriba.
