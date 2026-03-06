# Lab Helm 1 — Découverte & Prise en main

## 🎯 Objectif

Ce premier lab a pour but de vous familiariser avec l'écosystème Helm avant de toucher à notre application **DevOps-News**. Vous allez installer Helm, explorer Artifact Hub, déployer un chart communautaire et manipuler le cycle de vie d'une release (install, upgrade, rollback, uninstall).

**Modules couverts :** 1 (Écosystème Cloud Native) & 2 (Commandes fondamentales)

**Temps estimé :** 45 min - 1h00

---

## 📋 Pré-requis

1. Avoir un cluster GKE opérationnel et `kubectl` configuré.
2. Se placer dans le dossier du lab : `cd helm/`.

---

## Étape 1 : Installation et vérification

### 1.1 Installer Helm

```bash
curl -fsSL -o get_helm.sh https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-4
chmod +x get_helm.sh
./get_helm.sh
```

### 1.2 Vérifier l'installation

```bash
helm version
```

Vous devriez voir s'afficher la version du binaire Helm ainsi que sa version du protocole. Helm est un **binaire client uniquement** — contrairement à Helm v2, il n'y a aucun composant serveur à installer dans le cluster.

### 1.3 Configurer l'auto-complétion (fortement recommandé)

```bash
helm completion bash | sudo tee /etc/bash_completion.d/helm > /dev/null
source /etc/bash_completion.d/helm
```

Tapez `helm ` puis appuyez sur `Tab` deux fois pour vérifier que l'auto-complétion fonctionne.

> **Pourquoi Helm connaît-il votre cluster ?** Helm utilise le même fichier `~/.kube/config` que `kubectl`. Il n'a besoin d'aucune configuration supplémentaire.

---

## Étape 2 : Explorer Artifact Hub

Artifact Hub est la place de marché centrale pour les charts Helm, l'équivalent de Docker Hub pour les images.

### 2.1 Ajouter le repository Bitnami

```bash
helm repo add bitnami https://charts.bitnami.com/bitnami
helm repo update
```

### 2.2 Explorer les charts disponibles

```bash
# Lister tous les repos configurés localement
helm repo list

# Rechercher nginx dans les repos locaux
helm search repo nginx

# Rechercher sur Artifact Hub (nécessite une connexion internet)
helm search hub nginx
```

**Questions de réflexion :**
- Quelle est la différence entre `helm search repo` et `helm search hub` ?
- Que représentent les colonnes `CHART VERSION` et `APP VERSION` ?

### 2.3 Inspecter un chart avant de l'installer

```bash
# Afficher la description et les métadonnées du chart
helm show chart bitnami/nginx

# Afficher tous les paramètres configurables
helm show values bitnami/nginx
```

Prenez le temps de parcourir les paramètres disponibles. Notez en particulier les sections `replicaCount`, `service`, et `resources`.

---

## Étape 3 : Première Release

### 3.1 Créer un namespace dédié

```bash
kubectl create namespace helm-decouverte
```

### 3.2 Installer le chart nginx

Nous allons déployer nginx en surchargeant deux paramètres :
- 2 réplicas (au lieu de 1 par défaut)
- Un service de type `ClusterIP` (pas de LoadBalancer pour ce test)

```bash
helm install mon-serveur bitnami/nginx \
  --namespace helm-decouverte \
  --set replicaCount=2 \
  --set service.type=ClusterIP
```

### 3.3 Vérifier l'état de la release

```bash
# Vue d'ensemble de toutes les releases
helm list -n helm-decouverte

# Détails et ressources créées par cette release
helm status mon-serveur -n helm-decouverte

# Vérifier les pods créés par Helm dans Kubernetes
kubectl get all -n helm-decouverte
```

**Observez :** Les ressources Kubernetes portent le nom de la release (`mon-serveur-nginx`). C'est le mécanisme qui permet d'installer plusieurs instances du même chart dans un même cluster.

### 3.4 Inspecter les valeurs actives

