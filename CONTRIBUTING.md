# Contribución a Nexus-Battle-Infrastructure

Este es el repositorio de documentación técnica del producto. No contiene código ejecutable. Toda contribución ingresa mediante Pull Request hacia `main` y debe ser trazable hasta una Issue de [Nexus-Battle-Management](https://github.com/Nexus-Battle-VI/Nexus-Battle-Management), que es la fuente única de verdad del Product Backlog.

Este repositorio no tiene Issues ni Project propios. Epics, User Stories, Enablers, Tasks y Bugs se gestionan exclusivamente en Management.

## Ramas

La estrategia es _trunk-based_ liviano. La única rama permanente es `main`.

No existen ramas `develop`, `qa`, `staging` ni `release/*`. Los entornos `dev`, `test` y `prod` son entornos de despliegue, no ramas.

Cada cambio se realiza en una rama de corta duración creada desde `main`:

```text
docs/adr-011-orm
docs/corregir-estimacion-costes
chore/bootstrap-sprint1-foundation
ci/cache-dependencias
docs/diagrama-de-despliegue
docs/catalogo-de-eventos
docs/reorganizar-adr
```

La rama se elimina automáticamente al integrar el Pull Request.

## Commits

Se utiliza Conventional Commits con los tipos `feat`, `fix`, `docs`, `test`, `refactor`, `chore`, `ci` y `build`.

El título del Pull Request es el mensaje del commit de integración, porque `main` solo admite _squash_:

```text
docs(infrastructure): [EN-12] registrar ADR de estrategia de datos
docs(infrastructure): [EN-12] corregir la estimacion de costes
```

## Trazabilidad

Todo Pull Request debe referenciar su Issue central con el nombre completo del repositorio:

```text
Refs Nexus-Battle-VI/Nexus-Battle-Management#NUMERO
```

Desde este repositorio no se usa `#NUMERO`, porque apuntaría a una Issue local inexistente o equivocada.

`Closes` se emplea únicamente cuando el Pull Request completa totalmente una Task, un Bug o una Task subordinada de un Enabler. **Un Pull Request no cierra la User Story padre.** La HU permanece abierta hasta que todos los módulos estén integrados, se cumpla la Definition of Done, exista evidencia y el Product Owner acepte el resultado.

## Flujo de trabajo

1. Se verifica que la Issue cumple la Definition of Ready.
2. Se crea la rama desde `main` actualizada.
3. Se desarrolla siguiendo Red → Green → Refactor.
4. Se ejecuta la verificación local completa.
5. Se abre el Pull Request y se completa la plantilla.
6. Se atiende la revisión del Code Owner.
7. Se integra mediante _squash_ cuando el pipeline está verde.
8. Se registra la evidencia desde la Issue central.

## Verificación local

Este repositorio no tiene dependencias ni compilación. Antes de abrir un Pull Request se comprueba que:

- los enlaces internos entre documentos resuelven;
- los diagramas PlantUML abren sin error;
- el JSON y el YAML son sintácticamente válidos;
- **lo que se afirma como implementado lo está de verdad**.

CI verifica automáticamente la presencia de los 36 documentos exigidos, que todo ADR declara su estado, que la plantilla de ruleset conserva su placeholder y que no hay secretos.

## Reglas de la documentación

**La regla central: lo que se describe como implementado, lo está.**

- Lo pendiente se declara como pendiente, con su motivo y su condición de desbloqueo.
- Una limitación conocida se enuncia, no se omite. Omitirla induce decisiones basadas en un sistema que no existe.
- Un ADR declara siempre su **estado**. Solo pasa a `Accepted` con evidencia de aprobación registrada.
- Las cifras se acompañan de sus supuestos. Una estimación sin supuestos no es revisable.
- Los diagramas de despliegue **separan visualmente demo y objetivo**.
- No se afirma que algo es gratuito de forma permanente.

## Cómo se escribe un ADR

```text
Contexto     -> que problema existe y por que ahora
Decision     -> que se decide, en concreto
Consecuencias-> lo que se gana, lo que cuesta, lo que queda prohibido
Alternativas -> que mas se considero y por que se descarto
Evidencia    -> como se puede comprobar
```

Un ADR sin alternativas consideradas no documenta una decisión: documenta un resultado.

## Diagramas

PlantUML en `docs/diagrams`. Cada diagrama de despliegue indica de forma visible si el elemento **existe** o es **futuro**, para que nadie confunda la demo con la arquitectura objetivo.

## Seguridad

No se incorporan secretos, credenciales ni tokens al repositorio. La configuración sensible se entrega por variables de entorno y se documenta sin valores reales en `.env.example`. Ver [SECURITY.md](SECURITY.md).

## Dependencias

Este repositorio no tiene dependencias de npm. Dependabot vigila únicamente las acciones de GitHub usadas en el workflow.
