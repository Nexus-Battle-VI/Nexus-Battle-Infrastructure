# EN-037.4 (Management #573) — Resultados de construcción de imágenes

Todas las construcciones de este documento se ejecutaron LOCALMENTE (Docker
Desktop, host `x86_64`) contra el `Dockerfile` real de
`Nexus-Battle-Combat` (rama `feat/en-037-4-ai-worker-container`, que añade la
etapa `trainer` — ver `docs/runbooks/en-037-4-despliegue-ia-combat.md` para
el contrato completo de esa etapa). Ninguna imagen de este documento se
publicó a GHCR: la publicación real queda a cargo del pipeline de CI de
Combat (`.github/workflows/ci.yml`, job `publish`, solo desde `main`).

## Resumen

| Imagen | Target | Plataforma | Resultado | Evidencia |
| --- | --- | --- | --- | --- |
| `nexus-battle-combat:test-native` | `runtime` | `linux/amd64` (nativo) | OK | Build limpio, reutiliza cache de etapas compartidas |
| `nexus-battle-combat-trainer:test-native` | `trainer` | `linux/amd64` (nativo) | OK | Usuario no-root, Node+Python coexisten, label OCI correcto |
| `arm64-onnx-smoke:test` (spike aislado, no es la imagen real) | — | `linux/arm64` (QEMU) | OK | Ver `architecture-compatibility.md` |
| `arm64-torch-smoke:test` (spike aislado) | — | `linux/arm64` (QEMU) | OK | Ver `architecture-compatibility.md` |
| `arm64-trainer-combo:test` (spike que replica el patrón real) | — | `linux/arm64` (QEMU) | OK | Ver `architecture-compatibility.md` |
| `nexus-battle-combat-trainer:test-arm64` (Dockerfile REAL) | `trainer` | `linux/arm64` (QEMU) | **OK** | Confirmado, ver debajo |

**Resultado confirmado de la fila final** — la imagen REAL (`--target
trainer`, `Dockerfile` real de Combat sin modificar para la prueba,
`--platform linux/arm64`, `--build-arg SOURCE_COMMIT=$(git rev-parse HEAD)`):

```
$ docker buildx build --platform linux/arm64 --target trainer \
    -t nexus-battle-combat-trainer:test-arm64 \
    --build-arg SOURCE_COMMIT=$(git rev-parse HEAD) --load .
... (build exitoso)

$ docker run --rm --platform linux/arm64 nexus-battle-combat-trainer:test-arm64 whoami
node

$ docker run --rm --platform linux/arm64 nexus-battle-combat-trainer:test-arm64 \
    uv run --project ai python -c "import torch, numpy, onnx, onnxscript, pymongo, platform; print('torch', torch.__version__, platform.machine())"
   Building nexus-combat-ai @ file:///app/ai
      Built nexus-combat-ai @ file:///app/ai
torch 2.14.1+cpu aarch64

[exited with code 0]
```

Esta es la prueba AUTORITATIVA: no un spike aislado que replica el patrón,
sino el `Dockerfile` real de la rama de este PR, construido para `linux/arm64`,
corriendo como usuario no-root, con Python+PyTorch funcionando de verdad
bajo emulación ARM64. Los tres spikes de las filas 3-5 quedan como evidencia
de respaldo (cada pieza aislada), esta fila es la confirmación integrada.

## 1. `runtime` (sin cambios de comportamiento, solo confirmación de que la etapa `trainer` nueva no la afecta)

```
$ docker build --target runtime -t nexus-battle-combat:test-native .
...
#19 exporting to image ... DONE 0.6s
```

Build exitoso, capas compartidas (`deps`, `build`, `prod-deps`) cacheadas sin
cambios — confirma que añadir la etapa `trainer` al `Dockerfile` NO alteró
la imagen `runtime` existente.

## 2. `trainer` (nueva, EN-037.4)

```
$ docker build --target trainer -t nexus-battle-combat-trainer:test-native \
    --build-arg SOURCE_COMMIT=$(git rev-parse HEAD) .
...
$ docker run --rm nexus-battle-combat-trainer:test-native whoami
node
$ docker run --rm nexus-battle-combat-trainer:test-native node --version
v24.21.0
$ docker run --rm nexus-battle-combat-trainer:test-native uv run --project ai python -c \
    "import torch, numpy, onnx, onnxscript, pymongo, platform; print('torch', torch.__version__, platform.machine())"
torch 2.14.1+cpu x86_64
$ docker inspect nexus-battle-combat-trainer:test-native --format '{{json .Config.Labels}}'
{"org.opencontainers.image.revision":"6f9c63e0c2b2a58f76a08fc5431f4c173fe52b81","org.opencontainers.image.title":"nexus-battle-combat-trainer"}
```

Confirma, con el `Dockerfile` real (no un spike aislado):

- Build exitoso, sin exponer secretos ni credenciales en capas.
- Usuario de ejecución: `node` (uid 1000, no root) — `whoami` lo confirma
  dentro del contenedor en ejecución, no solo leído del `Dockerfile`.
- Node 24 y el entorno Python (`uv run --project ai`) coexisten en la misma
  imagen y ambos ejecutan correctamente.
- El label OCI `org.opencontainers.image.revision` contiene el SHA REAL
  pasado en `--build-arg SOURCE_COMMIT`, no un placeholder.
- Sin `HEALTHCHECK` HTTP (correcto: este worker no expone puerto).

## 3. Contenido de la imagen — verificación de que `.dockerignore` excluye lo correcto

```
$ docker run --rm nexus-battle-combat-trainer:test-native sh -c "find /app/ai -maxdepth 1"
/app/ai
/app/ai/pyproject.toml
/app/ai/uv.lock
/app/ai/README.md
/app/ai/src
/app/ai/.venv
```

`ai/tests`, `ai/examples`, `ai/.pytest_cache`, `ai/.ruff_cache` NO están en la
imagen (excluidos por `.dockerignore`). `.venv` SÍ existe (la crea `uv sync`
dentro de la imagen, en tiempo de build — nunca copiada desde el host).

## 4. Tamaño de imagen

```
$ docker images nexus-battle-combat-trainer:test-native nexus-battle-combat:test-native --format '{{.Repository}}:{{.Tag}}  {{.Size}}'
```

(Completar con el resultado exacto del entorno de CI/revisión — el tamaño en
el host local de esta auditoría no es representativo del tamaño final en
GHCR tras compresión de capas multiarch; no se afirma una cifra sin volver a
medirla en el pipeline real.)

## Qué NO se verificó en este documento

- Publicación real a GHCR (requiere el pipeline de CI de Combat desde `main`,
  con `secrets.GITHUB_TOKEN` — no ejecutable desde este entorno local).
- Ejecución sobre hardware Graviton real (ver `architecture-compatibility.md`,
  sección "Alcance de esta evidencia").
- Medición de recursos bajo carga de entrenamiento/evaluación REAL con datos
  de producción (ver `resource-measurements.md`).
