resource "helm_release" "rook-ceph" {
  name       = "rook-ceph"
  repository = "https://charts.rook.io/release"

  namespace  = "rook-ceph"
}
