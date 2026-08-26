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

# Unica politica adjunta. No se concede nada mas: un nodo de esta topologia no
# necesita leer ni escribir ningun servicio de AWS.
resource "aws_iam_role_policy_attachment" "ssm" {
  role       = aws_iam_role.node.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "node" {
  name = "${var.name}-node"
  role = aws_iam_role.node.name
  tags = var.tags
}

resource "aws_instance" "node" {
  for_each = var.nodes

  ami                    = data.aws_ssm_parameter.al2023_arm64.value
  instance_type          = each.value.instance_type
  subnet_id              = var.subnet_id
  vpc_security_group_ids = [var.security_group_ids[each.value.role]]
  iam_instance_profile   = aws_iam_instance_profile.node.name

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
  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
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
