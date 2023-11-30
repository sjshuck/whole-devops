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
  #region = "ewr" // Newark
  region = "lax"

  vke-version       = "v1.28.3+2"
  vault-version     = "1.15.2"
  consul-version    = "1.17.0"
  rook-ceph-version = "v1.12.8"
  ceph-version      = "v18.2.0"
}
