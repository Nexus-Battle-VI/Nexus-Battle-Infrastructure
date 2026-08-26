output "user_name" {
  description = "Usuario creado. La clave de acceso NO se genera aqui: la creaia Terraform en texto plano dentro del fichero de estado."
  value       = aws_iam_user.operator.name
}

output "user_arn" {
  value = aws_iam_user.operator.arn
}

output "group_name" {
  value = aws_iam_group.operators.name
}

output "servicios_denegados" {
  description = "Lo que la politica impide de verdad, no lo que un documento pide que no se haga."
  value = [
    "Lambda", "DynamoDB", "CloudFront", "ECS y Fargate", "EKS",
    "RDS y DocumentDB", "ElastiCache", "Directory Service", "ALB y NLB",
    "NAT Gateway", "S3 fuera del bucket de estado",
    "Instancias fuera de ${join(", ", var.allowed_instance_types)}",
  ]
}
