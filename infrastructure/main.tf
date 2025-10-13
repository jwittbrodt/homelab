locals {
  ip = "192.168.178.53"
}

resource "talos_machine_secrets" "this" {}

data "talos_client_configuration" "this" {
  cluster_name         = "jw-homelab"
  client_configuration = talos_machine_secrets.this.client_configuration
  endpoints            = [local.ip]
}

data "talos_machine_configuration" "controlplane" {
  cluster_name     = data.talos_client_configuration.this.cluster_name
  cluster_endpoint = "https://${local.ip}:6443"
  machine_type     = "controlplane"
  machine_secrets  = talos_machine_secrets.this.machine_secrets
}

resource "talos_machine_configuration_apply" "controlplane" {
  client_configuration        = talos_machine_secrets.this.client_configuration
  machine_configuration_input = data.talos_machine_configuration.controlplane.machine_configuration
  node                        = local.ip
  config_patches = [
    yamlencode({
      machine = {
        install = {
          disk = "/dev/sdb"
        }
        network = {
          hostname = "${data.talos_client_configuration.this.cluster_name}-cp-1"
        }
      }
    }),
    yamlencode({
      cluster = {
        allowSchedulingOnControlPlanes = true
      }
    })
  ]
}

resource "talos_machine_bootstrap" "this" {
  node                 = talos_machine_configuration_apply.controlplane.node
  client_configuration = data.talos_client_configuration.this.client_configuration
}

resource "talos_cluster_kubeconfig" "this" {
  client_configuration = talos_machine_bootstrap.this.client_configuration
  node                 = talos_machine_bootstrap.this.node
}
