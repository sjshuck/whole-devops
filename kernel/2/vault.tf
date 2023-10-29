resource "kubernetes_namespace_v1" "vault" {
  metadata {
    name = "vault"
    labels = {
      name = "vault"
    }
  }
}

resource "kubernetes_service_account_v1" "vault" {
  metadata {
    name      = "vault"
    namespace = kubernetes_namespace_v1.vault.metadata[0].name
    labels = {
      name = "vault"
    }
  }
}

resource "kubernetes_config_map_v1" "vault-config" {
  metadata {
    name      = "vault-config"
    namespace = kubernetes_namespace_v1.vault.metadata[0].name
    labels = {
      name = "vault"
    }
  }

  data = {
    "extraconfig-from-values.json" = jsonencode({
      disable_mlock = true
      ui            = true

      listener = [{ tcp = {
        tls_disable     = 1
        address         = "[::]:8200"
        cluster_address = "[::]:8201"
      } }]

      // 2023-03-24T16:31:30.518Z [WARN]  service_registration.consul: check unable to talk with Consul backend: error="Unexpected response code: 404 (Unknown check ID \"vault:10.244.93.64:8200:vault-sealed-check\". Ensure that the check ID is passed, not the check name.)"
      storage = [{ consul = {
        address = "consul-server.consul.svc.cluster.local:8500"
        path    = "kernel/vault/"
      } }]
    })
  }
}

resource "kubernetes_cluster_role_binding_v1" "vault" {
  metadata {
    name = "vault"
    labels = {
      name = "vault"
    }
  }

  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "ClusterRole"
    name      = "system:auth-delegator"
  }

  subject {
    kind      = "ServiceAccount"
    name      = kubernetes_service_account_v1.vault.metadata[0].name
    namespace = kubernetes_namespace_v1.vault.metadata[0].name
  }
}

resource "kubernetes_service_v1" "vault-internal" {
  metadata {
    name      = "vault-internal"
    namespace = kubernetes_namespace_v1.vault.metadata[0].name
    labels = {
      name           = "vault"
      vault-internal = "true"
    }
  }

  spec {
    cluster_ip                  = "None"
    publish_not_ready_addresses = true

    port {
      name = "http"
      port = 8200
    }
    port {
      name = "https-internal"
      port = 8201
    }

    selector = {
      name      = "vault"
      component = "server"
    }
  }
}

resource "kubernetes_service_v1" "vault" {
  metadata {
    name      = "vault"
    namespace = kubernetes_namespace_v1.vault.metadata[0].name
    labels = {
      name = "vault"
    }
  }

  spec {
    publish_not_ready_addresses = true

    port {
      name = "http"
      port = 8200
    }
    port {
      name = "https-internal"
      port = 8201
    }

    selector = {
      name      = "vault"
      component = "server"
    }
  }
}

