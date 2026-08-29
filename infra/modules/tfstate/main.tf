/**
 * Bucket del estado de Terraform.
 *
 * Es la UNICA excepcion a la prohibicion de S3 del proyecto: la preve ADR-007 y
 * la habilita ADR-008 al pasar a `Accepted`. No se usa S3 para ninguna otra
 * cosa, y la politica de denegacion de `modules/iam` lo aplica de verdad,
 * permitiendo este bucket por nombre y denegando `s3:*` sobre cualquier otro.
 *
 * Por que ahora y no antes. El README de `infra` decia: «mientras el estado sea
 * local, no esta compartido y no esta respaldado. Es aceptable porque todavia
 * no hay nada aplicado; deja de serlo en cuanto lo haya». Ya hay 30 recursos
 * aplicados, asi que la condicion se cumplio.
 *
 * Y hay un motivo mas concreto, que aparecio al intentar que otra persona del
 * equipo planificara: sin el estado, `terraform plan` propone crear lo que ya
 * existe. La salida obvia —pasarse el fichero— **filtra la contrasena de las
 * bases**: el estado guarda `user_data` entero y sin hashear, y el arranque
 * lleva dentro `DB_PASSWORD`. El estado compartido no es comodidad, es la forma
 * de no tener que mandar ese fichero por chat.
 *
 * Sobre la circularidad: este bucket se declara en la misma configuracion cuyo
 * estado va a alojar, asi que acaba registrado dentro de si mismo. Es el patron
 * habitual y funciona; lo que no se puede es destruirlo con `terraform destroy`
 * sin sacarlo antes del estado. De ahi el `prevent_destroy`.
 */

resource "aws_s3_bucket" "this" {
  bucket = var.bucket
  tags   = var.tags

  lifecycle {
    # Perder este bucket es perder el registro de todo lo aplicado. No hay
    # ninguna operacion rutinaria que justifique destruirlo.
    prevent_destroy = true
  }
}

# Es lo que convierte una escritura mala del estado en algo reversible. Sin
# versionado, un `apply` interrumpido a medias deja un unico fichero corrupto y
# ninguna copia.
resource "aws_s3_bucket_versioning" "this" {
  bucket = aws_s3_bucket.this.id

  versioning_configuration {
    status = "Enabled"
  }
}

# SSE-S3 y no KMS a proposito. Una clave gestionada anade un cargo mensual fijo
# mas coste por peticion, y con un techo de USD 100 al mes eso se nota; el
# estado no sale de la cuenta y no lo lee ningun tercero. Si algun dia hace falta
# separar quien puede descifrarlo de quien puede leer el bucket, entonces KMS
# tendra una razon que hoy no tiene.
resource "aws_s3_bucket_server_side_encryption_configuration" "this" {
  bucket = aws_s3_bucket.this.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }

    # Reduce las llamadas de cifrado y no cuesta nada activarlo.
    bucket_key_enabled = true
  }
}

# Los cuatro, explicitos. El estado describe la infraestructura entera y lleva
# dentro el arranque de los nodos: no hay ninguna lectura publica que tenga
# sentido sobre este bucket.
resource "aws_s3_bucket_public_access_block" "this" {
  bucket = aws_s3_bucket.this.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_lifecycle_configuration" "this" {
  bucket = aws_s3_bucket.this.id

  # `depends_on` y no una referencia implicita: la regla actua sobre versiones
  # antiguas, que no existen hasta que el versionado esta activo.
  depends_on = [aws_s3_bucket_versioning.this]

  rule {
    id     = "caducar-versiones-antiguas"
    status = "Enabled"

    filter {}

    noncurrent_version_expiration {
      noncurrent_days = var.dias_de_retencion_de_versiones
    }

    # Una subida cortada deja una carga multiparte que sigue ocupando y
    # facturando sin aparecer en el listado de objetos.
    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }
}

data "aws_iam_policy_document" "solo_tls" {
  statement {
    sid    = "DenegarSinTLS"
    effect = "Deny"

    principals {
      type        = "*"
      identifiers = ["*"]
    }

    actions   = ["s3:*"]
    resources = [aws_s3_bucket.this.arn, "${aws_s3_bucket.this.arn}/*"]

    condition {
      test     = "Bool"
      variable = "aws:SecureTransport"
      values   = ["false"]
    }
  }
}

resource "aws_s3_bucket_policy" "this" {
  bucket = aws_s3_bucket.this.id
  policy = data.aws_iam_policy_document.solo_tls.json

  # Aplicar una politica mientras el bloqueo de acceso publico se esta creando
  # puede fallar por evaluacion parcial.
  depends_on = [aws_s3_bucket_public_access_block.this]
}
