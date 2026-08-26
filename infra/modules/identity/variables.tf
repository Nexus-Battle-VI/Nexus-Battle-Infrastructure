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
