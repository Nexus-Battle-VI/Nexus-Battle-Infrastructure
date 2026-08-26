output "user_pool_id" {
  value = aws_cognito_user_pool.this.id
}

output "client_id" {
  description = "Identificador del cliente publico. No es un secreto: viaja en la URL de inicio de sesion."
  value       = aws_cognito_user_pool_client.web.id
}

output "issuer" {
  description = "Valor esperado del claim `iss` al validar el JWT en cada servicio."
  value       = "https://cognito-idp.${data.aws_region.current.region}.amazonaws.com/${aws_cognito_user_pool.this.id}"
}

output "jwks_uri" {
  description = "Origen de las claves publicas. Cada servicio valida la firma contra esto, nunca contra una clave copiada."
  value       = "https://cognito-idp.${data.aws_region.current.region}.amazonaws.com/${aws_cognito_user_pool.this.id}/.well-known/jwks.json"
}

output "hosted_ui_domain" {
  value = "https://${aws_cognito_user_pool_domain.this.domain}.auth.${data.aws_region.current.region}.amazoncognito.com"
}

data "aws_region" "current" {}
