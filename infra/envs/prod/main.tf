# ---------------------------------------------------------------------------
# Entorno de demo. Topologia T2 de ADR-011: plano de aplicacion y plano de datos.
#
# APLICADO desde el 2026-08-26. El estado vive en local mientras ADR-008 no
# pase el respaldo a S3; `terraform.tfstate` esta fuera del control de versiones.
# ---------------------------------------------------------------------------

locals {
  name = "nexus-battles-vi"

  tags = {
    Project     = "nexus-battles-vi"
    Environment = "prod"
    ManagedBy   = "terraform"
    Repository  = "Nexus-Battle-Infrastructure"
  }

  product_assets_bucket_name = var.product_assets_bucket_name != "" ? var.product_assets_bucket_name : "nexus-battles-vi-product-assets-${var.account_id}"
}

module "governance" {
  source = "../../modules/governance"

  account_id  = var.account_id
  alert_email = var.alert_email
}

/**
 * La identidad de operacion se declara ANTES que el computo, igual que el
 * presupuesto: crear veintidos recursos a nombre de root deja un rastro de
 * auditoria que despues no se puede reescribir.
 */
/*
 * El bucket del estado. Se declara aqui, en la misma configuracion cuyo estado
 * aloja: acaba registrado dentro de si mismo, que es el patron habitual.
 *
 * El orden de activacion NO se puede saltar: primero se aplica esto con estado
 * local, y solo despues se descomenta el `backend "s3"` de `versions.tf` y se
 * ejecuta `terraform init -migrate-state`. El procedimiento esta en
 * `infra/README.md`.
 */
module "tfstate" {
  source = "../../modules/tfstate"

  tags = local.tags
}

module "product_assets" {
  source = "../../modules/product_assets"

  bucket_name         = local.product_assets_bucket_name
  tags                = local.tags
  allowed_web_origins = var.product_assets_cors_origins

  # El operador necesita que la política S3SoloParaElEstado haya incluido el bucket
  # antes de que la llamada a CreateBucket sea autorizada por IAM.
  depends_on = [module.iam]
}

module "iam" {
  source = "../../modules/iam"

  allowed_instance_types = var.allowed_instance_types
  product_assets_bucket  = local.product_assets_bucket_name
}

/**
 * Cola SQS de catalog.product.created (ADR-017, Accepted en Management #284,
 * merge de Infrastructure #65). Cubre EXCLUSIVAMENTE ese evento.
 */
module "catalog_events_queue" {
  source = "../../modules/catalog_events_queue"

  environment = var.environment
  tags        = local.tags
}

/**
 * Cola SQS de los cuatro eventos de ciclo de vida de Producto (ADR-018,
 * Accepted en Management #314): suspended/reactivated/inventory.adjusted/
 * premium.configured. Modulo separado de `catalog_events_queue` a proposito
 * -ver el comentario del modulo mismo-: la condicion de aprobacion de
 * Management#314 exige no modificar ni arriesgar la cola de
 * `catalog.product.created` ya existente.
 */
module "catalog_lifecycle_events_queue" {
  source = "../../modules/catalog_lifecycle_events_queue"

  environment = var.environment
  tags        = local.tags
}

module "network" {
  source = "../../modules/network"

  # El puerto 80 solo se abre cuando hay un dominio del que pedir certificado.
  acme_enabled = var.public_site_address != "" && var.tls_contact_email != ""

  name                 = local.name
  tags                 = local.tags
  availability_zone    = var.availability_zone
  public_ingress_cidrs = var.public_ingress_cidrs
}

module "identity" {
  source = "../../modules/identity"

  name = local.name
  tags = local.tags

  # El segundo factor por correo y la identidad de SES van juntos: sin identidad
  # verificada, Cognito no admite MFA por correo. Vacio deja el pool con el
  # emisor por defecto y el segundo factor en aplicacion autenticadora.
  ses_identity_arn   = var.ses_identity_arn
  from_email_address = var.from_email_address
  mfa_methods        = var.mfa_methods
  account_recovery   = var.account_recovery
  sms_role_arn       = var.sms_role_arn
  enable_sms         = var.enable_sms

  /**
   * Las URL de retorno incluyen el sitio publico AUTOMATICAMENTE.
   *
   * Es el acoplamiento que mas facil se olvida: exponer el sistema sin anadir su
   * origen aqui deja un despliegue alcanzable donde el inicio de sesion falla
   * con `redirect_mismatch`, y el error no menciona esta variable por ningun
   * lado. Derivarlo de `public_site_address` hace imposible desincronizarlos.
   *
   * `localhost` se conserva siempre: es el unico origen que Cognito admite por
   * HTTP y sin el se rompe el desarrollo local. Que Cognito lo permita como
   * excepcion explicita es lo que hace seguro dejarlo puesto.
   */
  callback_urls = compact([
    "http://localhost:5173/auth/callback",
    var.public_site_address == "" ? "" : "https://${var.public_site_address}/auth/callback",
  ])

