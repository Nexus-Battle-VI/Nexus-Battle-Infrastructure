/**
 * Rol que Cognito asume para publicar SMS por SNS.
 *
 * POR QUE EXISTE
 * --------------
 *
 * Activar el OTP por correo obliga a que la recuperacion de cuenta deje de ser
 * por correo: si el buzon es a la vez el segundo factor y la via de vuelta,
 * quien lo controle se salta el factor pidiendo una recuperacion. La unica
 * alternativa de autoservicio que AWS ofrece es el telefono.
 *
 * Se crea SOLO si se pide (`enable_sms`). No se crea "por si acaso": un rol de
 * IAM sin usar es superficie que nadie revisa.
 *
 * LO QUE NO RESUELVE, Y CONVIENE SABER ANTES DE APLICARLO
 * ------------------------------------------------------
 *
 * 1. SNS tiene su PROPIO entorno de pruebas para SMS. Ahi solo entrega a
 *    numeros verificados uno a uno, igual que SES con el correo. Crear el rol
 *    no saca a la cuenta de ese entorno.
 * 2. Los SMS se cobran POR MENSAJE, asi que entran en el techo de USD 100 de
 *    ADR-007. No es coste fijo, pero tampoco es cero.
 * 3. Nadie tiene telefono registrado todavia. Cambiar `account_recovery` a
 *    `verified_phone_number` sin eso deja a TODO EL MUNDO sin recuperacion, en
 *    silencio, que es exactamente lo que ya paso con `admin_only`.
 *
 * Por eso este fichero aporta la CAPACIDAD y no la enciende.
 */

data "aws_iam_policy_document" "sms_assume" {
  count = var.enable_sms ? 1 : 0

  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["cognito-idp.amazonaws.com"]
    }

    /**
     * `sts:ExternalId` es lo que impide el problema del diputado confuso.
     *
     * Sin el, cualquier otro pool de Cognito -de esta cuenta o de otra- que
     * conociera el ARN del rol podria pedir a AWS que lo asumiera y mandar SMS
     * a cargo de esta factura. Con el, solo lo asume quien conoce ademas el
     * identificador, que aqui es el propio pool.
     */
    condition {
      test     = "StringEquals"
      variable = "sts:ExternalId"
      values   = [local.sms_external_id]
    }
  }
}

data "aws_iam_policy_document" "sms_publish" {
  count = var.enable_sms ? 1 : 0

  /**
   * `sns:Publish` sin recurso concreto es lo que AWS documenta para este caso:
   * un SMS no se publica contra un topico, sino contra un numero de telefono,
   * y ese destino no tiene ARN. Acotarlo a un topico haria que Cognito no
   * pudiera enviar nada.
   */
  statement {
    effect    = "Allow"
    actions   = ["sns:Publish"]
    resources = ["*"]
  }
}

resource "aws_iam_role" "sms" {
  count = var.enable_sms ? 1 : 0

  name               = "${var.name}-cognito-sms"
  description        = "Permite al pool de Cognito publicar SMS por SNS"
  assume_role_policy = data.aws_iam_policy_document.sms_assume[0].json

  tags = var.tags
}

resource "aws_iam_role_policy" "sms" {
  count = var.enable_sms ? 1 : 0

  name   = "publicar-sms"
  role   = aws_iam_role.sms[0].id
  policy = data.aws_iam_policy_document.sms_publish[0].json
}

locals {
  /**
   * El identificador externo se deriva del nombre del pool en lugar de pedirse.
   *
   * Es un valor que tiene que coincidir EXACTAMENTE entre la politica de
   * confianza del rol y la configuracion del pool. Dejarlo como variable
   * invitaba a cambiarlo en un sitio y no en el otro, y el sintoma de eso es
   * que Cognito deja de poder asumir el rol con un error que no menciona el
   * identificador.
   */
  sms_external_id = "${var.name}-sms"

  /** ARN efectivo: el rol creado aqui, o el que se aporte desde fuera. */
  sms_role_arn = var.enable_sms ? aws_iam_role.sms[0].arn : var.sms_role_arn
}
