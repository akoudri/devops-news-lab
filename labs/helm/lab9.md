# Lab Helm 9 — Umbrella Chart & Helmfile

## 🎯 Objectif

Jusqu'ici, vous avez déployé l'application DevOps-News comme un seul chart. Mais dans un écosystème réel, une plateforme se compose de **dizaines de services** : l'application métier, du monitoring, de l'ingress, du logging... Gérer chaque `helm install` manuellement devient vite ingérable.

Ce lab vous apprend deux approches complémentaires pour orchestrer des déploiements multi-services :

- **L'Umbrella Chart** : un chart parent qui regroupe plusieurs sous-charts en une seule release Helm.
- **Helmfile** : un outil déclaratif qui pilote plusieurs releases Helm indépendantes depuis un seul fichier.

Vous saurez quand utiliser l'un, l'autre, ou les deux.

**Module couvert :** 9 (Orchestration multi-services)

**Temps estimé :** 1h30 - 2h00

---

## 📋 Pré-requis

1. Avoir terminé le Lab 3 (chart `devops-news` complet).
2. Cluster GKE opérationnel avec `kubectl` et `helm` configurés.
3. Se placer dans le dossier : `cd helm/`

---

## Partie A — Umbrella Chart

### Étape 1 : Comprendre le concept

Un **Umbrella Chart** (ou chart parapluie) est un chart Helm qui ne contient **aucun template propre** — uniquement des dépendances vers d'autres charts. Son rôle est d'assembler une plateforme complète en une seule commande.

```
devops-news-platform/          ← Umbrella Chart (pas de templates propres)
├── Chart.yaml                 ← Déclare les sous-charts comme dépendances
├── values.yaml                ← Configure tous les sous-charts depuis un seul fichier
└── charts/                    ← Sous-charts téléchargés par `helm dependency update`
    ├── devops-news-0.1.0.tgz
    ├── kube-prometheus-stack-*.tgz
    └── redis-*.tgz
```

**Quand l'utiliser :**
- Vous voulez déployer une stack complète en une seule release (`helm install platform .`).
- Les composants ont un **cycle de vie couplé** : ils montent et descendent ensemble.
- Vous voulez un point d'entrée unique pour un environnement (dev, staging, prod).

