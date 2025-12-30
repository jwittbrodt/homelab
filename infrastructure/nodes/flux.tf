data "github_repository" "homelab" {
  full_name = "jwittbrodt/homelab"
}

resource "tls_private_key" "flux" {
  algorithm = "ED25519"
}

resource "github_repository_deploy_key" "flux" {
  title      = "flux deploy key"
  repository = data.github_repository.homelab.name
  key        = tls_private_key.flux.public_key_openssh
  read_only  = false
}

resource "flux_bootstrap_git" "this" {
  depends_on = [github_repository_deploy_key.flux, data.talos_cluster_health.this]

  embedded_manifests = true
  path               = "manifests"
}
