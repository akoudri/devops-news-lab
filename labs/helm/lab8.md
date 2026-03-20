# Lab Helm 8 — GitOps avec Argo CD

## 🎯 Objectif

Dans ce lab final, vous allez passer du déploiement impératif (`helm install`) au déploiement **déclaratif et automatisé** avec Argo CD. Vous connecterez votre chart `devops-news` à une instance Argo CD, observerez le mécanisme de **self-healing** en cas de drift, et gérerez les secrets de manière GitOps-compatible.

**Module couvert :** 8 (GitOps avec Argo CD et Helm)

**Temps estimé :** 1h30 - 2h00

---

## 📋 Pré-requis

1. Avoir terminé le Lab 5 (chart `devops-news-v3` complet et fonctionnel).
2. Avoir un dépôt Git (GitHub, GitLab ou Gitea) accessible depuis le cluster GKE.
3. Se placer dans le dossier : `cd helm/`

---

## Contexte : Du Push au Pull

En CI/CD classique, **votre pipeline pousse** les changements vers le cluster :

```
Developer → Git → CI/CD Pipeline → kubectl/helm → Cluster
```

Problème : si quelqu'un modifie une ressource directement avec `kubectl`, le cluster dérive de ce que Git décrit. La CI/CD ne le sait pas.

Avec GitOps (**Pull model**), **un agent dans le cluster surveille Git** et synchronise en permanence :

```
Developer → Git ← Argo CD (surveille) → Cluster
                              ↑
                    Détecte et corrige les dérives
```

---

## Étape 1 : Installation d'Argo CD sur GKE

### 1.1 Déployer Argo CD

```bash
kubectl create namespace argocd

kubectl apply -n argocd -f \
  https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
```

### 1.2 Attendre que tous les pods soient prêts

```bash
kubectl wait --for=condition=Ready pods --all -n argocd --timeout=300s
```

### 1.3 Accéder à l'interface web

```bash
# Exposer l'interface Argo CD en LoadBalancer (adapté à GKE)
kubectl patch svc argocd-server -n argocd \
  -p '{"spec": {"type": "LoadBalancer"}}'

# Attendre l'IP externe
kubectl get svc argocd-server -n argocd -w
```

Une fois l'IP assignée, ouvrez `https://<EXTERNAL-IP>` dans votre navigateur.

> **Note SSL :** Le certificat auto-signé d'Argo CD déclenchera un avertissement navigateur. Acceptez l'exception de sécurité pour ce lab.

### 1.4 Récupérer le mot de passe initial

```bash
# Récupérer le mot de passe admin initial
kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath="{.data.password}" | base64 -d && echo

# Se connecter avec l'outil CLI argocd
argocd login <EXTERNAL-IP> \
  --username admin \
  --password <MOT-DE-PASSE> \
  --insecure
```

---

## Étape 2 : Pousser le chart sur Git

Argo CD a besoin que votre chart soit **dans un dépôt Git** (ou un registre OCI). Nous allons pousser le chart `devops-news-v3`.

### 2.1 Structure Git recommandée

```
votre-repo/
├── charts/
│   └── devops-news/        ← Votre chart (copie de devops-news-v3)
│       ├── Chart.yaml
│       ├── values.yaml
│       └── templates/
└── environments/
    ├── dev/
    │   └── values-dev.yaml ← Valeurs de surcharge par env
    └── prod/
        └── values-prod.yaml
```

### 2.2 Pousser sur Git

```bash
# Initialiser un dépôt Git (si pas déjà fait)
git init votre-repo
cd votre-repo

# Copier le chart
mkdir -p charts/
cp -r ../helm/devops-news-v3 charts/devops-news

# Créer les fichiers de valeurs par environnement
mkdir -p environments/dev environments/prod

cat > environments/dev/values-dev.yaml << 'EOF'
backend:
  replicas: 1
  logLevel: "DEBUG"
frontend:
  service:
    type: ClusterIP
redis:
  password: "dev-secret-helmlab7"
cleaner:
  enabled: true
  schedule: "*/5 * * * *"
EOF

cat > environments/prod/values-prod.yaml << 'EOF'
backend:
  replicas: 3
  logLevel: "INFO"
  resources:
    limits:
      cpu: "500m"
      memory: "256Mi"
frontend:
  replicas: 2
  service:
    type: LoadBalancer
redis:
  password: "prod-secret-helmlab7-changeme"
  storage: "2Gi"
EOF

git add .
git commit -m "feat: add devops-news helm chart and environment values"
git push
```

