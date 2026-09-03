variable "user_name" {
  description = "Usuario con el que se opera a diario, en lugar de root."
  type        = string
  default     = "nexus-battles-operador"
}

variable "group_name" {
  description = "Grupo que lleva los permisos. Las politicas se atan al grupo y no al usuario, para que anadir a alguien no obligue a repetirlas."
  type        = string
  default     = "nexus-battles-operadores"
}

variable "tfstate_bucket" {
  description = <<-DESC
    Bucket del estado de Terraform. Es la unica excepcion a la prohibicion de S3
    que preve ADR-007, habilitada por ADR-008 al pasar a Accepted.

    Se nombra aqui aunque el bucket todavia no exista: la politica lo permite por
    adelantado para que crearlo no requiera tocar los permisos.
  DESC
  type        = string
  default     = "nexus-battles-vi-tfstate"
}

variable "allowed_instance_types" {
  description = <<-DESC
    Tipos de instancia que se pueden lanzar.

    El presupuesto avisa DESPUES de gastar; esto impide antes. La lista llega
    hasta `t4g.medium` porque es lo que ADR-011 dimensiono; ampliarla es editar
    esta variable, que es una decision visible en un PR.
  DESC
  type        = list(string)
  default     = ["t4g.nano", "t4g.micro", "t4g.small", "t4g.medium"]
}

variable "product_assets_bucket" {
  description = <<-DESC
    Bucket de recursos visuales de Producto (ADR-016 / EN-027.9).
    Excepción acotada de ADR-007 habilitada para almacenar activos dinámicos de catálogo.
  DESC
  type        = string
  default     = null
}
