output "vpc_id" {
  value = aws_vpc.this.id
}

output "subnet_id" {
  value = aws_subnet.public.id
}

output "security_group_ids" {
  description = "Grupo de seguridad por rol de nodo."
  value = {
    app  = aws_security_group.app.id
    data = aws_security_group.data.id
  }
}

output "public_ingress_open" {
  description = "Falso mientras no haya ningun origen autorizado. Sirve de comprobacion explicita del BLOCKER de ADR-004."
  value       = length(var.public_ingress_cidrs) > 0
}
