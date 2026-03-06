# Lab Helm 4 — Templating Avancé

## 🎯 Objectif

Dans ce lab, vous allez enrichir le chart `devops-news` créé au Lab 3 avec les techniques de templating avancé : helpers réutilisables (`_helpers.tpl`), conditions, boucles `range`, manipulation du scope avec `with`, pipelines de fonctions et accès aux fichiers externes.

**Module couvert :** 5 (Le Templating Avancé)

**Temps estimé :** 1h15 - 1h30

---

## 📋 Pré-requis

1. Avoir terminé et compris le Lab 3.
2. Travailler sur une copie du chart produit au Lab 3 :
```bash
cp -r helm/devops-news helm/devops-news-v2
cd helm/
```

---

## Étape 1 : Création du fichier `_helpers.tpl`

Le fichier `_helpers.tpl` est la bibliothèque de fonctions réutilisables de votre chart. Les blocs définis ici peuvent être appelés depuis n'importe quel template, ce qui évite la duplication de code (**DRY**).

### 1.1 Créer le fichier

Créez `devops-news-v2/templates/_helpers.tpl` :

```yaml
{{/*
Nom complet d'une ressource (release + composant).
Utilisation : {{ include "devops-news.fullname" (dict "root" . "component" "backend") }}
*/}}
{{- define "devops-news.fullname" -}}
{{- printf "%s-%s" .root.Release.Name .component | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Labels standards Kubernetes recommandés par la communauté.
À inclure dans metadata.labels de toutes les ressources.
Utilisation : {{ include "devops-news.labels" (dict "root" . "component" "backend") }}
*/}}
{{- define "devops-news.labels" -}}
app.kubernetes.io/name: {{ .component }}
app.kubernetes.io/instance: {{ .root.Release.Name }}
app.kubernetes.io/version: {{ .root.Chart.AppVersion | quote }}
app.kubernetes.io/managed-by: {{ .root.Release.Service }}
helm.sh/chart: {{ printf "%s-%s" .root.Chart.Name .root.Chart.Version }}
{{- end }}

{{/*
Selector labels (sous-ensemble des labels, utilisé dans spec.selector.matchLabels).
*/}}
{{- define "devops-news.selectorLabels" -}}
app.kubernetes.io/name: {{ .component }}
app.kubernetes.io/instance: {{ .root.Release.Name }}
{{- end }}

{{/*
Nom du secret Redis.
*/}}
{{- define "devops-news.redisSecretName" -}}
{{- printf "%s-redis-secret" .Release.Name }}
{{- end }}
```

### 1.2 Pourquoi `include` plutôt que `template` ?

La directive `template` de Go est une **action** — elle ne peut pas être passée à une autre fonction. `include` retourne une **chaîne de caractères**, ce qui permet de la passer à `nindent` pour contrôler l'indentation :

```yaml
# ✅ Correct — on peut indenter le résultat
labels:
  {{- include "devops-news.labels" (dict "root" . "component" "backend") | nindent 2 }}

# ❌ Impossible avec template
labels:
  {{- template "devops-news.labels" . | nindent 2 }}  # Erreur de syntaxe
```

---

## Étape 2 : Refactoriser les templates avec les helpers

### 2.1 Mettre à jour `templates/backend.yaml`

Remplacez les noms et labels codés en dur par les helpers :

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: {{ include "devops-news.fullname" (dict "root" . "component" "backend") }}
  labels:
    {{- include "devops-news.labels" (dict "root" . "component" "backend") | nindent 4 }}
spec:
  replicas: {{ .Values.backend.replicas }}
  selector:
    matchLabels:
      {{- include "devops-news.selectorLabels" (dict "root" . "component" "backend") | nindent 6 }}
  template:
    metadata:
      labels:
        {{- include "devops-news.selectorLabels" (dict "root" . "component" "backend") | nindent 8 }}
    spec:
      containers:
        - name: api
          image: "{{ .Values.images.repoAccount }}/devops-news-api:{{ .Values.images.tags.backend }}"
          imagePullPolicy: {{ .Values.images.pullPolicy }}
          ports:
            - containerPort: {{ .Values.backend.service.port }}
          env:
            - name: REDIS_HOST
              value: {{ include "devops-news.fullname" (dict "root" . "component" "redis") | quote }}
            - name: REDIS_PORT
              value: {{ .Values.redis.service.port | quote }}
            - name: REDIS_PASSWORD
              valueFrom:
                secretKeyRef:
                  name: {{ include "devops-news.redisSecretName" . }}
                  key: password
            - name: LOG_LEVEL
              value: {{ .Values.backend.logLevel | quote }}
          resources:
            {{- toYaml .Values.backend.resources | nindent 12 }}
