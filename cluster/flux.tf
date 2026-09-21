# ---------------------------------------------------------------------------
# Заняття 9. Скопіюйте цей файл у теку cluster/ разом із kubernetes-providers.tf.
# Потім додайте у terraform.tfvars рядок git_url з адресою свого форку.
# ---------------------------------------------------------------------------

variable "git_url" {
  description = <<-EOT
    Адреса ВАШОГО форку цього репозиторію, звідки Flux братиме маніфести.
    Репозиторій має бути публічним: тоді Flux читає його без жодних облікових
    даних. Формат: https://github.com/ваш-логін/hillel-eks-practice
  EOT
  type        = string

  validation {
    condition     = can(regex("^https://", var.git_url))
    error_message = "Вкажіть адресу, що починається з https:// — для публічного репозиторію цього досить."
  }
}

variable "git_branch" {
  description = <<-EOT
    Гілка, за якою стежить Flux.
    УВАГА: чарт flux2-sync за замовчуванням дивиться в гілку master, а GitHub
    для нових репозиторіїв створює main.
  EOT
  type        = string
  default     = "main"
}

variable "app_path" {
  description = "Тека з маніфестами застосунку всередині репозиторію."
  type        = string
  default     = "./apps/shop"
}

variable "sync_interval" {
  description = "Як часто Flux перевіряє репозиторій. На занятті коротко, щоб бачити результат одразу."
  type        = string
  default     = "1m"
}

# ---------------------------------------------------------------------------
# Крок 1. Контролери Flux.
#
# Чарт за замовчуванням ставить УСІ ШІСТЬ контролерів. Два з них — для
# автоматичного оновлення образів — нам не потрібні, і кожен забирає
# 100m процесора й 64Mi пам'яті. Вимикаємо їх.
# ---------------------------------------------------------------------------
resource "helm_release" "flux" {
  name             = "flux2"
  repository       = "https://fluxcd-community.github.io/helm-charts"
  chart            = "flux2"
  version          = "2.19.1"
  namespace        = "flux-system"
  create_namespace = true

  values = [yamlencode({
    sourceController       = { create = true }
    kustomizeController    = { create = true }
    helmController         = { create = true }
    notificationController = { create = true }

    imageAutomationController = { create = false }
    imageReflectionController = { create = false }
  })]

  # Контролерам потрібен хоча б один живий вузол.
  depends_on = [module.eks]
}

# ---------------------------------------------------------------------------
# Крок 2. Звідки брати маніфести і що з ними робити.
#
# Чарт створює в кластері два об'єкти з іменем релізу:
#   GitRepository  — ЩО стежити: адреса репозиторію, гілка, інтервал
#   Kustomization  — ЯК застосовувати: тека, prune, інтервал звіряння
#
# depends_on обов'язковий: ці два типи з'являються в кластері лише після
# встановлення контролерів із кроку 1.
# ---------------------------------------------------------------------------
resource "helm_release" "flux_sync" {
  name       = "shop-sync"
  repository = "https://fluxcd-community.github.io/helm-charts"
  chart      = "flux2-sync"
  version    = "1.15.1"
  namespace  = "flux-system"

  depends_on = [helm_release.flux]

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
        path     = var.app_path
        interval = var.sync_interval
        # prune: прибрали файл із репозиторію — Flux прибере й об'єкт у кластері
        prune = true
      }
    }
  })]
}

output "flux_check_commands" {
  description = "Команди для перевірки, що Flux працює."
  value       = <<-EOT
    kubectl get pods -n flux-system
    kubectl get gitrepositories,kustomizations -n flux-system
    kubectl get pods -n shop
  EOT
}
