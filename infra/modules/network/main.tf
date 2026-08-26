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

# No se declara ninguna regla de entrada cuando la lista esta vacia. Sin reglas,
# el grupo deniega todo el trafico entrante: es el comportamiento correcto
# mientras el BLOCKER de identidad siga abierto.
resource "aws_vpc_security_group_ingress_rule" "app_https" {
  for_each = toset(var.public_ingress_cidrs)

  security_group_id = aws_security_group.app.id
  description       = "HTTPS desde origen autorizado"
  cidr_ipv4         = each.value
  from_port         = 443
  to_port           = 443
  ip_protocol       = "tcp"
}

resource "aws_vpc_security_group_ingress_rule" "app_http" {
  for_each = toset(var.public_ingress_cidrs)

  security_group_id = aws_security_group.app.id
  description       = "HTTP desde origen autorizado, solo para el reto ACME de Let's Encrypt"
  cidr_ipv4         = each.value
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
