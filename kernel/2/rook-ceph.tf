resource "kubernetes_namespace_v1" "rook-ceph" {
  metadata {
    name = "rook-ceph"
    labels = {
      name = "rook-ceph"
    }
  }
}

resource "helm_release" "rook-ceph" {
  repository = "https://charts.rook.io/release"
  chart      = "rook-ceph"
  version    = "v1.11.4"

  name      = "rook-ceph"
  namespace = kubernetes_namespace_v1.rook-ceph.metadata[0].name
  values = [yamlencode({
  })]
}
