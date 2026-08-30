# ---------------------------------------------------------------------------
# Nodos de computo.
#
# Sin par de claves y sin puerto 22: el acceso administrativo va por SSM Session
# Manager. Una clave SSH es un secreto de larga duracion que hay que custodiar,
# rotar y revocar; Session Manager no necesita ninguno y deja registro.
# ---------------------------------------------------------------------------

# AMI de Amazon Linux 2023 para arm64, resuelta desde el parametro publico de
# SSM. Nunca se fija un identificador de AMI a mano: caduca y varia por region.
data "aws_ssm_parameter" "al2023_arm64" {
  name = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-arm64"
}

data "aws_iam_policy_document" "assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "node" {
  name               = "${var.name}-node"
  assume_role_policy = data.aws_iam_policy_document.assume.json
  tags               = var.tags
}

# SSM para administracion. Cognito Admin* (mas abajo) es la SEGUNDA y ultima
# concesion a este rol: un nodo de esta topologia no necesita leer ni escribir
# ningun otro servicio de AWS.
resource "aws_iam_role_policy_attachment" "ssm" {
  role       = aws_iam_role.node.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

/**
 * Autorizacion IAM para el login server-side de Account (HU-02).
 *
 * `AdminInitiateAuth`/`AdminRespondToAuthChallenge` son las operaciones que
 * Cognito exige de verdad para `AuthFlow = ADMIN_USER_PASSWORD_AUTH`: a
 * diferencia de `InitiateAuth` publico, estas dos van firmadas con
 * credenciales de AWS, y por eso son las que dejan la autorizacion en IAM y no
 * en el `client_id`. Acotadas por `Resource` a un unico pool: ni "*" ni
 * `cognito-idp:*`, que concederia tambien crear o borrar pools, usuarios o
 * clientes de aplicacion.
 *
 * BLOCKER DE TOPOLOGIA — declarado y no disimulado: este rol es el UNICO que
 * existe para el nodo `app` (ver `aws_iam_instance_profile.node` mas abajo), y
 * ADR-011 pone los seis contenedores del nodo `app` -proxy, web, account,
 * inventory, catalog, community, commerce- en la MISMA instancia EC2. Docker
 * no aisla por contenedor el acceso al servicio de metadatos (169.254.169.254,
 * IMDSv2): cualquier contenedor de ese nodo puede, en la practica, obtener las
 * mismas credenciales que Account y llamar estas dos acciones, no solo
 * Account. No existe hoy un mecanismo para restringir esto por contenedor sin
 * cambiar de topologia (roles de tarea de ECS/Fargate, ServiceAccounts de
 * Kubernetes, o una instancia por servicio) -precisamente lo que ADR-011
 * descarto por coste-, y no se inventa aqui uno nuevo. Aislar esto de verdad
 * es una decision arquitectonica futura, no un ajuste de esta rama.
 */
data "aws_iam_policy_document" "cognito_admin_auth" {
  statement {
    sid    = "AccountAdminAuth"
    effect = "Allow"

    actions = [
      "cognito-idp:AdminInitiateAuth",
      "cognito-idp:AdminRespondToAuthChallenge",
    ]

    resources = [var.cognito_user_pool_arn]
  }

  /**
   * Reflejo del rol en el pool.
   *
   * Account es la fuente de verdad de los roles -viven en `account_roles`, en
   * PostgreSQL- y el pool solo los refleja para que viajen dentro del
   * testimonio. Es lo que el modulo `identity` ya dice de los grupos; lo que
   * faltaba era el permiso que lo hace posible.
   *
   * Sin esto, quien se registrara por la pantalla del proveedor quedaba fuera
   * del grupo `PLAYER`: Account escribia el rol en PostgreSQL y el testimonio
   * viajaba sin `cognito:groups`, de modo que los demas servicios veian a esa
   * persona sin ningun rol. No daba sintoma porque ninguna puerta pide
   * `PLAYER` -todas piden `ADMINISTRATOR` o `MODERATOR`- y por eso la
   * divergencia era invisible en lugar de inexistente.
   *
   * SON CUATRO ACCIONES Y NO MAS, deliberadamente. `AdminListGroupsForUser` es
   * de lectura y hace falta para calcular la diferencia: sin ella el reflejo
   * solo podria sumar, y retirar un rol en Account nunca llegaria al testimonio.
   *
   * `AdminGetUser` se anadio el 2026-08-30 y tiene su propio motivo: el correo
   * verificado NO viaja en el access token -ese atributo vive en el ID token, y
   * cambiar `tokenUse` romperia el RBAC de los cinco servicios-, asi que Account
   * tiene que preguntarselo al proveedor por el sujeto. Sin este permiso el
   * registro falla CERRADO con 503, que es el comportamiento correcto pero deja
   * el alta inutilizable.
   * NO se conceden `AdminCreateUser` ni `AdminDeleteUser`: Account dejo de
   * crear identidades y no debe recuperar esa capacidad por la puerta de atras.
   * Tampoco `CreateGroup` ni `DeleteGroup`: los grupos los declara el modulo
   * `identity`, y que el servicio pudiera crearlos dejaria a la
   * infraestructura describiendo algo distinto de lo que existe.
   *
   * El blocker de topologia descrito arriba aplica igual a estas tres: cualquier
   * contenedor del nodo `app` puede invocarlas, no solo Account.
   */
  statement {
    sid    = "AccountRoleReflection"
    effect = "Allow"

    actions = [
      "cognito-idp:AdminListGroupsForUser",
      "cognito-idp:AdminAddUserToGroup",
      "cognito-idp:AdminRemoveUserFromGroup",
      # Solo LECTURA de atributos. No se concede AdminUpdateUserAttributes: el
      # producto lee lo que el proveedor comprobo, nunca lo declara por su
      # cuenta. Poder escribirlo convertiria la prueba en una afirmacion propia.
      "cognito-idp:AdminGetUser",
    ]

    resources = [var.cognito_user_pool_arn]
  }
}

resource "aws_iam_role_policy" "cognito_admin_auth" {
  name   = "${var.name}-cognito-admin-auth"
  role   = aws_iam_role.node.name
  policy = data.aws_iam_policy_document.cognito_admin_auth.json
}

resource "aws_iam_instance_profile" "node" {
  name = "${var.name}-node"
  role = aws_iam_role.node.name
  tags = var.tags
}

# ---------------------------------------------------------------------------
# Arranque de cada nodo.
#
# El guion se compone aqui y no se ejecuta a mano por SSM: un nodo recreado
# vuelve al mismo estado sin que nadie tenga que recordar lo que hizo la vez
# anterior. Es la misma razon por la que ADR-008 eligio Terraform.
#
# `user_data` es legible desde la propia instancia a traves de los metadatos.
# Con IMDSv2 obligatorio y un limite de un salto no lo alcanza un contenedor por
# accidente, pero conviene saber que la contrasena de las bases viaja ahi.
# ---------------------------------------------------------------------------
locals {
  arranque = {
    for clave, nodo in var.nodes : clave => templatefile(
      "${path.module}/templates/bootstrap.sh.tftpl",
      {
        rol            = nodo.role
        data_host      = var.nodes["data"].private_ip
        compose        = var.bootstrap[nodo.role].compose
        ficheros       = var.bootstrap[nodo.role].ficheros
        entorno        = var.bootstrap[nodo.role].entorno
        arrancar_stack = var.arrancar_stack
        compose_url    = var.compose_plugin_url
        compose_sha256 = var.compose_plugin_sha256
      }
    )
  }
}

resource "aws_instance" "node" {
  for_each = var.nodes

  ami                    = data.aws_ssm_parameter.al2023_arm64.value
  instance_type          = each.value.instance_type
  subnet_id              = var.subnet_id
  vpc_security_group_ids = [var.security_group_ids[each.value.role]]
  iam_instance_profile   = aws_iam_instance_profile.node.name

  # Direccion privada FIJA, y no la que asigne la subred.
  #
  # El nodo `app` necesita saber donde esta el de datos antes de arrancar, y
  # leerlo de `aws_instance.node["data"]` desde el mismo `for_each` seria una
  # autorreferencia que Terraform rechaza. Fijarla en el mapa de nodos rompe el
  # ciclo y ademas deja la topologia legible en un solo sitio.
  private_ip = each.value.private_ip

  /**
   * Comprimido, y no por elegancia: EC2 limita `user_data` a 16 KB.
   *
   * El arranque lleva dentro el compose del nodo y sus ficheros de apoyo -el
   * Caddyfile, los guiones de inicializacion de las bases-, asi que crece cada
   * vez que crece cualquiera de ellos. Al anadir el sitio publico al Caddyfile
   * se paso del limite y el plan fallo con:
   *
   *   expected length of user_data to be in the range (0 - 16384)
   *
   * cloud-init descomprime el gzip por su cuenta -documentado, no supuesto- de
   * modo que el guion llega igual a la maquina. Lo unico que cambia es cuanto
   * ocupa en transito.
   *
   * El limite sigue existiendo sobre el resultado comprimido. Cuando vuelva a
   * quedarse corto, la salida no es comprimir mas: es dejar de meter ficheros
   * en el arranque y traerlos de otro sitio.
   *
   * SOLO SE COMPRIME DONDE HACE FALTA, y esto importa. Cambiar de `user_data` a
   * `user_data_base64` cambia el atributo aunque el guion sea identico, y con
   * `user_data_replace_on_change` eso REEMPLAZA la instancia. Comprimir tambien
   * el nodo de datos lo habria destruido -con PostgreSQL y MongoDB dentro- sin
   * que su arranque hubiera cambiado una sola linea.
   *
   * El plan lo dijo: `2 to add, 0 to change, 2 to destroy`. Merece la pena
   * mirar el plan POR NODO antes de cada apply.
   *
   * El de datos se queda sin comprimir porque su arranque es pequeno y estable.
   * Si algun dia crece hasta el limite, comprimirlo costara una recreacion, y
   * entonces habra que respaldar antes en lugar de descubrirlo a mitad.
   */
  user_data        = each.value.role == "data" ? local.arranque[each.key] : null
  user_data_base64 = each.value.role == "data" ? null : base64gzip(local.arranque[each.key])

  # Sin esto, cambiar el arranque NO cambia nada en la maquina.
  #
  # Por defecto `user_data_replace_on_change` es `false`: Terraform actualiza el
  # atributo en el estado, informa de "updated in-place" y la instancia sigue
  # corriendo el script con el que nacio. El `apply` sale en verde y el nodo se
  # queda como estaba.
  #
  # Se detecto con el arreglo de las credenciales de servicio: el plan proponia
  # "2 to change" sobre las dos instancias y ninguna habria ejecutado el
  # `init-postgres.sh` nuevo.
  #
  # Que reemplazar la instancia sea caro es precisamente el punto: el arranque
  # solo se ejecuta al nacer, asi que un cambio en el arranque ES un cambio de
  # instancia. Decirlo en el plan vale mas que ahorrarselo.
  user_data_replace_on_change = true

  # Necesaria para descargar imagenes: no hay NAT Gateway.
  #
  # Es AUTOASIGNADA y no elastica, y la diferencia importa para el coste: AWS
  # libera la direccion al apagar la instancia, de modo que se cobra por hora
  # ENCENDIDA, igual que el computo. Una IP elastica se cobraria tambien parada.
  #
  # La contrapartida de apagar no es economica sino operativa: al arrancar se
  # asigna otra distinta. Hoy no importa porque ningun nombre DNS apunta aqui.
  associate_public_ip_address = true

  # IMDSv2 obligatorio. Con IMDSv1 basta una vulnerabilidad de peticion del lado
  # del servidor para leer las credenciales del rol de la instancia.
  #
  # `http_put_response_hop_limit = 2`, no 1: la peticion a IMDS sale de un
  # contenedor Docker, que es un salto de red adicional sobre el host. Con
  # limite 1 la respuesta no vuelve a atravesarlo y el contenedor no recibe el
  # token de IMDSv2 -es la recomendacion de AWS para hosts con contenedores-,
  # que es exactamente como corre Account (y el resto de servicios) en este
  # nodo. Coherente con lo ya documentado aqui mismo: las credenciales del rol
  # de instancia se comparten a nivel de nodo, no de contenedor.
  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 2
  }

  root_block_device {
    volume_type           = "gp3"
    volume_size           = each.value.volume_gb
    encrypted             = true
    delete_on_termination = true
    tags                  = merge(var.tags, { Name = "${var.name}-${each.key}" })
  }

  tags = merge(var.tags, {
    Name = "${var.name}-${each.key}"
    Role = each.value.role
  })

  lifecycle {
    # El volumen raiz del nodo de datos contiene las bases. Un cambio de AMI no
    # debe recrear la instancia en silencio y llevarse los datos por delante.
    ignore_changes = [ami]
  }
}

