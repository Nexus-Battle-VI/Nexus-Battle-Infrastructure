variable "environment" {
  type = string
  validation {
    condition     = contains(["dev", "test", "prod"], var.environment)
    error_message = "environment debe ser 'dev', 'test' o 'prod'."
  }
}

variable "tags" { type = map(string) }
