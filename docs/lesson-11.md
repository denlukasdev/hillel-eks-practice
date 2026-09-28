# Заняття 11. Стан, Gateway API і власний чарт

Сьогодні три речі:

| Що | Як | Руками чи теорія |
|---|---|---|
| PostgreSQL на диску EBS | StatefulSet у `apps/shop`, пароль із Parameter Store | руками |
| Gateway API і сертифікати Let's Encrypt | Gateway, HTTPRoute, cert-manager | теорія |
| Власний чарт `shop` | `charts/shop`, `helm install` вручну | руками |

Terraform сьогодні не змінюється: драйвер дисків EBS із роллю Pod Identity
стоїть у кластері ще з заняття 8.

**Передумова:** на занятті 10 у `apps/shop/kustomization.yaml` мають бути
розкоментовані `secret-store.yaml` і `external-secret.yaml` — пароль бази
приходить звідти.

---

## 0. Оновити форк і підняти вузол

1. На GitHub: **Sync fork → Update branch**, потім `git pull`.
   З'являться `infrastructure/storageclass.yaml`, `apps/shop/postgres.yaml`,
   `charts/shop/` і цей файл.
2. Вузол (у CloudShell):

   ```bash
   NG=$(aws eks list-nodegroups --cluster-name <prefix>-eks \
          --query 'nodegroups[0]' --output text)
   aws eks update-nodegroup-config --cluster-name <prefix>-eks \
          --nodegroup-name $NG --scaling-config desiredSize=1
   ```

3. Коли вузол `Ready`, Flux сам застосує новий клас сховища:

   ```bash
   kubectl get storageclass
   # NAME            PROVISIONER       ... VOLUMEBINDINGMODE
   # gp2             kubernetes.io/aws-ebs Immediate
   # gp3 (default)   ebs.csi.aws.com   ... WaitForFirstConsumer
   ```

   Зверніть увагу: `gp2` є, але **без** `(default)`. У кластерах EKS від
   версії 1.30 класу за замовчуванням немає — PVC без класу висів би в `Pending`.

---

## 1. Практика 1. PostgreSQL на EBS

1. У `apps/shop/kustomization.yaml` розкоментуйте `- postgres.yaml`.
   Закомітьте й запуште.
2. Спостерігайте, як з'являються диск і под:

   ```bash
   kubectl get pvc,pods -n shop -w
   # data-postgres-0   Pending  -> Bound
   # postgres-0        Pending  -> ContainerCreating -> Running
   ```

   PVC спершу `Pending` — це нормально: `WaitForFirstConsumer` чекає, доки
   планувальник вибере вузол, і лише тоді створює диск **у зоні цього вузла**.

3. Знайдіть диск в AWS:

   ```bash
   kubectl get pv
   kubectl get pv <ім'я> -o jsonpath='{.spec.csi.volumeHandle}{"\n"}'   # vol-...
   ```

   Консоль **EC2 → Volumes** — диск на 1 GiB, тип gp3, зашифрований.

4. Дані переживають под:

   ```bash
   kubectl exec -it -n shop postgres-0 -- psql -U postgres -d shop
   ```

   ```sql
   CREATE TABLE orders (id serial PRIMARY KEY, item text);
   INSERT INTO orders (item) VALUES ('antenna'), ('coax');
   \q
   ```

   ```bash
   kubectl delete pod -n shop postgres-0          # StatefulSet створить його знову
   kubectl wait -n shop --for=condition=Ready pod/postgres-0 --timeout=120s
   kubectl exec -n shop postgres-0 -- psql -U postgres -d shop -c 'SELECT * FROM orders;'
   ```

5. Зони: диск і вузол в одній зоні.

   ```bash
   kubectl get pv -o jsonpath='{.items[*].spec.nodeAffinity.required.nodeSelectorTerms[*].matchExpressions[*].values}{"\n"}'
   kubectl get nodes -L topology.kubernetes.io/zone
   ```

---

## 2. Практика 2. Власний чарт

Чарт лежить у `charts/shop`. Ставимо його **вручну** в окремий namespace —
поруч із тим shop, яким керує Flux. На занятті 12 цей самий чарт
публікуватиме CI, а ставитиме Flux.

```bash
helm lint charts/shop
helm template demo charts/shop | less              # що саме буде застосовано

helm install shop-chart charts/shop -n shop-chart --create-namespace
kubectl get pods -n shop-chart
kubectl port-forward -n shop-chart svc/shop-chart-web 8081:80
curl localhost:8081/ ; curl localhost:8081/api/
```

Змінити значення й подивитись, як поди перезапускаються самі:

```bash
helm upgrade shop-chart charts/shop -n shop-chart --set web.message="v2 from helm"
kubectl get pods -n shop-chart -w                  # нові поди web
helm history shop-chart -n shop-chart
helm rollback shop-chart 1 -n shop-chart
```

**Із зірочкою.** База в чарті:

```bash
helm upgrade shop-chart charts/shop -n shop-chart --set postgres.enabled=true
helm upgrade shop-chart charts/shop -n shop-chart --set postgres.enabled=true --set secrets.enabled=false
# ^ упаде з поясненням: так працює fail у шаблоні
```

---

## 3. Прибирання

```bash
helm uninstall shop-chart -n shop-chart
kubectl get pvc -n shop-chart          # якщо вмикали базу — PVC лишився!
kubectl delete namespace shop-chart    # разом із PVC зникне й диск EBS
```

Якщо на занятті вмикали `web-public.yaml` — закоментуйте його, запуште
й дочекайтесь, поки NLB зникне. Потім вузли в нуль:

```bash
aws eks update-nodegroup-config --cluster-name <prefix>-eks \
       --nodegroup-name $NG --scaling-config desiredSize=0
```

База в `shop` лишається: диск на 1 GiB gp3 коштує центи на місяць, а на
занятті 12 вона знадобиться.

---

## Пастки

**`postgres-0` у `CreateContainerConfigError`.** Немає Secret `shop-config`:
не розкоментовані `secret-store.yaml` і `external-secret.yaml` з заняття 10.

**`postgres-0` у `Pending` з `volume node affinity conflict`.** Диск EBS живе
в одній зоні, а новий вузол після підйому з нуля піднявся в іншій. Под туди,
де диска немає, не поставиш. Варіанти: опустити й підняти вузол ще раз
(група вибирає зону сама), або — якщо дані не потрібні — видалити PVC:

```bash
kubectl delete pvc -n shop data-postgres-0
kubectl delete pod -n shop postgres-0      # StatefulSet створить новий диск у зоні вузла
```

У продакшні це розв'язують групою вузлів на кожну зону, Karpenter або
керованою базою RDS.

**Дані зникли після перезапуску пода.** Приклади з інтернету монтують том у
`/var/lib/postgresql/data`. Для образу PostgreSQL 18 це вже не працює:
монтувати треба `/var/lib/postgresql`.

**PVC вічно `Pending` без подій.** У PVC вказано клас, якого немає, або
класу немає зовсім, а класу за замовчуванням у кластері немає.

**`helm install` каже `cannot re-use a name that is still in use`.** Реліз
із таким ім'ям уже є: `helm list -A`.

---

## Ресурси вузла після заняття

| Що додалось | Подів | CPU requests | Пам'ять requests |
|---|---|---|---|
| PostgreSQL у `shop` | 1 | 100m | 256Mi |
| Чарт у `shop-chart`, без бази (на час практики) | 2 | 100m | 64Mi |
| Чарт із базою (завдання із зірочкою) | +1 | +100m | +256Mi |

Числа орієнтовні, реальні — `kubectl describe node <ім'я> | grep -A8 "Allocated resources"`.
