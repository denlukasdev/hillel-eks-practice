# ---------------------------------------------------------------------------
# Заняття 12. Flux розгортає чарт із ECR.
#
# Дві частини:
#   1) доступ source-controller до приватного реєстру — роль через Pod Identity;
#   2) третя синхронізація Flux — для теки apps/shop-release.
# ---------------------------------------------------------------------------

# --- 1. Доступ Flux до ECR --------------------------------------------------
#
# Чарт із приватного реєстру тягне source-controller. Роль вузла тут не
# допоможе: поди не мають доступу до метаданих вузла (hop limit = 1).
# Тому — та сама Pod Identity, що в LBC та ESO, і та сама політика довіри
# pod_identity_trust із platform-iam.tf.
resource "aws_iam_role" "flux_source" {
  name               = "${var.prefix}-flux-source"
  assume_role_policy = data.aws_iam_policy_document.pod_identity_trust.json

  tags = local.common_tags
}

# Готова політика AWS: лише читання з ECR.
resource "aws_iam_role_policy_attachment" "flux_source_ecr" {
  role       = aws_iam_role.flux_source.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
}

# УВАГА: под отримує облікові дані лише на старті. source-controller уже
# працює, тому після apply його треба перезапустити:
#   kubectl rollout restart deployment/source-controller -n flux-system
resource "aws_eks_pod_identity_association" "flux_source" {
  cluster_name    = module.eks.cluster_name
  namespace       = "flux-system"
  service_account = "source-controller"
  role_arn        = aws_iam_role.flux_source.arn

  tags = local.common_tags
}

# --- 2. Синхронізація для теки apps/shop-release ---------------------------
#
# Той самий патерн, що infra-sync на занятті 10: Terraform знає адресу
# реєстру (у ній номер акаунта) і передає її у Flux, а Flux підставляє її
# в маніфести на місце ${ECR_REGISTRY}.
resource "helm_release" "release_sync" {
  name       = "release-sync"
  repository = "https://fluxcd-community.github.io/helm-charts"
  chart      = "flux2-sync"
  version    = "1.15.1"
  namespace  = "flux-system"

  depends_on = [
    helm_release.infra_sync,
    aws_eks_pod_identity_association.flux_source,
  ]

  values = [yamlencode({
    gitRepository = {
      spec = {
        url      = var.git_url
        interval = var.sync_interval
        ref = {
          branch = var.git_branch
        }
      }
    }

    kustomization = {
      spec = {
        path     = "./apps/shop-release"
        interval = var.sync_interval
        prune    = true

        # Чарт містить ExternalSecret — потрібен оператор з infrastructure/.
        dependsOn = [
          { name = "infra-sync" }
        ]

        postBuild = {
          substitute = {
            ECR_REGISTRY = local.ecr_registry
          }
        }
      }
    }
  })]
}
