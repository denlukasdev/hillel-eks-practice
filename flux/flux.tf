# ---------------------------------------------------------------------------
# Крок 1. Контролери Flux.
#
# Чарт за замовчуванням ставить УСІ ШІСТЬ контролерів. Два з них — для
# автоматичного оновлення образів — нам не потрібні, і кожен забирає
# 100m процесора й 64Mi пам'яті. Вимикаємо їх: це два поди й чверть
# ресурсів Flux, які інакше просто стояли б без діла.
# ---------------------------------------------------------------------------
resource "helm_release" "flux" {
  name             = "flux2"
  repository       = "https://fluxcd-community.github.io/helm-charts"
  chart            = "flux2"
  version          = "2.19.1"
  namespace        = "flux-system"
  create_namespace = true

  values = [yamlencode({
    # потрібні нам
    sourceController       = { create = true }
    kustomizeController    = { create = true }
    helmController         = { create = true }
    notificationController = { create = true }

    # автоматизація образів — не потрібна на цьому етапі
    imageAutomationController = { create = false }
    imageReflectionController = { create = false }
  })]
}

# ---------------------------------------------------------------------------
# Крок 2. Звідки брати маніфести застосунку і що з ними робити.
#
# GitRepository — ЩО стежити: адреса репозиторію й гілка.
# Kustomization — ЯК застосовувати: яку теку, як часто, чи прибирати зайве.
#
# depends_on обов'язковий: ці два об'єкти мають типи, які з'являються в
# кластері лише після встановлення контролерів із кроку 1.
#
# ЗМІНА НА ЗАНЯТТІ 10: застосунок тепер залежить від інфраструктури
# (див. infrastructure.tf). Поле dependsOn — це вже не Terraform, а Flux:
# kustomize-controller не застосує теку apps/shop, поки Kustomization
# infra-sync не стане Ready. Без цього ExternalSecret прилетів би в кластер
# раніше, ніж з'явився його тип, і застосування впало б.
# ---------------------------------------------------------------------------
resource "helm_release" "flux_sync" {
  name       = "shop-sync"
  repository = "https://fluxcd-community.github.io/helm-charts"
  chart      = "flux2-sync"
  version    = "1.15.1"
  namespace  = "flux-system"

  depends_on = [helm_release.flux, helm_release.infra_sync]

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
        # prune: якщо файл прибрали з репозиторію, Flux прибере й об'єкт
        # у кластері. Саме це робить git єдиним джерелом правди.
        prune = true

        # нове на занятті 10
        dependsOn = [
          { name = "infra-sync" }
        ]
      }
    }
  })]
}
