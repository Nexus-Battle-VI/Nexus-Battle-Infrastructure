# ---------------------------------------------------------------------------
# Proveedor de identidad — Amazon Cognito, plan Essentials (ADR-004).
#
# Essentials y no Lite porque el requisito contempla segundo factor por correo,
# que Lite no incluye. Suplirlo por cuenta propia obligaria a custodiar secretos
# de segundo factor, que es justo lo que ADR-004 prohibe.
# ---------------------------------------------------------------------------

resource "aws_cognito_user_pool" "this" {
  name = var.name

  user_pool_tier = "ESSENTIALS"

  # El correo es el identificador de inicio de sesion, pero NO es el
  # identificador del sujeto: ese es el `sub`, que es estable. Un correo cambia.
  username_attributes      = ["email"]
  auto_verified_attributes = ["email"]

  password_policy {
    minimum_length                   = 12
    require_lowercase                = true
    require_uppercase                = true
    require_numbers                  = true
    require_symbols                  = true
    temporary_password_validity_days = 3
  }

  # OPTIONAL y no ON de forma deliberada: forzar el segundo factor antes de que
  # exista pantalla de inscripcion dejaria a todo el mundo fuera. Pasa a ON
  # cuando Web implemente el flujo.
  mfa_configuration = "OPTIONAL"

  email_mfa_configuration {
    message = "Tu codigo de verificacion de Nexus Battles VI es {####}"
    subject = "Codigo de verificacion - Nexus Battles VI"
  }

  account_recovery_setting {
    recovery_mechanism {
      name     = "verified_email"
      priority = 1
    }
  }

  # Correo por defecto de Cognito: sin coste y sin dominio verificado. Tiene un
  # limite diario bajo, suficiente para la demo. SES exige verificacion de
  # dominio y salida del sandbox, y no esta aprobado.
  email_configuration {
    email_sending_account = "COGNITO_DEFAULT"
  }

  deletion_protection = "ACTIVE"

  tags = var.tags
}

# ---------------------------------------------------------------------------
# Grupos = los roles que el dominio de Account ya modela.
#
# La fuente de verdad de los roles sigue siendo Account: aqui solo se refleja
# la pertenencia para que viaje en el testimonio. `precedence` menor gana.
# ---------------------------------------------------------------------------
resource "aws_cognito_user_group" "roles" {
  for_each = {
    ADMINISTRATOR = { precedence = 1, description = "Gestiona catalogo y roles" }
    MODERATOR     = { precedence = 2, description = "Modera hilos y mensajes" }
    PLAYER        = { precedence = 3, description = "Rol base, no puede retirarse" }
  }

  name         = each.key
  user_pool_id = aws_cognito_user_pool.this.id
  description  = each.value.description
  precedence   = each.value.precedence
}

# ---------------------------------------------------------------------------
# Cliente de aplicacion para Web.
#
# PUBLICO: sin secreto de cliente. Un secreto embebido en el navegador no es un
# secreto, y Cognito exigiria un SECRET_HASH que el navegador no puede proteger.
# El flujo es codigo de autorizacion con PKCE.
# ---------------------------------------------------------------------------
resource "aws_cognito_user_pool_client" "web" {
  name         = "${var.name}-web"
  user_pool_id = aws_cognito_user_pool.this.id

  generate_secret = false

  allowed_oauth_flows                  = ["code"]
  allowed_oauth_flows_user_pool_client = true
  allowed_oauth_scopes                 = ["openid", "email", "profile"]

  callback_urls = var.callback_urls
  logout_urls   = var.logout_urls

  supported_identity_providers = ["COGNITO"]

  # El de acceso caduca pronto porque es el que viaja en cada peticion. La
  # rotacion del de refresco impide reutilizar uno robado mas de una vez.
  access_token_validity  = 15
  id_token_validity      = 15
  refresh_token_validity = 1

  token_validity_units {
    access_token  = "minutes"
    id_token      = "minutes"
    refresh_token = "days"
  }

  enable_token_revocation = true

  refresh_token_rotation {
    feature = "ENABLED"
  }

  # Solo los flujos que Web necesita. Los de contrasena directa quedan fuera:
  # obligarian al frontend a manejar credenciales en lugar de delegarlas.
  explicit_auth_flows = ["ALLOW_REFRESH_TOKEN_AUTH", "ALLOW_USER_SRP_AUTH"]

  prevent_user_existence_errors = "ENABLED"
}

resource "aws_cognito_user_pool_domain" "this" {
  domain       = var.name
  user_pool_id = aws_cognito_user_pool.this.id
}
