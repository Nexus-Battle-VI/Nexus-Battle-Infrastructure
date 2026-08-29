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

variable "mfa_method" {
  description = <<-DESC
    Segundo factor del pool: "software_token" o "email".

    Por defecto es la aplicacion autenticadora, y no por preferencia de estilo:
    el MFA por correo EXIGE SES. Cognito rechaza configurarlo mientras el pool
    use su emisor por defecto.

    Poner "email" sin `ses_identity_arn` hace fallar el plan, no el apply: hay
    una precondicion que lo comprueba y explica por que.
  DESC
  type        = string
  default     = "software_token"

  validation {
    condition     = contains(["software_token", "email"], var.mfa_method)
    error_message = "mfa_method debe ser \"software_token\" o \"email\"."
  }
}
