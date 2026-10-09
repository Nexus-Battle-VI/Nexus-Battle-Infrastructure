# EN-037.4 (Management #573) — Compatibilidad de arquitectura ARM64

Evidencia real de compatibilidad de las dos dependencias nativas que bloquean
este despliegue: `onnxruntime-node` (runtime/evaluator) y PyTorch CPU
(trainer). Metodologia y limitaciones declaradas explícitamente — ver
"Alcance de esta evidencia" al final.

## Resultado resumido

| Dependencia | ¿Resuelve wheel/binario `linux/arm64`? | ¿Carga y ejecuta bajo `linux/arm64`? | Método |
| --- | --- | --- | --- |
| `onnxruntime-node@1.30.0` | Sí (bundlea binarios para `linux/arm64` en el propio paquete npm) | Sí | QEMU (`docker run --platform linux/arm64`) |
| `torch==2.14.1+cpu` (vía `uv.lock`, índice `https://download.pytorch.org/whl/cpu`) | Sí (`manylinux_2_28_aarch64`, hash pinneado en `uv.lock`) | Sí | QEMU (`docker buildx build --platform linux/arm64` + `docker run --platform linux/arm64`) |

**Ambos resultados son POSITIVOS.** No se encontró ningún bloqueo de
compatibilidad ARM64 para ninguna de las dos dependencias nativas.

## 1. ONNX Runtime Node

`onnxruntime-node@1.30.0` (fijado en `package.json`/`package-lock.json` de
Combat) distribuye sus binarios nativos DENTRO del propio tarball npm —
confirmado inspeccionando `node_modules/onnxruntime-node/bin/napi-v6/`:

```
node_modules/onnxruntime-node/bin/napi-v6/
├── darwin/arm64
├── linux/arm64      <- libonnxruntime.so.1 (25.135.496 bytes), onnxruntime_binding.node (394.648 bytes)
├── linux/x64
├── win32/arm64
└── win32/x64
```

Ningún binario vacío ni placeholder: ambos archivos de `linux/arm64` existen
con tamaño real.

### Prueba de ejecución real (QEMU)

Imagen `node:24-bookworm-slim` (misma base que `Dockerfile` de Combat),
construida y ejecutada con `--platform linux/arm64` sobre un host `x86_64`
(QEMU vía `binfmt_misc`, registrado por Docker Desktop):

```
$ docker run --rm --platform linux/arm64 arm64-onnx-smoke:test
{"step":"env","platform":"linux","arch":"arm64","nodeVersion":"v24.21.0"}
{"step":"session_created","loadMs":1886,"inputNames":["candidate_features"],"outputNames":["scores"]}
{"step":"infer_1x72","infer1Ms":49,"scores":[-0.06342776119709015],"allFinite":true}
{"step":"infer_3x72","infer3Ms":61,"scores":[-0.07240612804889679,-0.07240612804889679,-0.07240612804889679],"allFinite":true}
{"step":"done","ok":true}
```

Checklist de EN-037.4 §5.2, con resultado real:

