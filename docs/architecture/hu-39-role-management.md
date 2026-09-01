# HU-39 — Diseño de asignación de roles y matriz RBAC

## Trazabilidad

- **Historia:** [HU-39 — Asignación de rol mediante RBAC](https://github.com/Nexus-Battle-VI/Nexus-Battle-Management/issues/27)
- **Diseño:** [TASK HU-39.1](https://github.com/Nexus-Battle-VI/Nexus-Battle-Management/issues/237)
- **Requisito:** `RF-39`
- **Identidad previa:** HU-02 / [ADR-004](../adr/ADR-004-identity-directory.md)
- **Evidencia de implementación:** [HU-39-asignacion-de-roles.md](../evidence/HU-39-asignacion-de-roles.md)

Fuentes UML editables:

- [Caso de uso](../diagrams/hu-39-use-case.puml)
- [Actividad](../diagrams/hu-39-activity-role-management.puml)
- [Secuencia](../diagrams/hu-39-sequence-role-management.puml)
- [Dominio](../diagrams/hu-39-domain-rbac.puml)

## Decisiones funcionales resueltas

1. Solo un `SUPER_ADMINISTRATOR` autenticado gestiona roles.
2. La API concede y retira `MODERATOR` y `ADMINISTRATOR`; nunca concede
   `SUPER_ADMINISTRATOR`. El único rol raíz se inicializa una vez y no se
   reproduce mediante una operación ordinaria.
3. `PLAYER` es el rol base no retirable. El «rol vigente» que ve la persona es
   el de mayor precedencia entre `PLAYER` y, como máximo, un rol elevado de
   operación. `SUPER_ADMINISTRATOR` tiene la precedencia máxima.
4. Antes de conceder `ADMINISTRATOR`, Cognito debe confirmar
   `SOFTWARE_TOKEN_MFA`. Asignar primero y pedir el factor después abriría una
   ventana en la que una cuenta administrativa entraría con sola contraseña.
5. La retirada cierra las sesiones de Cognito. Como los servicios verifican
   localmente JWT ya emitidos, un access token anterior puede conservar sus
   claims hasta `exp`, como máximo 15 minutos. Un testimonio nuevo refleja la
   retirada inmediatamente.
6. El cambio de rol no elimina perfil, inventario, publicaciones ni historial.

## Caso de uso textual

### Asignar rol mediante RBAC

**Actor principal:** Super Administrador autenticado.

**Entrada conceptual:** identidad del actor, cuenta destino y rol solicitado.

**Precondiciones:**

- el testimonio es válido y no está vencido;
- el actor tiene `SUPER_ADMINISTRATOR`;
- la cuenta destino existe;
- el rol solicitado es `MODERATOR` o `ADMINISTRATOR`;
- para `ADMINISTRATOR`, la cuenta destino tiene TOTP confirmado.

**Flujo principal:**

1. Localizar actor y destino.
2. Validar la regla de gestión en el dominio.
3. Calcular el conjunto resultante sin retirar `PLAYER`.
4. Persistir el resultado en `account_roles`, fuente de verdad.
5. Reflejar el conjunto completo en los grupos de Cognito.
6. Devolver la cuenta actualizada.
7. La interfaz vuelve a consultar y presenta el rol de mayor precedencia.

**Alternativas y fronteras:**

- sin testimonio: 401;
- actor no Super Administrador: 403;
- destino inexistente: 404;
- rol ajeno al vocabulario o `SUPER_ADMINISTRATOR`: 400;
- Administrador sin TOTP: 409, sin escribir en ningún lado;
- fallo de Cognito al conceder: 503; PostgreSQL conserva el rol, pero ningún
  testimonio nuevo lo transporta hasta reparar el reflejo;
- rol ya poseído: 200 idempotente.

### Retirar rol

1. Validar actor, destino y rol retirable.
2. Calcular el conjunto resultante.
3. Reflejar primero en Cognito para que testimonios nuevos dejen de conceder.
4. Persistir después en PostgreSQL.
5. Ejecutar cierre global de sesiones.

Retirar `PLAYER` o el propio `SUPER_ADMINISTRATOR` raíz responde 400. Si falla
el reflejo, PostgreSQL no se modifica. Si falla la persistencia después del
reflejo, el estado intermedio niega en vez de conceder.

## Matriz de permisos de RF-39

Esta es la definición funcional; no se convierte en permisos individuales por
usuario ni en una tabla duplicada por pantalla.

| Permiso / acción | Jugador | Moderador | Administrador | Super Administrador |
| --- | --- | --- | --- | --- |
| Crear cuenta de jugador | Sí | No | No | No |
| Modificar perfil propio | Sí | Sí | Sí | Sí |
| Publicar comentarios | Sí | Sí | Sí | Sí |
| Eliminar comentario propio | Sí | Sí | Sí | Sí |
| Moderar comentarios | No | Sí | Sí | Sí |
| Emitir advertencias | No | Sí | Sí | Sí |
| Suspender usuarios | No | Temporal | Sí | Sí |
| Banear definitivamente | No | No | Sí | Sí |
| Crear admin/moderador | No | No | No | Sí |
| Gestionar productos | No | No | Sí | Sí |

## Cobertura real y frontera

| Fila | Estado verificable |
| --- | --- |
| Crear jugador | El alta pública existente crea `PLAYER`; HU-39 no rediseña el registro. |
| Moderar comentarios | Community protege ocultar publicaciones y cerrar hilos; Super satisface la jerarquía de moderación. |
| Gestionar productos | Catalog exige Administrador; Super satisface Administrador en un solo sentido. |
| Crear admin/moderador | Account y Web lo entregan mediante asignación de roles existente, no creando otra identidad. |
| Modificar perfil propio | Pertenece a HU-05; no se implementa aquí. |
| Publicar/eliminar comentario propio | Publicar existe; eliminar comentario propio no tiene operación actual. |
| Advertir, suspender y banear | No existen operaciones actuales; corresponden a HUs de sanciones. |

Una fila sin operación no puede producir una prueba HTTP honesta. Este diseño
define quién podrá ejecutarla cuando exista, pero HU-39 no inventa endpoints de
sanción para aparentar cobertura.

## Contrato conceptual

El contexto Account/Identity ofrece estas capacidades, sin prescribir HTTP:

- localizar una cuenta gestionable por un identificador humano normalizado;
- conceder un rol operativo a una cuenta;
- retirar un rol operativo;
- consultar los roles persistidos y el rol vigente por precedencia;
- consultar si el segundo factor administrativo está confirmado;
- reflejar los roles persistidos en el directorio de identidad;
- revocar sesiones después de una retirada.

La autorización funcional pertenece al dominio. Los adaptadores traducen
protocolo, persistencia, Cognito y errores de disponibilidad, pero no deciden
qué actor puede elevar una cuenta.

## Persistencia e integración

`account_roles` es la fuente de verdad. Cognito es un reflejo necesario porque
`cognito:groups` viaja en el testimonio que verifican los demás servicios. No
hay transacción distribuida, por lo que el orden se elige para que cualquier
fallo intermedio niegue permisos:

```text
conceder: PostgreSQL -> Cognito
retirar : Cognito -> PostgreSQL -> cierre global de sesión
```

Web oculta la navegación a quien no es Super Administrador, pero esa puerta es
presentación. Account vuelve a verificar el JWT y el rol en cada operación; una
URL o petición escrita a mano recibe 401/403.

## Impacto arquitectónico

- **Account/Identity:** propietario de cuentas, roles y regla de gestión.
- **Cognito:** emisor del testimonio, estado TOTP y reflejo de grupos.
- **Web:** búsqueda y gestión para el Super Administrador; rol vigente por
  precedencia.
- **Catalog y Community:** consumidores de los claims; aplican su propia
  operación sensible sin acceder a la base de Account.
- **Infrastructure:** IAM mínimo para consultar MFA, reflejar grupos y cerrar
  sesiones.

Ningún servicio consulta directamente los datos de otro bounded context.
