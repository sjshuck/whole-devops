resource "kubernetes_namespace_v1" "rook-ceph" {
  metadata {
    name = "rook-ceph"
    labels = {
      name = "rook-ceph"
    }
  }
}

locals {
  rook-ceph-block-dev = "/dev/loop5" // steer clear of whatever VKE wants to do

  rook-ceph-host-setup-mounts = {
    // loop device's backing image in here
    var-local = "/var/local"

    // strace(1) reports that losetup(8) touches things in here
    dev = "/dev"
    sys = "/sys"
  }
}

resource "kubernetes_job_v1" "rook-ceph-host-setup" {
  metadata {
    name      = "host-setup"
    namespace = kubernetes_namespace_v1.rook-ceph.metadata[0].name
  }

  spec {
    parallelism = 3

    template {
      metadata {}
      spec {
        topology_spread_constraint {
          topology_key       = "kubernetes.io/hostname"
          when_unsatisfiable = "DoNotSchedule"
        }

        container {
          image = "ubuntu:jammy"
          name  = "host-setup"

          security_context {
            privileged = true
          }

          env {
            name  = "BLOCK_DEV"
            value = local.rook-ceph-block-dev
          }

          command = ["/bin/bash"]
          args = [
            "-c", <<-SETUP
              set -ex -o pipefail

              data_img=/var/local/data.img
              fallocate -l 200G "$data_img"
              loop_dev="$(losetup -j "$data_img")"
              if [[ ! $loop_dev ]]; then
                  losetup --direct-io=on "$BLOCK_DEV" "$data_img"
              fi
            SETUP
          ]

          dynamic "volume_mount" {
            for_each = local.rook-ceph-host-setup-mounts
            content {
              name       = volume_mount.key
              mount_path = volume_mount.value
            }
          }
        }

        dynamic "volume" {
          for_each = local.rook-ceph-host-setup-mounts
          content {
            name = volume.key
            host_path {
              path = volume.value
              type = "Directory"
            }
          }
        }
      }
    }
  }
}

resource "helm_release" "rook-ceph-operator" {
  repository = "https://charts.rook.io/release"
  chart      = "rook-ceph"
  version    = local.rook-ceph-version

  name      = "rook-ceph-operator"
  namespace = kubernetes_namespace_v1.rook-ceph.metadata[0].name
  values    = [yamlencode({
    allowLoopDevices = true
  })]
}

resource "helm_release" "rook-ceph-cluster" {
  repository = "https://charts.rook.io/release"
  chart      = "rook-ceph-cluster"
  version    = local.rook-ceph-version

  name      = "rook-ceph-cluster"
  namespace = kubernetes_namespace_v1.rook-ceph.metadata[0].name
  values = [yamlencode({
    cephClusterSpec = {
      cephVersion = {
        image = "quay.io/ceph/ceph:${local.ceph-version}"
      }

      // TODO I'm not sure if this is used for actual user data.  Doubtful but
      // needs confirmation.
      // If yes, then we likely have to set up the VKE nodes after phase 1, and
      // also think about cleanup operations in the event of recreating the
      // cluster.
      // If no, then we should leave this value blank, which means emptyDir
      // instead of hostPath.
      dataDirHostPath = "/var/lib/rook"

      waitTimeoutForHealthyOSDInMinutes = 10

      mon = {
        count                = 3
        allowMultiplePerNode = false
      }
      mgr = {
        count = 2
        modules = [{
          name    = "pg_autoscaler"
          enabled = true
        }]
      }
      dashboard = {
        enabled = true
        ssl     = true
      }
      logCollector = {
        enabled     = true
        periodicity = "daily"
        maxLogSize  = "500M"
      }
      resources = {
        mgr = {
          requests = { cpu = "500m", memory = "512Mi" }
          limits   = { cpu = "1000m", memory = "1Gi" }
        }
        mon = {
          requests = { cpu = "1000m", memory = "1Gi" }
          limits   = { cpu = "2000m", memory = "2Gi" }
        }
        osd = {
          requests = { cpu = "1000m", memory = "4Gi" }
          limits   = { cpu = "2000m", memory = "4Gi" }
        }
        prepareosd = {
          requests = { cpu = "500m", memory = "50Mi" }
          // No limits so we avoid OOM kill
        }
        mgr-sidecar = {
          requests = { cpu = "100m", memory = "40Mi" }
          limits   = { cpu = "500m", memory = "100Mi" }
        }
        crashcollector = {
          requests = { cpu = "100m", memory = "60Mi" }
          limits   = { cpu = "500m", memory = "60Mi" }
        }
        logcollector = {
          requests = { cpu = "100m", memory = "100Mi" }
          limits   = { cpu = "500m", memory = "1Gi" }
        }
        cleanup = {
          requests = { cpu = "500m", memory = "100Mi" }
          limits   = { cpu = "500m", memory = "1Gi" }
        }
      }
      priorityClassNames = {
        mon = "system-node-critical"
        osd = "system-node-critical"
        mgr = "system-cluster-critical"
      }
      storage = {
        useAllNodes      = true
        devicePathFilter = "^\\Q${local.rook-ceph-block-dev}\\E$" // RE2 literal
      }
      disruptionManagement = {
        managePodBudgets = true
      }
      healthCheck = {
        daemonHealth = {
          mon    = { interval = "45s" }
          osd    = { interval = "60s" }
          status = { interval = "60s" }
        }
      }
    }

    ingress = {
      dashboard = {}
    }

    cephFileSystems = [{
      name = "kernel"
      spec = {
        metadataPool = {
          failureDomain = "host"
          replicated = {
            size = 3
          }
        }
        dataPools = [{
          name          = "data0"
          failureDomain = "host"
          replicated = {
            size = 3
          }
        }]
        preserveFilesystemOnDelete = true
        metadataServer = {
          activeCount   = 1
          activeStandby = true
        }
      }
      storageClass = {
        enabled = false
      }
    }]

    cephBlockPools   = []
    cephObjectStores = []
  })]

  depends_on = [
    helm_release.rook-ceph-operator,
    kubernetes_job_v1.rook-ceph-host-setup,
  ]
}