resource "kubernetes_stateful_set_v1" "vault" {
  metadata {
    name      = "vault"
    namespace = kubernetes_namespace_v1.vault.metadata[0].name
    labels = {
      name = "vault"
    }
  }

  spec {
    service_name          = kubernetes_service_v1.vault-internal.metadata[0].name
    pod_management_policy = "Parallel"
    replicas              = 2
    update_strategy {
      type = "OnDelete"
    }

    selector {
      match_labels = {
        name      = "vault"
        component = "server"
      }
    }

    template {
      metadata {
        labels = {
          name      = "vault"
          component = "server"
        }
      }

      spec {
        affinity {
          pod_anti_affinity {
            required_during_scheduling_ignored_during_execution {
              label_selector {
                match_labels = {
                  name      = "vault"
                  component = "server"
                }
              }
              topology_key = "kubernetes.io/hostname"
            }
          }
        }
        termination_grace_period_seconds = 10
        service_account_name             = kubernetes_service_account_v1.vault.metadata[0].name

        security_context {
          run_as_non_root = true
          run_as_group    = 1000
          run_as_user     = 100
          fs_group        = 1000
        }

        host_network = false

        volume {
          name = "config"
          config_map {
            name = "vault-config"
          }
        }
        volume {
          name = "home"
          empty_dir {}
        }

        container {
          name              = "vault"
          image             = "hashicorp/vault:${local.vault-version}"
          image_pull_policy = "IfNotPresent"

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

          command = ["/bin/sh", "-ec"]
          args = [
            <<-COMMAND
              cp /vault/config/extraconfig-from-values.json /tmp/storageconfig.json;
              [ -n "$${HOST_IP}" ] && sed -Ei "s|HOST_IP|$${HOST_IP?}|g" /tmp/storageconfig.json;
              [ -n "$${POD_IP}" ] && sed -Ei "s|POD_IP|$${POD_IP?}|g" /tmp/storageconfig.json;
              [ -n "$${HOSTNAME}" ] && sed -Ei "s|HOSTNAME|$${HOSTNAME?}|g" /tmp/storageconfig.json;
              [ -n "$${API_ADDR}" ] && sed -Ei "s|API_ADDR|$${API_ADDR?}|g" /tmp/storageconfig.json;
              [ -n "$${TRANSIT_ADDR}" ] && sed -Ei "s|TRANSIT_ADDR|$${TRANSIT_ADDR?}|g" /tmp/storageconfig.json;
              [ -n "$${RAFT_ADDR}" ] && sed -Ei "s|RAFT_ADDR|$${RAFT_ADDR?}|g" /tmp/storageconfig.json;
              /usr/local/bin/docker-entrypoint.sh vault server -config=/tmp/storageconfig.json
            COMMAND
          ]

          security_context {
            allow_privilege_escalation = false
          }

          dynamic "env" {
            for_each = {
              HOST_IP             = "status.hostIP"
              POD_IP              = "status.podIP"
              VAULT_K8S_POD_NAME  = "metadata.name"
              HOSTNAME            = "metadata.name"
              VAULT_K8S_NAMESPACE = "metadata.namespace"
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
          dynamic "env" {
            for_each = {
              VAULT_ADDR         = "https://127.0.0.1:8200"
              VAULT_API_ADDR     = "http://$(POD_IP):8200"
              SKIP_CHOWN         = "true"
              SKIP_SETCAP        = "true"
              VAULT_CLUSTER_ADDR = "https://$(HOSTNAME).vault-internal:8201"
              HOME               = "/home/vault"
            }
            content {
              name  = env.key
              value = env.value
            }
          }

          volume_mount {
            name       = "config"
            mount_path = "/vault/config"
          }
          volume_mount {
            name       = "home"
            mount_path = "/home/vault"
          }

          dynamic "port" {
            for_each = {
              http           = 8200
              https-internal = 8201
              http-rep       = 8202
            }
            content {
              name           = port.key
              container_port = port.value
            }
          }

          readiness_probe {
            exec {
              command = [
                "/bin/sh", "-c", <<-PROBE
                  vault status -address=http://localhost:8200
                PROBE
              ]
            }
            failure_threshold     = 2
            initial_delay_seconds = 5
            period_seconds        = 5
            success_threshold     = 1
            timeout_seconds       = 3
          }

          lifecycle {
            # Vault container doesn't receive SIGTERM from Kubernetes
            # and after the grace period ends, Kube sends SIGKILL.  This
            # causes issues with graceful shutdowns such as deregistering itself
            # from Consul (zombie services).
            pre_stop {
              exec {
                command = [
                  # Adding a sleep here to give the pod eviction a
                  # chance to propagate, so requests will not be made
                  # to this pod while it's terminating
                  "/bin/sh", "-c", <<-COMMAND
                    sleep 5 && kill -SIGTERM $(pidof vault)
                  COMMAND
                ]
              }
            }
          }
        }
      }
    }
  }

  // This is needed for a couple reasons.
  // 1. "kubectl rollout" does not support updateStrategy: OnDelete, and
  // 2. We need to initialize Vault before healthcheck can pass
  wait_for_rollout = false
}
