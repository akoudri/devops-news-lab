# Lab Helm 3 — Créer le Chart DevOps-News From Scratch

## 🎯 Objectif

C'est le lab central de la formation. Vous allez créer **de zéro** le chart Helm complet de l'application **DevOps-News**, en packager une version et la déployer sur GKE.

Ce lab est **autonome** : les consignes décrivent ce que le chart doit produire, mais c'est à vous d'écrire les templates. Une solution complète est disponible en [Annexe](#-annexe--solution-complète).

**Module couvert :** 4 (Développement de Charts from scratch)

**Temps estimé :** 2h00 - 2h30

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

## Étape 8 : Gestion des dépendances — Redis comme sous-chart

Jusqu'ici, vous avez géré Redis avec vos propres templates (StatefulSet + Service + Secret). C'est une approche valide pour apprendre, mais en production on préfère déléguer les composants tiers à des charts éprouvés et maintenus par la communauté.

Helm gère cela via le mécanisme de **dépendances** déclaré dans `Chart.yaml`.

### 8.1 Comprendre les deux approches

| Approche | Avantage | Inconvénient |
|---|---|---|
| Templates maison (Labs 3-5) | Contrôle total, pédagogique | Maintenance à votre charge |
| Sous-chart communautaire | Maintenu, sécurisé, éprouvé | Moins de contrôle fin |

### 8.2 Déclarer la dépendance dans `Chart.yaml`

Ajoutez le bloc `dependencies` à la fin de `devops-news/Chart.yaml` :

```yaml
dependencies:
  - name: redis
    version: "25.x.x"           # Contrainte SemVer — accepte toutes les 25.x.x
    repository: "oci://registry-1.docker.io/bitnamicharts"
    condition: redis.enabled     # La même clé que votre values.yaml existant
    alias: redis                 # Nom utilisé pour accéder aux values du sous-chart
```

> **`condition`** est la clé : si `redis.enabled: false` dans les values, le sous-chart entier est ignoré lors du déploiement. C'est le même paramètre que celui déjà défini dans votre `values.yaml`.

### 8.3 Résoudre les dépendances

```bash
# Télécharge le chart bitnami/redis dans devops-news/charts/
helm dependency update ./devops-news

# Vérifier ce qui a été téléchargé
ls devops-news/charts/
# → redis-25.x.x.tgz

# Inspecter le fichier de verrouillage généré
cat devops-news/Chart.lock
```

Le fichier `Chart.lock` est l'équivalent d'un `package-lock.json` : il **fige la version exacte** résolue (`19.6.4` par exemple) pour garantir que tous les membres de l'équipe et tous les déploiements utilisent exactement le même sous-chart.

> **Règle d'or :** `Chart.lock` doit être commité dans Git. Le dossier `charts/` ne doit **pas** l'être (ajoutez-le dans `.helmignore`).

```bash
echo "charts/" >> devops-news/.helmignore
```

### 8.4 Adapter `values.yaml` pour le sous-chart

Le sous-chart Bitnami Redis s'attend à recevoir sa configuration sous la clé `redis` (ou l'alias déclaré). Remplacez le bloc `redis` de votre `values.yaml` par :

```yaml
# ─────────────────────────────────────────
# Redis — géré par le sous-chart bitnami/redis
# ─────────────────────────────────────────
redis:
  enabled: true
  # Paramètres natifs du chart bitnami/redis
  auth:
    enabled: true
    password: "supersecret"
  master:
    persistence:
      storageClass: "standard-rwo"
      size: "1Gi"
  replica:
    replicaCount: 0              # Pas de réplicas en mode standalone
  architecture: standalone
```

### 8.5 Adapter les templates backend et cleaner

Le sous-chart Bitnami crée son propre Service Redis. Son nom suit la convention `<release>-redis-master`. Mettez à jour la variable `REDIS_HOST` dans `templates/backend.yaml` et `templates/cleaner.yaml` :

```yaml
- name: REDIS_HOST
  value: "{{ .Release.Name }}-redis-master"
```

Et pour le Secret, Bitnami crée son propre Secret nommé `<release>-redis`. Remplacez la référence au `secretKeyRef` :

```yaml
- name: REDIS_PASSWORD
  valueFrom:
    secretKeyRef:
      name: {{ .Release.Name }}-redis
      key: redis-password          # Clé utilisée par le chart Bitnami
```

Vous pouvez maintenant supprimer vos fichiers `templates/redis.yaml` et `templates/redis-secret.yaml` — ils sont remplacés par le sous-chart.

### 8.6 Valider et déployer

