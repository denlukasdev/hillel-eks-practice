terraform {
  required_version = ">= 1.9"

  # Блок cloud підключає воркспейс у HCP Terraform.
  # Замініть ОРГАНІЗАЦІЯ на ім'я своєї організації.
  # Якщо працюєте локально зі станом у файлі — закоментуйте весь блок cloud.
  cloud {
    organization = "lukasdev_devops"

    workspaces {
      tags = ["hillel-eks"]
    }
  }

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }

    # Знадобиться, коли ви скопіюєте сюди файли з lessons/09-flux.
    # Поки ресурсів helm немає, провайдер лише завантажується під час init
    # і більше нічого не робить.
    helm = {
      source  = "hashicorp/helm"
      version = "~> 3.0"
    }
  }
}

provider "aws" {
  region = var.region

  default_tags {
    tags = local.common_tags
  }
}