---
apiVersion: v1
kind: Service
metadata:
  name: {{ include "devops-news.fullname" (dict "root" . "component" "backend") }}
  labels:
    {{- include "devops-news.labels" (dict "root" . "component" "backend") | nindent 4 }}
spec:
  type: {{ .Values.backend.service.type }}
  selector:
    {{- include "devops-news.selectorLabels" (dict "root" . "component" "backend") | nindent 4 }}
  ports:
    - port: {{ .Values.backend.service.port }}
      targetPort: {{ .Values.backend.service.port }}
```

**Action :** Appliquez la même refactorisation à `frontend.yaml`, `redis.yaml` et `cleaner.yaml`.

### 2.2 Valider la refactorisation

```bash
helm template test ./devops-news-v2
```

Les noms et labels doivent être identiques à ceux du Lab 3.

---

## Étape 3 : Variables d'environnement dynamiques avec `range`

Le backend a des variables d'environnement fixes. Nous allons permettre à l'utilisateur d'injecter des variables arbitraires via `values.yaml`.

### 3.1 Ajouter `extraEnv` dans `values.yaml`

```yaml
backend:
  # ... paramètres existants ...
  extraEnv: []
  # Exemple d'utilisation :
  # extraEnv:
  #   - name: FEATURE_FLAG_X
  #     value: "true"
  #   - name: SENTRY_DSN
  #     value: "https://xxx@sentry.io/123"
```

### 3.2 Utiliser `range` dans le template backend

Dans la section `env:` du conteneur, ajoutez après les variables fixes :

```yaml
          env:
            - name: REDIS_HOST
              value: {{ include "devops-news.fullname" (dict "root" . "component" "redis") | quote }}
            - name: REDIS_PORT
              value: {{ .Values.redis.service.port | quote }}
            - name: REDIS_PASSWORD
              valueFrom:
                secretKeyRef:
                  name: {{ include "devops-news.redisSecretName" . }}
                  key: password
            - name: LOG_LEVEL
              value: {{ .Values.backend.logLevel | quote }}
            {{- range .Values.backend.extraEnv }}
            - name: {{ .name | quote }}
              value: {{ .value | quote }}
            {{- end }}
```

### 3.3 Tester avec une variable additionnelle

```bash
helm template test ./devops-news-v2 \
  --set 'backend.extraEnv[0].name=FEATURE_NEW_UI' \
  --set 'backend.extraEnv[0].value=true' \
  | grep -A 5 "FEATURE_NEW_UI"
```

---

## Étape 4 : Conditions et blocs optionnels

### 4.1 Le CronJob conditionnel

Le cleaner n'est pas toujours nécessaire (ex: en environnement de test). Rendez-le optionnel.

Ajoutez dans `values.yaml` :

```yaml
cleaner:
  enabled: true          # ← Nouveau paramètre
  schedule: "*/2 * * * *"
  maxAgeSeconds: 3600
```

Encadrez tout le contenu de `templates/cleaner.yaml` avec une condition :

```yaml
{{- if .Values.cleaner.enabled }}
# ... tout le contenu du CronJob ...
{{- end }}
```

Testez :
```bash
# Avec cleaner activé (défaut)
helm template test ./devops-news-v2 | grep -c "kind: CronJob"
# Attendu : 1

# Avec cleaner désactivé
helm template test ./devops-news-v2 --set cleaner.enabled=false | grep -c "kind: CronJob"
# Attendu : 0
```

### 4.2 Comprendre l'importance des tirets (`-`)

Créez un template de test temporaire `templates/test-whitespace.yaml` :

```yaml
---
# Sans tirets
result1:
  {{ if true }}
  presente: oui
  {{ end }}

# Avec tirets
result2:
  {{- if true }}
  presente: oui
  {{- end }}
```

```bash
helm template test ./devops-news-v2 | grep -A 6 "result"
```

Observez les lignes vides supplémentaires générées **sans** les tirets. Dans un fichier YAML Kubernetes, ces lignes vides peuvent causer des erreurs d'indentation. **Utilisez toujours les tirets** dans vos templates.

Supprimez ce fichier de test après observation :
```bash
rm devops-news-v2/templates/test-whitespace.yaml
```

---

## Étape 5 : Manipulation du scope avec `with`

### 5.1 Simplifier l'accès aux variables imbriquées

Dans le template Redis, le chemin `{{ .Values.redis.storageClassName }}` est répétitif. Utilisez `with` pour raccourcir :

```yaml
# Avant (sans with)
storageClassName: {{ .Values.redis.storageClassName | quote }}
resources:
  requests:
    storage: {{ .Values.redis.storage }}