  logout_urls = compact([
    "http://localhost:5173/",
    var.public_site_address == "" ? "" : "https://${var.public_site_address}/",
  ])
}

# Lo que cada rol de nodo escribe en disco al arrancar.
#
# Los ficheros se LEEN de `compose/`, no se duplican aqui. Es la unica forma de
# que el mismo `docker compose config` que valida el CI valide lo que de verdad
# acaba en la instancia: una copia dentro de Terraform seria una copia que se
# desvia sin que nada se queje.
locals {
  compose_dir = "${path.root}/../../../compose"

  bootstrap = {
    app = {
      compose = file("${local.compose_dir}/nodes/app.yml")
      ficheros = {
        "Caddyfile" = file("${local.compose_dir}/Caddyfile")
      }
      entorno = {
        DATA_HOST             = var.nodes["data"].private_ip
        DB_PASSWORD           = var.db_password
        AUTH_MODE             = var.auth_mode
        AUTHENTICATION_DRIVER = var.authentication_driver
        COGNITO_USER_POOL_ID  = module.identity.user_pool_id
        COGNITO_CLIENT_ID     = module.identity.client_id

        # El bucket y el rol ya existen en el grafo: Catalog debe recibir la
        # configuracion para usar ese almacenamiento en lugar de memoria.
        ASSETS_STORAGE_DRIVER      = "s3"
        PRODUCT_ASSETS_BUCKET_NAME = module.product_assets.bucket_id
        AWS_REGION                 = var.region

        # Firma compartida por Account, Catalog, Commerce, Inventory y
        # Notifications. arrancar_stack exige un valor no vacio.
        INTERNAL_SERVICE_AUTH_SECRET = var.internal_service_auth_secret

        # Cola real de catalog.product.created (ADR-017 Accepted). El nombre
        # coincide con lo que Notifications ya sabe leer
        # (`CATALOG_QUEUE_URL`, ver Nexus-Battle-Notifications env.ts) y con
        # lo que se documenta como recomendado para el futuro dispatcher de
        # Catalog (`CATALOG_EVENTS_QUEUE_URL`, alias equivalente en el mismo
        # env.ts).
        #
        # NO basta con definir esta variable para que Notifications consuma
        # de verdad: su adaptador SQS es GLOBAL (`QUEUE_DRIVER=sqs`), y ese
        # mismo interruptor exige tambien `QUEUE_URL` -la cola general de
        # ADR-006, para account.registered/verified y demas notificaciones
        # transaccionales-, que sigue sin provisionar porque ADR-006 sigue
        # `Proposed`. Activar `QUEUE_DRIVER=sqs` sin esa cola general rompe el
        # arranque del worker (`loadConfig` lo rechaza) para TODOS los
        # consumidores, no solo el de catalog.product.created. Se deja
        # `QUEUE_DRIVER=memory` en compose por esa razon: es una brecha de
        # ADR-006, no de esta cola.
        CATALOG_QUEUE_URL = module.catalog_events_queue.queue_url

        # MISMO output que CATALOG_QUEUE_URL arriba, no una cola distinta:
        # Catalog#51 (dispatcher del outbox hacia SQS, HU-38) publica leyendo
        # este nombre, mientras que Notifications consume leyendo
        # CATALOG_QUEUE_URL. Ver la nota extensa arriba sobre por que definir
        # esta variable tampoco activa por si sola el envio real -Catalog
        # ademas exige CATALOG_EVENT_DISPATCH_ENABLED=true (compose/nodes/app.yml)
        # y, como el resto, sigue sin `terraform apply`.
        CATALOG_EVENTS_QUEUE_URL = module.catalog_events_queue.queue_url

        # Cola real de los cuatro eventos de ciclo de vida (ADR-018 Accepted,
        # Management#314). Igual que CATALOG_QUEUE_URL arriba: tener esta
        # variable puesta NO activa por si sola el consumo real.
        #
        # Notifications ya reconoce `CATALOG_LIFECYCLE_QUEUE_URL`, pero
        # auditado su codigo (`catalog-notifications-application.ts`),
        # `lifecycleQueue` sigue activandose con `config.queueDriver`
        # -el interruptor GENERAL, no uno propio- y sigue reenviando a
        # `config.deadLetterQueueUrl` -la DLQ GENERAL- en vez de confiar en la
        # redrive policy de esta cola dedicada. Ambos son el mismo tipo de
        # acoplamiento que Notifications#23 ya corrigio para
        # `catalog.product.created`, pero nadie corrigio el equivalente para
        # el ciclo de vida. Activar `QUEUE_DRIVER=sqs` para forzar el consumo
        # aqui repetiria exactamente el problema que #23 resolvio -y ademas
        # exigiria la cola general de ADR-006, todavia `Proposed`-, asi que
        # deliberadamente NO se hace. `QUEUE_DRIVER` permanece `memory`. El
        # consumo real de esta cola espera un PR de Notifications que agregue
        # un driver lifecycle independiente (ver ADR-018 y
        # docs/contracts/event-catalog.md).
        CATALOG_LIFECYCLE_QUEUE_URL = module.catalog_lifecycle_events_queue.queue_url

        # Filtro automatico de contenido de Community (HU-41.7,
        # Management#29). Vacio por defecto: Community arranca igual y no
        # genera ninguna deteccion. Terraform NO define aqui la politica
        # funcional, solo transporta lo que cada ambiente decida.
        COMMENT_MODERATION_FORBIDDEN_TERMS     = var.comment_moderation_forbidden_terms
        COMMENT_MODERATION_SUSPICIOUS_PATTERNS = var.comment_moderation_suspicious_patterns

        # Vacio deja el sitio publico en `localhost:8443`, que nadie alcanza.
        # Abrir `public_ingress_cidrs` sin poner esto abriria dos puertos donde
        # el proxy no sirve nada util.
        SITIO_PUBLICO = var.public_site_address
        TLS_CONTACTO  = var.tls_contact_email
      }
    }

    data = {
      compose = file("${local.compose_dir}/nodes/data.yml")
      ficheros = {
        "init-postgres.sh" = file("${local.compose_dir}/init-postgres.sh")
        "init-mongo.js"    = file("${local.compose_dir}/init-mongo.js")
      }
      entorno = {
        DB_PASSWORD = var.db_password

        # La usa `mongo-rs-init` para declarar el miembro del conjunto con la
        # direccion por la que lo alcanzan los servicios de la OTRA maquina.
        # Con `localhost` la configuracion del conjunto quedaria escrita con una
        # direccion que ningun cliente puede resolver.
        DATA_HOST = var.nodes["data"].private_ip
      }
    }
  }
}

