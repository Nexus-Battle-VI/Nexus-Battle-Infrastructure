variable "region" {
  type    = string
  default = "us-east-1"
}

variable "profile" {
  type    = string
  default = "nexus-battles"
}

variable "availability_zone" {
  type    = string
  default = "us-east-1a"
}

variable "account_id" {
  type = string
}

variable "alert_email" {
  type = string
}

variable "nodes" {
  type = map(object({
    instance_type = string
    role          = string
    volume_gb     = number
    private_ip    = string
  }))

  validation {
    condition     = contains(keys(var.nodes), "data")
    error_message = "El plano de aplicacion resuelve la direccion del nodo 'data' desde este mapa: sin el, no hay a donde apuntar."
  }
}

variable "db_password" {
  description = <<-DESC
    Contrasena de las bases de datos del nodo `data`.

    Vacia por defecto A PROPOSITO. La composicion de referencia usa la palabra
    literal `cambiar`, que sirve para desarrollo y no para una instancia real.
    Mientras no exista un origen de credenciales decidido, esto queda vacio y el
    stack no se arranca: ver `arrancar_stack`.
  DESC
  type        = string
  default     = ""
  sensitive   = true
}

variable "internal_service_auth_secret" {
  description = <<-DESC
    Secreto compartido del contrato interno entre servicios.

    Lo usan Account y Catalog para firmar y verificar las consultas de evidencia
    de segundo factor con HMAC-SHA256. Ambos deben recibir EL MISMO valor: si
    difieren, Catalog no podra comprobar la evidencia y las mutaciones
    administrativas fallaran CERRADAS con 503, que es el comportamiento correcto
    pero deja el catalogo inadministrable.

    Vacio por defecto, igual que `db_password`. Con el vacio, el contrato interno
    de Account responde 503 y Catalog rechaza las mutaciones administrativas: un
    despliegue incompleto NO deja el endpoint interno abierto.

    PENDIENTE OPERACIONAL, y conviene no perderlo de vista: este valor sigue el
    mismo camino que `db_password` -entra en `user_data`, que el estado de
    Terraform guarda entero y sin cifrar-. Es la limitacion ya aceptada para la
    contrasena de las bases, no una nueva, pero aqui vuelve a aplicar. Un origen
    de credenciales en tiempo de ejecucion la resolveria para las dos; mientras
    no exista, este secreto hereda esa exposicion.
  DESC
  type        = string
  default     = ""
  sensitive   = true
}

variable "arrancar_stack" {
  description = "Si el arranque de cada nodo termina levantando su composicion."
  type        = bool
  default     = false

  validation {
    condition     = !var.arrancar_stack || length(var.db_password) >= 16
    error_message = "Para arrancar el stack hace falta una contrasena de al menos 16 caracteres. Con la de la composicion de referencia, el nodo quedaria con credenciales conocidas."
  }
}

variable "auth_mode" {
  description = "`disabled` mientras el BLOCKER de ADR-004 siga abierto; `jwt` cuando se cierre."
  type        = string
  default     = "disabled"

  validation {
    condition     = contains(["disabled", "jwt"], var.auth_mode)
    error_message = "auth_mode solo admite 'disabled' o 'jwt'."
  }
}

variable "authentication_driver" {
  description = <<-DESC
    Como verifica Account las contrasenas.

    `fake` compara contra cuentas sembradas en memoria y sirve para levantar el
    stack sin depender de AWS. `cognito` invoca `AdminInitiateAuth` de verdad,
    que es lo que HU-02 necesita; el rol de instancia ya tiene ese permiso.
  DESC
  type        = string
  default     = "fake"

  validation {
    condition     = contains(["fake", "cognito"], var.authentication_driver)
    error_message = "authentication_driver solo admite 'fake' o 'cognito'."
  }
}

variable "compose_plugin_url" {
  description = "Complemento `compose`, con la version fijada. No esta en los repositorios de AL2023."
  type        = string
  default     = "https://github.com/docker/compose/releases/download/v5.5.0/docker-compose-linux-aarch64"
}

