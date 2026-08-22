# ADR-003 — Stack de frontend y convivencia con TypeScript 7

- **Estado:** Proposed
- **Fecha:** 2026-08-21
- **Decide:** Arquitectura
- **Relacionado:** [ADR-002](ADR-002-backend-stack.md)

## Contexto

`Nexus-Battle-Web` es la interfaz de los seis bounded contexts. El plan fija React 19, Vite 8, TypeScript 7, Tailwind CSS 4, TanStack Query 5, Zustand, Vitest, React Testing Library, ESLint, Prettier y npm.

Al ejecutar el bootstrap apareció un **conflicto real** que este ADR resuelve: TypeScript 7 rompe las herramientas de análisis estático del ecosistema.

## El problema, con evidencia

```text
typescript-eslint@8.67.0   peer typescript ">=4.8.4 <6.1.0"
ts-jest@29.4.12            peer typescript ">=4.3 <7"
```

Instalar TypeScript 7.0.2 junto a `typescript-eslint` produce `ERESOLVE`. Forzarlo con `--legacy-peer-deps` instala, pero **falla en ejecución**:

```text
Error: typescript-eslint does not support TS 7.0.
  at node_modules/typescript-eslint/dist/index.js:52
```

Se comprobó además que:

- Ninguna versión publicada de `typescript-eslint` lo soporta, incluida la etiqueta `canary` (8.67.1-alpha.24), cuyo peer sigue siendo `<6.1.0`.
- Los `overrides` de npm **no** resuelven el conflicto: npm deduplica TypeScript 7 a la raíz y el override se ignora.

Un `--legacy-peer-deps` habría producido un `lint` roto que aparenta estar verde. Eso es peor que no tener lint, y se descartó.

## Decisión

Se adopta el patrón ***side-by-side*** que el propio mensaje de error de typescript-eslint y el anuncio de TypeScript 7.0 señalan: **dos copias de TypeScript con responsabilidades distintas**.

```json
{
  "typescript": "6.0.3",
  "typescript7": "npm:typescript@7.0.2"
}
```

| Copia | Responsabilidad |
| --- | --- |
| `typescript` 6.0.3 | API JavaScript que consumen typescript-eslint y ts-jest |
| `typescript7` (alias) 7.0.2 | **Compilador y verificador de tipos del producto** |

Los scripts invocan explícitamente el compilador correcto:

```json
"typecheck": "node node_modules/typescript7/bin/tsc --noEmit"
```

**La verificación de tipos autoritativa es TypeScript 7.0.2**, y `build` depende de ella. TypeScript 6 existe únicamente como API de herramientas.

Aplica a `Nexus-Battle-Web` y a `Nexus-Battle-Notifications`. Los backends NestJS quedan en 5.9 por el motivo de [ADR-002](ADR-002-backend-stack.md).

### Stack de la aplicación web

| Pieza | Versión |
| --- | --- |
| React | 19.2.8 |
| Vite | 8.2.2 |
| Tailwind CSS | 4.3.3 (configuración en CSS con `@theme`) |
| TanStack Query | 5.101.4 |
| Zustand | 5.0.15 |
| React Router | 8.3.0 |
| Vitest + RTL | 4.1.11 / 16.3.2 |
| ESLint | 10.9.0 |

**No hay microfrontends.** Una única aplicación con una feature por bounded context.

Dos reglas de arquitectura verificadas por CI mediante `no-restricted-imports`:

- Las capas compartidas (`shared`, `lib`, `components`) no importan de `features`.
- Una feature no importa de otra feature.

## Hallazgos del salto a TypeScript 7

Dos cambios de la versión mayor afectaron al código y quedan registrados porque volverán a aparecer:

| Cambio | Efecto | Solución aplicada |
| --- | --- | --- |
| `baseUrl` eliminado (`TS5102`) | El `tsconfig.json` no compila | Los `paths` se declaran relativos con prefijo `./` |
| `exactOptionalPropertyTypes` | No se puede asignar `undefined` a una propiedad opcional de `RequestInit` | `HttpClient` compone el init por partes en lugar de declarar `headers: undefined` |

En Notifications apareció además `erasableSyntaxOnly`, que **prohíbe las *parameter properties***. Se reescribieron los constructores con asignación explícita. El beneficio es real: permite ejecutar los fuentes TypeScript directamente con `node --watch` en desarrollo, sin paso de compilación.

## Consecuencias

**Lo que se gana**

- `npm install` resuelve limpio, sin `--force` ni `--legacy-peer-deps`, con 0 vulnerabilidades.
- El lint con información de tipos funciona de verdad, en lugar de estar roto silenciosamente.
- El producto se verifica con el compilador de TypeScript 7.

**Lo que cuesta**

- Dos copias de TypeScript en `node_modules`. El coste es espacio en disco, no complejidad de uso: los scripts encapsulan qué compilador se invoca.
- Las pruebas de Notifications se transpilan con la API de TypeScript 6 mientras el typecheck usa la 7. Es aceptable porque TypeScript 7.0 es el port nativo del mismo verificador y comparte semántica, y porque **la autoridad sobre los tipos es el typecheck, no el transpilador de pruebas**.

## Condición de salida

Ambas copias se reducen a una cuando `typescript-eslint` soporte TypeScript ≥ 7.1. El seguimiento upstream es `typescript-eslint#10940`. Cuando ocurra, se elimina el alias `typescript7` y se sube `typescript` a la versión mayor, registrándolo como revisión de este ADR.

## Alternativas consideradas

| Alternativa | Por qué se descartó |
| --- | --- |
| `--legacy-peer-deps` | Instala, pero el lint falla en ejecución. Un lint roto que aparenta estar verde es peor que no tenerlo |
| `overrides` de npm | Verificado: npm deduplica TypeScript 7 a la raíz y el override no surte efecto |
| Renunciar a TypeScript 7 | Descartaría el objetivo de usar el stack de 2026 sin ganar nada, porque el patrón side-by-side está soportado oficialmente |
| Sustituir ESLint por oxlint | Evita el conflicto, pero el plan fija ESLint y se perderían las reglas con información de tipos |

## Evidencia

Verificado en un entorno aislado antes de aplicarlo al repositorio:

```text
npm install                                       -> OK, 0 vulnerabilidades, sin flags
npx tsc --version                                 -> Version 6.0.3   (tooling)
node node_modules/typescript7/bin/tsc --version    -> Version 7.0.2   (producto)
node node_modules/typescript7/bin/tsc --noEmit     -> sin errores
npx eslint .                                       -> type-aware operativo
```

`Nexus-Battle-Web` compila en producción (101.64 kB gzip) con 56 pruebas verdes y cobertura del 92.08 % en sentencias.
