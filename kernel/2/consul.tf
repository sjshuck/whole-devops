resource "kubernetes_namespace_v1" "consul" {
  metadata {
    name = "consul"
    labels = {
      name = "consul"
    }
  }
}

# PodDisruptionBudget to prevent degrading the server cluster through
# voluntary cluster changes.
resource "kubernetes_pod_disruption_budget_v1" "consul" {
  metadata {
    name      = "consul"
    namespace = kubernetes_namespace_v1.consul.metadata[0].name
    labels = {
      app       = "consul"
      component = "server"
    }
  }

  spec {
    max_unavailable = 0
    selector {
      match_labels = {
        app       = "consul"
        component = "server"
      }
    }
  }
}

resource "kubernetes_service_account_v1" "consul" {
  metadata {
    name      = "consul"
    namespace = kubernetes_namespace_v1.consul.metadata[0].name
    labels = {
      app       = "consul"
      component = "server"
    }
  }
}

resource "kubernetes_config_map_v1" "consul-config" {
  metadata {
    name      = "consul-config"
    namespace = kubernetes_namespace_v1.consul.metadata[0].name
    labels = {
      app       = "consul"
      component = "server"
    }
  }

  data = {
    "server.json" = jsonencode({
      bind_addr        = "0.0.0.0"
      bootstrap_expect = 3
      client_addr      = "0.0.0.0"
      connect = {
        enabled = true
      }
      datacenter = "dc1"
      data_dir   = "/consul/data"
      domain     = "consul"
      ports = {
        grpc     = 8502
        grpc_tls = -1
        serf_lan = 8301
      }
      recursors  = []
      retry_join = ["consul-server.consul.svc.cluster.local:8301"]
      server     = true
    })

    "extra-from-values.json" = jsonencode({})

    "ui-config.json" = jsonencode({
      ui_config = {
        enabled = true
      }
    })

    "central-config.json" = jsonencode({
      enable_central_service_config = true
    })
  }
}

resource "kubernetes_service_v1" "consul-dns" {
  metadata {
    name      = "consul-dns"
    namespace = kubernetes_namespace_v1.consul.metadata[0].name
    labels = {
      app       = "consul"
      component = "dns"
    }
  }

  spec {
    selector = {
      app    = "consul"
      hasDNS = "true"
    }

    type = "ClusterIP"
    port {
      name        = "dns-tcp"
      port        = 53
      protocol    = "TCP"
      target_port = "dns-tcp"
    }
    port {
      name        = "dns-udp"
      port        = 53
      protocol    = "UDP"
      target_port = "dns-udp"
    }
  }
}

resource "kubernetes_service_v1" "consul-server" {
  metadata {
    name      = "consul-server"
    namespace = kubernetes_namespace_v1.consul.metadata[0].name
    labels = {
      app       = "consul"
      component = "server"
    }
  }

  spec {
    selector = {
      app       = "consul"
      component = "server"
    }

    cluster_ip                  = "None"
    publish_not_ready_addresses = true

    dynamic "port" {
      for_each = {
        http        = { port = 8500 }
        grpc        = { port = 8502 }
        serflan-tcp = { port = 8301 }
        serflan-udp = { port = 8301, protocol = "UDP" }
        serfwan-tcp = { port = 8302 }
        serfwan-udp = { port = 8302, protocol = "UDP" }
        server      = { port = 8300 }
        dns-tcp     = { port = 8600 }
        dns-udp     = { port = 8600, protocol = "UDP" }
      }
      content {
        name     = port.key
        port     = port.value.port
        protocol = lookup(port.value, "protocol", "TCP")
      }
    }
  }
}

resource "kubernetes_service_v1" "consul-ui" {
  metadata {
    name      = "consul-ui"
    namespace = kubernetes_namespace_v1.consul.metadata[0].name
    labels = {
      app       = "consul"
      component = "ui"
    }
  }

  spec {
    selector = {
      app       = "consul"
      component = "server"
    }

    port {
      name        = "http"
      port        = 80
      target_port = 8500
    }
  }
}

