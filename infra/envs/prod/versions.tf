terraform {
  required_version = ">= 1.9"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }

  # Estado local por ahora. El backend S3 con bloqueo esta descrito en
  # infra/README.md y se activa cuando exista el bucket: crearlo requiere una
  # primera aplicacion con estado local, y ese orden hay que respetarlo.
  #
  # backend "s3" {
  #   bucket       = "nexus-battles-vi-tfstate"
  #   key          = "envs/prod/terraform.tfstate"
  #   region       = "us-east-1"
  #   encrypt      = true
  #   use_lockfile = true
  # }
}

provider "aws" {
  region  = var.region
  profile = var.profile

  default_tags {
    tags = local.tags
  }
}
