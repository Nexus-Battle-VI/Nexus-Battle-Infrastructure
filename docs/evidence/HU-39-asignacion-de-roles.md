# HU-39 — Evidencia de asignación de roles mediante RBAC

- **Issue central:** [Nexus-Battle-VI/Nexus-Battle-Management#27](https://github.com/Nexus-Battle-VI/Nexus-Battle-Management/issues/27)
- **Diseño y matriz:** [HU-39 — Diseño de asignación de roles](../architecture/hu-39-role-management.md)
- **Fecha de la verificación:** 2026-08-30
- **Entorno:** `https://nexus.simuladorupbbga.app` (producción)
- **Estado:** despliegue y controles automáticos terminados; recorrido de extremo a extremo con una persona, pendiente

Esta evidencia distingue deliberadamente tres cosas que no son equivalentes:
las pruebas locales, el artefacto publicado y el comportamiento observado en
producción. No contiene contraseñas, testimonios, claves TOTP ni cuerpos de
respuesta.

## Trazabilidad de tareas

| Task | Evidencia que la completa |
| --- | --- |
| [HU-39.1 — Diseño](https://github.com/Nexus-Battle-VI/Nexus-Battle-Management/issues/237) | Caso de uso textual, matriz literal, contrato conceptual y cuatro fuentes PlantUML editables en el [diseño](../architecture/hu-39-role-management.md). |
| [HU-39.2 — Node.js](https://github.com/Nexus-Battle-VI/Nexus-Battle-Management/issues/238) | Account [#28](https://github.com/Nexus-Battle-VI/Nexus-Battle-Account/pull/28), pruebas 335/335 y despliegue con digest verificado. |
| [HU-39.3 — Interfaz](https://github.com/Nexus-Battle-VI/Nexus-Battle-Management/issues/239) | Web [#37](https://github.com/Nexus-Battle-VI/Nexus-Battle-Web/pull/37), pruebas 280/280 y comprobación real a 1360×768 y 390×844. |
| [HU-39.4 — Pruebas RBAC](https://github.com/Nexus-Battle-VI/Nexus-Battle-Management/issues/240) | Controles de Account, Web, Catalog y Community documentados abajo; el recorrido humano final permanece señalado como pendiente. |

Las cuatro Tasks solo deben cerrarse al integrar este PR. La HU padre permanece
abierta hasta que el Product Owner acepte el recorrido humano completo.

## Decisiones aplicadas

| Decisión | Resultado |
| --- | --- |
| D1 | Solo `SUPER_ADMINISTRATOR` puede gestionar roles. |
| D2 | La jerarquía es de un solo sentido: Super Administrador satisface una ruta de Administrador; el inverso no. |
| D3 | Al conceder se persiste antes de reflejar; al retirar se refleja antes de persistir. El fallo intermedio niega privilegios. |
| D4 | `ADMINISTRATOR` exige TOTP confirmado en `UserMFASettingList`. |
| D5 | La API no concede `SUPER_ADMINISTRATOR`. |
| D6 | Al retirar se ejecuta `AdminUserGlobalSignOut`. Esto revoca sesiones de Cognito, pero no convierte en revocables los JWT que los servicios validan localmente: un access token ya emitido puede seguir siendo aceptado hasta su `exp`, como máximo 15 minutos con la configuración actual. |
| D7 | Internamente se conserva `PLAYER`; la interfaz presenta como vigente el rol de mayor precedencia. |

## Entrega por repositorio

| Repositorio | PR | Resultado en `main` |
| --- | --- | --- |
| Account | [#28](https://github.com/Nexus-Battle-VI/Nexus-Battle-Account/pull/28) | Merge `cf2c60d203cf2facd5e09f0f01097a788559c485` |
| Web | [#37](https://github.com/Nexus-Battle-VI/Nexus-Battle-Web/pull/37) | Merge `efd08b2cc50c32034721b52795bc975f8dfcd21c` |
| Infrastructure | [#46](https://github.com/Nexus-Battle-VI/Nexus-Battle-Infrastructure/pull/46) | IAM actualizado y bootstrap de elevación retirado |
| Catalog | [#19](https://github.com/Nexus-Battle-VI/Nexus-Battle-Catalog/pull/19) | Control de matriz RBAC agregado |
| Community | [#12](https://github.com/Nexus-Battle-VI/Nexus-Battle-Community/pull/12) | Control de matriz RBAC agregado |

No se modificó `Nexus-Battle-Management`.

## Controles de código y pruebas

| Control | Resultado | Qué fallaría si la afirmación fuera falsa |
| --- | --- | --- |
| Account | `format:check`, `lint`, `typecheck`, `build`; Jest **335/335** | Fallan los casos de autorización D1, orden D3, TOTP D4, roles inválidos, idempotencia, errores 503, precedencia de `search` y jerarquía D2. |
| Web | `format:check`, `lint`, `typecheck`, `build`; Vitest **280/280** | Fallan la visibilidad Super-only, la búsqueda, los controles de TOTP, las confirmaciones y el refresco posterior. |
| Catalog | Suite **181/181** y DoD técnica | El test con testimonio falso de Super Administrador puro deja de obtener 200 en una ruta `@Roles(Administrator)`. |
| Community | Suite **127/127** y DoD técnica | El test de Super Administrador puro deja de poder moderar; los controles de Player y Moderator fijan el otro lado de la matriz. |
| Infrastructure | `terraform fmt`, `terraform validate`; prueba del auditor MFA **7/7** | El control de mutación demuestra que el auditor falla cuando existe una cuenta administrativa sin factor. |
| Interfaz local | Navegador real a 1360×768 y 390×844; en móvil `scrollWidth = clientWidth = 390` | Un desbordamiento horizontal o una ruta rota habría cambiado esas mediciones o impedido completar el flujo simulado. |

Los workflows de los commits mergeados también terminaron en verde:

- [Account CI 33326907232](https://github.com/Nexus-Battle-VI/Nexus-Battle-Account/actions/runs/33326907232), incluido el trabajo `Publicar imagen en GHCR`.
- [Web CI 33326948420](https://github.com/Nexus-Battle-VI/Nexus-Battle-Web/actions/runs/33326948420), incluido el trabajo `Publicar imagen en GHCR`.

El control relevante no fue solo que el workflow dijera `success`: se comprobó
que el trabajo de publicación existía, se ejecutó sobre el SHA mergeado y
terminó correctamente.

## Infraestructura aplicada

El plan previo mostró únicamente una modificación en sitio:

```text
Plan: 0 to add, 1 to change, 0 to destroy.
```

Se aplicó el plan guardado:

```text
Apply complete! Resources: 0 added, 1 changed, 0 destroyed.
```

Después se leyó de nuevo la política del rol del nodo y se confirmó que contiene
`cognito-idp:AdminUserGlobalSignOut`. Un nuevo `terraform plan` terminó con:

```text
No changes. Your infrastructure matches the configuration.
```

Si la acción IAM no estuviera realmente aplicada, la lectura posterior de la
política sería falsa; si hubiese deriva, el segundo plan propondría cambios.

## Despliegue por SSM y digests

Destino resuelto desde el estado de Terraform: nodo `app`
`i-03b4b9adc8dea0d2d`, conectado a SSM. Se desplegó Account antes de Web.

| Servicio | Comando SSM | Resultado | Digest observado en el contenedor |
| --- | --- | --- | --- |
| Account | `a7e1cc20-58af-4da0-9180-db2472101157` | `Success`; migración finalizada; contenedor `running`; imagen del contenedor igual a la imagen descargada | `sha256:c2d784435fa6e72236b40dfa487a1afde48d1210680ea6a73bb4f88e2c561a5a` |
| Web | `613a8d5e-e757-443c-9b33-10689364054a` | `Success`; contenedor `running`; imagen del contenedor igual a la imagen descargada | `sha256:95cd03c9124236bc951012b1d8876cfbc7b48787acb3e6ddef0c19eb8abd0f26` |

El digest evita confundir «contenedor saludable» con «versión nueva ejecutándose».
El control posterior por SSM confirmó `proxy`, `account` y `web` en estado
`running`, sin error estándar.

## Comprobaciones contra producción sin credenciales

Solo se conservaron códigos de estado:

```text
GET  /                                                     -> 200
GET  /api/accounts/search?email=probe@example.invalid      -> 401
POST /api/accounts/00000000-0000-4000-8000-000000000000/roles
  body { role: MODERATOR }, sin testimonio                 -> 401
```

La búsqueda también se invocó por la entrada interna de Caddy en el nodo y
respondió 401. Si `search` hubiese sido absorbido por `@Get(':id')`, el guard no
sería el único control: las pruebas de integración fijan explícitamente el
enrutamiento y la consulta autenticada debe completarse en el recorrido humano.

## Auditoría del segundo factor

Se ejecutó `scripts/verificar-segundo-factor-administrativo.py` contra Cognito,
sin imprimir identificadores de cuenta:

```text
ADMINISTRATOR,SUPER_ADMINISTRATOR -> exit 0; 1 cuenta comprobada
PLAYER (control negativo)         -> exit 1, como se esperaba
```

El segundo resultado es el control de mutación: prueba que el guion detecta
cuentas sin factor y no devuelve éxito incondicional.

## Inicialización única del rol raíz

El recorrido humano descubrió una precondición que el plan había dado por
cumplida: Cognito tenía 1 `ADMINISTRATOR`, pero 0 `SUPER_ADMINISTRATOR`. Por
tanto, HU-39 estaba desplegada pero ninguna identidad podía entrar a su pantalla
ni invocar sus operaciones. El texto «el bootstrap sobra cuando HU-39 exista»
era incompleto: solo sobra después de que exista el único rol raíz.

Con autorización expresa se inicializó la cuenta administrativa existente como
único `SUPER_ADMINISTRATOR`. No se restauró el bootstrap al árbol: se ejecutó
una vez su versión auditada desde el historial de Git. Antes de escribir se
comprobó, sin registrar la identidad:

```text
Cognito: ADMINISTRATOR=1, SUPER_ADMINISTRATOR=0
TOTP confirmado=true
PostgreSQL: account_count=1, roles=PLAYER+ADMINISTRATOR
```

La concesión respetó PostgreSQL primero y Cognito después. Solo al confirmar
`SUPER_ADMINISTRATOR` en ambos lados se retiró el rol anterior en orden inverso:
Cognito primero, PostgreSQL después. Se eliminó exactamente 1 fila
`ADMINISTRATOR` y se ejecutó `AdminUserGlobalSignOut`.

El control final independiente dio:

```text
Cognito: PLAYER=5, MODERATOR=0, ADMINISTRATOR=0, SUPER_ADMINISTRATOR=1
Grupos de la identidad raíz: PLAYER, SUPER_ADMINISTRATOR
PostgreSQL: PLAYER, SUPER_ADMINISTRATOR
Auditor MFA: exit 0; 1 cuenta administrativa comprobada
```

No quedó ningún guion de elevación en `main`, y D5 continúa impidiendo conceder
otro `SUPER_ADMINISTRATOR` mediante la API.

## Recorrido humano en curso

Debe hacerse con una persona delante y sin compartir secretos con el registro de
ejecución:

Controles ya observados contra producción:

```text
GET  /api/accounts/search sin testimonio -> 401
POST /api/accounts/:id/roles sin testimonio -> 401
PLAYER intentando asignar un rol -> 403
```

Queda por completar:

1. Una cuenta de prueba inscribe TOTP en *Mi Cuenta → Seguridad*.
2. El Super Administrador recién inicializado obtiene un testimonio nuevo, busca la cuenta y la eleva a `ADMINISTRATOR` desde `/admin/roles`.
3. La cuenta cierra sesión y vuelve a entrar; Cognito solicita el código TOTP.
4. Con el nuevo testimonio accede a una ruta administrativa de Catalog, 200.
5. El Super Administrador retira el rol.
6. Se comprueba 403 con un testimonio renovado. También se registra si el token anterior sigue siendo aceptado durante la ventana máxima documentada de 15 minutos.
7. Como control negativo separado, una cuenta PLAYER intenta la operación de asignación y recibe 403.

Hasta completar esos pasos no se afirma que la HU esté verificada de extremo a
extremo en producción. Las pruebas y los 401 demuestran contrato y autenticación;
no sustituyen una autorización real con roles de Cognito.

## Alcance no construido por esta HU

Estas acciones no tienen operación implementada en los servicios actuales y no
se inventaron endpoints para simular que la matriz estaba completa:

| Acción | Estado |
| --- | --- |
| Emitir advertencias | No existe operación. |
| Suspender usuarios temporalmente | Existe el estado de dominio, no una operación. |
| Banear definitivamente | No existe operación. |
| Eliminar comentario propio | No existe operación de borrado propio en Community. |

Sí se verificaron mediante pruebas los caminos existentes de moderación en
Community y administración de productos en Catalog.
