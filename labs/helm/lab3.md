# Lab Helm 3 — Créer le Chart DevOps-News From Scratch

## 🎯 Objectif

C'est le lab central de la formation. Vous allez créer **de zéro** le chart Helm complet de l'application **DevOps-News**, en packager une version et la déployer sur GKE.

Ce lab est **autonome** : les consignes décrivent ce que le chart doit produire, mais c'est à vous d'écrire les templates. Une solution complète est disponible en [Annexe](#-annexe--solution-complète).

**Module couvert :** 4 (Développement de Charts from scratch)

**Temps estimé :** 1h30 - 2h00

---

## 📋 Pré-requis

1. Avoir terminé les Labs 1 et 2.
2. Nettoyage préalable (si les namespaces du Lab 2 existent encore) :
```bash
helm uninstall devops-news-dev -n devops-news-dev --ignore-not-found
helm uninstall devops-news-prod -n devops-news-prod --ignore-not-found
kubectl delete namespace devops-news-dev devops-news-prod --ignore-not-found
```
3. Se placer dans le dossier : `cd helm/`

---

## Architecture du chart à produire

```
helm/devops-news/
├── Chart.yaml
├── values.yaml
├── .helmignore
└── templates/
    ├── backend.yaml      (Deployment + Service)
    ├── frontend.yaml     (Deployment + Service)
    ├── redis.yaml        (StatefulSet + Service)
    ├── redis-secret.yaml (Secret pour le mot de passe)
    └── cleaner.yaml      (CronJob)
```

---

## Étape 1 : Initialisation

### 1.1 Créer la structure de base

```bash
cd helm/
helm create devops-news
```

### 1.2 Nettoyer le boilerplate généré

Helm génère des templates d'exemple (Deployment nginx, Ingress, HPA, etc.) qui ne correspondent pas à notre application. Supprimez-les :

```bash
rm -rf devops-news/templates/*
rm -rf devops-news/tests/
# Vider le fichier values.yaml (on repart de zéro)
> devops-news/values.yaml
```

---

## Étape 2 : Définir `Chart.yaml`

Remplacez le contenu de `devops-news/Chart.yaml` par :

```yaml
apiVersion: v2
name: devops-news
description: Application de démonstration pour la formation Helm (Flask + Redis + Nginx)
type: application

# Version du package Helm (SemVer)
version: 0.1.0

# Version de l'application déployée
appVersion: "1.0.0"

maintainers:
  - name: Ali Koudri
    email: ali.koudri@janus-academy.fr

keywords:
  - demo
  - flask
  - redis
  - nginx
```

---

## Étape 3 : Définir `values.yaml`

Voici le contrat que votre chart doit exposer. Copiez ce contenu dans `devops-news/values.yaml` :

```yaml
# ─────────────────────────────────────────
# Images Docker
# ─────────────────────────────────────────
images:
  repoAccount: "pueblo2708"
  pullPolicy: IfNotPresent
  tags:
    backend: "latest"
    frontend: "latest"
    cleaner: "latest"

# ─────────────────────────────────────────
# Backend (API Flask)
# ─────────────────────────────────────────
backend:
  replicas: 2
  logLevel: "INFO"
  service:
    type: ClusterIP
    port: 5000
  resources: {}

# ─────────────────────────────────────────
# Frontend (Nginx)
# ─────────────────────────────────────────
frontend:
  replicas: 1
  service:
    type: LoadBalancer
    port: 80
  resources: {}

# ─────────────────────────────────────────
# Redis
# ─────────────────────────────────────────
redis:
  enabled: true
  password: "supersecret"
  storage: "1Gi"
  storageClassName: "standard-rwo"
  service:
    port: 6379

# ─────────────────────────────────────────
# Cleaner (CronJob)
# ─────────────────────────────────────────
cleaner:
  schedule: "*/2 * * * *"
  maxAgeSeconds: 3600
```

---

## Étape 4 : Créer les templates

Pour chaque template ci-dessous, vous disposez des **consignes** décrivant ce que le template doit produire. Écrivez le code vous-même. Validez chaque template avec `helm template` avant de passer au suivant.

### 4.1 Le Secret Redis — `templates/redis-secret.yaml`

**Consignes :**
- Créer un `Secret` Kubernetes de type `Opaque`.
- Le nom doit inclure le nom de la release : `{{ .Release.Name }}-redis-secret`.
- La clé du secret doit s'appeler `password`.
- La valeur doit être le mot de passe Redis **encodé en base64** via la fonction `b64enc`.
- Ce Secret ne doit être créé **que si** `redis.enabled` est `true`.

**Validation :**
```bash
helm template test ./devops-news | grep -A 10 "kind: Secret"
```

---

### 4.2 Redis — `templates/redis.yaml`

**Consignes :**
- Créer un `Service` ClusterIP nommé `{{ .Release.Name }}-redis` exposant le port `redis.service.port`.
- Créer un `StatefulSet` nommé `{{ .Release.Name }}-redis` avec :
  - 1 réplica
  - L'image `redis:6.0-alpine`
  - Le mot de passe injecté via `secretKeyRef` (référencer le Secret créé en 4.1)
  - Un `volumeMount` sur `/data`
  - Un `volumeClaimTemplates` de taille `redis.storage` avec la `storageClassName` configurée
- L'ensemble du bloc (Service + StatefulSet) ne doit être généré que si `redis.enabled` est `true`.

**Validation :**
```bash
helm template test ./devops-news | grep -A 5 "kind: StatefulSet"
```

---

### 4.3 Backend — `templates/backend.yaml`

**Consignes :**
- Créer un `Deployment` nommé `{{ .Release.Name }}-backend` avec :
  - `backend.replicas` réplicas
  - L'image construite dynamiquement : `images.repoAccount`/devops-news-api:`images.tags.backend`
  - Les variables d'environnement suivantes :
    - `REDIS_HOST` : valeur `{{ .Release.Name }}-redis` (le nom du service Redis)
    - `REDIS_PORT` : valeur `redis.service.port` (en tant que chaîne, utilisez `quote`)
    - `REDIS_PASSWORD` : injecté depuis le Secret Redis, clé `password`
    - `LOG_LEVEL` : valeur `backend.logLevel`
  - Un bloc `resources` injecté avec `toYaml` + `nindent` (supporte la valeur `{}`)
- Créer un `Service` ClusterIP nommé `{{ .Release.Name }}-backend` exposant `backend.service.port`.

**Validation :**
```bash
helm template test ./devops-news | grep -A 30 "kind: Deployment" | head -40
```

---

### 4.4 Frontend — `templates/frontend.yaml`

**Consignes :**
- Créer un `Deployment` nommé `{{ .Release.Name }}-frontend` avec :
  - `frontend.replicas` réplicas
  - L'image `images.repoAccount`/devops-news-front:`images.tags.frontend`
  - Le port conteneur `80`
- Créer un `Service` dont le type est `frontend.service.type`, exposant le port `frontend.service.port`.

> ⚠️ **Contrainte réseau :** Le Nginx de l'image `devops-news-front` est configuré pour proxifier vers `http://backend:5000`. Or, dans le chart Helm, le service backend s'appelle `{{ .Release.Name }}-backend`. L'image actuelle ne supporte pas encore cette configuration dynamique. Pour ce lab, utilisez l'image telle quelle et **documentez cette limitation** dans un commentaire YAML en tête du template.

**Validation :**
```bash
helm template test ./devops-news | grep -A 20 "kind: Service"
```

---

### 4.5 Cleaner — `templates/cleaner.yaml`

**Consignes :**
- Créer un `CronJob` nommé `{{ .Release.Name }}-cleaner` avec :
  - Le schedule défini par `cleaner.schedule`
  - `restartPolicy: OnFailure`
  - L'image `images.repoAccount`/devops-news-cleaner:`images.tags.cleaner`
  - Les variables d'environnement : `REDIS_HOST`, `REDIS_PASSWORD` (depuis le Secret), `MAX_AGE_SECONDS` (depuis `cleaner.maxAgeSeconds`, utilisez `quote`)

**Validation :**
```bash
helm template test ./devops-news | grep -A 30 "kind: CronJob"
```

---

## Étape 5 : Validation globale du chart

### 5.1 Lint

```bash
helm lint ./devops-news
```

Corrigez toutes les erreurs et avertissements avant de continuer.

### 5.2 Dry-run complet

```bash
kubectl create namespace devops-news-lab3

helm install news ./devops-news \
  --namespace devops-news-lab3 \
  --dry-run --debug 2>&1 | less
```

Parcourez le YAML généré et vérifiez que :
- Tous les noms de ressources commencent par `news-`
- Le Secret Redis est bien présent
- Les variables d'environnement sont correctement injectées

---

## Étape 6 : Déploiement et test

### 6.1 Installation

```bash
helm install news ./devops-news \
  --namespace devops-news-lab3
```

### 6.2 Vérification

```bash
kubectl get all -n devops-news-lab3
kubectl get pvc -n devops-news-lab3
kubectl get secret -n devops-news-lab3
```

### 6.3 Test fonctionnel

```bash
# Attendre l'IP externe
kubectl get svc news-frontend -n devops-news-lab3 -w

# Tester l'API backend via port-forward
kubectl port-forward svc/news-backend 5001:5000 -n devops-news-lab3 &
curl http://localhost:5001/health
curl -X POST http://localhost:5001/news \
  -H "Content-Type: application/json" \
  -d '{"title": "Helm fonctionne !", "content": "Mon premier chart from scratch"}'
curl http://localhost:5001/news
```

---

## Étape 7 : Packaging et distribution

Une fois le chart fonctionnel, créez une archive distribuable.

```bash
# Créer l'archive .tgz
helm package ./devops-news

# Inspecter le package créé
ls -la devops-news-0.1.0.tgz
helm show chart devops-news-0.1.0.tgz
helm show values devops-news-0.1.0.tgz
```

> **Pour aller plus loin :** Cette archive peut être publiée sur un registre OCI (GitHub Packages, Artifact Hub, Harbor) pour être partagée avec d'autres équipes.

---

## ✅ Validation finale

1. `helm lint ./devops-news` ne retourne aucune erreur.
2. Toutes les ressources sont en état `Running` ou `Completed`.
3. Le fichier `.tgz` est généré et inspectable.
4. Vous pouvez déployer une **deuxième instance** dans un autre namespace sans aucun conflit de noms :

```bash
kubectl create namespace devops-news-lab3-bis
helm install news-v2 ./devops-news --namespace devops-news-lab3-bis
kubectl get all -n devops-news-lab3-bis
```

---

## Nettoyage

```bash
helm uninstall news -n devops-news-lab3
helm uninstall news-v2 -n devops-news-lab3-bis
kubectl delete namespace devops-news-lab3 devops-news-lab3-bis
```

---

---

# 📎 Annexe : Solution Complète

> **Ne lisez cette section qu'après avoir tenté de réaliser le lab par vous-même.**

---

### `templates/redis-secret.yaml`

```yaml
{{- if .Values.redis.enabled }}
apiVersion: v1
kind: Secret
metadata:
  name: {{ .Release.Name }}-redis-secret
  labels:
    app.kubernetes.io/name: redis
    app.kubernetes.io/instance: {{ .Release.Name }}
type: Opaque
data:
  password: {{ .Values.redis.password | b64enc | quote }}
{{- end }}
```

---

### `templates/redis.yaml`

```yaml
{{- if .Values.redis.enabled }}
apiVersion: v1
kind: Service
metadata:
  name: {{ .Release.Name }}-redis
  labels:
    app.kubernetes.io/name: redis
    app.kubernetes.io/instance: {{ .Release.Name }}
spec:
  ports:
    - port: {{ .Values.redis.service.port }}
      targetPort: {{ .Values.redis.service.port }}
  selector:
    app.kubernetes.io/name: redis
    app.kubernetes.io/instance: {{ .Release.Name }}
---
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: {{ .Release.Name }}-redis
  labels:
    app.kubernetes.io/name: redis
    app.kubernetes.io/instance: {{ .Release.Name }}
spec:
  serviceName: {{ .Release.Name }}-redis
  replicas: 1
  selector:
    matchLabels:
      app.kubernetes.io/name: redis
      app.kubernetes.io/instance: {{ .Release.Name }}
  template:
    metadata:
      labels:
        app.kubernetes.io/name: redis
        app.kubernetes.io/instance: {{ .Release.Name }}
    spec:
      containers:
        - name: redis
          image: redis:6.0-alpine
          command:
            - redis-server
            - "--requirepass"
            - "$(REDIS_PASSWORD)"
            - "--appendonly"
            - "yes"
          env:
            - name: REDIS_PASSWORD
              valueFrom:
                secretKeyRef:
                  name: {{ .Release.Name }}-redis-secret
                  key: password
          ports:
            - containerPort: {{ .Values.redis.service.port }}
          volumeMounts:
            - name: data
              mountPath: /data
  volumeClaimTemplates:
    - metadata:
        name: data
      spec:
        accessModes: ["ReadWriteOnce"]
        storageClassName: {{ .Values.redis.storageClassName | quote }}
        resources:
          requests:
            storage: {{ .Values.redis.storage }}
{{- end }}
```

---

### `templates/backend.yaml`

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: {{ .Release.Name }}-backend
  labels:
    app.kubernetes.io/name: backend
    app.kubernetes.io/instance: {{ .Release.Name }}
    app.kubernetes.io/component: backend
spec:
  replicas: {{ .Values.backend.replicas }}
  selector:
    matchLabels:
      app.kubernetes.io/name: backend
      app.kubernetes.io/instance: {{ .Release.Name }}
  template:
    metadata:
      labels:
        app.kubernetes.io/name: backend
        app.kubernetes.io/instance: {{ .Release.Name }}
        app.kubernetes.io/component: backend
    spec:
      containers:
        - name: api
          image: "{{ .Values.images.repoAccount }}/devops-news-api:{{ .Values.images.tags.backend }}"
          imagePullPolicy: {{ .Values.images.pullPolicy }}
          ports:
            - containerPort: {{ .Values.backend.service.port }}
          env:
            - name: REDIS_HOST
              value: "{{ .Release.Name }}-redis"
            - name: REDIS_PORT
              value: {{ .Values.redis.service.port | quote }}
            - name: REDIS_PASSWORD
              valueFrom:
                secretKeyRef:
                  name: {{ .Release.Name }}-redis-secret
                  key: password
            - name: LOG_LEVEL
              value: {{ .Values.backend.logLevel | quote }}
          resources:
            {{- toYaml .Values.backend.resources | nindent 12 }}
---
apiVersion: v1
kind: Service
metadata:
  name: {{ .Release.Name }}-backend
  labels:
    app.kubernetes.io/name: backend
    app.kubernetes.io/instance: {{ .Release.Name }}
spec:
  type: {{ .Values.backend.service.type }}
  selector:
    app.kubernetes.io/name: backend
    app.kubernetes.io/instance: {{ .Release.Name }}
  ports:
    - port: {{ .Values.backend.service.port }}
      targetPort: {{ .Values.backend.service.port }}
```

---

### `templates/frontend.yaml`

```yaml
# NOTE : L'image devops-news-front proxifie en dur vers http://backend:5000
# Dans un déploiement Helm, le service backend se nomme {{ .Release.Name }}-backend.
# Cette limitation devra être corrigée en passant le nom du backend via une variable
# d'environnement Nginx dans une version future du chart.
apiVersion: apps/v1
kind: Deployment
metadata:
  name: {{ .Release.Name }}-frontend
  labels:
    app.kubernetes.io/name: frontend
    app.kubernetes.io/instance: {{ .Release.Name }}
spec:
  replicas: {{ .Values.frontend.replicas }}
  selector:
    matchLabels:
      app.kubernetes.io/name: frontend
      app.kubernetes.io/instance: {{ .Release.Name }}
  template:
    metadata:
      labels:
        app.kubernetes.io/name: frontend
        app.kubernetes.io/instance: {{ .Release.Name }}
    spec:
      containers:
        - name: web
          image: "{{ .Values.images.repoAccount }}/devops-news-front:{{ .Values.images.tags.frontend }}"
          imagePullPolicy: {{ .Values.images.pullPolicy }}
          ports:
            - containerPort: 80
          resources:
            {{- toYaml .Values.frontend.resources | nindent 12 }}
---
apiVersion: v1
kind: Service
metadata:
  name: {{ .Release.Name }}-frontend
  labels:
    app.kubernetes.io/name: frontend
    app.kubernetes.io/instance: {{ .Release.Name }}
spec:
  type: {{ .Values.frontend.service.type }}
  selector:
    app.kubernetes.io/name: frontend
    app.kubernetes.io/instance: {{ .Release.Name }}
  ports:
    - port: {{ .Values.frontend.service.port }}
      targetPort: 80
```

---

### `templates/cleaner.yaml`

```yaml
apiVersion: batch/v1
kind: CronJob
metadata:
  name: {{ .Release.Name }}-cleaner
  labels:
    app.kubernetes.io/name: cleaner
    app.kubernetes.io/instance: {{ .Release.Name }}
spec:
  schedule: {{ .Values.cleaner.schedule | quote }}
  jobTemplate:
    spec:
      template:
        spec:
          restartPolicy: OnFailure
          containers:
            - name: cleaner
              image: "{{ .Values.images.repoAccount }}/devops-news-cleaner:{{ .Values.images.tags.cleaner }}"
              imagePullPolicy: {{ .Values.images.pullPolicy }}
              env:
                - name: REDIS_HOST
                  value: "{{ .Release.Name }}-redis"
                - name: REDIS_PORT
                  value: {{ .Values.redis.service.port | quote }}
                - name: REDIS_PASSWORD
                  valueFrom:
                    secretKeyRef:
                      name: {{ .Release.Name }}-redis-secret
                      key: password
                - name: MAX_AGE_SECONDS
                  value: {{ .Values.cleaner.maxAgeSeconds | quote }}
```
