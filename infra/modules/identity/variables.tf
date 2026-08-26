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

variable "mfa_method" {
  description = <<-DESC
    Segundo factor del pool: "software_token" o "email".

    Por defecto es la aplicacion autenticadora, y no por preferencia de estilo:
    el MFA por correo EXIGE SES. Cognito rechaza configurarlo mientras el pool
    use su emisor por defecto, y SES pide identidad verificada y salir del
    entorno de pruebas.

    Poner "email" sin aprovisionar SES antes hace fallar el apply.
  DESC
  type        = string
  default     = "software_token"

  validation {
    condition     = contains(["software_token", "email"], var.mfa_method)
    error_message = "mfa_method debe ser \"software_token\" o \"email\"."
  }
}
