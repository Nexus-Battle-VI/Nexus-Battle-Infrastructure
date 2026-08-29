terraform {
  # 1.10 y no 1.9: el bloqueo nativo del backend S3 (`use_lockfile`) aparece
  # en 1.10. Con 1.9 el backend se activa sin bloqueo y sin decirlo.
  required_version = ">= 1.10"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }

  # El bucket ya existe (`modules/tfstate`, aplicado). El orden que exigia
  # crearlo con estado local antes de declarar el backend esta cumplido.
  #
  # `use_lockfile` usa escrituras condicionales de S3 para el bloqueo: no
  # necesita DynamoDB, que ademas esta prohibida en este proyecto. Exige
  # Terraform 1.10, de ahi `required_version` arriba.
  backend "s3" {
    # El perfil va escrito a mano y no como `var.profile`: un bloque `backend`
    # se resuelve ANTES que las variables y no admite ninguna. Sin esta linea el
    # backend usa la cadena de credenciales por defecto —no la del proveedor, que
    # si lleva `profile`— y `terraform init` falla con
    # `InvalidClientTokenId: The security token included in the request is invalid`.
    #
    # El literal duplica el valor por defecto de `var.profile`. Es una duplicacion
    # aceptable: `CLAUDE.md` fija que toda invocacion del CLI use este perfil, y
    # el job de Terraform del CI corre con `init -backend=false`, asi que nunca
    # llega aqui.
    profile      = "nexus-battles"
    bucket       = "nexus-battles-vi-tfstate"
    key          = "envs/prod/terraform.tfstate"
    region       = "us-east-1"
    encrypt      = true
    use_lockfile = true
  }
}

provider "aws" {
  region  = var.region
  profile = var.profile

  default_tags {
    tags = local.tags
  }
}
