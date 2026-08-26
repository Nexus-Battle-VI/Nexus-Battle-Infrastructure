/**
 * Identidad de operacion, para dejar de trabajar como root.
 *
 * AWS desaconseja usar la cuenta root para nada que no sea lo que solo root
 * puede hacer. Este modulo crea el principal con el que se opera a diario, y es
 * de las pocas cosas para las que root sirve: crearlo.
 *
 * NO crea la clave de acceso. `aws_iam_access_key` guardaria el secreto en
 * TEXTO PLANO dentro del fichero de estado, que aqui es local. La clave se
 * genera aparte, y por eso este modulo no la produce ni la conoce.
 */

resource "aws_iam_group" "operators" {
  name = var.group_name
}

resource "aws_iam_user" "operator" {
  name = var.user_name

  # No se fuerza el borrado de la clave al destruir: si alguien tiene una activa,
  # que el destroy falle es preferible a retirarle el acceso sin avisar.
  force_destroy = false
}

resource "aws_iam_user_group_membership" "operator" {
  user   = aws_iam_user.operator.name
  groups = [aws_iam_group.operators.name]
}

/**
 * Permiso amplio, acotado por una denegacion explicita.
 *
 * Un permiso a medida se queda corto en cada `terraform apply` nuevo y acaba
 * ampliandose a ciegas hasta ser equivalente a administrador, pero sin que nadie
 * lo haya decidido. Es preferible partir de administrador y **restar** de forma
 * explicita lo que el proyecto ha decidido no usar: en IAM la denegacion gana
 * siempre, asi que el limite es real y no una convencion.
 */
resource "aws_iam_group_policy_attachment" "admin" {
  group      = aws_iam_group.operators.name
  policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
}

/**
 * La lista de servicios prohibidos, convertida en control.
 *
 * Hasta ahora vivia en un fichero de reglas: alguien podia provisionar un NAT
 * Gateway sin mas consecuencia que un comentario en la revision. Aqui **la
 * llamada a la API falla**, que es la diferencia entre una norma y un limite.
 *
 * Es el mismo criterio que se aplico a las restricciones del dominio: no basta
 * con que el codigo se porte bien, la proteccion tiene que estar donde nadie
 * pueda saltarsela por descuido.
 */
data "aws_iam_policy_document" "prohibidos" {
  statement {
    sid    = "ServiciosFueraDelAlcance"
    effect = "Deny"

    actions = [
      "lambda:*",
      "dynamodb:*",
      "cloudfront:*",
      # Cubre tambien Fargate, que no tiene espacio de nombres propio.
      "ecs:*",
      "eks:*",
      # `rds:*` cubre DocumentDB, que usa la misma API.
      "rds:*",
      "elasticache:*",
      # Directory Service, donde vive Managed Microsoft AD.
      "ds:*",
      # ALB y NLB.
      "elasticloadbalancing:*",
    ]

    resources = ["*"]
  }

  statement {
    sid    = "SinNatGateway"
    effect = "Deny"

    # Un NAT Gateway cuesta mas al mes que el techo entero del proyecto, y se
    # provisiona sin querer con casi cualquier constructo de alto nivel.
    actions   = ["ec2:CreateNatGateway"]
    resources = ["*"]
  }

  /**
   * S3 solo para el estado de Terraform.
   *
   * Es la unica excepcion que ADR-007 preve, y ADR-008 la habilito al pasar a
   * Accepted. `not_resources` deja fuera el bucket de estado y deniega el resto,
   * de modo que la excepcion es exactamente eso y no una puerta abierta.
   */
  statement {
    sid    = "S3SoloParaElEstado"
    effect = "Deny"

    actions = ["s3:*"]

    not_resources = [
      "arn:aws:s3:::${var.tfstate_bucket}",
      "arn:aws:s3:::${var.tfstate_bucket}/*",
    ]
  }

  /**
   * El techo de coste, aplicado donde se decide.
   *
   * El presupuesto avisa DESPUES de gastar. Esto impide antes: una instancia
   * fuera de la lista no se puede lanzar, y ampliarla obliga a editar esta
   * politica, que es una decision visible en un PR y no un `-t` en una consola.
   */
  statement {
    sid    = "SoloInstanciasAcotadas"
    effect = "Deny"

    actions   = ["ec2:RunInstances"]
    resources = ["arn:aws:ec2:*:*:instance/*"]

    condition {
      test     = "StringNotEquals"
      variable = "ec2:InstanceType"
      values   = var.allowed_instance_types
    }
  }
}

resource "aws_iam_group_policy" "prohibidos" {
  name   = "nexus-battles-fuera-de-alcance"
  group  = aws_iam_group.operators.name
  policy = data.aws_iam_policy_document.prohibidos.json
}
