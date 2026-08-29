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