# ---------------------------------------------------------------------------
# Direccion estable para el nodo que sirve el sitio publico.
#
# La IP asignada automaticamente CAMBIA cada vez que la instancia se reemplaza, y
# el nodo `app` se reemplaza siempre que cambia su arranque. Ya paso dos veces el
# 2026-08-29. Sin una direccion fija, cada reemplazo rompe el registro DNS y, con
# el, el certificado y las URL de retorno de Cognito.
#
# COSTE: ninguno adicional mientras la instancia este encendida. AWS cobra la
# misma tarifa por IPv4 publica sea automatica o elastica, y asociar una elastica
# libera la automatica. Lo que si cambia es que una elastica se cobra tambien con
# la instancia APAGADA, y sin asociar. Si se retiran los nodos, hay que retirarla
# tambien o seguira facturando.
#
# Se declara aparte de la instancia a proposito: asi anadirla a un nodo que ya
# existe no lo reemplaza.
#
# RIESGO CONOCIDO, y se deja dicho en lugar de taparlo: Terraform asocia la
# direccion en cuanto la instancia pasa a `running`, y para entonces cloud-init
# suele estar todavia instalando paquetes. Cambiar la IP publica corta las
# conexiones salientes EN CURSO -las nuevas funcionan de inmediato-, asi que un
# reemplazo del nodo puede dejar el arranque a medias.
#
# Se penso en envolver los pasos de red del arranque en reintentos, y se
# descarto: ese guion lo comparten los DOS nodos, asi que tocarlo obliga a
# reemplazar tambien el de datos -con PostgreSQL y MongoDB dentro- por un
# beneficio que solo necesita el nodo `app`. El plan lo dijo: `2 to destroy`.
# Cambiar destruccion segura de datos por un fallo transitorio posible es mal
# negocio.
#
# Si un reemplazo deja el nodo a medias, se ve al comprobarlo -los contenedores
# no estan- y se resuelve volviendo a aplicar. Cuando el arranque tenga que
# cambiar por otro motivo, ese es el momento de anadir los reintentos.
# ---------------------------------------------------------------------------
resource "aws_eip" "app" {
  count = var.stable_public_ip ? 1 : 0

  domain = "vpc"
  tags   = merge(var.tags, { Name = "${var.name}-app" })
}

resource "aws_eip_association" "app" {
  count = var.stable_public_ip ? 1 : 0

  instance_id   = aws_instance.node["app"].id
  allocation_id = aws_eip.app[0].id
}
