# Lab Helm 6 — Intégration avec Kustomize

## 🎯 Objectif

Dans ce lab, vous allez explorer deux scénarios complémentaires de collaboration entre Helm et Kustomize : le **post-rendering** (patcher la sortie d'un chart tiers en temps réel) et l'**approche hybride** (Helm génère la base, Kustomize gère les overlays d'environnement).

**Module couvert :** 7 (Intégration avec Kustomize)

**Temps estimé :** 1h00 - 1h15

---

## 📋 Pré-requis

1. Avoir terminé les Labs 3 et 4.
2. `kustomize` installé :
```bash
curl -s "https://raw.githubusercontent.com/kubernetes-sigs/kustomize/master/hack/install_kustomize.sh" | bash
sudo mv kustomize /usr/local/bin/
kustomize version
```
3. Se placer dans le dossier : `cd helm/`

---

## Contexte : Quand choisir quoi ?

| Situation | Outil recommandé |
|-----------|-----------------|
| Vous créez votre propre application | **Helm from scratch** (Labs 3-5) |
| Vous utilisez un chart communautaire et voulez le personnaliser légèrement | **Helm + Post-rendering Kustomize** |
| Vous gérez plusieurs environnements avec des différences mineures | **Helm values files** (Lab 2) |
| Les différences entre environnements sont structurelles (ajout/suppression de ressources) | **Kustomize overlays** sur la sortie Helm |

---

## Étape 1 : Le problème du chart tiers non personnalisable

Imaginons que votre entreprise impose une annotation de sécurité sur **tous** les Pods déployés dans le cluster, pour le SIEM (Security Information and Event Management) :

```yaml
annotations:
  security.corporate.com/scanned: "true"
  security.corporate.com/team: "platform"
```

Le chart `devops-news-v3` ne propose pas cette annotation dans son `values.yaml`. Plutôt que de modifier le chart (et perdre les mises à jour futures), nous allons utiliser Kustomize comme **post-renderer**.

---

## Étape 2 : Le Post-Renderer Helm + Kustomize

Le post-renderer est un mécanisme qui intercepte le YAML généré par Helm **avant** qu'il soit envoyé à Kubernetes, pour le modifier à la volée.

```
helm install ... --post-renderer ./script.sh
                         │
                Helm génère le YAML
                         │
              Helm passe le YAML via STDIN
              au script post-renderer
                         │
              Le script modifie le YAML
              (ici via Kustomize)
                         │
              Helm envoie le YAML modifié
              à l'API Server Kubernetes
```

### 2.1 Créer la structure Kustomize

```bash
mkdir -p helm/post-render/patches
```

### 2.2 Créer le `kustomization.yaml`

Créez `helm/post-render/kustomization.yaml` :

```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

# Kustomize va lire les ressources depuis STDIN (envoyé par Helm)
resources:
  - all.yaml

# Patch pour ajouter les annotations de sécurité sur tous les Deployments
patches:
  - path: patches/security-annotations.yaml
    target:
      kind: Deployment
  - path: patches/security-annotations.yaml
    target:
      kind: StatefulSet
  - path: patches/security-annotations.yaml
    target:
      kind: CronJob
```

### 2.3 Créer le patch d'annotations

Créez `helm/post-render/patches/security-annotations.yaml` :

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: placeholder  # Sera ignoré — c'est le `target` du kustomization.yaml qui cible
spec:
  template:
    metadata:
      annotations:
        security.corporate.com/scanned: "true"
        security.corporate.com/team: "platform"
        security.corporate.com/scan-date: "2026-01-01"
```

### 2.4 Créer le script wrapper

Helm ne sait pas parler directement à Kustomize (Helm envoie un flux YAML continu, Kustomize attend un fichier). Nous avons besoin d'un script intermédiaire.

Créez `helm/post-render/kustomize-wrapper.sh` :

```bash
#!/bin/bash
# Ce script reçoit le YAML de Helm via STDIN,
# le sauvegarde dans un fichier temporaire,
# le passe à Kustomize, puis envoie le résultat vers STDOUT.

set -e

# Répertoire de ce script
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Sauvegarder le YAML de Helm dans un fichier temporaire
cat > "${SCRIPT_DIR}/all.yaml"

# Lancer Kustomize et envoyer le résultat vers STDOUT (récupéré par Helm)
kustomize build "${SCRIPT_DIR}"
```

```bash
chmod +x helm/post-render/kustomize-wrapper.sh
```

### 2.5 Tester le post-renderer

```bash
kubectl create namespace devops-news-lab6

helm install news-patched ./devops-news-v3 \
  --namespace devops-news-lab6 \
  --post-renderer ./post-render/kustomize-wrapper.sh \
  --dry-run 2>&1 | grep -A 5 "security.corporate.com"
```

Vous devriez voir les annotations de sécurité dans le YAML généré.

### 2.6 Déploiement réel

```bash
helm install news-patched ./devops-news-v3 \
  --namespace devops-news-lab6 \
  --post-renderer ./post-render/kustomize-wrapper.sh
```

Vérifiez que les annotations sont bien présentes sur les Pods :

```bash
kubectl get pods -n devops-news-lab6 -o jsonpath='{.items[0].metadata.annotations}' | python3 -m json.tool
```

---

## Étape 3 : L'approche hybride — Helm base + Kustomize overlays

Dans ce scénario, Helm génère le YAML de base que Kustomize enrichit via des overlays d'environnement. C'est utile quand les différences entre environnements sont **structurelles** (ex : ajout d'un sidecar en prod, suppression d'un service en dev).

### 3.1 Générer la base avec `helm template`

```bash
mkdir -p helm/kustomize-hybrid/base

# Helm génère le manifest de base et le sauvegarde
helm template devops-news ./devops-news-v3 \
  --namespace devops-news-lab6 \
  > helm/kustomize-hybrid/base/all.yaml
```

### 3.2 Créer le `kustomization.yaml` de base

Créez `helm/kustomize-hybrid/base/kustomization.yaml` :

```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

resources:
  - all.yaml
```

### 3.3 Créer l'overlay Dev

```bash
mkdir -p helm/kustomize-hybrid/overlays/dev
```

Créez `helm/kustomize-hybrid/overlays/dev/kustomization.yaml` :

```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

resources:
  - ../../base

namespace: devops-news-dev

commonLabels:
  env: dev

patches:
  # Réduire les réplicas en dev
  - target:
      kind: Deployment
      name: devops-news-backend
    patch: |-
      - op: replace
        path: /spec/replicas
        value: 1
  - target:
      kind: Deployment
      name: devops-news-frontend
    patch: |-
      - op: replace
        path: /spec/replicas
        value: 1
  # Passer le service frontend en ClusterIP (pas de LoadBalancer en dev)
  - target:
      kind: Service
      name: devops-news-frontend
    patch: |-
      - op: replace
        path: /spec/type
        value: ClusterIP
```

### 3.4 Créer l'overlay Prod

```bash
mkdir -p helm/kustomize-hybrid/overlays/prod
```

Créez `helm/kustomize-hybrid/overlays/prod/kustomization.yaml` :

```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

resources:
  - ../../base

namespace: devops-news-prod

commonLabels:
  env: prod
  tier: gold

patches:
  # Haute disponibilité en prod
  - target:
      kind: Deployment
      name: devops-news-backend
    patch: |-
      - op: replace
        path: /spec/replicas
        value: 3
      - op: add
        path: /spec/template/spec/containers/0/resources
        value:
          limits:
            cpu: "500m"
            memory: "256Mi"
          requests:
            cpu: "100m"
            memory: "128Mi"
  - target:
      kind: Deployment
      name: devops-news-frontend
    patch: |-
      - op: replace
        path: /spec/replicas
        value: 2
```

### 3.5 Prévisualiser les overlays

```bash
# Preview dev
kubectl kustomize helm/kustomize-hybrid/overlays/dev | grep -E "replicas:|type: "

# Preview prod
kubectl kustomize helm/kustomize-hybrid/overlays/prod | grep -E "replicas:|resources:"
```

### 3.6 Déploiement des deux environnements

```bash
kubectl create namespace devops-news-dev
kubectl create namespace devops-news-prod

kubectl apply -k helm/kustomize-hybrid/overlays/dev
kubectl apply -k helm/kustomize-hybrid/overlays/prod

# Comparer les pods
echo "=== DEV ===" && kubectl get pods -n devops-news-dev
echo "=== PROD ===" && kubectl get pods -n devops-news-prod
```

---

## Étape 4 : Réflexion — Helm vs Kustomize vs Hybride

**Exercice de réflexion :** Pour chaque scénario suivant, indiquez quelle approche vous utiliseriez et pourquoi.

| Scénario | Approche recommandée | Justification |
|----------|---------------------|---------------|
| Vous distribuez votre app à 10 clients différents | ? | |
| Vous déployez Prometheus (chart communautaire) et devez ajouter un label propriétaire | ? | |
| Vous avez Dev/Staging/Prod avec des différences uniquement de réplicas et LOG_LEVEL | ? | |
| Vous avez Dev/Prod avec un sidecar Vault Agent uniquement en Prod | ? | |

> **Réponses attendues :** Helm from scratch / Post-renderer / Values files / Kustomize overlay

---

## Étape 5 : Mise en garde — quand arrêter Kustomize

Si vous vous retrouvez à patcher plus de 50% du YAML généré par Helm via Kustomize, c'est un signal fort : il est temps de créer votre propre chart from scratch (cf. Lab 3) plutôt que de s'appuyer sur un chart tiers.

```bash
# Mesurer grossièrement le ratio patch/total
TOTAL=$(helm template test ./devops-news-v3 | wc -l)
PATCHED=$(diff \
  <(helm template test ./devops-news-v3) \
  <(helm template test ./devops-news-v3 --post-renderer ./post-render/kustomize-wrapper.sh) \
  | grep "^>" | wc -l)
echo "Lignes patchées : $PATCHED / $TOTAL total"
```

---

## ✅ Validation finale

1. Les annotations de sécurité sont présentes sur tous les Deployments, StatefulSets et CronJobs.
2. Les overlays Dev et Prod diffèrent bien en termes de réplicas.
3. `kubectl kustomize overlays/dev` génère un YAML valide sans erreur.

---

## Nettoyage

```bash
helm uninstall news-patched -n devops-news-lab6
kubectl delete -k helm/kustomize-hybrid/overlays/dev
kubectl delete -k helm/kustomize-hybrid/overlays/prod
kubectl delete namespace devops-news-lab6 devops-news-dev devops-news-prod
```
