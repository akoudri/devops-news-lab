# Lab Helm 2 — Personnalisation par Environnement

## 🎯 Objectif

Dans ce lab, nous allons déployer notre application **DevOps-News** à l'aide d'un chart communautaire et expérimenter toutes les stratégies de personnalisation de Helm : fichiers de valeurs, surcharge ciblée, multi-environnements Dev/Prod.

**Module couvert :** 3 (Personnalisation des déploiements)

**Temps estimé :** 1h00 - 1h15

---

## 📋 Pré-requis

1. Avoir terminé le Lab 1.
2. Se placer dans le dossier : `cd helm/`.
3. Le chart `devops-news` sera celui fourni dans `helm/devops-news/` (chart pré-construit pour ce lab).

---

## Architecture cible

Nous allons déployer deux instances de DevOps-News en parallèle, chacune dans son propre namespace, avec des configurations différentes :

| Paramètre | Dev | Prod |
|-----------|-----|------|
| Namespace | `devops-news-dev` | `devops-news-prod` |
| Réplicas backend | 1 | 3 |
| Réplicas frontend | 1 | 2 |
| LOG_LEVEL | DEBUG | INFO |
| Service frontend | ClusterIP | LoadBalancer |
| Limites CPU/RAM | Non | Oui |

---

## Étape 1 : Comprendre la structure du chart fourni

```bash
ls helm/devops-news/
```

```
devops-news/
├── Chart.yaml
├── values.yaml          ← Les valeurs par défaut
└── templates/
    ├── backend.yaml
    ├── frontend.yaml
    ├── redis.yaml
    └── cleaner.yaml
```

### 1.1 Lire le fichier `values.yaml`

```bash
cat helm/devops-news/values.yaml
```

Passez en revue tous les paramètres disponibles. Le `values.yaml` est **le contrat** entre vous et les utilisateurs du chart. Il documente ce qui peut être configuré.

### 1.2 Afficher le YAML généré avec les valeurs par défaut

```bash
helm template devops-news ./helm/devops-news
```

Observez comment les valeurs de `values.yaml` sont injectées dans les templates.

---

## Étape 2 : Créer les fichiers de valeurs par environnement

### 2.1 Créer `values-dev.yaml`

Créez le fichier `helm/values-dev.yaml` avec le contenu suivant :

```yaml
# Environnement de développement — Économique et bavard
backend:
  replicas: 1
  logLevel: "DEBUG"
  service:
    type: ClusterIP

frontend:
  replicas: 1
  service:
    type: ClusterIP  # Pas de LoadBalancer en dev (coût GKE)

redis:
  password: "dev-secret"

cleaner:
  schedule: "*/5 * * * *"  # Nettoyage plus fréquent pour les tests
```

### 2.2 Créer `values-prod.yaml`

Créez le fichier `helm/values-prod.yaml` :

```yaml
# Environnement de production — Robuste et sécurisé
backend:
  replicas: 3
  logLevel: "INFO"
  service:
    type: ClusterIP
  resources:
    limits:
      cpu: "500m"
      memory: "256Mi"
    requests:
      cpu: "100m"
      memory: "128Mi"

frontend:
  replicas: 2
  service:
    type: LoadBalancer  # IP publique en prod

redis:
  password: "prod-supersecret-changeme"
  storage: 2Gi          # Plus d'espace en prod

cleaner:
  schedule: "0 * * * *"  # Nettoyage toutes les heures
```

---

## Étape 3 : Comparer les manifests générés

Avant de déployer quoi que ce soit, utilisons `helm template` pour **visualiser** exactement ce qui sera déployé dans chaque environnement.

```bash
# Générer le YAML pour Dev
helm template devops-news-dev ./helm/devops-news \
  -f helm/values-dev.yaml \
  > /tmp/manifest-dev.yaml

# Générer le YAML pour Prod
helm template devops-news-prod ./helm/devops-news \
  -f helm/values-prod.yaml \
  > /tmp/manifest-prod.yaml

# Comparer les deux
diff /tmp/manifest-dev.yaml /tmp/manifest-prod.yaml
```

**Questions de réflexion :**
- Quelles lignes diffèrent entre Dev et Prod ?
- Les noms des ressources Kubernetes changent-ils entre les deux releases ?

---

## Étape 4 : Déploiement en Dev

### 4.1 Simuler d'abord avec `--dry-run`

```bash
kubectl create namespace devops-news-dev

helm install devops-news-dev ./helm/devops-news \
  --namespace devops-news-dev \
  -f helm/values-dev.yaml \
  --dry-run --debug 2>&1 | head -80
```

Vérifiez qu'il n'y a pas d'erreur dans le YAML généré.

### 4.2 Installation réelle en Dev

```bash
helm install devops-news-dev ./helm/devops-news \
  --namespace devops-news-dev \
  -f helm/values-dev.yaml
```

