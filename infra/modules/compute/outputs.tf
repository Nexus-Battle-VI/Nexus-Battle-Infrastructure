output "nodes" {
  description = "Direcciones de cada nodo. La privada es la que usan los servicios entre si."
  value = {
    for k, i in aws_instance.node : k => {
      id         = i.id
      private_ip = i.private_ip
      # Con IP elastica, `i.public_ip` puede quedarse con la automatica en el
      # estado hasta el siguiente refresco. Se prefiere la elastica cuando
      # existe: es la que hay que poner en el DNS.
      public_ip = k == "app" && var.stable_public_ip ? aws_eip.app[0].public_ip : i.public_ip
      role      = i.tags["Role"]
    }
  }
}

output "monthly_public_ipv4_usd" {
  description = "Coste mensual de las IP publicas de esta topologia, a 0,005 USD/h. Se paga con la instancia encendida o apagada."
  value       = ceil(length(keys(var.nodes)) * 0.005 * 730 * 100) / 100
}

output "app_public_ip" {
  description = "Direccion a la que debe apuntar el registro A del sitio publico. Estable solo si `stable_public_ip` es cierto."
  value       = var.stable_public_ip ? aws_eip.app[0].public_ip : aws_instance.node["app"].public_ip
}
