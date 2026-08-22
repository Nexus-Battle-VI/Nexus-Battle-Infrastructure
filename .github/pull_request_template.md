<!--
Título del Pull Request (convención obligatoria):
  docs(infrastructure): [EN-12] registrar ADR de estrategia de datos
  docs(infrastructure): [EN-12] corregir la estimacion de costes

Tipos permitidos: feat, fix, docs, test, refactor, chore, ci, build
-->

## Trazabilidad

Management Issue:

```text
Refs Nexus-Battle-VI/Nexus-Battle-Management#NUMERO
```

- **Tipo:** HU / EN / BUG / CHORE
- **Team:** Team Alfa / Team Beta / Team Gama
- **Alcance:** ADR / arquitectura / diagramas / costes / contratos / gobierno

> Se utiliza siempre el nombre completo del repositorio. Desde otro repositorio no se usa `#NUMERO`, porque apuntaría a una Issue local inexistente o equivocada.
>
> `Closes` solo se emplea cuando el Pull Request completa totalmente una Task, un Bug o una Task subordinada de un Enabler. **Un Pull Request no cierra la User Story padre.** La HU permanece abierta hasta que todos los módulos estén integrados, se cumpla la Definition of Done, exista evidencia y el Product Owner acepte el resultado.

## Resumen

<!-- Qué se entrega, en una o dos frases. -->

## Contexto y alcance

<!-- Problema que se resuelve, decisiones tomadas y qué queda expresamente fuera de este Pull Request. -->

## Criterios de aceptación cubiertos

<!-- Se enumeran los criterios de la Issue central que este Pull Request demuestra. Si la cobertura es parcial, se indica cuáles quedan pendientes y en qué módulo. -->

- [ ]

## Verificación

- [ ] Los enlaces internos entre documentos resuelven
- [ ] Los diagramas PlantUML abren sin error
- [ ] El JSON y el YAML son sintácticamente válidos
- [ ] Lo que se afirma como implementado **lo está**, y lo pendiente se declara como pendiente
- [ ] No aplica (se justifica a continuación)

> Este repositorio no contiene código ejecutable. Su verificación consiste en
> que la documentación describa el sistema real, no el sistema deseado.

## Contratos

- [ ] OpenAPI actualizado
- [ ] AsyncAPI actualizado
- [ ] Introduce un cambio incompatible (_breaking change_)
- [ ] No aplica

<!-- Si existe cambio incompatible, se describe el impacto y la estrategia de migración acordada. -->

## Arquitectura

- **ADR aplicable:**
- **Patrón utilizado:**
- **Bounded context afectado:**

<!-- Se confirma que el dominio no importa framework, SDK, ORM, HTTP ni drivers de base de datos, y que no existe acceso directo a datos de otro servicio. -->

## Seguridad

<!-- Datos sensibles tratados, permisos, validación de entrada, dependencias añadidas y hallazgos de seguridad revisados. Si no aplica, se escribe "No aplica" y se justifica. -->

## Evidencia

<!-- Enlaces a la ejecución del pipeline, reporte de cobertura, capturas o registros. La evidencia no contiene secretos y se enlaza también desde la Issue central. -->

## Definition of Done técnica

- [ ] Pruebas ejecutadas y aprobadas
- [ ] Cobertura global mayor o igual a 80 %
- [ ] `lint` sin hallazgos
- [ ] `format:check` sin diferencias
- [ ] `typecheck` sin errores
- [ ] `build` correcto
- [ ] No se incorporan secretos ni credenciales
- [ ] Contratos actualizados cuando aplica
- [ ] Documentación técnica actualizada
- [ ] Pipeline verde
- [ ] Revisión por pares completada

> La Definition of Done completa del producto se mantiene en [Management](https://github.com/Nexus-Battle-VI/Nexus-Battle-Management/blob/main/docs/governance/definition-of-done.md). Esta lista es su verificación técnica en el repositorio.
