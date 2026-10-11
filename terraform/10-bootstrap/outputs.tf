output "argocd_chart_version" {
  value = helm_release.argocd.version
}

output "watched_repo" {
  value = "${var.repo_url} @ ${var.target_revision} : ${var.app_path}"
}

output "argocd_ui" {
  value = "kubectl -n argocd port-forward svc/argocd-server 8080:80   # then Cloud Shell 'Web Preview' -> port 8080"
}