# Après (avec with — le scope . est remplacé par .Values.redis)
{{- with .Values.redis }}
storageClassName: {{ .storageClassName | quote }}
resources:
  requests:
    storage: {{ .storage }}
{{- end }}
```

### 5.2 Accéder à la racine depuis un bloc `with`

À l'intérieur d'un bloc `with`, le `.` est redéfini. Pour accéder à des variables racines (ex : `.Release.Name`), utilisez `$` :

```yaml
{{- with .Values.redis }}
# . == .Values.redis ici
name: {{ $.Release.Name }}-redis    # $ donne accès à la racine
port: {{ .service.port }}           # . donne accès à .Values.redis.service.port
{{- end }}
```

---

## Étape 6 : Pipelines et fonctions utilitaires

### 6.1 Les pipelines

Helm utilise la syntaxe pipe (`|`) de Go pour chaîner les transformations, exactement comme en Bash :

```yaml
# Mettre en majuscule et entourer de guillemets
env_name: {{ .Values.backend.logLevel | upper | quote }}

# Résultat pour logLevel: "info" → "INFO"
```

Testez dans votre template backend en ajoutant temporairement :

```yaml
          env:
            - name: LOG_LEVEL_DISPLAY
              value: {{ .Values.backend.logLevel | upper | quote }}
```

### 6.2 La fonction `default`

Ajoutez un paramètre optionnel `backend.port` qui, s'il n'est pas défini, utilise `5000` :

```yaml
# Dans le template
containerPort: {{ .Values.backend.service.port | default 5000 }}
```

### 6.3 La fonction `toYaml` et `nindent`

C'est la combinaison la plus importante du templating Helm. Elle permet d'injecter un bloc YAML entier depuis `values.yaml` en conservant l'indentation.

Ajoutez la gestion des `resources` dans le frontend (elle était `{}` jusqu'ici) :

```yaml
# Dans values.yaml
frontend:
  resources:
    limits:
      cpu: "200m"
      memory: "128Mi"
    requests:
      cpu: "50m"
      memory: "64Mi"
```

```yaml
# Dans le template frontend
          resources:
            {{- toYaml .Values.frontend.resources | nindent 12 }}
```

**Pourquoi `nindent 12` ?** L'indentation de `resources:` dans un pod spec est de 10 espaces. `nindent 12` ajoute un saut de ligne initial **et** 12 espaces à chaque ligne injectée, ce qui aligne correctement `limits:` et `requests:` sous `resources:`.

---

## Étape 7 : Accès aux fichiers externes avec `.Files`

Plutôt qu'injecter la configuration Nginx via l'image Docker, nous pouvons la gérer via une `ConfigMap` Helm.

### 7.1 Créer le fichier de configuration

Créez `devops-news-v2/config/nginx.conf` :

```nginx
server {
    listen 80;
    server_name _;

    root /usr/share/nginx/html;
    index index.html;

    location / {
        try_files $uri $uri/ /index.html;
    }

    location /api/ {
        proxy_pass http://{{ BACKEND_SERVICE }}:5000/;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
    }
}
```

### 7.2 Créer le template ConfigMap

Créez `devops-news-v2/templates/frontend-config.yaml` :

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: {{ include "devops-news.fullname" (dict "root" . "component" "frontend-config") }}
  labels:
    {{- include "devops-news.labels" (dict "root" . "component" "frontend") | nindent 4 }}
data:
  nginx.conf: |
    {{- .Files.Get "config/nginx.conf" | nindent 4 }}
```

### 7.3 Valider

```bash
helm template test ./devops-news-v2 | grep -A 20 "kind: ConfigMap"
```

Le contenu du fichier `nginx.conf` doit apparaître dans la ConfigMap générée.

> **Sécurité :** `.Files.Get` ne permet pas de sortir du répertoire du chart. Vous ne pouvez pas accéder à `/etc/passwd` ou à des fichiers en dehors du dossier `devops-news-v2/`.

---

## Étape 8 : Validation et déploiement final

```bash
# Lint complet
helm lint ./devops-news-v2

# Bump de version dans Chart.yaml
sed -i 's/version: 0.1.0/version: 0.2.0/' devops-news-v2/Chart.yaml

# Déploiement
kubectl create namespace devops-news-lab4
helm install news ./devops-news-v2 --namespace devops-news-lab4

# Vérification des labels Kubernetes
kubectl get pods -n devops-news-lab4 --show-labels
```

Les pods doivent afficher les labels `app.kubernetes.io/managed-by=Helm`, `helm.sh/chart=devops-news-0.2.0`, etc.

---

## ✅ Validation finale

1. `helm lint ./devops-news-v2` : zéro erreur.
2. Le CronJob est absent quand `cleaner.enabled=false`.
3. Les `extraEnv` s'injectent correctement dans les pods backend.
4. Les labels standards `app.kubernetes.io/*` sont présents sur toutes les ressources.
5. La ConfigMap nginx est générée avec le contenu du fichier externe.

---

## Nettoyage

```bash
helm uninstall news -n devops-news-lab4
kubectl delete namespace devops-news-lab4
```
