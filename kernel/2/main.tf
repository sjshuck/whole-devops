terraform {
  required_providers {
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.18"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.9"
    }
  }

  backend "local" {}
}

provider "kubernetes" {
  config_path = "../kubeconfig.yaml"
}

provider "helm" {
  kubernetes {
    config_path = "../kubeconfig.yaml"
  }
}
