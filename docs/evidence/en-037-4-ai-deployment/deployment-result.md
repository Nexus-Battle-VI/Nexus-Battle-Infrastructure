# EN-037.4 (Management #573) — Resultado del despliegue

## Declaración honesta de alcance

**No se desplegó nada en AWS durante este trabajo.** Este entorno no tuvo
acceso a credenciales AWS ni a SSM (el servidor MCP `aws-mcp` configurado
para esta sesión falló al conectar — timeout de conexión — y no se
reintentó con credenciales alternativas). Todo lo que este PR entrega es:

- Código, Dockerfiles, CI y Compose **preparados y verificados localmente**.
- Evidencia de compatibilidad ARM64 real (bajo emulación QEMU — ver
  `architecture-compatibility.md` para la distinción exacta frente a
  hardware Graviton real).
- Mediciones de recursos LOCALES reales (ver `resource-measurements.md`),
  explícitamente marcadas como no-sustitutas de la medición SSM pendiente.
- Un hallazgo de drift crítico en Terraform que debe resolverse antes de
  cualquier `plan`/`apply` futuro (`deployment-preflight.md`).

**Nada en este PR ejecutó `terraform plan`, `terraform apply`, ni ninguna
sesión SSM contra el nodo `app` real.**

## Qué está listo para desplegar (una vez autorizado y con acceso AWS)

| Componente | Estado |
| --- | --- |
| `Dockerfile` de Combat, etapa `trainer` | Código listo, build local verificado (nativo + ARM64 emulado) |
| `.github/workflows/ci.yml` de Combat, build/publish de `nexus-battle-combat-trainer` | Código listo, no ejecutado en GitHub Actions real (solo sintaxis validada localmente) |
| `compose/nodes/app.yml` — `combat-trainer`/`combat-evaluator` | Código listo, `docker compose config` validado localmente con variables reales |
| `compose/compose.example.yml` — equivalentes locales | Código listo, validado localmente |
| `compose/.env.example` — `COMBAT_SOURCE_COMMIT` | Documentado |
| Runbook operativo | Completo (`docs/runbooks/en-037-4-despliegue-ia-combat.md`) |

## Qué falta, explícitamente, antes de poder cerrar #573 con evidencia completa

1. **Publicar realmente** `nexus-battle-combat-trainer` a GHCR (requiere
   que el PR complementario de Combat se revise, apruebe y llegue a
   `main` — el pipeline de publicación solo corre desde ahí).
2. **Medición SSM real** de los cuatro escenarios (A-D) en el nodo `app`
   real — bloqueada sin acceso AWS en este entorno. Ver el procedimiento
   exacto en `resource-measurements.md`.
3. **Verificación en hardware Graviton real** (no solo QEMU) de ambas
   dependencias nativas — recomendado como parte del primer despliegue
   controlado, no como un paso separado.
4. **Despliegue controlado real** siguiendo el orden de `docs/runbooks/en-037-4-despliegue-ia-combat.md`
   (migrar → runtime ONNX → Combat → trainer solo → medir → evaluator
   solo → medir → ambos → medir → evidencia).

## Por qué esto es correcto incluso sin desplegar en AWS

El prompt maestro de #573 (§15.5, §23) autoriza explícitamente esta
situación: *"Si el acceso real a AWS no está disponible, completar las
pruebas que sí puedan realizarse y declarar el despliegue AWS como no
verificado. No inventar evidencia de producción."* Este documento, y los
cuatro que lo acompañan, son exactamente esa declaración — ni más ni
menos de lo que se pudo verificar desde este entorno.