---

## Étape 3 : Connecter Argo CD au dépôt Git

### 3.1 Ajouter le dépôt (interface CLI)

```bash
# Pour un dépôt public
argocd repo add https://github.com/<votre-org>/<votre-repo>.git

# Pour un dépôt privé avec token GitHub
argocd repo add https://github.com/<votre-org>/<votre-repo>.git \
  --username <votre-username> \
  --password <votre-token>
```

### 3.2 Vérifier la connexion

```bash
argocd repo list
```

Le statut doit être `Successful`.

---

## Étape 4 : Créer une Application Argo CD (Dev)

Une **Application** Argo CD est une ressource Kubernetes qui décrit : où se trouve la source (Git), comment la déployer (Helm), et où la déployer (cluster + namespace).

### 4.1 Via le fichier YAML (approche GitOps recommandée)

Créez `environments/dev/argocd-application.yaml` dans votre dépôt Git :

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: devops-news-dev
  namespace: argocd
  # Cette annotation permet à Argo CD de supprimer l'app
  # quand ce fichier est supprimé du dépôt Git (App of Apps pattern)
  finalizers:
    - resources-finalizer.argocd.argoproj.io
spec:
  project: default

  # ── Source : où est le chart et les valeurs ────────────────────────
  source:
    repoURL: https://github.com/<votre-org>/<votre-repo>.git
    targetRevision: main
    path: charts/devops-news  # Chemin vers le chart dans le repo
    helm:
      # Fichier de valeurs additionnel (relatif à la racine du repo)
      valueFiles:
        - ../../environments/dev/values-dev.yaml
      # Surcharges supplémentaires (ex: tag d'image issu du CI)
      parameters:
        - name: images.tags.backend
          value: "latest"

  # ── Destination : où déployer ──────────────────────────────────────
  destination:
    server: https://kubernetes.default.svc  # Le cluster local
    namespace: devops-news-argocd-dev

  # ── Politique de synchronisation ──────────────────────────────────
  syncPolicy:
    # Création automatique du namespace
    syncOptions:
      - CreateNamespace=true
    automated:
      # Déployer automatiquement dès qu'un commit est détecté
      prune: true      # Supprimer les ressources K8s retirées du chart
      selfHeal: true   # Corriger les modifications manuelles (drift)
```

### 4.2 Appliquer l'Application

```bash
# Pousser le fichier argocd-application.yaml dans Git, puis :
kubectl apply -f environments/dev/argocd-application.yaml
```

Ou via la CLI :

```bash
argocd app create devops-news-dev \
  --repo https://github.com/<votre-org>/<votre-repo>.git \
  --path charts/devops-news \
  --dest-server https://kubernetes.default.svc \
  --dest-namespace devops-news-argocd-dev \
  --revision main \
  --values ../../environments/dev/values-dev.yaml \
  --sync-policy automated \
  --auto-prune \
  --self-heal
```

---

## Étape 5 : Observer la synchronisation

### 5.1 Surveiller l'état de l'application

```bash
# Vue CLI
argocd app get devops-news-dev

# Lister toutes les apps
argocd app list
```

Dans l'interface web Argo CD, vous pouvez voir :
- Le graphe des ressources créées par le chart
- L'état de synchronisation (`Synced` / `OutOfSync`)
- L'état de santé (`Healthy` / `Degraded` / `Progressing`)

### 5.2 Vérifier les ressources Kubernetes

```bash
kubectl get all -n devops-news-argocd-dev
```

---

## Étape 6 : Démonstration approfondie du Drift

C'est l'expérience centrale du GitOps. Nous allons simuler **quatre scénarios de drift** distincts, mesurer chacun avec `argocd app diff`, et comprendre les limites du self-healing.

> **Définition :** Un *drift* (dérive) est tout écart entre l'état décrit dans Git et l'état réel observé dans le cluster. Argo CD le détecte en continu et le corrige si `selfHeal: true`.

### 6.1 Outillage : `argocd app diff`

Avant de simuler quoi que ce soit, prenez connaissance de la commande qui rend le drift visible :

```bash
# Comparer l'état Git avec l'état du cluster — doit être vide (pas de drift)
argocd app diff devops-news-dev

