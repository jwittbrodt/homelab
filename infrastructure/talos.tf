locals {
  local_subnet = "192.168.178.0/24"
  node_config = {
    201 = {
      is_controlplane = true
    }
    202 = {
      is_controlplane = true
    }
    203 = {
      is_controlplane = true
    }
    204 = {
      is_controlplane = false
    }
  }

  nodes = { for hostnum, node in local.node_config : hostnum => merge(node, { "ip" = cidrhost(local.local_subnet, hostnum) }) }

  controlplane_vip = cidrhost(local.local_subnet, 200)
  cluster_endpoint = "https://${local.controlplane_vip}:6443"
}

resource "talos_machine_secrets" "this" {}

data "talos_client_configuration" "this" {
  cluster_name         = "jw-homelab"
  client_configuration = talos_machine_secrets.this.client_configuration
  endpoints            = [for num, node in local.nodes : node.ip if node.is_controlplane]
}

data "talos_machine_configuration" "controlplane" {
  cluster_name     = data.talos_client_configuration.this.cluster_name
  cluster_endpoint = local.cluster_endpoint
  machine_type     = "controlplane"
  machine_secrets  = talos_machine_secrets.this.machine_secrets
}

data "talos_machine_configuration" "worker" {
  cluster_name     = data.talos_client_configuration.this.cluster_name
  cluster_endpoint = local.cluster_endpoint
  machine_type     = "worker"
  machine_secrets  = talos_machine_secrets.this.machine_secrets
}

locals {
  controlplane_config_patches = [
    yamlencode({
      cluster = {
        allowSchedulingOnControlPlanes = true
      }
      machine = {
        nodeLabels = {
          "node.kubernetes.io/exclude-from-external-load-balancers" = {
            "$patch" = "delete"
          }
        }
      }
    }),
    yamlencode({
      machine = {
        network = {
          interfaces = [
            {
              interface = "enp1s0"
              dhcp      = true
              vip = {
                ip = local.controlplane_vip
              }
            }
          ]
        }
      }
    })
  ]
  worker_config_patches = []
  kubeproxy_strict_arp_for_metallb = yamlencode({
    cluster = {
      proxy = {
        mode = "ipvs"
        extraArgs = {
          "ipvs-strict-arp" = true
        }
      }
    }
  })
}

resource "talos_machine_configuration_apply" "nodes" {
  for_each = local.nodes

  client_configuration        = talos_machine_secrets.this.client_configuration
  machine_configuration_input = each.value.is_controlplane ? data.talos_machine_configuration.controlplane.machine_configuration : data.talos_machine_configuration.worker.machine_configuration
  node                        = each.value.ip
  config_patches = concat([yamlencode(
    {
      machine = {
        install = {
          disk = lookup(each.value, "install_disk", "/dev/sdb")
        }
        network = {
          hostname = join("-", compact([data.talos_client_configuration.this.cluster_name, each.value.is_controlplane ? "cp" : "", each.key]))
        }
      }
    }), local.kubeproxy_strict_arp_for_metallb],
  each.value.is_controlplane ? local.controlplane_config_patches : local.worker_config_patches)
}


resource "talos_machine_bootstrap" "this" {
  node                 = talos_machine_configuration_apply.nodes[201].node
  client_configuration = data.talos_client_configuration.this.client_configuration
}

resource "talos_cluster_kubeconfig" "this" {
  client_configuration = talos_machine_bootstrap.this.client_configuration
  node                 = local.controlplane_vip
  endpoint             = local.controlplane_vip

  lifecycle {
    replace_triggered_by = [talos_machine_configuration_apply.nodes]
  }
}

data "talos_cluster_health" "this" {
  client_configuration = talos_machine_bootstrap.this.client_configuration
  control_plane_nodes  = [for num, node in local.nodes : node.ip if node.is_controlplane]
  worker_nodes         = [for num, node in local.nodes : node.ip if !node.is_controlplane]
  endpoints            = [talos_cluster_kubeconfig.this.endpoint]
}
