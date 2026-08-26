variable "region" {
  type    = string
  default = "us-east-1"
}

variable "profile" {
  type    = string
  default = "nexus-battles"
}

variable "availability_zone" {
  type    = string
  default = "us-east-1a"
}

variable "account_id" {
  type = string
}

variable "alert_email" {
  type = string
}

variable "nodes" {
  type = map(object({
    instance_type = string
    role          = string
    volume_gb     = number
  }))
}

variable "public_ingress_cidrs" {
  description = "Vacio mientras el BLOCKER de ADR-004 siga abierto."
  type        = list(string)
  default     = []
}

variable "activate_cost_allocation_tags" {
  description = <<-DESC
    Activa el desglose de coste por etiqueta en Cost Explorer.

    Falso en la primera aplicacion: AWS necesita ver la etiqueta en un recurso
    real antes de permitir activarla, y tarda hasta 24 h en exponerla. Se pone a
    cierto en una segunda aplicacion al dia siguiente.
  DESC
  type        = bool
  default     = false
}

variable "allowed_instance_types" {
  description = <<-DESC
    Tipos de instancia que la politica de IAM permite lanzar.

    El presupuesto avisa DESPUES de gastar; esto impide antes. Debe incluir todo
    lo que aparezca en `nodes`, o el `apply` fallara al lanzar la instancia — que
    es exactamente el comportamiento buscado.
  DESC
  type        = list(string)
  default     = ["t4g.nano", "t4g.micro", "t4g.small", "t4g.medium"]
}
