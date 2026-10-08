# Заняття 13. Локальний стенд для логів

```
web (nginx, JSON-логи)  ->  fluent-bit (збирач)  ->  victorialogs (сховище й пошук)
```

Нічого з цієї теки не копіюється в `cluster/`: стенд працює на вашому
комп'ютері в Docker Compose і не потребує AWS.

```bash
docker compose up -d
# застосунок:  http://localhost:8080
# пошук логів: http://localhost:9428/select/vmui
docker compose down -v
```

| Файл | Що в ньому |
|---|---|
| `compose.yaml` | чотири сервіси стенда |
| `nginx/default.conf` | формат журналу JSON |
| `fluent-bit/fluent-bit.yaml` | конвеєр збирача: звідки, що зробити, куди |

Завдання й запити — у `docs/lesson-13.md`.
