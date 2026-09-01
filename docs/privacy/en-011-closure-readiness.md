# EN-011 — Estado de cierre

Analiza qué parte de [EN-011](https://github.com/Nexus-Battle-VI/Nexus-Battle-Management/issues/197)
queda satisfecha por este PR (puramente documental) y qué queda delegado a
HU-43/HU-45. Corrige una imprecisión de la primera versión de esta rama, que
trataba el estado `Proposed` de ADR-006 como un bloqueo de HU-43 sin que
ningún documento lo sustentara.

## Conclusión

**La definición documental de EN-011 puede quedar completa con este PR.** No
existe un bloqueo de ADR-006 para cerrar la parte documental: ADR-006 cubre
tres integraciones concretas (Notifications, precio de Catalog, reserva de
checkout) y no define el derecho al olvido en su alcance.

Antes de cerrar EN-011 hay que decidir un único punto real, señalado abajo:
**si sus criterios de aceptación exigen también comportamiento runtime del
consentimiento/publicación, o si esas responsabilidades se delegan
explícitamente a las HUs consumidoras.**

- **HU-43** sí requiere una decisión arquitectónica de orquestación
  multi-contexto antes de su implementación completa — decisión que
  [ADR-014](../adr/ADR-014-privacy-data-governance.md) ya propone
  (orquestación síncrona con registro de progreso), sin depender de que
  ADR-006 avance primero.
- **HU-45** puede avanzar ya mediante integración síncrona sobre las APIs
  existentes (mismo patrón que `Commerce -> Catalog`), y solo queda
  condicionada por la disponibilidad real de las fuentes de datos que exige
  la Política §9 (inventario, estadísticas, comentarios, transacciones) —
  estadísticas/progreso no tienen owner asignado todavía, lo cual es una
  dependencia de HU-45, no de EN-011.

## El único punto que sí puede impedir cerrar EN-011 tal como está redactada

La Política v0.3 exige, con lenguaje que describe comportamiento en
ejecución, no solo intención documental:

- §17: *"El acceso a la información de esta Política... forma parte del
  proceso de registro de la cuenta"* — implica que la Política debe estar
  **publicada y accesible** desde el producto, no solo versionada en este
  repositorio.
- §6, Anexo A: *"La plataforma deberá mantener evidencia verificable de la
  aceptación"* — implica que el sistema **registra** algo, no solo que el
  requisito esté descrito.

Este PR entrega la política versionada, la matriz, el contrato de
portabilidad y el análisis del gap de consentimiento — **todo documental**.
No publica la Política en ningún endpoint del producto ni hace que Account
registre versión+fecha de aceptación: eso sigue siendo `terms_accepted`, un
booleano, tal como documenta
[consent-versioning.md](consent-versioning.md).

**No se pudo verificar contra el texto real y actualizado de los criterios
de aceptación de Management #197** — esta sesión no tiene acceso autenticado
a la API de GitHub para leerlos. Se documenta la pregunta en lugar de asumir
una respuesta:

> ¿Los CA de EN-011 exigen que la Política esté efectivamente publicada y
> que el consentimiento quede efectivamente registrado con versión y fecha
> (comportamiento runtime), o EN-011 se define como el enabler puramente
> documental/de gobierno, delegando el runtime a HU-43/HU-45 (o a una Task
> de Account futura para el consentimiento)?

## Recomendación

1. Quien revise este PR debe confirmar contra el texto vigente de
   Management #197 cuál de las dos lecturas aplica.
2. Si EN-011 delega el runtime a las HUs consumidoras: **este PR es
   suficiente para cerrar EN-011** tal como está.
3. Si EN-011 exige evidencia runtime propia: EN-011 necesita, antes de
   cerrarse, un refinamiento de alcance explícito — por ejemplo, acotar sus
   CA a "la Política está versionada, gobernada y lista para que HU-43/HU-45
   la consuman" en vez de "el sistema aplica la Política", o añadir una Task
   mínima (publicar la Política en un endpoint accesible) dentro del propio
   EN-011 en vez de dentro de una HU.

Ninguna de las dos opciones se decide en este documento — es una decisión de
Product Owner/Scrum Master sobre el alcance de EN-011, no una decisión
arquitectónica de Infrastructure.
