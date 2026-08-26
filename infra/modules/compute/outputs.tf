output "nodes" {
  description = "Direcciones de cada nodo. La privada es la que usan los servicios entre si."
  value = {
    for k, i in aws_instance.node : k => {
      id         = i.id
      private_ip = i.private_ip
      public_ip  = i.public_ip
      role       = i.tags["Role"]
    }
  }
}

output "monthly_public_ipv4_usd" {
  description = "Coste mensual de las IP publicas de esta topologia, a 0,005 USD/h. Se paga con la instancia encendida o apagada."
  value       = ceil(length(keys(var.nodes)) * 0.005 * 730 * 100) / 100
}
