{{/*
Заняття 11. Іменовані шаблони — «функції» чарту.
Файли, що починаються з _, Helm не рендерить у маніфести: тут лише визначення,
які інші шаблони підключають через include.
*/}}

{{/*
Мітки для всіх об'єктів. Виклик:
  {{- include "shop.labels" (dict "root" . "component" "web") | nindent 4 }}
*/}}
{{- define "shop.labels" -}}
app.kubernetes.io/name: {{ .root.Chart.Name }}
app.kubernetes.io/instance: {{ .root.Release.Name }}
app.kubernetes.io/component: {{ .component }}
app.kubernetes.io/version: {{ .root.Chart.AppVersion | quote }}
app.kubernetes.io/managed-by: {{ .root.Release.Service }}
{{- end }}

{{/*
Мітки для selector. ЛИШЕ незмінні: selector у Deployment після створення
змінити не можна, тому версії тут немає.
*/}}
{{- define "shop.selectorLabels" -}}
app.kubernetes.io/instance: {{ .root.Release.Name }}
app.kubernetes.io/component: {{ .component }}
{{- end }}
