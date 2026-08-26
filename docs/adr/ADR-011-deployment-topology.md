# ADR-011 — Topología de despliegue: cuántas instancias y por qué

- **Estado:** **Accepted** el 2026-08-25
- **Fecha:** 2026-08-25
- **Decide:** Arquitectura
- **Relacionado:** [ADR-004](ADR-004-identity-directory.md), [ADR-007](ADR-007-aws-cost-optimized-platform.md), [ADR-008](ADR-008-iac.md)

## Contexto

Durante la revisión de la arquitectura de demo se planteó una objeción legítima: si el sistema es de microservicios, **¿no debería cada servicio tener su propia instancia?** Se apoyaba en tres problemas concretos y correctos de meter todo en una sola máquina.

Este ADR existe porque la objeción es buena y la respuesta no es obvia. Merece números, no doctrina.

## Los tres problemas planteados, uno a uno

### 1. Punto único de fallo

**El problema es real y está declarado.** Una sola EC2 significa que si cae la instancia, cae el producto entero.

**Pero una EC2 por servicio no lo resuelve.** En una sola zona de disponibilidad y sin grupo de autoescalado, cada instancia es a su vez un punto único de fallo para su servicio, y **el proxy inverso sigue siendo un punto único que tumba todo**.

Peor aún: la probabilidad de que **algo** esté caído **sube** con el número de nodos.

| Probabilidad de fallo por instancia | 1 nodo | 2 nodos | 3 nodos | 8 nodos |
| --- | ---: | ---: | ---: | ---: |
| 0,1 % | 0,100 % | 0,200 % | 0,300 % | 0,797 % |
| 0,5 % | 0,500 % | 0,998 % | 1,493 % | 3,931 % |
| 1,0 % | 1,000 % | 1,990 % | 2,970 % | 7,726 % |

Repartir en ocho nodos **reduce el radio de impacto de cada fallo y multiplica por ocho su frecuencia**. Sin autoescalado, cada uno de esos fallos exige intervención manual: una EC2 muerta sigue muerta hasta que alguien lo note.

Un contenedor con `restart: unless-stopped` vuelve solo en segundos. **Para el fallo más frecuente —el proceso que revienta— los contenedores en un host se recuperan más rápido que instancias separadas sin grupo de autoescalado.**

Lo que sí resuelve el punto único de fallo: **multi-AZ, reemplazo automático y balanceador**. Está descrito en [target-scale-deployment.md](../architecture/target-scale-deployment.md) y su coste está muy por encima del techo.

### 2. Falta de escala independiente

**El problema es real.** En un host compartido no se puede escalar un servicio sin agrandar la máquina entera.

**Pero una EC2 por servicio tampoco da escalado.** Da *asignación estática*: se puede dar a Catalog una máquina mayor que a Community, y ahí termina. Escalar de verdad —añadir instancias según demanda— exige grupo de autoescalado y balanceador, o un orquestador. Sin eso, ante un pico de tráfico hay que redimensionar a mano, exactamente igual que con una sola máquina.

A ≤ 30 usuarios concurrentes ([assumptions.md](../costs/assumptions.md)) **no hay nada que escalar**. El escalado independiente es un requisito de la arquitectura objetivo, no de la demo.

### 3. Un servicio acapara memoria o procesador

**El problema era real y ya está resuelto**, sin gastar un céntimo.

Cada contenedor declara `mem_limit` y `pids_limit`. Cuando uno supera su techo, el núcleo mata **ese** contenedor y `restart: unless-stopped` lo levanta; el resto no se entera. Es exactamente el aislamiento de recursos que dan los *cgroups*, y es el motivo por el que existen los contenedores.

La CPU no se limita a propósito: su contención degrada el rendimiento pero no mata procesos, y estrangular ráfagas legítimas en una instancia de núcleos compartidos haría más daño que bien.

## Comparación de topologías

Con precios reales de la Price List API y los techos de memoria ya fijados en la composición de referencia:

| Topología | Nodos | 24/7 | Solo demos | Duración de un mes de techo |
| --- | ---: | ---: | ---: | ---: |
| T1 · una instancia | 1 | 30,58 | 6,72 | 14,9 meses |
| **T2 · apps \| datos** | **2** | **35,03** | **11,17** | **9,0 meses** |
| T3 · borde \| apps \| datos | 3 | 45,61 | 15,79 | 6,3 meses |
| T4 · una EC2 por servicio | 8 | 92,39 | 38,71 | 2,6 meses |

T4 consume el **92 % del techo mensual** encendida, y en régimen de demos sigue costando 3,5 veces más que T2. El motivo no es el cómputo: son las **direcciones IPv4**. Cada nodo necesita una para descargar imágenes de GHCR —no hay NAT Gateway, prohibido por coste— y **la IPv4 se cobra igual apagada que encendida**. Con ocho nodos, apagar deja de ser una palanca de ahorro.

## Decisión

**Topología T2: dos instancias, separando el plano sin estado del plano con estado.**

| Nodo | Tipo | Contiene | Memoria necesaria | Margen |
| --- | --- | --- | ---: | ---: |
| `app` | `t4g.small` | proxy, web, los 6 servicios | 1 340 MiB | 708 MiB |
| `data` | `t4g.small` | PostgreSQL, MongoDB | 972 MiB | 1 076 MiB |

El criterio no es «cuántos microservicios hay» sino **qué componentes tienen ciclos de vida operativos opuestos**:

- Las aplicaciones **se redespliegan en cada integración**. Las bases de datos **no deben reiniciarse nunca**.
- Un reinicio del host por parche del núcleo tumba lo que haya en él. Separando, el parcheo del plano de aplicación **no toca los datos**.
- El agotamiento de recursos del plano de aplicación **no puede alcanzar físicamente** al motor de datos, ni siquiera si fallara un límite de contenedor.

Esa separación es un principio de arquitectura con nombre propio —plano con estado frente a plano sin estado— y es más defendible que «una máquina por servicio», que no responde a ninguna propiedad del sistema salvo su organigrama.

### La topología es una variable, no una constante

El módulo de cómputo recibe un **mapa de nodos**. Pasar de T2 a T3 o a T4 es editar un fichero de variables y ejecutar `terraform plan`, no reescribir la infraestructura.

Se hace así deliberadamente: si el tráfico real desmiente los supuestos, o si aparece presupuesto para la arquitectura objetivo, **la decisión se revisa con un `plan` delante**, no con una discusión.

## Consecuencias

**Lo que se gana**

- El plano de datos queda aislado del despliegue y del parcheo del plano de aplicación.
- El aislamiento de recursos entre servicios ya existe, a coste cero, vía *cgroups*.
- La topología es configuración, no arquitectura tallada en piedra.
- En régimen de demos, 11,17 USD/mes: el presupuesto de un mes cubre nueve.

**Lo que cuesta**

- **Sigue habiendo puntos únicos de fallo**: el nodo de aplicación y el nodo de datos. Esta topología reduce el radio de impacto; **no proporciona alta disponibilidad y no debe presentarse como si lo hiciera**.
- No hay escalado automático de ningún servicio.
- El nodo de datos sigue sin réplica ni conmutación por error. Perder su volumen EBS es perder los datos.
- 4,45 USD/mes más que la topología de un solo nodo, en régimen de demos.

## Lo que este ADR no cambia

**El BLOCKER de [ADR-004](ADR-004-identity-directory.md) sigue activo.** Ninguna topología resuelve la ausencia de control de acceso. Por eso los grupos de seguridad definidos en Terraform **no abren ingreso público por defecto**: la infraestructura aplica el blocker en lugar de confiar en que alguien lo recuerde.
