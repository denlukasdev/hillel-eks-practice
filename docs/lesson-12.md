# Заняття 12. CI/CD від коміту до кластера

На занятті — теорія. Усе, що нижче, — **домашнє завдання**: покроково
зібрати той самий ланцюжок у своєму акаунті.

```
коміт у форк -> GitHub Actions -> ECR (образ + чарт) -> Flux -> под у кластері
```

| Що | Де лежить | Хто застосовує |
|---|---|---|
| Реєстри ECR, роль для GitHub, доступ Flux до ECR | `lessons/12-cicd/*.tf` | Terraform, `cluster/` |
| Образ застосунку | `app/Dockerfile` | GitHub Actions |
| Пайплайн | `.github/workflows/release.yaml` | GitHub Actions |
| Реліз із чарту | `apps/shop-release/` | Flux, `release-sync` |

Реліз ставиться в окремий namespace `shop-release` — поруч із `shop`,
яким Flux керує через kustomize з заняття 9.

---

## Завдання 1. Реєстри й довіра — Terraform

1. Оновіть форк (**Sync fork**), `git pull`, підніміть вузол:

   ```bash
   NG=$(aws eks list-nodegroups --cluster-name <prefix>-eks \
          --query 'nodegroups[0]' --output text)
   aws eks update-nodegroup-config --cluster-name <prefix>-eks \
          --nodegroup-name $NG --scaling-config desiredSize=1
   ```

2. Скопіюйте файли заняття й додайте свій форк у `cluster/terraform.tfvars`:

   ```bash
   cp lessons/12-cicd/*.tf cluster/
   ```

   ```hcl
   github_repository = "vash-login/hillel-eks-practice"
   ```

3. Застосуйте:

   ```bash
   cd cluster
   terraform apply          # Plan: 11 to add, 0 to change
   terraform output github_release_role_arn
   terraform output ecr_registry
   ```

4. Перезапустіть source-controller, щоб він отримав нову роль:

   ```bash
   kubectl rollout restart deployment/source-controller -n flux-system
   ```

**Готово, коли:** у консолі **ECR → Repositories** є `shop` і `charts/shop`,
а `kubectl get kustomization release-sync -n flux-system` показує `True`.
`HelmRelease shop` поки що не готовий — чарту в реєстрі ще немає, це нормально.

---

## Завдання 2. Перший реліз — GitHub Actions

1. У своєму форку: вкладка **Actions** → увімкніть workflow
   (у форках вони вимкнені за замовчуванням).
2. **Settings → Secrets and variables → Actions → Variables → New repository
   variable**: ім'я `AWS_ROLE_ARN`, значення — вивід `github_release_role_arn`.
   Це саме *variable*, а не *secret*: ARN ролі не є таємницею.
3. **Actions → release → Run workflow** на гілці `main`.
4. Відкрийте запуск і пройдіться по кроках: версія, вхід в AWS без ключа,
   збірка образу, публікація чарту.

**Готово, коли:** запуск зелений, а в ECR в обох репозиторіях з'явився тег
`0.2.<номер запуску>`.

---

## Завдання 3. Flux розгортає реліз

Нічого застосовувати не треба — лише дивитись:

```bash
kubectl get ocirepository,helmrelease -n shop-release
# обидва READY True; у статусі видно версію чарту, наприклад 0.2.1

kubectl get pods -n shop-release
kubectl port-forward -n shop-release svc/shop-web 8082:80
curl localhost:8082/            # shop from ECR, delivered by Flux
curl localhost:8082/version     # version: 0.2.1  commit: <ваш коміт>
```

**Готово, коли:** `/version` показує ту саму версію, що в ECR, і хеш вашого коміту.

---

## Завдання 4. Повний цикл одним комітом

1. Змініть щось у `app/Dockerfile` або в `charts/shop` (наприклад, текст у
   `values.yaml`), закомітьте в `main` і запуште.
2. Нічого більше не робіть. Спостерігайте:

   ```bash
   kubectl get helmrelease shop -n shop-release -w
   ```

3. За кілька хвилин `curl localhost:8082/version` покаже нову версію
   і новий коміт.

**Готово, коли:** версія змінилась без жодної команди `kubectl apply`,
`helm` чи `terraform`.

**Із зірочкою.** Зафіксуйте версію: в `apps/shop-release/oci-repository.yaml`
замініть `semver: "0.2.x"` на конкретну попередню версію, закомітьте.
Flux відкотить реліз. Потім поверніть діапазон.

---

## Прибирання

Реєстр ECR коштує копійки (платите за гігабайти образів), балансувальників
тут немає. Достатньо опустити вузли:

```bash
aws eks update-nodegroup-config --cluster-name <prefix>-eks \
       --nodegroup-name $NG --scaling-config desiredSize=0
```

---

## Пастки

**Workflow не запускається у форку.** Вкладка Actions → «I understand my
workflows, go ahead and enable them».

**Завдання `release` пропущене (skipped).** Не задано змінну `AWS_ROLE_ARN`,
або її створено як *secret*, а не *variable*.

**`Not authorized to perform sts:AssumeRoleWithWebIdentity`.** У
`github_repository` не той репозиторій (регістр літер має значення) або
запуск не з гілки `main` — політика довіри дозволяє лише її.

**`tag invalid: The image tag '0.2.7' already exists … and cannot be
overwritten`.** Ви натиснули Re-run: номер запуску той самий, а теги в
реєстрі незмінні. Запустіть workflow заново через **Run workflow**.

**`OCIRepository`: `failed to get credential` або `no basic auth
credentials`.** source-controller не перезапущено після apply — він стартував
раніше, ніж з'явилась асоціація Pod Identity.

**`HelmRelease` не оновлюється, хоча в ECR нова версія.** Перевірте, що вона
підпадає під діапазон у `oci-repository.yaml`: `0.3.0` під `0.2.x` не підпадає.

**`EntityAlreadyExists` для OIDC provider.** Постачальник токенів GitHub в
акаунті вже є. Імпортуйте його:
`terraform import aws_iam_openid_connect_provider.github <arn>`.
