variable "name" {
  type = string
}

variable "tags" {
  type = map(string)
}

variable "callback_urls" {
  description = "URL de retorno autorizadas del cliente publico de Web."
  type        = list(string)
  default     = ["http://localhost:5173/auth/callback"]
}

variable "logout_urls" {
  type    = list(string)
  default = ["http://localhost:5173/"]
}

variable "ses_identity_arn" {
  description = <<-DESC
    ARN de una identidad de SES ya verificada, que el pool usara como remitente.

    Vacio significa emisor por defecto de Cognito, que NO admite MFA por correo:
    Cognito rechaza `email_mfa_configuration` mientras `EmailSendingAccount` sea
    `COGNITO_DEFAULT`. Es la razon por la que `mfa_method = "email"` exige
    tambien esta variable.

    La identidad debe estar verificada ANTES del apply. Este modulo no la crea a
    proposito: verificar una direccion exige que una persona abra un correo y
    pulse un enlace, y un recurso de Terraform que depende de eso se queda
    colgado sin decir por que.

    La region de la identidad debe ser la misma del pool.
  DESC
  type        = string
  default     = ""

  validation {
    condition     = var.ses_identity_arn == "" || can(regex("^arn:aws:ses:", var.ses_identity_arn))
    error_message = "ses_identity_arn debe ser un ARN de SES, o cadena vacia."
  }
}

variable "from_email_address" {
  description = <<-DESC
    Remitente que ve quien recibe el correo. Debe corresponder a la identidad
    verificada, o pertenecer a su dominio si la identidad es un dominio.

    Se ignora cuando `ses_identity_arn` esta vacio: el emisor por defecto de
    Cognito usa su propia direccion y no admite otra.
  DESC
  type        = string
  default     = ""
}

variable "mfa_methods" {
  description = <<-DESC
    Segundos factores que el pool ofrece. Uno, o los dos.

    Con los dos activos, Cognito reta con `SELECT_MFA_TYPE` y quien entra elige.
    Con uno solo, va directo a ese.

    `software_token` (aplicacion autenticadora) no cuesta nada y no depende de
    ningun servicio externo. `email` EXIGE SES: Cognito rechaza
    `email_mfa_configuration` mientras el pool use su emisor por defecto, y hay
    una precondicion que lo comprueba en el PLAN en lugar de dejarlo fallar a
    mitad del apply.

    LIMITE REAL DE ESTA CUENTA, que no se disimula: SES esta en su entorno de
    pruebas y la solicitud para salir fue DENEGADA (caso 178781013000904). El
    codigo por correo llegara SOLO a las direcciones ya verificadas en SES. Para
    cualquier otra persona no llegara, y Cognito no distingue ese caso de un
    correo que tarda. Por eso `email` no es el unico factor por defecto: dejar a
    alguien con un unico factor que no le llega es dejarlo fuera.
  DESC
  type        = set(string)
  default     = ["software_token"]

  validation {
    condition = length(var.mfa_methods) > 0 && length(
      setsubtract(var.mfa_methods, ["software_token", "email"])
    ) == 0
    error_message = "mfa_methods admite \"software_token\" y \"email\", y no puede estar vacio."
  }
}

variable "account_recovery" {
  description = <<-DESC
    Como se recupera una cuenta cuya contrasena se olvido.

    NO es un mecanismo de autenticacion y no debe mezclarse con `mfa_methods`.
    Se declara aparte justo para que la relacion entre ambos sea visible: si el
    correo es a la vez el segundo factor y la via de recuperacion, quien tenga
    el correo se salta el segundo factor pidiendo una recuperacion. Cognito
    rechaza esa combinacion, y aqui hay una precondicion que la detiene antes.

    - `verified_email`         autoservicio por correo. Incompatible con
                               `email` en `mfa_methods`.
    - `verified_phone_number`  autoservicio por SMS. Exige `sms_role_arn`.
    - `admin_only`             sin autoservicio. Comprobado en este proyecto: la
                               pantalla alojada deja de mostrar el enlace de
                               recuperacion y quien olvide su contrasena queda
                               fuera. No usar sin saberlo.
  DESC
  type        = string
  default     = "verified_email"

  validation {
    condition = contains(
      ["verified_email", "verified_phone_number", "admin_only"], var.account_recovery
    )
    error_message = "account_recovery debe ser verified_email, verified_phone_number o admin_only."
  }
}

variable "sms_role_arn" {
  description = <<-DESC
    Rol que Cognito asume para publicar SMS por SNS. Vacio deja el pool sin SMS.

    Necesario para `account_recovery = "verified_phone_number"`.

    Mismo limite que SES y por el mismo motivo: SNS tiene su propio entorno de
    pruebas para SMS, y ahi solo entrega a numeros verificados. Ademas el SMS se
    cobra por mensaje, asi que entra en el techo de USD 100 de ADR-007.
  DESC
  type        = string
  default     = ""
}

variable "sms_external_id" {
  description = "Identificador externo del rol de SMS. Evita el problema del diputado confuso."
  type        = string
  default     = ""
}
