terraform {
  required_providers {
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

resource "vultr_kubernetes" "kernel" {
  region  = local.region
  version = "v1.26.2+2"
  label   = "kernel"

  node_pools {
    node_quantity = 3
    plan          = "vc2-2c-4gb"
    label         = "kernel"
  }
}

output "kubeconfig" {
  value     = base64decode(vultr_kubernetes.kernel.kube_config)
  sensitive = true
}