variable "compose_plugin_sha256" {
  description = "Huella publicada del binario anterior, verificada en el nodo antes de ejecutarlo."
  type        = string
  default     = "ff42489f5a9b879d5d117c5ffea6defc27390b3286da8ad52cbc9c6ab5df590e"
}

variable "public_ingress_cidrs" {
  description = "Vacio mientras el BLOCKER de ADR-004 siga abierto."
  type        = list(string)
  default     = []
}

variable "activate_cost_allocation_tags" {
  description = <<-DESC
    Activa el desglose de coste por etiqueta en Cost Explorer.

    Falso en la primera aplicacion: AWS necesita ver la etiqueta en un recurso
    real antes de permitir activarla, y tarda hasta 24 h en exponerla. Se pone a
    cierto en una segunda aplicacion al dia siguiente.
  DESC
  type        = bool
  default     = false
}

variable "allowed_instance_types" {
  description = <<-DESC
    Tipos de instancia que la politica de IAM permite lanzar.

    El presupuesto avisa DESPUES de gastar; esto impide antes. Debe incluir todo
    lo que aparezca en `nodes`, o el `apply` fallara al lanzar la instancia — que
    es exactamente el comportamiento buscado.
  DESC
  type        = list(string)
  default     = ["t4g.nano", "t4g.micro", "t4g.small", "t4g.medium"]
}

# ---------------------------------------------------------------------------
# Segundo factor por correo (ADR-004)
# ---------------------------------------------------------------------------

variable "ses_identity_arn" {
  description = <<-DESC
    ARN de una identidad de SES ya verificada, que el pool usara como remitente.

    Vacio deja el emisor por defecto de Cognito, que NO admite MFA por correo.

    La identidad debe verificarse ANTES del apply, y esto no lo hace Terraform a
    proposito: verificar una direccion exige que una persona abra un correo y
    pulse un enlace.

    ATENCION - LIMITE REAL DE ESTA CUENTA: SES esta en el entorno de pruebas y la
    solicitud para salir de el fue DENEGADA (caso 178781013000904). En ese
    entorno **solo se puede escribir a direcciones ya verificadas**. El segundo
    factor por correo funcionara para las cuentas administrativas cuyo correo
    este verificado en SES, y no para nadie mas. Es suficiente para la demo
    porque los roles administrativos son contados, y conviene saberlo antes de
    prometer el flujo a cualquier usuario.
  DESC
  type        = string
  default     = ""
}

variable "from_email_address" {
  description = "Remitente visible. Debe corresponder a la identidad verificada."
  type        = string
  default     = ""
}

variable "mfa_methods" {
  description = <<-DESC
    Segundos factores que ofrece el pool. Con los dos, Cognito reta con
    `SELECT_MFA_TYPE` y quien entra elige.

    Se queda en solo `software_token` MIENTRAS no haya recuperacion por SMS:
    activar `email` obliga a que la recuperacion deje de ser por correo, y hoy
    nadie tiene telefono registrado. Cambiar una sin la otra deja a todo el
    mundo sin poder recuperar su cuenta, que es exactamente lo que ya paso con
    `admin_only`.

    Ver `docs/adr/ADR-004-identity-directory.md`, seccion del segundo factor.
  DESC
  type        = set(string)
  default     = ["software_token"]
}

variable "account_recovery" {
  description = <<-DESC
    Via de recuperacion de cuenta. NO es autenticacion, y por eso va aparte.

    `verified_email` es incompatible con `email` en `mfa_methods`, y hay una
    precondicion que lo detiene en el plan.
  DESC
  type        = string
  default     = "verified_email"
}

variable "sms_role_arn" {
  description = "Rol de SNS para SMS. Vacio deja el pool sin SMS y sin recuperacion por telefono."
  type        = string
  default     = ""
}