# Forcer un refresh immédiat (Argo CD poll toutes les 3 min par défaut)
argocd app diff devops-news-dev --refresh
```

Gardez un second terminal ouvert avec :

```bash
watch -n 3 "argocd app get devops-news-dev --refresh | grep -E 'Health|Sync'"
```

---

### Scénario A — Drift de réplicas (le plus courant)

```bash
# Un opérateur scale manuellement le backend "pour tenir une charge"
BACKEND=$(kubectl get deploy -n devops-news-argocd-dev \
  -l app.kubernetes.io/name=backend \
  -o jsonpath='{.items[0].metadata.name}')

kubectl scale deployment $BACKEND --replicas=5 -n devops-news-argocd-dev
```

**Observer immédiatement le drift :**

```bash
argocd app diff devops-news-dev --refresh
```

La sortie affiche en rouge/vert exactement quelle ligne a changé, comme un `git diff` :

```diff
===== apps/Deployment devops-news-argocd-dev/news-dev-backend ======
 spec:
-  replicas: 1     ← ce que Git décrit
+  replicas: 5     ← ce que le cluster a
```

**Observer le self-healing :**

```bash
watch -n 2 "kubectl get pods -n devops-news-argocd-dev | grep backend"
```

Argo CD remet 1 réplica dans les 3 minutes. L'application repasse `Synced`.

---

### Scénario B — Suppression accidentelle d'une ressource

```bash
# Quelqu'un supprime le Service frontend par erreur
kubectl delete svc \
  $(kubectl get svc -n devops-news-argocd-dev \
    -l app.kubernetes.io/name=frontend \
    -o jsonpath='{.items[0].metadata.name}') \
  -n devops-news-argocd-dev
```

**Observer le drift :**

```bash
argocd app diff devops-news-dev --refresh
# La sortie montre une ressource entière manquante (bloc en rouge)
```

**Observer la recréation automatique :**

```bash
kubectl get svc -n devops-news-argocd-dev -w
```

Argo CD recrée le Service en quelques secondes — le `prune: true` de la syncPolicy s'applique aussi dans l'autre sens : si une ressource *manque* dans le cluster mais est présente dans Git, elle est recréée.

---

### Scénario C — Modification d'un label (drift silencieux)

Ce scénario illustre un drift qui n'impacte pas le fonctionnement mais crée une incohérence de configuration.

```bash
# Modifier un label sur le Deployment backend
BACKEND=$(kubectl get deploy -n devops-news-argocd-dev \
  -l app.kubernetes.io/name=backend \
  -o jsonpath='{.items[0].metadata.name}')

kubectl label deployment $BACKEND \
  team=ops-override \
  -n devops-news-argocd-dev
```

**Observer :**

```bash
argocd app diff devops-news-dev --refresh
```

Argo CD détecte l'ajout du label non décrit dans Git et le supprime lors de la prochaine réconciliation.

> **Point de réflexion :** Ce comportement peut surprendre les équipes qui gèrent des labels via des outils externes (ex: un outil de coûts cloud qui ajoute des labels de facturation). La solution est d'utiliser les `ignoreDifferences` dans la spec de l'Application ArgoCD pour exclure certains champs de la comparaison.

---

### Scénario D — Drift de Secret (le plus critique)

```bash
# Quelqu'un modifie manuellement le mot de passe Redis dans le Secret
kubectl patch secret \
  $(kubectl get secret -n devops-news-argocd-dev \
    -l app.kubernetes.io/name=redis \
    -o jsonpath='{.items[0].metadata.name}') \
  -n devops-news-argocd-dev \
  --type='json' \
  -p='[{"op":"replace","path":"/data/redis-password","value":"'$(echo -n "hacked" | base64)'"}]'