1. Importación del paquete → OK (`require('onnxruntime-node')` no lanza).
2. Creación de `InferenceSession` → OK, 1886 ms bajo emulación.
3. Carga de `model.onnx` válido → OK (`test/fixtures/ai-model-registry/model.onnx` de Combat, artefacto real producido por el pipeline).
4. Inferencia `[1,72]` → OK, 49 ms, score finito.
5. Inferencia `[N,72]` (`N=3`) → OK, 61 ms, 3 scores finitos.
6. Resultado finito → OK (`allFinite: true` en ambos casos).
7. Comparación contra fixtures conocidos → no aplicable aquí (la paridad numérica exacta es responsabilidad de Combat/#569, no de este spike de infraestructura); lo que se demuestra aquí es que el binario CARGA Y EJECUTA, no la precisión numérica.
8. Tiempo/memoria de carga → 1886 ms (carga de sesión), ver `resource-measurements.md` para memoria.
9. Cierre sin errores → OK (`exit code 0`).

Advertencia benigna observada (no afecta el resultado): `onnxruntime cpuid_info
warning: Unknown CPU vendor` — esperado bajo emulación QEMU, el detector de
microarquitectura de ONNX Runtime no reconoce la CPU virtual que expone QEMU;
en hardware Graviton real este aviso no debería aparecer.

## 2. PyTorch CPU

`ai/pyproject.toml` fija `torch` contra el índice
`https://download.pytorch.org/whl/cpu` (`[tool.uv.sources]`). `ai/uv.lock`
YA tiene resuelto y con hash pinneado un wheel `linux/arm64`:

```
name = "torch"
version = "2.14.1+cpu"
wheels = [
  ...
  { url = ".../torch-2.14.1%2Bcpu-cp313-cp313-manylinux_2_28_aarch64.whl",
    hash = "sha256:783a3dec10d272e40ed3f1a05ec228400300d3229b8f7521a9327645fae88646", ... },
  ...
]
```

Es decir: la pregunta "¿existe un wheel CPU oficial para `linux/aarch64` en
esta versión exacta de PyTorch?" ya tenía una respuesta positiva en el
lockfile, antes de ejecutar nada. Lo que faltaba demostrar es que **se
instala y ejecuta de verdad**.

### Prueba de ejecución real (QEMU)

Dos builds independientes, mismo resultado:

**(a)** Base `python:3.13-slim-bookworm` + `pip install uv` + `uv sync --frozen --no-dev` sobre una copia de `ai/` (sin `.venv`/caches):

```
$ docker run --rm --platform linux/arm64 arm64-torch-smoke:test
torch 2.14.1+cpu
cuda_available False
machine aarch64
forward_ok torch.Size([3, 1]) True
```

**(b)** Base `node:24-bookworm-slim` (la base REAL del Dockerfile de Combat) + `uv` copiado desde `ghcr.io/astral-sh/uv:0.9.17` + `uv python install 3.13` + `uv sync --frozen --no-dev` — el patrón EXACTO que usa la etapa `trainer` del `Dockerfile` real de Combat:

```
$ docker run --rm --platform linux/arm64 arm64-trainer-combo:test
torch 2.14.1+cpu aarch64
```

Ambas corridas resuelven el mismo wheel pinneado (`manylinux_2_28_aarch64`),
lo instalan sin error, importan `torch`+`numpy`+`onnx`+`onnxscript`+`pymongo`,
y ejecutan un forward pass real (`nn.Linear`) con resultado finito.

Advertencia benigna observada en ambas corridas (no afecta el resultado):

```
.../third_party/xbyak_aarch64/src/util_impl_linux.h, 444: Can't open MIDR_EL1 sysfs entry
```

`MIDR_EL1` es un registro de identificación de CPU ARM real; QEMU en modo de
emulación de usuario no lo expone, así que oneDNN (backend de PyTorch) no
puede leer la microarquitectura exacta y cae a una ruta genérica. Esto es un
artefacto conocido de la emulación, no un fallo — en hardware Graviton real
el registro SÍ existe y este aviso no debería aparecer. No afecta la
corrección del resultado (el forward pass sigue siendo numéricamente
correcto), solo potencialmente el rendimiento (sin optimizaciones específicas
de microarquitectura).

### Build natural (confirmación adicional, sin emulación)

El mismo `Dockerfile` real de Combat, etapa `trainer`, construido SIN
`--platform` (arquitectura nativa del host, `x86_64`) y ejecutado:

```
$ docker run --rm nexus-battle-combat-trainer:test-native whoami
node
$ docker run --rm nexus-battle-combat-trainer:test-native node --version
v24.21.0
$ docker run --rm nexus-battle-combat-trainer:test-native uv run --project ai python -c "..."
torch 2.14.1+cpu x86_64
```

Confirma que la etapa `trainer` construye limpiamente, corre como usuario
`node` (no root), y that Node+Python coexisten correctamente en la misma
imagen — independientemente de la arquitectura.

## Alcance de esta evidencia (léase antes de usar este documento para autorizar producción)

- **Todas las pruebas `linux/arm64` de este documento corrieron bajo
  emulación QEMU sobre un host `x86_64` (Docker Desktop local), NUNCA sobre
  hardware Graviton/AWS real.** La emulación QEMU demuestra que el binario
  nativo es compatible con la ABI/arquitectura ARM64 (un binario mal
  compilado o cross-compilado incorrectamente falla de inmediato bajo QEMU,
  no "funciona un poco"), pero NO mide rendimiento real, ni descarta
  diferencias específicas de microarquitectura Graviton2/3 (ver las dos
  advertencias benignas arriba, ambas artefactos conocidos de emulación).
- No se tuvo acceso a una instancia EC2 `t4g.*` real en este entorno (sin
  credenciales/MCP de AWS disponibles — ver `deployment-result.md`). La
  verificación final en hardware Graviton real queda pendiente y debe
  ejecutarse como parte del despliegue controlado (§15 del prompt maestro
  de #573), no se afirma aquí que ya ocurrió.
- El fixture `model.onnx` usado es el artefacto REAL del pipeline (`#570`),
  no un archivo sintético inventado para esta prueba.
- Esta evidencia cubre exclusivamente COMPATIBILIDAD (¿carga y ejecuta?),
  nunca RENDIMIENTO ni CAPACIDAD del nodo — eso es `resource-measurements.md`.
