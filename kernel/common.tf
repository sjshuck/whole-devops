terraform {
  required_providers {
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.9"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.18"
    }
    vultr = {
      source  = "vultr/vultr"
      version = "~> 2.14"
    }
  }

  backend "local" {}
}

locals {
  region = "ewr" // Newark
}