```bash
# Voir uniquement les valeurs que VOUS avez surchargées
helm get values mon-serveur -n helm-decouverte

# Voir TOUTES les valeurs (les vôtres + les valeurs par défaut)
helm get values mon-serveur --all -n helm-decouverte

# Voir le manifest YAML complet qui a été envoyé à Kubernetes
helm get manifest mon-serveur -n helm-decouverte
```

---

## Étape 4 : Cycle de vie d'une Release

### 4.1 Upgrade — Modifier la configuration

Le client vous demande de passer à 4 réplicas sans interruption de service.

```bash
helm upgrade mon-serveur bitnami/nginx \
  --namespace helm-decouverte \
  --set replicaCount=4 \
  --set service.type=ClusterIP
```

Observez le déploiement progressif :

```bash
kubectl get pods -n helm-decouverte -w
```

### 4.2 Consulter l'historique

```bash
helm history mon-serveur -n helm-decouverte
```

Vous voyez maintenant deux révisions :
- **Révision 1** : l'installation initiale (2 réplicas)
- **Révision 2** : le upgrade (4 réplicas)

### 4.3 Rollback — Revenir en arrière

"Oups, 4 réplicas sur ce cluster de test, c'est trop. Retour à la révision 1."

```bash
helm rollback mon-serveur 1 -n helm-decouverte
```

Vérifiez que les pods sont revenus à 2 réplicas :

```bash
kubectl get pods -n helm-decouverte
helm history mon-serveur -n helm-decouverte
```

> **Notez :** Le rollback crée une nouvelle révision (révision 3). Helm ne supprime jamais l'historique — il ajoute toujours un nouvel état.

---

## Étape 5 : La différence entre `helm template` et `--dry-run`

Ces deux commandes permettent de prévisualiser ce que Helm va déployer, mais elles fonctionnent différemment.

### 5.1 `helm template` — Rendu local, sans cluster

```bash
helm template mon-test bitnami/nginx \
  --set replicaCount=3 \
  --set service.type=LoadBalancer
```

Cette commande **n'a pas besoin d'un cluster actif**. Elle rend le YAML en local et l'affiche dans le terminal. Idéale pour un pipeline CI/CD qui n'a pas accès au cluster.

### 5.2 `--dry-run --debug` — Simulation avec validation côté serveur

```bash
helm install mon-test bitnami/nginx \
  --namespace helm-decouverte \
  --set replicaCount=3 \
  --set service.type=LoadBalancer \
  --dry-run --debug
```

Cette commande **contacte le cluster** et fait valider le YAML par l'API Server Kubernetes. Elle détecte donc des erreurs que `helm template` ne voit pas (ex : CRD manquante, quota de namespace dépassé).

> **Règle d'usage :**
> - En CI/CD sans accès cluster → `helm template`
> - Pour tester une configuration avant d'appliquer → `--dry-run --debug`

---

## Étape 6 : Nettoyage

```bash
helm uninstall mon-serveur -n helm-decouverte
kubectl delete namespace helm-decouverte
```

Vérifiez qu'il ne reste aucune ressource :

```bash
kubectl get all -n helm-decouverte
```

---

## ✅ Validation finale

Avant de passer au Lab 2, assurez-vous de savoir répondre à ces questions :

1. Quelle est la différence entre un **Chart**, une **Release** et un **Repository** ?
2. Pourquoi Helm crée-t-il une **nouvelle révision** lors d'un rollback plutôt que de supprimer la révision précédente ?
3. Dans quel cas préfère-t-on `helm template` à `helm install --dry-run` ?
4. Où Helm stocke-t-il l'état des releases dans le cluster ? *(Indice : `kubectl get secrets -n helm-decouverte | grep helm`)*

---

## 💡 Pour aller plus loin

```bash
# Explorer les métadonnées de release stockées par Helm dans les Secrets K8s
kubectl get secrets -n <namespace> -l owner=helm

# Voir les variables d'environnement internes de Helm
helm env
```