```

**Observer :**

```bash
argocd app diff devops-news-dev --refresh
```

> **Observation clé :** Argo CD détecte le drift sur le Secret ET le corrige. Mais les pods backend continuent à tourner avec l'**ancien** mot de passe en mémoire jusqu'à leur redémarrage. C'est pourquoi les secrets doivent être gérés en dehors de Helm (External Secrets Operator) — pour éviter que ce drift soit possible en premier lieu.

---

### 6.2 Configurer `ignoreDifferences` pour les faux positifs

Certains contrôleurs Kubernetes (HPA, cert-manager, cloud providers) modifient légitimement des champs que Helm a définis. Sans configuration, Argo CD les signale comme drift en permanence.

Ajoutez ce bloc à votre `Application` pour ignorer les champs modifiés par le HPA :

```yaml
spec:
  ignoreDifferences:
    - group: apps
      kind: Deployment
      jsonPointers:
        - /spec/replicas          # Ignoré si HPA gère les réplicas
    - group: ""
      kind: Service
      jsonPointers:
        - /spec/clusterIP         # Assigné par K8s, pas par Helm
        - /spec/clusterIPs
```

```bash
# Appliquer la mise à jour de l'Application
kubectl apply -f environments/dev/argocd-application.yaml
```

---

### 6.3 Mesurer le temps de réconciliation

Par défaut, Argo CD poll Git toutes les **3 minutes**. Pour les environnements critiques, on peut forcer une réconciliation immédiate via webhook Git.

```bash
# Forcer une sync immédiate (contourne le polling)
argocd app sync devops-news-dev

# Voir le délai de détection configuré
argocd app get devops-news-dev | grep "Refresh"
```

**Tableau récapitulatif des scénarios observés :**

| Scénario | Délai de détection | Correction automatique | Risque résiduel |
|---|---|---|---|
| Réplicas modifiés | ~3 min (polling) | ✅ Oui | Aucun |
| Service supprimé | ~3 min | ✅ Oui | Interruption brève |
| Label ajouté | ~3 min | ✅ Oui | Aucun |
| Secret modifié | ~3 min | ✅ Oui | Pods avec ancien secret jusqu'au restart |

---

## Étape 7 : Déployer un changement via Git (le vrai flux GitOps)

### 7.1 Modifier les valeurs dans Git

```bash
# Dans votre dépôt local, modifier values-dev.yaml
# Passer logLevel de DEBUG à INFO
sed -i 's/logLevel: "DEBUG"/logLevel: "INFO"/' environments/dev/values-dev.yaml

git add environments/dev/values-dev.yaml
git commit -m "fix: reduce log verbosity in dev environment"
git push
```

### 7.2 Observer le déploiement automatique

```bash
argocd app get devops-news-dev --refresh
argocd app wait devops-news-dev --health
```

Dans l'interface Argo CD, vous voyez le déploiement progressif des nouveaux pods avec `LOG_LEVEL=INFO`.

### 7.3 Rollback via Git (pas via helm rollback !)

En GitOps, le rollback se fait par un **git revert**, pas par `helm rollback` :

```bash
git revert HEAD --no-edit
git push
```

Argo CD détecte le nouveau commit et remet l'ancienne configuration. **L'historique Git est la source de vérité**.

---

## Étape 8 : Application Prod et multi-cluster

### 8.1 Créer l'application Prod

Créez `environments/prod/argocd-application.yaml` :

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: devops-news-prod
  namespace: argocd
  finalizers:
    - resources-finalizer.argocd.argoproj.io
spec:
  project: default
  source:
    repoURL: https://github.com/<votre-org>/<votre-repo>.git
    targetRevision: main
    path: charts/devops-news
    helm:
      valueFiles:
        - ../../environments/prod/values-prod.yaml
  destination:
    server: https://kubernetes.default.svc
    namespace: devops-news-argocd-prod
  syncPolicy:
    syncOptions:
      - CreateNamespace=true
    automated:
      prune: true
      selfHeal: true
```

