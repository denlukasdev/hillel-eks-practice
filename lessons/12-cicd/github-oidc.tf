# ---------------------------------------------------------------------------
# Заняття 12. Довіра між GitHub Actions і AWS — без жодного ключа.
#
# Той самий механізм, що в HCP Terraform на занятті 6:
#   GitHub видає запуску workflow короткоживучий токен OIDC
#   -> AWS перевіряє підпис і поля токена за політикою довіри ролі
#   -> видає тимчасові облікові дані.
# Змінились лише дві речі: хто видає токен і формат поля sub.
# ---------------------------------------------------------------------------

variable "github_repository" {
  description = <<-EOT
    ВАШ форк у форматі власник/репозиторій, наприклад
    vash-login/hillel-eks-practice. Лише workflow з цього репозиторію
    зможуть отримати роль.
  EOT
  type        = string

  validation {
    condition     = can(regex("^[^/]+/[^/]+$", var.github_repository))
    error_message = "Формат: власник/репозиторій, без https:// і без .git."
  }
}

# Постачальник токенів GitHub. Один на акаунт AWS: якщо такий уже є,
# apply скаже EntityAlreadyExists — тоді імпортуйте його або приберіть
# цей ресурс і підставте ARN наявного.
resource "aws_iam_openid_connect_provider" "github" {
  url            = "https://token.actions.githubusercontent.com"
  client_id_list = ["sts.amazonaws.com"]

  tags = local.common_tags
}

data "aws_iam_policy_document" "github_trust" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.github.arn]
    }

    # Токен видано саме для AWS.
    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }

    # НАЙВАЖЛИВІША УМОВА: з якого репозиторію і якої гілки.
    # Без неї роль отримав би БУДЬ-ЯКИЙ репозиторій на GitHub.
    # Лише гілка main: pull request чи інша гілка публікувати релізи не може.
    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:sub"
      values   = ["repo:${var.github_repository}:ref:refs/heads/main"]
    }
  }
}

resource "aws_iam_role" "github_release" {
  name               = "${var.prefix}-github-release"
  assume_role_policy = data.aws_iam_policy_document.github_trust.json

  tags = local.common_tags
}

data "aws_iam_policy_document" "ecr_push" {
  # Отримати токен для входу в реєстр. Ця дія не прив'язана до конкретного
  # репозиторію, тому Resource тут "*" — це не помилка і не дірка.
  statement {
    sid       = "Login"
    effect    = "Allow"
    actions   = ["ecr:GetAuthorizationToken"]
    resources = ["*"]
  }

  # Публікувати — лише у два наші репозиторії.
  statement {
    sid    = "PushPull"
    effect = "Allow"
    actions = [
      "ecr:BatchCheckLayerAvailability",
      "ecr:InitiateLayerUpload",
      "ecr:UploadLayerPart",
      "ecr:CompleteLayerUpload",
      "ecr:PutImage",
      "ecr:BatchGetImage",
      "ecr:GetDownloadUrlForLayer",
    ]
    resources = [for r in aws_ecr_repository.this : r.arn]
  }
}

resource "aws_iam_role_policy" "github_release" {
  name   = "ecr-push"
  role   = aws_iam_role.github_release.id
  policy = data.aws_iam_policy_document.ecr_push.json
}

output "github_release_role_arn" {
  description = "Впишіть у змінну AWS_ROLE_ARN репозиторію на GitHub (Settings -> Secrets and variables -> Actions -> Variables)."
  value       = aws_iam_role.github_release.arn
}