resource "kubernetes_stateful_set_v1" "consul" {
  metadata {
    name      = "consul"
    namespace = kubernetes_namespace_v1.consul.metadata[0].name
    labels = {
      app       = "consul"
      component = "server"
    }
  }

  spec {
    selector {
      match_labels = {
        app       = "consul"
        component = "server"
        hasDNS    = "true"
      }
    }

    service_name          = kubernetes_service_v1.consul-server.metadata[0].name
    pod_management_policy = "Parallel"
    replicas              = 3

    template {
      metadata {
        labels = {
          app       = "consul"
          component = "server"
          hasDNS    = "true"
        }
        annotations = {
          "consul.hashicorp.com/connect-inject" = "false"
        }
      }

      spec {
        affinity {
          pod_anti_affinity {
            required_during_scheduling_ignored_during_execution {
              label_selector {
                match_labels = {
                  app       = "consul"
                  component = "server"
                }
              }
              topology_key = "kubernetes.io/hostname"
            }
          }
        }

        termination_grace_period_seconds = 30
        service_account_name             = kubernetes_service_account_v1.consul.metadata[0].name
        security_context {
          fs_group        = 1000
          run_as_group    = 1000
          run_as_non_root = true
          run_as_user     = 100
        }

        volume {
          name = "config"
          config_map {
            name = kubernetes_config_map_v1.consul-config.metadata[0].name
          }
        }
        volume {
          name = "extra-config"
          empty_dir {}
        }

        container {
          name  = "consul"
          image = "hashicorp/consul:${local.consul-version}"

          dynamic "env" {
            for_each = {
              ADVERTISE_IP = "status.podIP"
              POD_IP       = "status.podIP"
              HOST_IP      = "status.hostIP"
            }
            content {
              name = env.key
              value_from {
                field_ref {
                  field_path = env.value
                }
              }
            }
          }

          env {
            name  = "CONSUL_DISABLE_PERM_MGMT"
            value = "1"
          }

          command = [
            "/bin/sh", "-ec", <<-COMMAND
              cp /consul/config/extra-from-values.json /consul/extra-config/extra-from-values.json
              [ -n "$${HOST_IP}" ] && sed -Ei "s|HOST_IP|$${HOST_IP?}|g" /consul/extra-config/extra-from-values.json
              [ -n "$${POD_IP}" ] && sed -Ei "s|POD_IP|$${POD_IP?}|g" /consul/extra-config/extra-from-values.json
              [ -n "$${HOSTNAME}" ] && sed -Ei "s|HOSTNAME|$${HOSTNAME?}|g" /consul/extra-config/extra-from-values.json

              exec /usr/local/bin/docker-entrypoint.sh consul agent \
                  -advertise="$${ADVERTISE_IP}" \
                  -config-dir=/consul/config \
                  -config-file=/consul/extra-config/extra-from-values.json ||
                  sleep 100000
            COMMAND
          ]

          dynamic "volume_mount" {
            for_each = {
              data-default = "/consul/data"
              config       = "/consul/config"
              extra-config = "/consul/extra-config"
            }
            content {
              name       = volume_mount.key
              mount_path = volume_mount.value
            }
          }

          dynamic "port" {
            for_each = kubernetes_service_v1.consul-server.spec[0].port

            content {
              name           = port.value.name
              container_port = port.value.port
              protocol       = port.value.protocol
            }
          }

          readiness_probe {
            exec {
              command = [
                "/bin/sh", "-ec", <<-PROBE
                  curl http://127.0.0.1:8500/v1/status/leader 2>/dev/null |
                    grep -E '".+"'
                PROBE
              ]
            }
            failure_threshold     = 2
            initial_delay_seconds = 5
            period_seconds        = 3
            success_threshold     = 1
            timeout_seconds       = 5
          }

          resources {
            limits = {
              cpu    = "100m"
              memory = "128Mi"
            }
            requests = {
              cpu    = "100m"
              memory = "128Mi"
            }
          }
        }
      }
    }

    volume_claim_template {
      metadata {
        name = "data-default"
      }

      spec {
        access_modes = toset(["ReadWriteOnce"])
        resources {
          requests = {
            storage = "10Gi" // minimum allowed by Kubernetes
          }
        }
      }
    }
  }
}
