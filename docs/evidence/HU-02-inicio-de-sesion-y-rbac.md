# HU-02 — Evidencia de inicio de sesión y verificación de rol

- **Issue central:** [Nexus-Battle-VI/Nexus-Battle-Management#11](https://github.com/Nexus-Battle-VI/Nexus-Battle-Management/issues/11)
- **Fecha de la verificación:** 2026-08-30
- **Entorno:** `https://nexus.simuladorupbbga.app` (producción)
- **Método:** ejecutado contra el sistema desplegado, con una persona delante. No se dan por buenos los resultados de la suite: la suite verde no encontró tres de los fallos que sí encontró usar el producto.

## Criterios de aceptación

| Criterio | Estado | Cómo se comprobó |
| --- | --- | --- |
| CA-01 — Inicio de sesión con correo | Cubierto | El campo acepta correo; `resolveAccountByIdentifier` lo intenta primero |
| CA-02 — Inicio de sesión con apodo | **Comprobado con persona** | Se entró con el apodo `Dabji` y completó el acceso |
| CA-03 — Credenciales inválidas | Cubierto | Mensaje genérico, idéntico para cuenta inexistente y contraseña errónea |
| CA-04 — Resolución del rol | Cubierto | El rol sale de `account_roles`, nunca del cuerpo de la petición |
| CA-05 — Autorización en el servicio, no en la interfaz | Cubierto | `/api/orders` responde 401 sin testimonio **y** con un JWT falso |
| CA-06 — Segundo factor administrativo | **Cubierto con divergencia** | Ver la sección siguiente |

### La divergencia, dicha entera

La HU dice, textualmente:

> Conforme a la aclaración posterior del cliente, este segundo factor **será
> enviado mediante correo electrónico**.

**Lo entregado para cuentas administrativas es TOTP**, no correo. No es un
descuido: es una decisión del 2026-08-29 tomada con estos hechos delante.

1. **El MFA por correo exige SES**, y la solicitud de acceso a producción de
   esta cuenta fue **DENEGADA** (caso 178781013000904). En el entorno de
   pruebas el código solo llega a direcciones verificadas una a una. Un segundo
   factor que no llega a la mayoría no es un segundo factor: es una puerta
   cerrada.
2. **Cognito rechaza la combinación** de MFA por correo con recuperación por
   correo verificado, y el rechazo es legítimo: si el buzón es a la vez el
   factor y la vía de recuperación, quien lo controle se salta el factor
   pidiendo una recuperación.
3. Para un rol que administra el sistema entero, dejar el segundo factor
   colgando del mismo buzón que sirve para recuperar la cuenta es peor que el
   inconveniente de usar una aplicación autenticadora.

**Esto requiere aceptación del Product Owner.** O se acepta TOTP para las
cuentas administrativas y se actualiza el texto de la HU, o se mantiene el
correo y se asume que el segundo factor administrativo depende de un permiso
que AWS nos denegó.

El OTP **por correo para usuarios finales** sí está construido y probado
(`SELECT_MFA_TYPE`, elección de factor, política por rol). Encenderlo es un
`terraform apply` cuando existan teléfonos verificados para la recuperación.

## Lo comprobado contra producción

### El circuito de identidad cierra en los dos lados

```
Cognito Username : c448f488-00e1-7086-18bd-9950b3fad71e
PostgreSQL subject: c448f488-00e1-7086-18bd-9950b3fad71e
```

Idénticos. La cuenta queda atada al sujeto del testimonio, no a nada que el
cliente envíe. Y el rol se refleja en los dos sitios:

```
account_roles (fuente de verdad) : PLAYER, ADMINISTRATOR
grupos del pool (reflejo)        : PLAYER, ADMINISTRATOR
```

### La autorización ocurre en el servicio

```
/api/products    sin token          -> 200   declarada @Public()
/api/orders      sin token          -> 401
/api/orders      con JWT inventado  -> 401
```

### El factor que cada rol puede usar, con sus dos controles

```
Dabji (ADMINISTRATOR) + EMAIL              -> 403   la política corta antes de Cognito
Dabji (ADMINISTRATOR) + AUTHENTICATOR_APP  -> 503   permitido: llega a Cognito
jugadorprueba (PLAYER) + EMAIL             -> 503   permitido: distingue por rol
```

Sin los dos últimos, el 403 no probaría nada: podría estar rechazando todo.

La regla vive en Account y no en Cognito porque **Cognito no puede aplicarla**:
`mfa_configuration` es del pool entero. Y se aplica en la ruta pública, no solo
al construir la pantalla: filtrar en la interfaz no es un control.

### Las guardas de la interfaz

```
/register  sin identidad  -> "Primero, tu identidad"
/ecommerce sin sesión     -> "Para continuar", y la URL no cambia
```

### El flujo OIDC

```
response_type=code   state=<nuevo en cada intento>
code_challenge_method=S256
redirect_uri=https://nexus.simuladorupbbga.app/auth/callback
```

El callback rechaza un `state` inventado con un mensaje distinto del que da un
código inválido: la validación es específica, no un «no» genérico.

## Lo que se descubrió usando el producto, y ninguna prueba encontró

Se registra porque es el argumento para cerrar historias con alguien delante:

1. **El alta devolvía al catálogo**, no al formulario que faltaba rellenar, y
   desde ahí no había forma de volver con la sesión viva.
2. **La cuenta nacía pendiente de una verificación que nadie resolvía.** El
   inicio de sesión por credenciales no podía funcionar para *ningún* usuario
   registrado por la vía normal.
3. **La pantalla del segundo factor decía «te enviamos un código por correo»** y
   no se enviaba ninguno. Las pruebas afirmaban que aparecía el título, no lo
   que decía el párrafo.
4. **`/register` estaba montado sin protección**, así que se rellenaba el
   formulario entero para recibir un 401.

## Lo que queda fuera de esta HU

- **OTP por correo activo**: depende de acceso a producción de SES y de
  teléfonos verificados para la recuperación. Arquitectura construida y probada.
- **HU-39**: conceder rol no tiene endpoint. La primera elevación se hizo con un
  bootstrap único y auditable, que debe retirarse cuando HU-39 exista.
- **Segundo factor obligatorio por pool** (`mfa_configuration = ON`): hoy es
  `OPTIONAL`, que según AWS solo reta a quien tenga factor inscrito. El control
  es `scripts/verificar-segundo-factor-administrativo.py`.
