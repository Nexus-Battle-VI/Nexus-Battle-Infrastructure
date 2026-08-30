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

  /**
   * `minimum_length = 9`, no 12.
   *
   * HU-01 (CA-03) exige contrasena de "mas de ocho caracteres": nueve es la
   * primera longitud que lo cumple. Doce no tiene ninguna aclaracion formal del
   * cliente ni del profesor que lo autorice (auditado contra el backlog de
   * Management al preparar esta rama) — era una politica mas estricta que la
   * HU sin decision que la respalde, y este ADR no debe inventarla. No es
   * `ForceNew`: se aplica sobre el pool existente sin reemplazarlo.
   */
  password_policy {
    minimum_length                   = 9
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
    for_each = contains(var.mfa_methods, "software_token") ? [1] : []

    content {
      enabled = true
    }
  }

  dynamic "email_mfa_configuration" {
    for_each = contains(var.mfa_methods, "email") ? [1] : []

    content {
      message = "Tu codigo de verificacion de Nexus Battles VI es {####}"
      subject = "Codigo de verificacion - Nexus Battles VI"
    }
  }

  /**
   * Recuperacion por correo verificado, y la razon de que ANTES no lo fuera.
   *
   * Este bloque decia `admin_only`, con este argumento: si el correo es a la vez
   * el segundo factor y el unico modo de recuperar la cuenta, el circulo se
   * cierra sobre si mismo, porque quien tenga el correo puede saltarse el MFA
   * pidiendo una recuperacion.
   *
   * El argumento era correcto **mientras el segundo factor fuera el correo**. La
   * decision de producto del 2026-08-29 es TOTP, y con TOTP el circulo no se
   * cierra: recuperar la contrasena por correo no entrega el autenticador, y
   * Cognito sigue exigiendo `SOFTWARE_TOKEN_MFA` en el inicio de sesion
   * siguiente. La premisa caduco con la decision.
   *
   * Lo que `admin_only` producia en la practica, comprobado sobre el sistema
   * desplegado: la pantalla alojada **no muestra** el enlace de recuperacion, y
   * la ruta `/forgotPassword` escrita a mano responde "Could not reset password
   * for the account". Es decir, cualquier jugador que olvide su contrasena queda
   * fuera sin ninguna via de vuelta. Se descubrio del unico modo en que estas
   * cosas se descubren: olvidando una contrasena de verdad.
   *
   * El pretexto de que "queda dicho en lugar de aparentar que lo hay" no se
   * sostenia: no habia nada que lo dijera. Solo un boton ausente y un error
   * generico.
   *
   * Contrapartida que se acepta a proposito: para una cuenta SIN segundo factor
   * -hoy, todas- quien controle el correo puede tomarla. Es la misma exposicion
   * que asume cualquier producto con recuperacion por correo, y es preferible a
   * que nadie pueda recuperar nada. Para las cuentas administrativas la
   * exposicion NO existe: se les exige TOTP inscrito antes de elevarlas.
   */
  account_recovery_setting {
    recovery_mechanism {
      name     = var.account_recovery
      priority = 1
    }
  }

  /**
   * SMS, solo si se aporta el rol. Es lo que habilita la recuperacion por
   * telefono, que es la unica que Cognito admite junto al MFA por correo.
   *
   * Se declara aparte de `mfa_methods` a proposito: recuperar una cuenta NO es
   * autenticarse, y mezclarlos es justo lo que cierra el circulo.
   */
  dynamic "sms_configuration" {
    for_each = var.sms_role_arn == "" ? [] : [1]

    content {
      external_id    = var.sms_external_id
      sns_caller_arn = var.sms_role_arn
    }
  }

  /**
   * Emisor de correo: el de Cognito, o SES si se aporta una identidad.
   *
   * El emisor por defecto no cuesta nada y basta para verificar cuentas, pero
   * **no admite MFA por correo**: Cognito rechaza `email_mfa_configuration`
   * mientras `EmailSendingAccount` sea `COGNITO_DEFAULT`. Por eso las dos cosas
   * van juntas y no por separado.
   *
   * Con `DEVELOPER`, Cognito crea por su cuenta un rol vinculado al servicio
   * para llamar a SES; no hace falta una politica de autorizacion de envio en
   * la identidad, porque esta en la misma cuenta y en la misma region. Lo que
   * si necesita quien aplica es `iam:CreateServiceLinkedRole`.
   *
   * Como la identidad verificada es una direccion y no un dominio, Cognito la
   * usa tambien como REPLY-TO. Se declara `from_email_address` de forma
   * explicita igualmente: que el remitente sea legible en el correo no deberia
   * depender de un valor por defecto.
   */
  email_configuration {
    email_sending_account = var.ses_identity_arn == "" ? "COGNITO_DEFAULT" : "DEVELOPER"
    source_arn            = var.ses_identity_arn == "" ? null : var.ses_identity_arn
    from_email_address    = var.ses_identity_arn == "" ? null : var.from_email_address
  }

  /**
   * Falla en el PLAN y no en el apply.
   *
   * Sin esto, `mfa_method = "email"` con el emisor por defecto llega hasta AWS
   * y vuelve como `InvalidParameterException`, con un mensaje que describe el
   * sintoma y no la causa. Aqui se dice la causa antes de tocar nada.
   */
  lifecycle {
    precondition {
      condition     = !contains(var.mfa_methods, "email") || var.ses_identity_arn != ""
      error_message = "mfa_methods con \"email\" exige ses_identity_arn: el emisor por defecto de Cognito no admite MFA por correo."
    }

    /**
     * El circulo que no debe cerrarse.
     *
     * Si el correo es a la vez el segundo factor y la via de recuperacion,
     * quien tenga el correo se salta el segundo factor pidiendo una
     * recuperacion, y el factor deja de serlo. Cognito rechaza la combinacion,
     * pero lo hace DURANTE el apply y con un mensaje que describe el sintoma.
     * Aqui se dice la causa antes de tocar nada.
     */
    precondition {
      condition     = !contains(var.mfa_methods, "email") || var.account_recovery != "verified_email"
      error_message = "El correo no puede ser a la vez segundo factor y via de recuperacion: quien tenga el correo se saltaria el factor pidiendo una recuperacion. Usa account_recovery = \"verified_phone_number\" (exige sms_role_arn) o retira \"email\" de mfa_methods."
    }

    /**
     * Recuperacion por telefono sin SMS configurado deja a TODO EL MUNDO fuera,
     * y en silencio: la pantalla alojada no muestra el enlace y no hay error que
     * lo explique. Este proyecto ya lo vivio con `admin_only`.
     */
    precondition {
      condition     = var.account_recovery != "verified_phone_number" || var.sms_role_arn != ""
      error_message = "account_recovery = \"verified_phone_number\" exige sms_role_arn: sin SMS configurado no hay recuperacion posible, y no lo dice ningun error."
    }

    /**
     * Quedarse sin ningun factor no es una configuracion valida: el pool esta
     * en OPTIONAL y sin factores nadie podria inscribir ninguno.
     */
    precondition {
      condition     = length(var.mfa_methods) > 0
      error_message = "mfa_methods no puede estar vacio: sin factores declarados nadie puede inscribir uno."
    }
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
    # Unico Super Administrador raiz del sistema (HU-02). Este bloque SOLO crea
    # el grupo de Cognito: no crea la cuenta, no le asigna contrasena, no
    # aprovisiona ningun usuario y no asigna el rol a nadie. Eso es HU-39.
    SUPER_ADMINISTRATOR = { precedence = 0, description = "Rol raiz unico, gestion total del sistema" }
    ADMINISTRATOR       = { precedence = 1, description = "Gestiona catalogo y roles" }
    MODERATOR           = { precedence = 2, description = "Modera hilos y mensajes" }
    PLAYER              = { precedence = 3, description = "Rol base, no puede retirarse" }
  }

  name         = each.key
  user_pool_id = aws_cognito_user_pool.this.id
  description  = each.value.description
  precedence   = each.value.precedence
}

