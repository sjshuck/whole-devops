resource "vultr_kubernetes" "kernel" {
  region  = local.region
  version = "v1.26.2+2"
  label   = "kernel"

  node_pools {
    node_quantity = 3
    plan          = "vc2-6c-16gb"
    label         = "kernel"
  }
}

output "kubeconfig" {
  value     = base64decode(vultr_kubernetes.kernel.kube_config)
  sensitive = true
}
