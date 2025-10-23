terraform {
  required_version = ">= 1.10.0"
  required_providers {
    talos = {
      source  = "siderolabs/talos"
      version = "0.9.0-alpha.0"
    }
    github = {
      source  = "integrations/github"
      version = "~>6.7.0"
    }
    tls = {
      source  = "hashicorp/tls"
      version = ">=4.0"
    }
    flux = {
      source  = "fluxcd/flux"
      version = ">= 1.2"
    }
  }
}

provider "talos" {}


provider "github" {
  owner = "jwittbrodt"
}

provider "flux" {
  kubernetes = {
    host                   = talos_cluster_kubeconfig.this.kubernetes_client_configuration.host
    client_certificate     = base64decode(talos_cluster_kubeconfig.this.kubernetes_client_configuration.client_certificate)
    client_key             = base64decode(talos_cluster_kubeconfig.this.kubernetes_client_configuration.client_key)
    cluster_ca_certificate = base64decode(talos_cluster_kubeconfig.this.kubernetes_client_configuration.ca_certificate)
  }
  git = {
    url = "ssh://${replace(data.github_repository.homelab.ssh_clone_url, ":", "/")}"
    ssh = {
      username    = "git"
      private_key = tls_private_key.flux.private_key_pem
    }
  }
}