### 4.3 Vérification

```bash
helm list -n devops-news-dev
kubectl get all -n devops-news-dev
```

---

## Étape 5 : Déploiement en Prod

```bash
kubectl create namespace devops-news-prod

helm install devops-news-prod ./helm/devops-news \
  --namespace devops-news-prod \
  -f helm/values-prod.yaml
```

### 5.1 Attendre l'IP externe du frontend

```bash
kubectl get svc -n devops-news-prod -w
```

Une fois l'EXTERNAL-IP assignée par GKE, ouvrez-la dans votre navigateur.

---

## Étape 6 : Surcharge ciblée avec `--set`

Imaginons que votre pipeline CI/CD injecte dynamiquement le tag de l'image (issu du numéro de build).

### 6.1 Upgrade avec un tag d'image spécifique

```bash
helm upgrade devops-news-dev ./helm/devops-news \
  --namespace devops-news-dev \
  -f helm/values-dev.yaml \
  --set images.tags.backend=v1.1 \
  --set images.tags.frontend=v1.1
```

### 6.2 La règle de priorité

Testez la règle de priorité de Helm : **le dernier argument écrase les précédents**.

```bash
# Ici, --set écrase la valeur de values-dev.yaml
helm upgrade devops-news-dev ./helm/devops-news \
  --namespace devops-news-dev \
  -f helm/values-dev.yaml \
  --set backend.replicas=2   # Écrase replicas: 1 du fichier
```

Vérifiez :
```bash
kubectl get pods -n devops-news-dev | grep backend
```

### 6.3 Comprendre la fusion des valeurs

```bash
# Voir ce qui a réellement été appliqué (vos surcharges uniquement)
helm get values devops-news-dev -n devops-news-dev

# Voir toutes les valeurs actives (vos surcharges + les défauts)
helm get values devops-news-dev --all -n devops-news-dev
```

---

## Étape 7 : Fusion de plusieurs fichiers de valeurs

Helm permet d'enchaîner plusieurs fichiers de valeurs. C'est utile pour séparer les valeurs communes des valeurs spécifiques à un environnement.

### 7.1 Créer un fichier de valeurs communes

Créez `helm/values-common.yaml` :

```yaml
# Valeurs partagées par tous les environnements
images:
  repoAccount: "pueblo2708"
  pullPolicy: IfNotPresent

cleaner:
  maxAgeSeconds: 3600
```

### 7.2 Utiliser plusieurs fichiers en cascade

```bash
helm template devops-news-multi ./helm/devops-news \
  -f helm/values-common.yaml \
  -f helm/values-dev.yaml
```

> **Règle d'or :** L'ordre des `-f` compte. Le fichier `values-dev.yaml` écrase les clés définies dans `values-common.yaml` si elles sont présentes dans les deux fichiers. Ne modifiez **jamais** le `values.yaml` d'un chart tiers — créez toujours vos propres fichiers de surcharge.

---

## Étape 8 : Comparaison Dev vs Prod en live

Vous avez maintenant deux environnements qui tournent en parallèle. Vérifiez les différences :

```bash
echo "=== DEV ==="
kubectl get pods -n devops-news-dev

echo "=== PROD ==="
kubectl get pods -n devops-news-prod

# Comparer les ConfigMaps/variables d'env (LOG_LEVEL)
kubectl exec -n devops-news-dev \
  $(kubectl get pods -n devops-news-dev -l app.kubernetes.io/component=backend -o jsonpath='{.items[0].metadata.name}') \
  -- env | grep LOG_LEVEL

kubectl exec -n devops-news-prod \
  $(kubectl get pods -n devops-news-prod -l app.kubernetes.io/component=backend -o jsonpath='{.items[0].metadata.name}') \
  -- env | grep LOG_LEVEL
```

---

## ✅ Validation finale

```bash
# Les deux releases doivent apparaître
helm list -A

# Voir l'historique de dev (qui a subi un upgrade)
helm history devops-news-dev -n devops-news-dev
```

Avant de passer au Lab 3, assurez-vous de savoir répondre à ces questions :

1. Quelle est la différence entre modifier `values.yaml` directement et créer un fichier `values-prod.yaml` ?
2. Si on enchaîne `-f values-a.yaml -f values-b.yaml --set key=c`, dans quel ordre s'appliquent les priorités ?
3. Pourquoi `helm get values --all` retourne-t-il plus de valeurs que `helm get values` ?

---

## Nettoyage (optionnel — gardez les namespaces pour le Lab 3)

```bash
# Supprimer uniquement si vous voulez repartir proprement
helm uninstall devops-news-dev -n devops-news-dev
helm uninstall devops-news-prod -n devops-news-prod
kubectl delete namespace devops-news-dev devops-news-prod
```
