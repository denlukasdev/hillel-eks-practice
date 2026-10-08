# Заняття 13. Моніторинг: логи

На занятті — теорія. Усе, що нижче, — **домашнє завдання, і воно необов'язкове**.
Завдання прості й незалежні одне від одного: можна зробити будь-яке.

| Завдання | Що потрібно | Час |
|---|---|---|
| 1. Логи пода руками | кластер із піднятим вузлом | 10 хв |
| 2. Хто це зробив: журнал аудиту в CloudWatch | кластер (вузол не потрібен) | 10 хв |
| 3. Локальний стенд: збирач → сховище → пошук | лише Docker, без AWS | 20 хв |
| 4. Із зірочкою: прибрати шум на збирачі | стенд із завдання 3 | 5 хв |

---

## Завдання 1. Логи пода руками

Підніміть вузол (як завжди) і подивіться, що вміє `kubectl logs`.

```bash
NG=$(aws eks list-nodegroups --cluster-name <prefix>-eks \
       --query 'nodegroups[0]' --output text)
aws eks update-nodegroup-config --cluster-name <prefix>-eks \
       --nodegroup-name $NG --scaling-config desiredSize=1
```

```bash
kubectl logs -n shop deploy/web --tail=20          # останні 20 рядків одного пода
kubectl logs -n shop -l app=web --prefix --tail=5  # усі поди з міткою, з іменем пода
kubectl logs -n shop deploy/web --since=10m --timestamps
kubectl logs -n shop deploy/web -f                 # стежити; вихід — Ctrl+C
```

Поки працює `-f`, в іншому терміналі зробіть кілька запитів — рядки з'являться:

```bash
kubectl port-forward -n shop svc/web 8081:80
curl localhost:8081/
```

Тепер два досліди.

**Контейнер перезапустився.** Зупиніть nginx усередині контейнера — Kubernetes
запустить контейнер заново:

```bash
POD=$(kubectl get pod -n shop -l app=web -o name | head -1)
kubectl exec -n shop $POD -- nginx -s quit
kubectl get -n shop $POD              # RESTARTS стало 1
kubectl logs -n shop $POD             # логи НОВОГО контейнера: старих рядків немає
kubectl logs -n shop $POD --previous  # логи попереднього контейнера
```

**Под видалили.** Запам'ятайте час і видаліть под:

```bash
kubectl delete -n shop $POD
kubectl logs -n shop $POD             # Error from server (NotFound)
```

**Готово, коли:** ви бачили логи попереднього контейнера через `--previous`
і переконались, що після видалення пода його логів більше немає.
Саме тому логи збирають із вузла й зберігають окремо.

---

## Завдання 2. Хто це зробив: журнал аудиту в CloudWatch

Кластер від першого дня надсилає логи контрольного рівня в CloudWatch Logs —
це значення модуля EKS за замовчуванням, тепер воно явно записане в
`cluster/eks.tf` (`enabled_log_types`). Вузол для цього завдання не потрібен.

1. Подивіться, що вже зібрано (у CloudShell або в терміналі):

   ```bash
   aws logs describe-log-groups --log-group-name-prefix /aws/eks/ \
     --query 'logGroups[].[logGroupName,retentionInDays,storedBytes]' --output table

   aws logs describe-log-streams --log-group-name /aws/eks/<prefix>-eks/cluster \
     --order-by LastEventTime --descending --max-items 10 \
     --query 'logStreams[].logStreamName'
   ```

   Потоки `kube-apiserver-audit-…` — журнал аудиту, `kube-apiserver-…` — сервер
   API, `authenticator-…` — вхід через IAM. `storedBytes` — скільки байтів
   накопичилось: саме за них і за прийом ви платите.

2. У консолі: **CloudWatch → Logs Insights**. Виберіть групу
   `/aws/eks/<prefix>-eks/cluster`, проміжок часу — **1 година** (або той, коли
   ви робили завдання 1), вставте запит і натисніть **Run query**:

   ```
   fields @timestamp, user.username, verb, objectRef.namespace, objectRef.name
   | filter @logStream like "kube-apiserver-audit"
   | filter objectRef.resource = "pods" and verb = "delete"
   | sort @timestamp desc
   | limit 20
   ```

   У колонці `user.username` — ваш ARN: це ви видалили под у завданні 1.
   Поруч можуть бути записи від `system:node:…` — це kubelet завершує видалення.

3. Другий запит — хто найбільше звертається до API кластера:

   ```
   filter @logStream like "kube-apiserver-audit"
   | stats count(*) as requests by user.username
   | sort requests desc
   | limit 10
   ```

**Готово, коли:** ви знайшли в журналі аудиту власне видалення пода й побачили,
які службові акаунти (Flux, kubelet) звертаються до API найчастіше.

> Logs Insights тарифікує обсяг просканованих даних, тому не ставте проміжок
> «за місяць» без потреби. Година журналу аудиту — це мегабайти.

---

## Завдання 3. Локальний стенд: збирач → сховище → пошук

Той самий конвеєр, що на занятті, у чотирьох контейнерах на вашому комп'ютері.
AWS не потрібен.

```
web (nginx, JSON-логи)  ->  fluent-bit (збирач)  ->  victorialogs (сховище й пошук)
        ^
     loadgen (запити щосекунди)
```