module "compute" {
  source = "../../modules/compute"

  # Un nombre DNS apuntando aqui exige una direccion que no cambie al reemplazar
  # el nodo. Se activa sola en cuanto hay sitio publico configurado.
  stable_public_ip = var.public_site_address != ""

  name                        = local.name
  tags                        = local.tags
  subnet_id                   = module.network.subnet_id
  security_group_ids          = module.network.security_group_ids
  nodes                       = var.nodes
  bootstrap                   = local.bootstrap
  arrancar_stack              = var.arrancar_stack
  compose_plugin_url          = var.compose_plugin_url
  compose_plugin_sha256       = var.compose_plugin_sha256
  cognito_user_pool_arn       = module.identity.user_pool_arn
  data_volume_gb              = var.data_volume_gb
  mount_data_volume           = var.mount_data_volume
  product_assets_bucket       = local.product_assets_bucket_name
  catalog_events_queue_arn    = module.catalog_events_queue.queue_arn
  catalog_lifecycle_queue_arn = module.catalog_lifecycle_events_queue.queue_arn

  # El presupuesto y las alertas existen antes que cualquier recurso de computo.
  # Esta dependencia lo convierte en una garantia del grafo, no en una costumbre.
  depends_on = [module.governance]
}

# ---------------------------------------------------------------------------
# Los presupuestos YA EXISTEN: se crearon el 2026-08-25, antes de escribir este
# codigo, porque ADR-007 exige que las alertas precedan a cualquier recurso de
# computo. Estos bloques los traen bajo Terraform sin recrearlos.
#
# Los bloques `import` solo surten efecto en el modulo RAIZ. Declararlos dentro
# del modulo no da error: simplemente se ignoran, y el plan propone crear un
# presupuesto que ya existe. Lo detecto el `terraform plan`.
# ---------------------------------------------------------------------------
import {
  to = module.governance.aws_budgets_budget.ceiling
  id = "${var.account_id}:nexus-battles-monthly-100"
}

import {
  to = module.governance.aws_budgets_budget.operational
  id = "${var.account_id}:nexus-battles-operational-25"
}

# ---------------------------------------------------------------------------
# Activacion de etiquetas para imputacion de coste.
#
# Desactivado por defecto y NO es un olvido: AWS solo permite activar una
# etiqueta que ya ha visto en algun recurso, y tarda hasta 24 h en exponerla.
# Se activa en una SEGUNDA aplicacion, un dia despues de crear los recursos.
# Declararlo aqui con `depends_on` no bastaria: la dependencia del grafo no
# acelera el rastreo de etiquetas de AWS.
# ---------------------------------------------------------------------------
resource "aws_ce_cost_allocation_tag" "this" {
  for_each = var.activate_cost_allocation_tags ? toset(["Project", "Environment", "Role"]) : toset([])

  tag_key = each.value
  status  = "Active"

  depends_on = [module.compute]
}
