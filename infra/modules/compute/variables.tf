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
    private_ip    = string
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

variable "bootstrap" {
  description = <<-DESC
    Que se escribe en cada nodo, POR ROL y no por nodo: dos nodos con el mismo
    rol reciben lo mismo, que es lo que hace que la topologia siga siendo una
    variable y no una lista de casos particulares.

    `compose`  contenido de `/opt/nexus/compose.yml`.
    `ficheros` nombre -> contenido, escritos junto al compose (guiones de
               inicializacion, Caddyfile).
    `entorno`  variables del `.env` que acompana al compose.
  DESC
  type = map(object({
    compose  = string
    ficheros = map(string)
    entorno  = map(string)
  }))
}

variable "arrancar_stack" {
  description = <<-DESC
    Si el arranque termina con `docker compose up -d`.

    `false` por defecto, y no como precaucion generica: mientras las
    credenciales de las bases sean las de la composicion de referencia —la
    palabra literal `cambiar`—, levantar el stack seria crear un sistema con
    contrasenas conocidas y llamarlo desplegado. El nodo queda preparado y el
    ultimo paso espera a que exista un origen real de credenciales.
  DESC
  type        = bool
  default     = false
}

variable "compose_plugin_url" {
  description = <<-DESC
    Complemento `compose` de Docker. Se descarga porque NO esta en los
    repositorios de AL2023: `dnf list --available` en el propio nodo devuelve
    `docker` pero no `docker-compose-plugin`.

    La version va FIJADA en la URL. Con `latest`, cada recreacion de un nodo
    seria una actualizacion que nadie decidio.
  DESC
  type        = string
}

variable "compose_plugin_sha256" {
  description = <<-DESC
    Huella publicada del binario anterior, verificada en el nodo ANTES de darle
    permiso de ejecucion. Sin esta comprobacion, el nodo ejecuta como root lo
    que le haya devuelto la red.
  DESC
  type        = string
}

variable "cognito_user_pool_arn" {
  description = <<-DESC
    ARN del user pool contra el que Account invoca AdminInitiateAuth /
    AdminRespondToAuthChallenge (HU-02). Acota la policy de IAM a este pool
    exacto, nunca a "*".
  DESC
  type        = string
}