```bash
# Lint — Helm résout automatiquement les templates du sous-chart
helm lint ./devops-news

# Dry-run pour voir les ressources générées par le sous-chart
helm install news ./devops-news \
  --namespace devops-news-lab3-deps \
  --create-namespace \
  --dry-run --debug 2>&1 | grep "kind:"

# Installation réelle
helm install news ./devops-news \
  --namespace devops-news-lab3-deps \
  --create-namespace
```

Observez que Kubernetes crée maintenant un `StatefulSet` Redis géré par Bitnami, avec des `readinessProbe`, `livenessProbe` et une configuration TLS optionnelle — sans que vous ayez écrit une seule ligne de YAML Redis.

```bash
# Lister les dépendances résolues
helm dependency list ./devops-news

kubectl get all -n devops-news-lab3-deps
```

### 8.7 Nettoyage de cette étape

```bash
helm uninstall news -n devops-news-lab3-deps
kubectl delete namespace devops-news-lab3-deps
```

---

## Étape 9 : Publication sur un registre OCI

Un chart packagé en `.tgz` n'a de valeur que s'il est **distribué**. Nous allons publier le chart sur **GitHub Packages** (registre OCI gratuit), la solution la plus directe pour une équipe utilisant GitHub.

> **Qu'est-ce qu'un registre OCI pour Helm ?** Depuis Helm 3.8, les charts peuvent être stockés et distribués via n'importe quel registre compatible OCI (le même protocole que Docker Hub). Plus besoin d'un serveur de repo Helm dédié — on réutilise l'infrastructure Docker existante.

### 9.1 Préparer le package

```bash
# Incrémenter la version du chart avant publication
# Dans Chart.yaml : version: 0.1.0 → 0.2.0
sed -i 's/^version: 0.1.0/version: 0.2.0/' devops-news/Chart.yaml

# Créer l'archive
helm package ./devops-news
ls -la devops-news-0.2.0.tgz
```

### 9.2 S'authentifier sur GitHub Packages

```bash
# Créer un Personal Access Token GitHub avec le scope write:packages
# https://github.com/settings/tokens

export GITHUB_TOKEN=<votre-token>
export GITHUB_USER=<votre-username>

echo $GITHUB_TOKEN | helm registry login ghcr.io \
  --username $GITHUB_USER \
  --password-stdin
```

### 9.3 Pousser le chart

```bash
helm push devops-news-0.2.0.tgz oci://ghcr.io/$GITHUB_USER/helm-charts
```

La sortie doit ressembler à :
```
Pushed: ghcr.io/<user>/helm-charts/devops-news:0.2.0
Digest: sha256:a3f2...
```

### 9.4 Inspecter le chart publié

```bash
# Afficher les métadonnées du chart distant (sans l'installer)
helm show chart oci://ghcr.io/$GITHUB_USER/helm-charts/devops-news --version 0.2.0

# Afficher les valeurs configurables
helm show values oci://ghcr.io/$GITHUB_USER/helm-charts/devops-news --version 0.2.0
```

### 9.5 Installer directement depuis le registre OCI

La puissance du registre OCI : n'importe quelle équipe peut maintenant installer votre chart **sans cloner votre dépôt Git** :

```bash
kubectl create namespace devops-news-oci

helm install news-oci \
  oci://ghcr.io/$GITHUB_USER/helm-charts/devops-news \
  --version 0.2.0 \
  --namespace devops-news-oci
```

### 9.6 Sécuriser avec un Digest (Helm v4 — bonne pratique)

En spécifiant un tag (`:0.2.0`), vous vous exposez à une éventuelle mutation du tag. La pratique la plus sûre est d'utiliser le **digest SHA256**, immuable par définition :

```bash
# Récupérer le digest
DIGEST=$(helm show chart oci://ghcr.io/$GITHUB_USER/helm-charts/devops-news \
  --version 0.2.0 2>/dev/null | grep -i digest || \
  echo "sha256:$(helm pull oci://ghcr.io/$GITHUB_USER/helm-charts/devops-news \
  --version 0.2.0 --prov 2>/dev/null; sha256sum devops-news-0.2.0.tgz | cut -d' ' -f1)")

# Installation par digest (immuable — garantit exactement ce qui a été publié)
helm install news-pinned \
  oci://ghcr.io/$GITHUB_USER/helm-charts/devops-news@$DIGEST \
  --namespace devops-news-oci
```

### 9.7 Nettoyage de cette étape

```bash
helm uninstall news-oci -n devops-news-oci
helm uninstall news-pinned -n devops-news-oci
kubectl delete namespace devops-news-oci
helm registry logout ghcr.io
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
