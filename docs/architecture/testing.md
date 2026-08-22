# Estrategia de pruebas

## Resultado actual

| Repositorio | Pruebas | Sentencias | Ramas | Funciones |
| --- | --- | --- | --- | --- |
| Notifications | 133 | 99,75 % | 96,63 % | 98,97 % |
| Account | 94 | 99,72 % | 93,80 % | 100 % |
| Player-Inventory | 83 | 98,03 % | 91,58 % | 98,70 % |
| Catalog | 95 | 98,39 % | 92,74 % | 99,00 % |
| Community | 67 | 98,65 % | 90,72 % | 99,06 % |
| Commerce | 74 | 99,03 % | 92,56 % | 100 % |
| Web | 56 | 92,08 % | 97,61 % | 84,90 % |
| **Total** | **602** | — | — | — |

Umbral exigido: **80 %**, configurado como umbral del ejecutor de pruebas. Por debajo, el comando falla y CI con él.

## Herramientas

| Ámbito | Herramienta |
| --- | --- |
| Backends NestJS | Jest 30 + ts-jest, Supertest para HTTP |
| Notifications | Jest 30 en modo ESM + ts-jest |
| Web | Vitest 4 + React Testing Library + jsdom |
| Cobertura | Jest / `@vitest/coverage-v8` |

## Qué se prueba en cada nivel

### Dominio

Las reglas de negocio, incluidas las que un modelo ingenuo resolvería mal:

- Que el inventario **admite más unidades de un objeto ya poseído aunque esté lleno**, porque la capacidad limita ranuras, no unidades.
- Que un producto archivado **no admite cambios de precio**, para no distorsionar el histórico.
- Que un pedido confirmado **rechaza añadir, retirar y reconfirmar**.
- Que un mensaje ocultado **se conserva** aunque deje de ser visible.
- Que `Money` **rechaza importes fraccionarios** y mezclar monedas.

### Aplicación

Los casos de uso contra dobles de los puertos, incluidos los caminos de fallo:

- Que `RegisterAccount` **retira el sujeto de identidad** si falla la persistencia.
- Que una plantilla inexistente **no se reintenta**, porque reintentarla produciría el mismo error.
- Que un fallo transitorio **libera la reserva de idempotencia** y uno permanente **la conserva**.

### Adaptadores

Que el repositorio en memoria **almacena instantáneas, no referencias vivas**. La prueba muta el agregado sin volver a guardarlo y comprueba que el almacén no cambió.

Sin esa prueba, un caso de uso que olvidara `save()` pasaría igualmente.

### Integración

**La aplicación real, sin sustituir adaptadores.** Los cinco servicios NestJS levantan el módulo completo con Supertest: raíz de composición, tuberías de validación y controladores.

Notifications ejercita el flujo cola → consumidor → caso de uso → adaptador de correo, y levanta un servidor HTTP real para las sondas.

## Dos hallazgos que las pruebas produjeron

Se registran porque son la justificación de por qué se escriben:

**1. La política de reintentos nunca se agotaba.**

La prueba `agota los reintentos y termina en la cola de mensajes fallidos` falló. El motivo era real: el agregado se reconstruía desde cero en cada entrega, el contador volvía a 1 y el mensaje se reencolaba indefinidamente. Se corrigió propagando el contador de entregas de la cola hasta el agregado.

**2. El cliente HTTP capturaba `fetch` demasiado pronto.**

Las pruebas de Web fallaban contra el singleton porque `HttpClient` había capturado `globalThis.fetch` en el constructor, antes de que la prueba instalara el suyo. **El arreglo fue del código, no de la prueba**: `fetch` se resuelve ahora en cada petición, lo que además permite que un polyfill cargado más tarde funcione.

En ambos casos la prueba encontró un defecto real. Ajustar la prueba para que pasara habría ocultado los dos.

## Reglas de arquitectura verificadas por CI

No son pruebas, pero cumplen la misma función: impedir que una restricción se erosione.

| Regla | Dónde |
| --- | --- |
| El dominio no importa NestJS, SDK, ORM, HTTP ni drivers | Los seis servicios |
| La aplicación no importa adaptadores | Los seis servicios |
| Las capas compartidas no importan de features | Web |
| Una feature no importa de otra feature | Web |

Implementadas como `no-restricted-imports` de ESLint. **Un cambio que las incumpla no puede integrarse.**

## Lo que no se prueba, y por qué

| Ausencia | Motivo |
| --- | --- |
| **Pruebas de contrato entre servicios** | Los servicios no se comunican todavía. Un contrato sin consumidor real no verifica nada |
| **Testcontainers** | No hay adaptadores de base de datos que ejercitar; depende de ADR-005 |
| **Playwright en Web** | Con una sola pantalla implementada aportaría menos que las pruebas actuales |
| **Pruebas de carga** | Sin infraestructura provisionada no hay nada que medir |

Las cuatro se incorporarán cuando exista aquello que deben verificar. Escribirlas antes produciría pruebas que pasan sin comprobar nada.

## Qué no se admite

- Pruebas vacías o que solo afirman `true`.
- Pruebas deshabilitadas sin justificación en el Pull Request.
- Consultar por clases CSS o estructura interna en lugar de por rol o texto accesible.
- Ajustar una prueba para que pase cuando lo que falla es el código.