**Quand ne PAS l'utiliser :**
- Les composants ont des cycles de vie indépendants (ex : le monitoring ne doit pas redémarrer quand l'app change).
- L'équipe infra gère le monitoring et l'équipe app gère l'application — chacun doit pouvoir déployer indépendamment.

---

### Étape 2 : Créer l'Umbrella Chart

#### 2.1 Scaffolding

```bash
mkdir -p devops-news-platform
```

Créez le fichier `devops-news-platform/Chart.yaml` :

```yaml
apiVersion: v2
name: devops-news-platform
description: Umbrella Chart — DevOps-News + monitoring stack
type: application
version: 1.0.0
appVersion: "1.0.0"

dependencies:
  # Notre application DevOps-News (chart local)
  - name: devops-news
    version: "0.1.0"
    repository: "file://../devops-news"

  # Redis standalone depuis Bitnami
  - name: redis
    version: "~20.x"
    repository: "https://charts.bitnami.com/bitnami"
    condition: redis.enabled

  # Stack de monitoring (Prometheus + Grafana)
  - name: kube-prometheus-stack
    version: "~72.x"
    repository: "https://prometheus-community.github.io/helm-charts"
    condition: monitoring.enabled
```

> **Note :** La syntaxe `file://../devops-news` permet de référencer un chart local. En production, vous pointeriez vers un registry OCI ou un repo Helm.

#### 2.2 Comprendre les dépendances

Avant de continuer, examinons les mécanismes clés :

| Champ | Rôle |
|-------|------|
| `repository: "file://..."` | Référence un chart local sur le filesystem |
| `repository: "https://..."` | Référence un dépôt Helm distant |
| `version: "~20.x"` | Contrainte de version SemVer (dernière 20.x.x compatible) |
| `condition: redis.enabled` | Active/désactive la dépendance selon une valeur booléenne |

---

### Étape 3 : Configurer les valeurs globales

Créez le fichier `devops-news-platform/values.yaml` :

```yaml
# ──────────────────────────────────────────────
# Valeurs globales (partagées entre tous les sous-charts)
# ──────────────────────────────────────────────
global:
  environment: dev

# ──────────────────────────────────────────────
# Configuration du sous-chart devops-news
# ──────────────────────────────────────────────
devops-news:
  backend:
    replicaCount: 1
    image:
      repository: ghcr.io/votre-org/devops-news-backend
      tag: "latest"
    env:
      LOG_LEVEL: "DEBUG"
      REDIS_HOST: "devops-news-platform-redis-master"
  frontend:
    replicaCount: 1
  redis:
    # Désactiver le Redis embarqué dans le chart devops-news
    # car on utilise le Redis Bitnami de l'umbrella
    enabled: false

# ──────────────────────────────────────────────
# Configuration du sous-chart Redis (Bitnami)
# ──────────────────────────────────────────────
redis:
  enabled: true
  architecture: standalone
  auth:
    password: "devops-news-redis-password"
  master:
    resources:
      requests:
        cpu: 100m
        memory: 128Mi

# ──────────────────────────────────────────────
# Configuration du sous-chart kube-prometheus-stack
# ──────────────────────────────────────────────
monitoring:
  enabled: true

kube-prometheus-stack:
  prometheus:
    prometheusSpec:
      retention: 7d
      resources:
        requests:
          cpu: 200m
          memory: 512Mi
  grafana:
    adminPassword: "admin-devops-news"
    service:
      type: ClusterIP
  # Désactiver les composants non nécessaires pour le lab
  alertmanager:
    enabled: false
  nodeExporter:
    enabled: false
  kubeStateMetrics:
    enabled: false
```

> **Règle d'or :** Chaque clé de premier niveau dans `values.yaml` correspond au **nom** du sous-chart dans `Chart.yaml`. Helm injecte automatiquement les bonnes valeurs dans chaque sous-chart. Les valeurs sous `global:` sont accessibles par **tous** les sous-charts via `.Values.global`.

---

### Étape 4 : Construire et déployer

#### 4.1 Télécharger les dépendances

```bash
helm dependency update ./devops-news-platform
```

Observez le dossier `charts/` qui se remplit :

```bash
ls devops-news-platform/charts/
```

Vous devriez voir les archives `.tgz` des sous-charts téléchargés, ainsi qu'un fichier `Chart.lock` à la racine — c'est l'équivalent d'un `package-lock.json` pour Helm.

#### 4.2 Vérifier le rendu

Avant de déployer, inspectez les manifests générés :

```bash
helm template devops-news-platform ./devops-news-platform \
  --namespace devops-news-umbrella \
  | head -100
```

Vérifiez que :
- Les Deployments de devops-news sont présents.
- Le StatefulSet Redis Bitnami est généré.
- Les composants Prometheus/Grafana apparaissent.

#### 4.3 Installer

```bash
kubectl create namespace devops-news-umbrella

helm install devops-news-platform ./devops-news-platform \
  --namespace devops-news-umbrella \
  --wait --timeout 5m
```

#### 4.4 Vérifier le déploiement

```bash
# Voir tous les pods de la plateforme
kubectl get pods -n devops-news-umbrella

# Vérifier la release Helm
helm list -n devops-news-umbrella
```

Vous avez déployé **toute la plateforme** (application + Redis + monitoring) en une seule commande.

---

### Étape 5 : Surcharger par environnement

Créez un fichier `devops-news-platform/values-prod.yaml` pour la production :

```yaml
global:
  environment: prod

devops-news:
  backend:
    replicaCount: 3
    env:
      LOG_LEVEL: "WARNING"
  frontend:
    replicaCount: 2

redis:
  master:
    resources:
      requests:
        cpu: 500m
        memory: 512Mi

kube-prometheus-stack:
  prometheus:
    prometheusSpec:
      retention: 30d
      resources:
        requests:
          cpu: 1
          memory: 2Gi
```

Testez le rendu prod :

```bash
helm template devops-news-platform ./devops-news-platform \
  -f devops-news-platform/values-prod.yaml \
  --namespace devops-news-prod \
  | grep -E "replicas:|retention:"
```

> **Question :** Que se passe-t-il si une clé est définie dans `values.yaml` et dans `values-prod.yaml` ? Laquelle gagne ? Vérifiez avec `helm template` en comparant les deux rendus.

---

### Étape 6 : Limites de l'Umbrella Chart

Avant de passer à Helmfile, prenez un moment pour noter les limites que vous avez observées :

1. **Couplage fort** : un `helm upgrade` touche toute la stack. Modifier le LOG_LEVEL du backend redéploie aussi Prometheus.
2. **Versioning monolithique** : la version de l'umbrella n'est pas liée aux versions des composants individuels.
3. **Blast radius** : un template cassé dans un sous-chart bloque le déploiement de tout l'ensemble.
4. **Permissions** : l'équipe app ne peut pas déployer sans avoir aussi les droits sur le monitoring.

C'est exactement le problème que Helmfile résout.

---

## Partie B — Helmfile

### Étape 7 : Découvrir Helmfile

**Helmfile** est un outil déclaratif qui gère **plusieurs releases Helm indépendantes** depuis un seul fichier YAML. Contrairement à l'Umbrella Chart, chaque release a son propre cycle de vie.

```
Umbrella Chart :    1 release  → N sous-charts (couplés)
Helmfile :          N releases → N charts (indépendants)
```

#### 7.1 Installation

```bash
# Télécharger le binaire Helmfile
curl -sL https://github.com/helmfile/helmfile/releases/latest/download/helmfile_linux_amd64.tar.gz \
  | tar xz -C /tmp
sudo mv /tmp/helmfile /usr/local/bin/

# Vérifier l'installation
helmfile version
```

#### 7.2 Plugin helm-diff (obligatoire)

Helmfile utilise le plugin `helm-diff` pour afficher les changements avant de les appliquer :

```bash
helm plugin install https://github.com/databus23/helm-diff
```

---

### Étape 8 : Créer le Helmfile

Créez le dossier de travail et le fichier `helmfile/helmfile.yaml` :

```bash
mkdir -p helmfile
```

```yaml
# helmfile/helmfile.yaml

# ──────────────────────────────────────────────
# Dépôts Helm
# ──────────────────────────────────────────────
repositories:
  - name: bitnami
    url: https://charts.bitnami.com/bitnami
  - name: prometheus-community
    url: https://prometheus-community.github.io/helm-charts

# ──────────────────────────────────────────────
# Valeurs par défaut appliquées à toutes les releases
# ──────────────────────────────────────────────
helmDefaults:
  wait: true
  timeout: 300
  createNamespace: true

# ──────────────────────────────────────────────
# Releases
# ──────────────────────────────────────────────
releases:
  # --- Application DevOps-News ---
  - name: devops-news
    namespace: devops-news
    chart: ../devops-news
    version: ~0.1.0
    values:
      - ../devops-news/values.yaml
      - values/devops-news.yaml

  # --- Redis ---
  - name: redis
    namespace: devops-news
    chart: bitnami/redis
    version: ~20.0.0
    values:
      - values/redis.yaml

  # --- Monitoring ---
  - name: monitoring
    namespace: monitoring
    chart: prometheus-community/kube-prometheus-stack
    version: ~72.0.0
    values:
      - values/monitoring.yaml
```

Créez les fichiers de valeurs séparés :

```bash
mkdir -p helmfile/values
```

`helmfile/values/devops-news.yaml` :

```yaml
backend:
  replicaCount: 1
  env:
    LOG_LEVEL: "DEBUG"
    REDIS_HOST: "redis-master.devops-news.svc.cluster.local"
frontend:
  replicaCount: 1
```

`helmfile/values/redis.yaml` :

```yaml
architecture: standalone
auth:
  password: "devops-news-redis-password"
master:
  resources:
    requests:
      cpu: 100m
      memory: 128Mi
```

`helmfile/values/monitoring.yaml` :

```yaml
prometheus:
  prometheusSpec:
    retention: 7d
    resources:
      requests:
        cpu: 200m
        memory: 512Mi
grafana:
  adminPassword: "admin-devops-news"
  service:
    type: ClusterIP
alertmanager:
  enabled: false
nodeExporter:
  enabled: false
kubeStateMetrics:
  enabled: false
```

---

### Étape 9 : Déployer avec Helmfile

#### 9.1 Visualiser le plan

```bash
cd helmfile/
helmfile diff
```

Helmfile vous montre un **diff coloré** de ce qui va changer dans le cluster — exactement comme un `terraform plan`. Prenez le temps de lire la sortie.

#### 9.2 Appliquer

```bash
helmfile apply
```

Helmfile exécute séquentiellement les `helm install`/`upgrade` nécessaires. Chaque release est indépendante.

#### 9.3 Vérifier

```bash
# Lister les releases gérées par Helmfile
helmfile list

# Vérifier les pods
kubectl get pods -n devops-news
kubectl get pods -n monitoring
```

> **Comparaison clé :** Avec l'Umbrella Chart, un seul `helm list` montrait une release. Ici, `helmfile list` affiche **trois releases indépendantes**, chacune dans son namespace.

---

### Étape 10 : Environnements Helmfile

Le vrai pouvoir de Helmfile réside dans la gestion des environnements.

#### 10.1 Restructurer avec les environnements

Modifiez `helmfile/helmfile.yaml` pour ajouter des environnements :

```yaml
# helmfile/helmfile.yaml

repositories:
  - name: bitnami
    url: https://charts.bitnami.com/bitnami
  - name: prometheus-community
    url: https://prometheus-community.github.io/helm-charts

helmDefaults:
  wait: true
  timeout: 300
  createNamespace: true

# ──────────────────────────────────────────────
# Environnements
# ──────────────────────────────────────────────
environments:
  dev:
    values:
      - environments/dev.yaml
  prod:
    values:
      - environments/prod.yaml

# ──────────────────────────────────────────────
# Releases (utilisent les valeurs de l'environnement actif)
# ──────────────────────────────────────────────
releases:
  - name: devops-news
    namespace: devops-news-{{ .Environment.Name }}
    chart: ../devops-news
    version: ~0.1.0
    values:
      - ../devops-news/values.yaml
      - values/devops-news.yaml
      - values/devops-news.{{ .Environment.Name }}.yaml

  - name: redis
    namespace: devops-news-{{ .Environment.Name }}
    chart: bitnami/redis
    version: ~20.0.0
    values:
      - values/redis.yaml

  - name: monitoring
    namespace: monitoring-{{ .Environment.Name }}
    chart: prometheus-community/kube-prometheus-stack
    version: ~72.0.0
    values:
      - values/monitoring.yaml
    # Désactiver le monitoring en dev pour économiser les ressources
    installed: {{ eq .Environment.Name "prod" }}
```

#### 10.2 Créer les fichiers d'environnement

```bash
mkdir -p helmfile/environments
```

`helmfile/environments/dev.yaml` :

```yaml
environment: dev
```

`helmfile/environments/prod.yaml` :

```yaml
environment: prod
```

`helmfile/values/devops-news.dev.yaml` :

```yaml
backend:
  replicaCount: 1
  env:
    LOG_LEVEL: "DEBUG"
frontend:
  replicaCount: 1
```

`helmfile/values/devops-news.prod.yaml` :

```yaml
backend:
  replicaCount: 3
  env:
    LOG_LEVEL: "WARNING"
frontend:
  replicaCount: 2
```

#### 10.3 Déployer par environnement

```bash
# Déployer uniquement l'environnement dev
helmfile -e dev diff
helmfile -e dev apply

# Déployer la production
helmfile -e prod diff
helmfile -e prod apply
```

Vérifiez les namespaces créés :

```bash
kubectl get namespaces | grep devops-news
```

Vous devriez voir `devops-news-dev` et `devops-news-prod`.

> **Observation :** En dev, le monitoring n'est **pas installé** grâce à la directive `installed: {{ eq .Environment.Name "prod" }}`. Helmfile n'a même pas essayé de le déployer. C'est impossible avec un Umbrella Chart sans condition `if` dans chaque template.

---

### Étape 11 : Opérations ciblées

L'un des avantages majeurs de Helmfile : pouvoir agir sur une seule release sans toucher aux autres.

#### 11.1 Déployer une seule release

```bash
# Mettre à jour uniquement devops-news, sans toucher à Redis ni au monitoring
helmfile -e dev -l name=devops-news apply
```

#### 11.2 Détruire une seule release

```bash
helmfile -e dev -l name=redis destroy
```

#### 11.3 Synchroniser l'état complet

```bash
# S'assurer que le cluster correspond exactement au helmfile
helmfile -e dev sync
```

> **Différence `apply` vs `sync` :** `apply` ne modifie que ce qui a changé (comme `terraform apply`). `sync` force une mise à jour de toutes les releases, même sans changement.

---

### Étape 12 : Hooks Helmfile

Helmfile supporte des hooks pour exécuter des actions avant ou après les opérations Helm.

Ajoutez des hooks à la release `devops-news` dans votre `helmfile.yaml` :

```yaml
  - name: devops-news
    namespace: devops-news-{{ .Environment.Name }}
    chart: ../devops-news
    version: ~0.1.0
    values:
      - ../devops-news/values.yaml
      - values/devops-news.yaml
      - values/devops-news.{{ .Environment.Name }}.yaml
    hooks:
      - events: ["presync"]
        showlogs: true
        command: "kubectl"
        args:
          - "create"
          - "namespace"
          - "devops-news-{{ `{{.Environment.Name}}` }}"
          - "--dry-run=client"
          - "-o"
          - "yaml"
      - events: ["postsync"]
        showlogs: true
        command: "kubectl"
        args:
          - "get"
          - "pods"
          - "-n"
          - "devops-news-{{ `{{.Environment.Name}}` }}"
```

---

## Étape 13 : Matrice de décision

Prenez un moment pour comparer les approches couvertes dans ce lab et les labs précédents :

| Critère | Umbrella Chart | Helmfile | Argo CD (Lab 8) |
|---------|---------------|----------|-----------------|
| **Modèle** | 1 release, N sous-charts | N releases indépendantes | N Applications, auto-sync |
| **Couplage** | Fort (tout monte/descend ensemble) | Faible (chaque release est autonome) | Faible (chaque Application est autonome) |
| **Cycle de vie** | Unique | Indépendant par release | Indépendant par Application |
| **Diff avant apply** | `helm diff` (plugin) | `helmfile diff` (natif) | Argo CD UI / `argocd app diff` |
| **Multi-env** | Fichiers `-f values-prod.yaml` | `environments:` natif | ApplicationSets ou dossiers séparés |
| **Déploiement ciblé** | Impossible | `-l name=xxx` | Par Application |
| **Idéal pour** | Stack couplée, PoC, demo | Multi-services en CI/CD | Production avec self-healing |
| **Outil requis** | `helm` seul | `helmfile` + `helm-diff` | Argo CD dans le cluster |

> **En pratique**, Helmfile et Argo CD ne sont pas concurrents mais complémentaires. De nombreuses équipes utilisent Helmfile pour structurer leur configuration Helm, puis Argo CD pour le déploiement GitOps. Helmfile gère la complexité de la configuration ; Argo CD gère le déploiement et la réconciliation.

---

## ✅ Validation finale

Vérifiez que vous savez répondre à ces questions :

1. **Quelle est la différence fondamentale entre un Umbrella Chart et Helmfile ?**
2. **Pourquoi `helm dependency update` est nécessaire pour l'Umbrella Chart mais pas pour Helmfile ?**
3. **Comment désactiver un composant dans un Umbrella Chart ? Et dans Helmfile ?**
4. **Quelle commande Helmfile permet de voir les changements avant de les appliquer ?**
5. **Pourquoi Helmfile est-il plus adapté quand plusieurs équipes gèrent différents composants ?**
6. **Comment Helmfile et Argo CD peuvent-ils coexister dans un workflow GitOps ?**

---

## Nettoyage

```bash
# Supprimer les releases Helmfile
cd helmfile/
helmfile -e dev destroy
helmfile -e prod destroy

# Supprimer la release Umbrella Chart
helm uninstall devops-news-platform -n devops-news-umbrella --ignore-not-found

# Supprimer les namespaces
kubectl delete namespace devops-news-umbrella devops-news-dev devops-news-prod \
  monitoring-dev monitoring-prod --ignore-not-found
```

---

## 📚 Structure finale des fichiers

```
helm/
├── devops-news-platform/          ← Umbrella Chart (Partie A)
│   ├── Chart.yaml
│   ├── values.yaml
│   ├── values-prod.yaml
│   └── charts/                    ← Généré par helm dependency update
│
└── helmfile/                      ← Helmfile (Partie B)
    ├── helmfile.yaml
    ├── environments/
    │   ├── dev.yaml
    │   └── prod.yaml
    └── values/
        ├── devops-news.yaml
        ├── devops-news.dev.yaml
        ├── devops-news.prod.yaml
        ├── redis.yaml
        └── monitoring.yaml
```
