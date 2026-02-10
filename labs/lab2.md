# Lab 2 : Refactoring et Gestion d'Environnements avec Kustomize

## 🎯 Objectif

Dans le Lab 1, vous avez créé des fichiers YAML "en dur". Si demain, vous devez déployer en Production avec 10 réplicas et en Dev avec 1 seul, vous devriez copier-coller et modifier tous les fichiers... C'est ingérable.

**Kustomize** (intégré nativement à `kubectl`) résout ce problème par un système d'héritage (Base & Overlays).

**Temps estimé :** 45 min - 1h00

## 📋 Pré-requis

1. Avoir terminé le Lab 1.
2. Se placer dans le dossier : `cd k8s/02-kustomize`.

---

## Architecture du Dossier

Nous allons restructurer nos fichiers selon ce standard de l'industrie :

```text
k8s/02-kustomize/
├── base/                   # Le "tronc commun" (fichiers du Lab 1)
│   ├── deployment.yaml
│   ├── service.yaml
│   └── kustomization.yaml  # Le chef d'orchestre de la base
└── overlays/               # Les spécificités par environnement
    ├── dev/
    │   └── kustomization.yaml
    └── prod/
        └── kustomization.yaml

```

---

## Étape 1 : Création de la "Base"

La **Base** contient ce qui est commun à tous les environnements (les images Docker, les ports, les volumes).

### 1.1 Préparation des fichiers

1. Créez le dossier `base`.
2. Copiez vos fichiers YAML du Lab 1 (`03-redis.yaml`, `04-backend.yaml`, etc.) à l'intérieur de `base/`.
3. **Supprimez** les fichiers `01-secret.yaml` et `02-configmap.yaml` de la base. Nous allons les générer dynamiquement !

### 1.2 Le fichier `kustomization.yaml`

Créez un fichier `base/kustomization.yaml`. Il liste les ressources à inclure.

```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

resources:
  - 03-redis.yaml
  - 04-backend.yaml
  - 05-frontend.yaml
  - 06-cleaner.yaml

# On définit ici les configurations communes
configMapGenerator:
  - name: backend-config
    literals:
      - LOG_LEVEL=INFO # Valeur par défaut
```

---

## Étape 2 : L'Environnement de Développement (Overlay Dev)

L'environnement de Dev doit être économique et isolé.
Créez le dossier `overlays/dev` et créez-y un fichier `kustomization.yaml`.

### Ce que nous allons faire avec Kustomize :

1. **Namespace :** Tout forcer dans le namespace `dev-news`.
2. **Suffixe :** Ajouter `-dev` à tous les noms de ressources.
3. **Labels :** Ajouter un label `env: dev` partout.
4. **Patch :** Réduire le nombre de réplicas du backend à 1 (pour économiser).
5. **Config :** Passer le LOG_LEVEL à DEBUG.

Copiez ceci dans `overlays/dev/kustomization.yaml` :

```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

# On hérite de la base
resources:
  - ../../base

# 1. Isolation
namespace: dev-news
nameSuffix: -dev

# 2. Identification
commonLabels:
  env: dev

# 3. Modification de la configuration (écrase la valeur de la base)
configMapGenerator:
  - name: backend-config
    behavior: merge
    literals:
      - LOG_LEVEL=DEBUG

# 4. Patching (Modification ciblée des YAMLs)
patches:
  - target:
      kind: Deployment
      name: backend
    patch: |-
      - op: replace
        path: /spec/replicas
        value: 1
```

👉 **Action : Prévisualisation**
Ne lancez pas encore l'apply. Regardez ce que Kustomize génère :

```bash
kubectl kustomize overlays/dev

```

_Observez que les noms ont changé (ex: `backend-dev`), et que le ConfigMap a un suffixe aléatoire (hash) pour forcer le redémarrage des pods en cas de modif._

👉 **Action : Déploiement**

```bash
# Créez le namespace d'abord (Kustomize ne le crée pas toujours seul)
kubectl create ns dev-news

# Appliquez avec l'option -k
kubectl apply -k overlays/dev

```

---

## Étape 3 : L'Environnement de Production (Overlay Prod)

La Prod doit être robuste.
Créez le dossier `overlays/prod` et son fichier `kustomization.yaml`.

### Objectifs :

1. **Namespace :** `prod-news`.
2. **Prefixe :** `prod-`.
3. **Réplicas :** 3 backends et 2 frontends pour la Haute Disponibilité (HA).
4. **Ressources :** On veut limiter la mémoire utilisée.

Fichier `overlays/prod/kustomization.yaml` :

```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

resources:
  - ../../base

namespace: prod-news
namePrefix: prod-

commonLabels:
  env: prod
  tier: gold

# Pas de modification de ConfigMap ici, on garde le INFO de la base

patches:
  # Patch 1 : Haute Disponibilité sur le Backend
  - target:
      kind: Deployment
      name: backend
    patch: |-
      - op: replace
        path: /spec/replicas
        value: 3
      # Ajout de limites de ressources (Best Practice Prod)
      - op: add
        path: /spec/template/spec/containers/0/resources
        value:
          limits:
            memory: "256Mi"
            cpu: "500m"

  # Patch 2 : Haute Disponibilité sur le Frontend
  - target:
      kind: Deployment
      name: frontend
    patch: |-
      - op: replace
        path: /spec/replicas
        value: 2
```

👉 **Action : Déploiement**

```bash
kubectl create ns prod-news
kubectl apply -k overlays/prod

```

---

## ✅ Validation et Comparaison

Vous avez maintenant deux versions de la même application qui tournent en parallèle. Vérifions les différences.

### 1. Vérifier les Pods

Comparez le nombre de pods entre Dev et Prod :

```bash
echo "--- DEV ---"
kubectl get pods -n dev-news
echo "--- PROD ---"
kubectl get pods -n prod-news

```

_Vous devriez voir 1 backend en Dev, et 3 en Prod._

### 2. Vérifier la Configuration

Regardez les variables d'environnement injectées :

**En Dev :**

```bash
# Trouvez le nom exact du pod backend
kubectl get pods -n dev-news
# Vérifiez la variable (remplacez le nom du pod)
kubectl describe pod backend-dev-XXXXX -n dev-news | grep LOG_LEVEL

```

_Attendu : `DEBUG_`

**En Prod :**

```bash
kubectl describe pod prod-backend-XXXXX -n prod-news | grep LOG_LEVEL

```

_Attendu : `INFO` (valeur héritée de la base)_

### 3. Nettoyage

Pour supprimer un environnement entier géré par Kustomize, c'est très simple :

```bash
kubectl delete -k overlays/dev

```

_(Gardez la Prod pour l'instant si vous voulez, ou supprimez tout avant le Lab 3)_.

---

## 💡 Ce que vous avez appris

- **DRY (Don't Repeat Yourself) :** Vous n'avez écrit les définitions de déploiement qu'une seule fois.
- **Isolation :** Les environnements ne se marchent pas dessus grâce aux namespaces et préfixes.
- **Configuration Immutable :** Kustomize gère les ConfigMaps avec des hashs (`backend-config-h5k9...`). Si vous changez la config, le nom change, et Kubernetes redéploie automatiquement les pods pour prendre en compte la modif. C'est une "Best Practice" critique.
