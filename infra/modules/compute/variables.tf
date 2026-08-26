variable "name" {
  type = string
}

variable "tags" {
  type = map(string)
}

variable "subnet_id" {
  type = string
}

variable "security_group_ids" {
  description = "Grupo de seguridad por rol de nodo, tal y como lo emite el modulo de red."
  type        = map(string)
}

variable "nodes" {
  description = <<-DESC
    Topologia de despliegue, como MAPA de nodos (ADR-011).

    Es una variable y no una constante a proposito: pasar de dos nodos a tres, o
    a uno por servicio, es editar este mapa y ejecutar `terraform plan`. La
    decision se revisa con un plan delante, no con una discusion.

    `role` selecciona el grupo de seguridad, y por tanto que puertos se abren.
  DESC
  type = map(object({
    instance_type = string
    role          = string
    volume_gb     = number
  }))

  validation {
    condition     = alltrue([for n in var.nodes : contains(["app", "data"], n.role)])
    error_message = "El rol de cada nodo debe ser 'app' o 'data'."
  }

  validation {
    condition     = alltrue([for n in var.nodes : startswith(n.instance_type, "t4g.")])
    error_message = "Solo se admiten instancias t4g (Graviton, arm64): las imagenes se construyen para linux/arm64."
  }
}
