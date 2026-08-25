variable "name" {
  description = "Prefijo de nombre para todos los recursos de red."
  type        = string
}

variable "tags" {
  description = "Etiquetas comunes para imputacion de coste."
  type        = map(string)
}

variable "vpc_cidr" {
  description = "Rango de la VPC."
  type        = string
  default     = "10.42.0.0/16"
}

variable "public_subnet_cidr" {
  description = "Rango de la subred publica."
  type        = string
  default     = "10.42.1.0/24"
}

variable "availability_zone" {
  description = "Zona de disponibilidad. Una sola: la demo no es multi-AZ y no finge serlo."
  type        = string
}

variable "public_ingress_cidrs" {
  description = <<-DESC
    Origenes autorizados a alcanzar los puertos publicos del nodo de aplicacion.

    Por defecto VACIO, y es deliberado: el BLOCKER de ADR-004 impide exponer el
    sistema a internet mientras ningun servicio verifique quien realiza la
    peticion. Abrir esto a 0.0.0.0/0 antes de resolver el blocker publica un
    sistema donde cualquiera puede confirmar pedidos a nombre de otra persona.
  DESC
  type        = list(string)
  default     = []
}
