# ---------------------------------------------------------------------------
# Заняття 12. Скопіюйте всю теку в cluster/:
#   cp lessons/12-cicd/*.tf cluster/
#
# Реєстри для того, що збирає CI: образ застосунку і чарт.
#
# МЕЖА ТА САМА, ЩО Й РАНІШЕ: Terraform створює інфраструктуру ДЛЯ пайплайна
# (реєстри, роль, довіру), але сам у пайплайні не запускається.
# ---------------------------------------------------------------------------

locals {
  # Ім'я репозиторію в ECR — це шлях в адресі образу:
  #   <акаунт>.dkr.ecr.<регіон>.amazonaws.com/shop:0.2.15
  #   <акаунт>.dkr.ecr.<регіон>.amazonaws.com/charts/shop:0.2.15
  # Репозиторій для чарту має існувати ЗАЗДАЛЕГІДЬ і називатися
  # <простір>/<ім'я чарту>: helm push сам його не створить.
  ecr_repositories = ["shop", "charts/shop"]
}

resource "aws_ecr_repository" "this" {
  for_each = toset(local.ecr_repositories)

  name = each.value

  # Тег, раз опублікований, перезаписати не можна. Версія 0.2.15 завжди
  # означає той самий вміст — на цьому тримається і відкат, і довіра до релізу.
  image_tag_mutability = "IMMUTABLE"

  # Перевірка образу на відомі вразливості одразу після публікації.
  image_scanning_configuration {
    scan_on_push = true
  }

  # Лише для навчання: дозволяє terraform destroy, коли в репозиторії є образи.
  # У продакшні тут false — реєстр не має зникати разом з усіма релізами.
  force_delete = true

  tags = local.common_tags
}

# Без цього реєстр росте вічно: кожен коміт — нова версія образу й чарту.
resource "aws_ecr_lifecycle_policy" "keep_last" {
  for_each = aws_ecr_repository.this

  repository = each.value.name

  policy = jsonencode({
    rules = [{
      rulePriority = 1
      description  = "Keep only the 10 most recent versions"
      selection = {
        tagStatus   = "any"
        countType   = "imageCountMoreThan"
        countNumber = 10
      }
      action = { type = "expire" }
    }]
  })
}

data "aws_caller_identity" "cicd" {}

locals {
  ecr_registry = "${data.aws_caller_identity.cicd.account_id}.dkr.ecr.${var.region}.amazonaws.com"
}

output "ecr_registry" {
  description = "Адреса реєстру ECR цього акаунта."
  value       = local.ecr_registry
}
