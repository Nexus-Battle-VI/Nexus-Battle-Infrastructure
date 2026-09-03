variable "bucket_name" {
  description = "Nombre único del bucket S3 para recursos visuales de Producto."
  type        = string
}

variable "tags" {
  description = "Etiquetas comunes del proyecto."
  type        = map(string)
}

variable "noncurrent_version_retention_days" {
  description = "Días de retención de versiones no vigentes en S3 (30 días por ADR-016)."
  type        = number
  default     = 30
}

variable "staging_retention_days" {
  description = "Días de caducidad automática de objetos temporales en staging/ (1 día por ADR-016)."
  type        = number
  default     = 1
}

variable "max_storage_bytes_alarm" {
  description = "Umbral en bytes para la alarma de almacenamiento (5 GB por defecto según ADR-016)."
  type        = number
  default     = 5368709120 # 5 GiB
}

variable "max_download_bytes_alarm" {
  description = "Umbral en bytes diarios/mensuales para la alarma de salida (50 GB por defecto según ADR-016)."
  type        = number
  default     = 53687091200 # 50 GiB
}

variable "alarm_actions" {
  description = "ARNs de acciones de notificación CloudWatch SNS (opcional)."
  type        = list(string)
  default     = []
}
