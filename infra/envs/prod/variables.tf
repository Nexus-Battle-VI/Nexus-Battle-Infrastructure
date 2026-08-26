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
    private_ip    = string
  }))

  validation {
    condition     = contains(keys(var.nodes), "data")
    error_message = "El plano de aplicacion resuelve la direccion del nodo 'data' desde este mapa: sin el, no hay a donde apuntar."
  }
}

variable "db_password" {
  description = <<-DESC
    Contrasena de las bases de datos del nodo `data`.

    Vacia por defecto A PROPOSITO. La composicion de referencia usa la palabra
    literal `cambiar`, que sirve para desarrollo y no para una instancia real.
    Mientras no exista un origen de credenciales decidido, esto queda vacio y el
    stack no se arranca: ver `arrancar_stack`.
  DESC
  type        = string
  default     = ""
  sensitive   = true
}

variable "arrancar_stack" {
  description = "Si el arranque de cada nodo termina levantando su composicion."
  type        = bool
  default     = false

  validation {
    condition     = !var.arrancar_stack || length(var.db_password) >= 16
    error_message = "Para arrancar el stack hace falta una contrasena de al menos 16 caracteres. Con la de la composicion de referencia, el nodo quedaria con credenciales conocidas."
  }
}

variable "auth_mode" {
  description = "`disabled` mientras el BLOCKER de ADR-004 siga abierto; `jwt` cuando se cierre."
  type        = string
  default     = "disabled"

  validation {
    condition     = contains(["disabled", "jwt"], var.auth_mode)
    error_message = "auth_mode solo admite 'disabled' o 'jwt'."
  }
}

variable "compose_plugin_url" {
  description = "Complemento `compose`, con la version fijada. No esta en los repositorios de AL2023."
  type        = string
  default     = "https://github.com/docker/compose/releases/download/v5.5.0/docker-compose-linux-aarch64"
}

variable "compose_plugin_sha256" {
  description = "Huella publicada del binario anterior, verificada en el nodo antes de ejecutarlo."
  type        = string
  default     = "ff42489f5a9b879d5d117c5ffea6defc27390b3286da8ad52cbc9c6ab5df590e"
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
