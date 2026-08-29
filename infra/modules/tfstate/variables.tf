variable "bucket" {
  description = <<-DESC
    Nombre del bucket del estado.

    El valor por defecto coincide con el que la politica de denegacion de
    `modules/iam` ya permite por nombre: alli se escribio por adelantado
    precisamente para que crear este bucket no exigiera tocar los permisos.
    Cambiarlo aqui obliga a cambiarlo tambien alli.
  DESC
  type        = string
  default     = "nexus-battles-vi-tfstate"
}

variable "dias_de_retencion_de_versiones" {
  description = <<-DESC
    Cuanto se conservan las versiones antiguas del estado.

    El versionado es lo que permite volver atras tras una escritura mala, pero
    sin caducidad crece para siempre. El estado ocupa unos 75 KB, asi que el
    coste es despreciable en cualquier caso; el limite existe por higiene, no
    por dinero.
  DESC
  type        = number
  default     = 90
}

variable "tags" {
  type = map(string)
}