variable "enable_sms" {
  description = <<-DESC
    Crea el rol de IAM para que Cognito publique SMS por SNS.

    Tener la capacidad y usarla como via de recuperacion son dos decisiones
    distintas: `account_recovery = "verified_phone_number"` deja fuera a quien
    no tenga telefono registrado, y hoy no lo tiene nadie.
  DESC
  type        = bool
  default     = false
}

variable "public_site_address" {
  description = <<-DESC
    Direccion con la que el proxy sirve el sitio publico, y con ella el
    certificado que usa.

    Vacio  -> `localhost:8443`, que nadie alcanza. El sistema NO esta expuesto.
    Una IP -> certificado de la CA local de Caddy. El navegador avisa.
    Dominio -> con `tls_contact_email`, certificado real de Let's Encrypt.

    HTTPS y no HTTP, y no por gusto: Cognito RECHAZA URL de retorno que no sean
    HTTPS, salvo `localhost`. Exponer esto por HTTP plano daria un sistema
    alcanzable en el que nadie podria iniciar sesion.

    VA DE LA MANO DE DOS COSAS MAS, y omitir cualquiera deja el sistema roto de
    una forma distinta:

      1. `public_ingress_cidrs`, o nadie llega.
      2. `callback_urls` del cliente de Cognito, o el retorno del inicio de
         sesion falla con `redirect_mismatch`.

    Y si la direccion es una IP: la publica del nodo CAMBIA cada vez que se
    reemplaza. Para que no se rompa en cada despliegue hace falta una IP
    elastica, o un dominio.
  DESC
  type        = string
  default     = ""
}

variable "tls_contact_email" {
  description = <<-DESC
    Correo de contacto para Let's Encrypt. Vacio significa `internal`: Caddy usa
    su CA local y el navegador avisa de certificado no confiable.

    Solo tiene efecto con un dominio publico resoluble en `public_site_address`:
    Let's Encrypt no emite certificados para una IP desnuda.
  DESC
  type        = string
  default     = ""

  /**
   * Un valor de relleno TUMBA EL PROXY, y con el todo el nodo.
   *
   * Caddy solo acepta `internal`, `force_automate` o un correo. Cualquier otra
   * cosa hace que el fichero de configuracion no se pueda adaptar y el
   * contenedor entra en bucle de reinicio: deja de servir tambien el sitio
   * interno, del que dependen las sondas de salud.
   *
   * Paso de verdad. Un `apply` con `tls_contact_email=TU-CORREO` -el marcador de
   * un ejemplo, copiado literal- dejo el nodo recien creado sin proxy:
   *
   *   Error: parsing caddyfile tokens for 'tls': single argument must either be
   *   'internal', 'force_automate', or an email address
   *
   * Se comprueba aqui porque es donde todavia no ha costado nada. Corregirlo
   * despues obliga a reemplazar el nodo otra vez, ya que el valor viaja en
   * `user_data`.
   */
  validation {
    condition     = var.tls_contact_email == "" || can(regex("^[^@[:space:]]+@[^@[:space:]]+[.][^@[:space:]]+$", var.tls_contact_email))
    error_message = "tls_contact_email debe ser un correo valido, o cadena vacia para usar la CA local. Un valor de relleno deja el proxy en bucle de reinicio."
  }
}

variable "data_volume_gb" {
  description = "Tamano en GiB del volumen EBS de datos del nodo `data`."
  type        = number
  default     = 20
}

variable "mount_data_volume" {
  description = <<-DESC
    Si el arranque monta el volumen de datos. Ver la variable homonima del
    modulo de computo: pasarla a cierto REEMPLAZA el nodo `data`, y hacerlo
    antes de migrar los datos los destruye. El orden esta en
    `docs/runbooks/migrar-datos-al-volumen.md`.
  DESC
  type        = bool
  default     = false
}

variable "product_assets_bucket_name" {
  description = "Nombre del bucket S3 para los recursos visuales de Producto (ADR-016 / EN-027.9)."
  type        = string
  default     = ""
}
