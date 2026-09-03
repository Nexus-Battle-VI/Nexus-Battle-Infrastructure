output "nodes" {
  value = module.compute.nodes
}

output "cognito_issuer" {
  value = module.identity.issuer
}

output "cognito_jwks_uri" {
  value = module.identity.jwks_uri
}

output "cognito_client_id" {
  value = module.identity.client_id
}

output "hosted_ui_domain" {
  value = module.identity.hosted_ui_domain
}

output "expuesto_a_internet" {
  description = "Debe ser falso mientras el BLOCKER de ADR-004 siga abierto."
  value       = module.network.public_ingress_open
}

output "coste_mensual_ipv4_usd" {
  value = module.compute.monthly_public_ipv4_usd
}

output "identidad_de_operacion" {
  description = "Usuario con el que operar en lugar de root. La clave de acceso NO la crea Terraform: la guardaria en texto plano en el fichero de estado."
  value       = module.iam.user_name
}

output "limites_aplicados_por_iam" {
  description = "Lo que la politica impide de verdad, no lo que un documento pide que no se haga."
  value       = module.iam.servicios_denegados
}

output "registro_dns_necesario" {
  description = "Que registro DNS hay que crear para que el sitio publico funcione. Vacio si no hay sitio publico configurado."
  value = var.public_site_address == "" ? "Sin sitio publico: no hace falta ningun registro DNS." : format(
    "Crear un registro A: %s -> %s",
    var.public_site_address,
    module.compute.app_public_ip,
  )
}

output "product_assets_bucket_id" {
  description = "Identificador y nombre del bucket S3 de assets de producto."
  value       = module.product_assets.bucket_id
}

output "product_assets_bucket_arn" {
  description = "ARN del bucket S3 de assets de producto."
  value       = module.product_assets.bucket_arn
}
