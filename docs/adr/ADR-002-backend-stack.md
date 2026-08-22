# ADR-002 — Stack de backend

- **Estado:** Proposed
- **Fecha:** 2026-08-21
- **Decide:** Arquitectura
- **Relacionado:** [ADR-003](ADR-003-frontend-stack.md), [ADR-005](ADR-005-data-strategy.md)

## Contexto

Seis servicios de backend deben compartir un stack común para que el conocimiento sea transferible entre Teams y el andamiaje reutilizable. Cinco exponen API HTTP; Notifications es un worker de larga duración sin API de negocio.

El plan de Sprint 1 fija Node 24 LTS, npm y NestJS 11. La pregunta abierta era **qué versión de TypeScript**, dado que TypeScript 7.0.2 es la versión estable publicada.

## Decisión

### Runtime y gestor de paquetes

| Elemento | Valor | Cómo se fija |
| --- | --- | --- |
| Node.js | 24.19.0 LTS (Krypton) | `.nvmrc` = `24`, `engines.node` = `>=24 <25` |
| npm | 11.17.0 | `packageManager: "npm@11.17.0"` |
| Instalación en CI | `npm ci` | Reproducible desde `package-lock.json` |

Se usa **npm exclusivamente**. No se admiten pnpm ni yarn: un único lockfile por repositorio elimina la clase entera de fallos por resolución divergente.

### Framework y TypeScript

| Servicio | Framework | TypeScript |
| --- | --- | --- |
| Account, Player-Inventory, Catalog, Community, Commerce | NestJS 11.2.1 | **5.9.3** |
| Notifications | Ninguno (worker Node) | **7.0.2** con API de tooling en 6.0.3 |

**Los backends NestJS se quedan en TypeScript 5.9.3.** El motivo es concreto y verificable:

```text
@nestjs/cli@11.0.24  ->  dependencies.typescript = "5.9.3"
```

El Nest CLI declara TypeScript 5.9.3 como **dependencia directa**, no como rango. Subir la versión mayor exigiría sustituir o rodear el Nest CLI, y el plan lo prohíbe explícitamente: no se introduce un sustituto silencioso de la herramienta oficial para forzar un número de versión.

**Notifications sí usa TypeScript 7** porque no depende del Nest CLI. Ver [ADR-003](ADR-003-frontend-stack.md) para el patrón *side-by-side* que ese salto exige.

### Arquitectura interna

Clean + Hexagonal, idéntica en los seis servicios:

```text
src/
  domain/          Entidades, objetos de valor, politicas y eventos
  application/     Casos de uso, puertos, DTO y errores
  adapters/        inbound/http y outbound/*
  infrastructure/  config, observability, health, bootstrap
```

Dos restricciones **verificadas por CI**, no solo documentadas:

- El dominio no importa NestJS, SDK de AWS, ORM, HTTP ni drivers de base de datos.
- La capa de aplicación depende de sus puertos, nunca de adaptadores concretos.

Están implementadas como reglas `no-restricted-imports` de ESLint sobre `src/domain` y `src/application`. Un cambio que las incumpla no puede integrarse.

**Los casos de uso son clases planas sin decoradores.** Se registran en el módulo mediante fábricas explícitas, de modo que la capa de aplicación podría ejecutarse fuera de NestJS sin cambios. Es la diferencia entre usar el framework y depender de él.

### Calidad

| Herramienta | Versión | Uso |
| --- | --- | --- |
| Jest | 30.4.2 | Pruebas unitarias y de integración |
| Supertest | 7.2.2 | Integración HTTP contra la aplicación real |
| ESLint | 10.9.0 | Reglas con información de tipos |
| Prettier | 3.9.6 | Formato |
| `@nestjs/swagger` | 11.4.7 | OpenAPI generado desde el código |

Umbral de cobertura: **80 %** configurado en Jest. Por debajo, el comando falla.

## Consecuencias

**Lo que se gana**

- Un arquetipo único: el andamiaje de Account se replicó a los otros cuatro servicios NestJS con un script, y el dominio de cada uno se escribió aparte.
- Las restricciones arquitectónicas dejan de depender de la disciplina y pasan a ser un fallo de CI.
- OpenAPI se genera desde el código, por lo que no puede quedar desincronizado de la implementación.

**Lo que cuesta**

- **Dos versiones de TypeScript conviven en el producto** (5.9 en NestJS, 7.0 en Notifications y Web). Es una inconsistencia real y visible. Se acepta porque la alternativa es peor: o se renuncia a TypeScript 7 en todas partes, o se rodea el Nest CLI.
- Registrar los casos de uso con fábricas explícitas es más verboso que anotarlos con `@Injectable()`. Se acepta a cambio de que la capa de aplicación no conozca el framework.

## Condición de salida

Los backends NestJS subirán a TypeScript 7 cuando el Nest CLI lo soporte **oficialmente**. La evidencia requerida es que `@nestjs/cli` declare una versión de TypeScript compatible con 7.x en sus dependencias. Ese cambio se registrará como una revisión de este ADR, no como un cambio silencioso.

## Alternativas consideradas

| Alternativa | Por qué se descartó |
| --- | --- |
| TypeScript 7 en todos los servicios | El Nest CLI no lo soporta. Requeriría sustituirlo por una compilación propia, que el plan prohíbe |
| TypeScript 5.9 también en Notifications y Web | Renunciaría al objetivo de usar el stack de 2026 donde sí es viable, sin ganar nada: esos dos repositorios no dependen del Nest CLI |
| Fastify en lugar de NestJS | Más ligero, pero el plan fija NestJS y el proyecto tiene valor académico en demostrar una arquitectura por capas explícita |

## Evidencia

- `npm view @nestjs/cli@11.0.24 dependencies` devuelve `"typescript": "5.9.3"`.
- Los cinco servicios NestJS compilan con `nest build` y superan `typecheck`, `lint`, `format:check` y cobertura ≥ 80 %.
- Notifications compila con TypeScript 7.0.2 verificado por `tsc --version`.