# ---------------------------------------------------------------------------
# Cliente de aplicacion — Web y, con IAM de por medio, Account.
#
# PUBLICO: sin secreto de cliente. Un secreto embebido en el navegador no es un
# secreto, y Cognito exigiria un SECRET_HASH que el navegador no puede proteger.
# El flujo de Web es codigo de autorizacion con PKCE.
#
# Sigue siendo UN SOLO cliente y no dos, a proposito: los cuatro servicios de
# dominio (Catalog, Commerce, Community, Player-Inventory) verifican el
# `client_id` del token contra un UNICO valor de `COGNITO_CLIENT_ID` compartido
# (PR #13) — ninguno acepta una lista. Provisionar un segundo cliente para
# Account emitiria tokens que esos cuatro servicios rechazarian con 401 sin
# tocar su codigo, que esta fuera del alcance de este repositorio. Aislar el
# flujo de Account de verdad exige que los cinco servicios acepten varios
# `client_id` validos — trabajo futuro de varios repositorios, no de este PR.
#
# Lo que SI separa el flujo de Account del de Web no es un cliente distinto,
# es IAM: `ALLOW_ADMIN_USER_PASSWORD_AUTH` (mas abajo) solo lo puede invocar
# quien tenga el permiso `cognito-idp:AdminInitiateAuth`/
# `AdminRespondToAuthChallenge` firmado con credenciales de AWS validas — ver
# el rol de instancia en el modulo `compute`. El `client_id` de este cliente es
# publico (viaja en el bundle de Web), pero de nada le sirve a quien no tenga
# esas credenciales: no puede invocar el flujo de administrador solo con el
# `client_id`, a diferencia de `ALLOW_USER_PASSWORD_AUTH`, que este modulo
# deliberadamente NO habilita aqui por esa misma razon.
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
   * `ALLOW_USER_SRP_AUTH`: Web, desde el navegador.
   *
   * `ALLOW_ADMIN_USER_PASSWORD_AUTH`: Account, server-side, para
   * `AdminInitiateAuth`/`AdminRespondToAuthChallenge` (HU-02). Deliberadamente
   * NO es `ALLOW_USER_PASSWORD_AUTH`: esa variante no exige IAM, solo el
   * `client_id`, que es publico porque viaja en el bundle de Web — habilitarla
   * abriria un camino directo a Cognito que se salta por completo el guard
   * aplicativo de Account (CA-06: Administrator/SuperAdministrator no pueden
   * autenticar sin el segundo factor). La variante Admin exige ademas una
   * peticion firmada con credenciales de AWS con el permiso
   * `cognito-idp:AdminInitiateAuth` sobre este pool -ver el rol de instancia en
   * el modulo `compute`-, que nadie fuera de la infraestructura del proyecto
   * tiene. El `client_id` publico deja de ser suficiente por si solo.
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
  explicit_auth_flows = ["ALLOW_USER_SRP_AUTH", "ALLOW_ADMIN_USER_PASSWORD_AUTH"]

  prevent_user_existence_errors = "ENABLED"
}

resource "aws_cognito_user_pool_domain" "this" {
  domain       = var.name
  user_pool_id = aws_cognito_user_pool.this.id
}