```bash
cd lessons/13-logs
docker compose up -d
docker compose ps            # чотири контейнери у стані running
```

1. Подивіться на сирі рядки — це те, що застосунок пише в stdout:

   ```bash
   docker compose logs web --tail=3
   ```

   Кожен рядок — JSON із полями `status`, `path`, `user_agent`, `request_id`.
   Формат задано в `nginx/default.conf`.

2. Відкрийте **http://localhost:9428/select/vmui** — вбудований інтерфейс
   VictoriaLogs. Виберіть проміжок **Last 5 minutes** і виконайте запити по черзі.
   Під графіком є вкладки результату: **Group** зручна для рядків логів,
   **JSON** — для підрахунків (запити зі `stats` і `fields`).

   ```
   *
   ```
   усі логи за вибраний час; розгорніть будь-який рядок — побачите поля

   ```
   status:>=500
   ```
   лише помилки сервера

   ```
   * | stats by (status) count() as requests | sort by (requests desc)
   ```
   скільки запитів із кожним статусом — дивіться на вкладці **JSON**

   ```
   status:404 | stats by (path) count() as hits | sort by (hits desc)
   ```
   яких сторінок не знаходять найчастіше

   ```
   path:="/admin" | fields _time, client, user_agent
   ```
   хто ходить на закриту сторінку

3. Простежте один запит. Зробіть його самі, з прикметним іменем клієнта:

   ```bash
   curl -s -o /dev/null -A "student" localhost:8080/api/pay
   ```

   ```
   user_agent:=student
   ```
   розгорніть рядок і скопіюйте значення `request_id`

   ```
   request_id:=<ваш ідентифікатор>
   ```
   рівно один рядок. У системі з кількох сервісів за цим ідентифікатором
   знайшлися б рядки кожного сервісу, через який пройшов запит.

**Готово, коли:** ви можете сказати, скільки було відповідей 503 за останні
п'ять хвилин, і знайшли власний запит за `request_id`.

Як улаштований збирач — у `fluent-bit/fluent-bit.yaml`: чотири кроки з
коментарями (звідки, збагатити, відфільтрувати, куди).

---

## Завдання 4. Із зірочкою: прибрати шум на збирачі

Порахуйте, яку частку логів складають перевірки стану (вкладка **JSON**):

```
* | stats by (user_agent) count() as requests
```

`kube-probe` — це імітація перевірок kubelet: у справжньому кластері вони
приходять кожні кілька секунд на кожен под. Користі з таких рядків мало,
а платите ви за кожен.

1. У `fluent-bit/fluent-bit.yaml` розкоментуйте три рядки фільтра `grep`.
2. Перезапустіть збирач: `docker compose restart fluent-bit`.
3. Перевірте: нових рядків немає, а решта логів іде далі.

   ```
   _time:1m path:="/healthz" | stats count() as n
   ```

**Готово, коли:** запит повертає `0`, а `docker compose logs web` і далі
показує `/healthz` — застосунок пише все, збирач вирішує, що зберігати.

---

## Прибирання

```bash
docker compose down -v      # контейнери й томи стенда
```

Вузли кластера — у нуль, як завжди:

```bash
aws eks update-nodegroup-config --cluster-name <prefix>-eks \
       --nodegroup-name $NG --scaling-config desiredSize=0
```

Логи контрольного рівня в CloudWatch зберігаються 90 днів і видаляються самі.

---

## Здача

Коментар у LMS до завдання — що з переліченого ви зробили:

- завдання 1–2: рядок результату запиту Logs Insights із вашим видаленням пода;
- завдання 3: результат запиту `stats by (status)` зі стенда;
- завдання 4: результат запиту з `0`.

---

## Пастки

**`kubectl logs` каже `previous terminated container … not found`.** Контейнер
ще не перезапускався: `--previous` працює лише після перезапуску.

**Групи `/aws/eks/<prefix>-eks/cluster` немає.** Перевірте регіон (`eu-central-1`)
та ім'я кластера: `aws eks list-clusters`.

**Logs Insights нічого не знаходить.** Проміжок часу не накриває момент
видалення пода, або кластер тоді був вимкнений. Розширте проміжок до 3 годин.

**`docker compose up` каже `port is already allocated`.** Порт 8080 або 9428
зайнятий іншою програмою. Змініть ліву частину в `compose.yaml`, наприклад
`"8088:80"`, і відкривайте відповідну адресу.

**В інтерфейсі VictoriaLogs порожньо.** Зачекайте 10–15 секунд після запуску
й перевірте проміжок часу вгорі праворуч. Далі дивіться журнал збирача:
`docker compose logs fluent-bit --tail=20` — у нормі там рядки `HTTP status=200`.

**Після правки `fluent-bit.yaml` збирач не стартує.** YAML чутливий до
відступів: три розкоментовані рядки мають стояти на рівні сусіднього
фільтра `modify`. Помилку видно в `docker compose logs fluent-bit`.

---

## Якщо цікаво піти далі

Той самий конвеєр у кластері — це збирач як DaemonSet і сховище. Офіційні
чарти: `victoria-logs-single` (сховище) і `victoria-logs-collector` (збирач),
ставляться так само, як LBC та ESO на занятті 10 — двома `HelmRelease`.
Майте на увазі бюджет вузла: розрахунок ресурсів — у `README.md`.
