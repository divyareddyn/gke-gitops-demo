Overview:
Terraform builds a private GKE cluster and installs Argo CD; Argo CD deploys a pinned
demo app from this repo; an HPA scales it under load; a NetworkPolicy restricts access.
