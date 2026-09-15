variable "environment" {
  description = "Entorno de despliegue. Forma parte del nombre de la cola, igual que en el AsyncAPI (`catalog-events-v1.asyncapi.yaml`)."
  type        = string

  validation {
    condition     = contains(["dev", "test", "prod"], var.environment)
    error_message = "environment debe ser 'dev', 'test' o 'prod', igual que el enum del contrato AsyncAPI."
  }
}

variable "tags" {
  description = "Etiquetas comunes del proyecto."
  type        = map(string)
}

variable "max_receive_count" {
  description = "Intentos antes de mover el mensaje a la DLQ (5 por ADR-017)."
  type        = number
  default     = 5
}

variable "max_age_oldest_message_alarm_seconds" {
  description = <<-DESC
    Umbral, en segundos, para la alarma de `ApproximateAgeOfOldestMessage` de
    la cola principal. 600 s (10 minutos) es diez veces el visibility timeout
    de 60 s de ADR-017: un mensaje mas viejo que eso ya fallo varios intentos
    de entrega o no tiene consumidor activo.
  DESC
  type        = number
  default     = 600
}

variable "alarm_actions" {
  description = "ARNs de acciones de notificacion CloudWatch (SNS), opcional. Vacio por defecto: no existe todavia un topico SNS en este proyecto."
  type        = list(string)
  default     = []
}