```bash
kubectl apply -f environments/prod/argocd-application.yaml
```

### 8.2 Comparer les deux environnements dans l'interface Argo CD

Dans l'interface web, vous avez maintenant deux applications visibles côte à côte :
- `devops-news-dev` : 1 réplica backend, service ClusterIP
- `devops-news-prod` : 3 réplicas backend, service LoadBalancer

---

## Étape 9 : Gestion des secrets en GitOps

Le fichier `values-dev.yaml` contient un mot de passe en clair. C'est inacceptable dans Git.

### 9.1 Approche recommandée : External Secrets Operator

```bash
# Installer l'External Secrets Operator
helm repo add external-secrets https://charts.external-secrets.io
helm install external-secrets external-secrets/external-secrets \
  --namespace external-secrets \
  --create-namespace
```

Dans cette architecture :
1. Le mot de passe Redis est stocké dans **GCP Secret Manager**
2. Votre chart Helm crée un objet `ExternalSecret`
3. L'opérateur récupère automatiquement la valeur et crée le `Secret` Kubernetes
4. **Aucun secret ne transite jamais par Git**

### 9.2 Approche alternative : Sealed Secrets

```bash
# Installer le contrôleur Sealed Secrets
helm repo add sealed-secrets https://bitnami-labs.github.io/sealed-secrets
helm install sealed-secrets sealed-secrets/sealed-secrets \
  --namespace kube-system

# Chiffrer un secret (seul le cluster peut le déchiffrer)
kubectl create secret generic redis-secret \
  --from-literal=password="prod-supersecret" \
  --dry-run=client -o yaml | \
  kubeseal --format yaml > environments/prod/sealed-redis-secret.yaml

# Ce fichier chiffré peut être commité dans Git sans risque
git add environments/prod/sealed-redis-secret.yaml
git commit -m "feat: add sealed redis secret for prod"
git push
```

> **Bonne pratique :** Supprimez le mot de passe en clair de `values-prod.yaml` et référencez plutôt le `SealedSecret` dans votre chart.

---

## ✅ Validation finale

```bash
argocd app list
```

Vérifiez que les deux applications affichent :
- Status: `Synced`
- Health: `Healthy`

**Questions de consolidation :**

1. Quelle est la différence fondamentale entre `helm upgrade` et un commit Git avec Argo CD ?
2. Pourquoi Argo CD recrée-t-il les ressources modifiées manuellement ? Quel mécanisme surveille-t-il ?
3. Dans quel cas `helm rollback` est-il encore pertinent avec GitOps ?
4. Quelle est la différence entre `prune: true` et `selfHeal: true` dans la `syncPolicy` ?

---

## Nettoyage

```bash
# Supprimer les applications Argo CD
argocd app delete devops-news-dev --cascade
argocd app delete devops-news-prod --cascade

# Supprimer les namespaces applicatifs
kubectl delete namespace devops-news-argocd-dev devops-news-argocd-prod

# Optionnel : désinstaller Argo CD
kubectl delete namespace argocd
```

---

## 🏆 Conclusion de la formation Helm

Vous avez parcouru l'ensemble de la chaîne de valeur du déploiement Kubernetes moderne :

| Lab | Compétence acquise |
|-----|-------------------|
| **Lab 1** | Manipulation du cycle de vie Helm (install, upgrade, rollback) |
| **Lab 2** | Gestion multi-environnements avec les fichiers de valeurs |
| **Lab 3** | Création d'un chart complet from scratch |
| **Lab 4** | Templating avancé : helpers, conditions, boucles, pipelines |
| **Lab 5** | Qualité et sécurité : schéma JSON, tests, hooks, secrets |
| **Lab 6** | Intégration Helm + Kustomize (post-rendering et hybride) |
| **Lab 7** | GitOps avec Argo CD : self-healing, drift detection, secrets |

**La suite :** Le [Lab 9](lab9.md) explore les **Umbrella Charts** et **Helmfile** pour orchestrer une plateforme complète de microservices — deux approches complémentaires au GitOps que vous venez de maîtriser.
