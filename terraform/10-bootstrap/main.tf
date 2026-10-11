# 1) Install Argo CD (controller + CRDs) from the official Helm chart, pinned.
resource "helm_release" "argocd" {
  name             = "argocd"
  repository       = "https://argoproj.github.io/argo-helm"
  chart            = "argo-cd"
  version          = var.argocd_chart_version
  namespace        = "argocd"
  create_namespace = true
  wait             = true
  timeout          = 900
  values           = [file("${path.module}/values/argocd.yaml")]
}

# 2) Register ONE AppProject + ONE Application pointing at our Git repo.
#    Uses a tiny local chart (./charts/root-app) so Terraform never needs the
#    Argo CD CRDs at plan time. After this, Argo CD — not Terraform, not
#    kubectl — deploys everything under gitops/apps/podinfo.
resource "helm_release" "root_app" {
  name      = "root-app"
  chart     = "${path.module}/charts/root-app"
  namespace = "argocd"
  wait      = true

  values = [yamlencode({
    repoURL        = var.repo_url
    targetRevision = var.target_revision
    path           = var.app_path
  })]

  depends_on = [helm_release.argocd]
}
