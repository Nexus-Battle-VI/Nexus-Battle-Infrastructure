# ---------------------------------------------------------------------------
# Red minima para la topologia de demo (ADR-011).
#
# Una VPC, una subred publica, una zona de disponibilidad. No hay NAT Gateway:
# esta prohibido por coste (ADR-007) y por eso las instancias necesitan IP
# publica para descargar imagenes. El coste de esas IP esta contabilizado en
# docs/costs/sprint-demo-estimate.md.
# ---------------------------------------------------------------------------

resource "aws_vpc" "this" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = merge(var.tags, { Name = "${var.name}-vpc" })
}

resource "aws_internet_gateway" "this" {
  vpc_id = aws_vpc.this.id
  tags   = merge(var.tags, { Name = "${var.name}-igw" })
}

resource "aws_subnet" "public" {
  vpc_id                  = aws_vpc.this.id
  cidr_block              = var.public_subnet_cidr
  availability_zone       = var.availability_zone
  map_public_ip_on_launch = false

  tags = merge(var.tags, { Name = "${var.name}-public" })
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.this.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.this.id
  }

  tags = merge(var.tags, { Name = "${var.name}-public" })
}

resource "aws_route_table_association" "public" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.public.id
}

# ---------------------------------------------------------------------------
# Grupo de seguridad del plano de aplicacion
# ---------------------------------------------------------------------------
resource "aws_security_group" "app" {
  name        = "${var.name}-app"
  description = "Plano sin estado: proxy inverso y servicios"
  vpc_id      = aws_vpc.this.id

  tags = merge(var.tags, { Name = "${var.name}-app" })
}

# Sin reglas de entrada, el grupo deniega todo. Es el estado por defecto: el
# sistema no esta expuesto.
resource "aws_vpc_security_group_ingress_rule" "app_https" {
  for_each = toset(var.public_ingress_cidrs)

  security_group_id = aws_security_group.app.id
  description       = "HTTPS desde origen autorizado"
  cidr_ipv4         = each.value
  from_port         = 443
  to_port           = 443
  ip_protocol       = "tcp"
}

/**
 * El puerto 80 se abre a TODO INTERNET, y es deliberado.
 *
 * Let's Encrypt valida el reto HTTP-01 desde muchos puntos del mundo y **no
 * publica sus direcciones**; su documentacion desaconseja expresamente filtrar
 * por origen, porque cambian sin aviso. Una lista de CIDR en este puerto no
 * dejaria emitir el certificado: no es que fuera mas estricta, es que no
 * funcionaria.
 *
 * Lo que queda expuesto ahi es minimo: el proxy solo sirve en 80 el reto de ACME
 * y una redireccion a HTTPS. Todo lo demas vive en 443, donde SI se aplica
 * `public_ingress_cidrs`.
 *
 * Se abre unicamente cuando hay un sitio publico configurado. Sin dominio no hay
 * certificado que pedir, y entonces este puerto no tiene ningun motivo para
 * estar abierto.
 *
 * La alternativa que evitaria abrirlo es el reto DNS-01, que demuestra el
 * control del dominio con un registro TXT y no necesita conexion entrante. Exige
 * un Caddy con el modulo DNS del registrador compilado dentro -la imagen oficial
 * no lo trae- y credenciales de la API del registrador guardadas en el nodo. Es
 * mas superficie de secreto para quitar un puerto que solo sirve redirecciones.
 */
resource "aws_vpc_security_group_ingress_rule" "app_acme" {
  count = var.acme_enabled ? 1 : 0

  security_group_id = aws_security_group.app.id
  description       = "HTTP abierto para el reto ACME de Let's Encrypt, que valida desde origenes no publicados"
  cidr_ipv4         = "0.0.0.0/0"
  from_port         = 80
  to_port           = 80
  ip_protocol       = "tcp"
}

# No se abre el puerto 22. El acceso administrativo va por SSM Session Manager,
# que no necesita puerto abierto, ni par de claves, ni bastion.
resource "aws_vpc_security_group_egress_rule" "app_all" {
  security_group_id = aws_security_group.app.id
  description       = "Salida libre: descarga de imagenes de GHCR y acceso a SSM"
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1"
}

# ---------------------------------------------------------------------------
# Grupo de seguridad del plano de datos
#
# Sin ninguna regla de entrada desde internet. Los motores solo aceptan
# conexiones del grupo de seguridad de aplicacion, no de un rango de IP: si el
# nodo de aplicacion se recrea y cambia de direccion, la regla sigue siendo
# correcta.
# ---------------------------------------------------------------------------
resource "aws_security_group" "data" {
  name        = "${var.name}-data"
  description = "Plano con estado: PostgreSQL y MongoDB"
  vpc_id      = aws_vpc.this.id

  tags = merge(var.tags, { Name = "${var.name}-data" })
}

resource "aws_vpc_security_group_ingress_rule" "data_postgres" {
  security_group_id            = aws_security_group.data.id
  description                  = "PostgreSQL solo desde el plano de aplicacion"
  referenced_security_group_id = aws_security_group.app.id
  from_port                    = 5432
  to_port                      = 5432
  ip_protocol                  = "tcp"
}

resource "aws_vpc_security_group_ingress_rule" "data_mongo" {
  security_group_id            = aws_security_group.data.id
  description                  = "MongoDB solo desde el plano de aplicacion"
  referenced_security_group_id = aws_security_group.app.id
  from_port                    = 27017
  to_port                      = 27017
  ip_protocol                  = "tcp"
}

resource "aws_vpc_security_group_egress_rule" "data_all" {
  security_group_id = aws_security_group.data.id
  description       = "Salida libre: descarga de imagenes y acceso a SSM"
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1"
}
