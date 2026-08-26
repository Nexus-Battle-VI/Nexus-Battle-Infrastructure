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

  /**
   * El segundo factor: aplicacion autenticadora, NO correo.
   *
   * ADR-004 eligio Cognito Essentials contando con el MFA por correo. Al
   * provisionarlo, Cognito lo rechaza:
   *
   *   Cannot set EmailMfaConfiguration when user pool EmailConfiguration
   *   contains an EmailSendingAccount of COGNITO_DEFAULT.
   *
   * Es decir: **el MFA por correo exige SES**. El emisor por defecto de Cognito
   * no sirve para eso, y SES pide una identidad verificada y salir del entorno
   * de pruebas antes de escribir a cualquiera.
   *
   * El codigo temporal de aplicacion no necesita nada de eso, no cuesta nada y
   * es mas fuerte: un codigo por correo lo intercepta quien tenga el correo, que
   * en esta configuracion es justo el canal que se querria proteger.
   *
   * Cambiarlo a correo es poner `email` en `mfa_method` y aprovisionar SES.
   * ADR-004 tiene que registrar esta correccion.
   */
  dynamic "software_token_mfa_configuration" {
    for_each = var.mfa_method == "software_token" ? [1] : []

    content {
      enabled = true
    }
  }

  dynamic "email_mfa_configuration" {
    for_each = var.mfa_method == "email" ? [1] : []

    content {
      message = "Tu codigo de verificacion de Nexus Battles VI es {####}"
      subject = "Codigo de verificacion - Nexus Battles VI"
    }
  }

  /**
   * Recuperacion por administrador, y NO por correo verificado.
   *
   * Cognito rechaza la combinacion "MFA por correo + recuperacion solo por
   * correo verificado", y el rechazo es legitimo: si el correo es a la vez el
   * segundo factor y el unico modo de recuperar la cuenta, el circulo se cierra
   * sobre si mismo. Quien tenga acceso al correo puede saltarse el MFA pidiendo
   * una recuperacion, de modo que el segundo factor deja de ser un segundo
   * factor.
   *
   * La alternativa que AWS admite es un mecanismo por telefono, y eso exige SMS:
   * un rol para SNS, salida del entorno de pruebas y coste por mensaje. Con el
   * techo de este proyecto no compensa para una demo.
   *
   * `admin_only` no se puede combinar con otros mecanismos, y esa es
   * precisamente la propiedad util aqui: no hay autoservicio de recuperacion, y
   * eso queda dicho en lugar de aparentar que lo hay.
   */
  account_recovery_setting {
    recovery_mechanism {
      name     = "admin_only"
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

    # Explicito aunque cero sea el valor por defecto del servidor: omitirlo hace
    # que el proveedor devuelva "inconsistent result after apply", porque en la
    # configuracion es nulo y AWS lo materializa como 0.
    #
    # Cero significa que el token anterior deja de valer en cuanto se canjea,
    # sin ventana de gracia. Es lo estricto, y es lo que se quiere: la ventana
    # existe para clientes que reintentan en paralelo, y aqui no los hay.
    retry_grace_period_seconds = 0
  }

  /**
   * Solo los flujos que Web necesita. Los de contrasena directa quedan fuera:
   * obligarian al frontend a manejar credenciales en lugar de delegarlas.
   *
   * `ALLOW_REFRESH_TOKEN_AUTH` NO aparece, y no es un olvido: Cognito rechaza
   * la creacion del cliente si se declara junto con la rotacion del token de
   * refresco.
   *
   *   ALLOW_REFRESH_TOKEN_AUTH is not a permitted ExplicitAuthFlow
   *   when refresh token rotation is enabled.
   *
   * Tiene sentido. Con rotacion, el canje de un token de refresco deja de ser un
   * flujo que el cliente pueda invocar a voluntad y pasa a estar gobernado por
   * la propia rotacion: cada canje invalida el anterior. Declararlo como flujo
   * explicito describiria un comportamiento que ya no existe.
   */
  explicit_auth_flows = ["ALLOW_USER_SRP_AUTH"]

  prevent_user_existence_errors = "ENABLED"
}

resource "aws_cognito_user_pool_domain" "this" {
  domain       = var.name
  user_pool_id = aws_cognito_user_pool.this.id
}
