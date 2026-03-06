# Lab 3 : Packaging et Déploiement Industriel avec Helm

## 🎯 Objectif

Dans le Lab 2, Kustomize nous a permis de gérer des variantes (patchs). Mais comment **distribuer** notre application à une autre équipe ? Comment leur permettre de changer l'image, le nombre de réplicas ou le mot de passe sans qu'ils aient besoin de toucher à une seule ligne de YAML ?

**Helm** est le "Package Manager" de Kubernetes (comme `apt` ou `yum` pour Linux). Il utilise des **Templates** pour générer du YAML dynamiquement.

**Temps estimé :** 1h00 - 1h15

## 📋 Pré-requis

1. **Nettoyage :** Supprimez les ressources du Lab 2 pour éviter les conflits de ports/noms.

```bash
kubectl delete namespace dev-news prod-news

```

2. Avoir la commande `helm` installée.
3. Se placer dans le dossier : `cd k8s/03-helm`.

---

## Architecture d'un Chart Helm

Un "Chart" est un paquet Helm. Sa structure est standardisée :

```text
devops-news/
├── Chart.yaml          # Méta-données (nom, version, description)
├── values.yaml         # Les valeurs par défaut (l'interface utilisateur)
├── templates/          # Les fichiers YAML avec des variables {{ .Values... }}
└── charts/             # Dépendances (vide pour ce lab)

```

---

## Étape 1 : Initialisation du Chart

Helm peut générer une structure de base.

1. Créez le chart :

```bash
helm create devops-news

```

2. **Nettoyage radical :** Le code généré par défaut est trop complexe pour débuter.

- Supprimez tout le contenu du dossier `devops-news/templates/`.
- Ouvrez `devops-news/values.yaml` et supprimez tout son contenu.

👉 **Action :** Nous allons repartir d'une page blanche pour bien comprendre le mécanisme.

---

## Étape 2 : Définir les Variables (`values.yaml`)

Le fichier `values.yaml` est le contrat entre vous (le créateur du paquet) et l'utilisateur.
Copiez ceci dans `devops-news/values.yaml` :

```yaml
# Configuration Globale
global:
  env: production

# Configuration des Images
images:
  repoAccount: "votre-pseudo-dockerhub" # À MODIFIER !
  pullPolicy: IfNotPresent
  tags:
    backend: v1
    frontend: v1
    cleaner: v1

# Configuration du Backend
backend:
  replicas: 2
  logLevel: "INFO"
  serviceType: ClusterIP

# Configuration du Frontend
frontend:
  replicas: 1
  servicePort: 80

# Configuration Redis (Persistence)
redis:
  enabled: true
  password: "supersecret" # Dans la vraie vie, on passerait ça via un Secret externe
  storage: 1Gi
```

---

## Étape 3 : La Templatisation (Le moteur)

Helm utilise le langage de template **Go Templates** (reconnaissable aux doubles accolades `{{ }}`).

### 3.1 Le Backend (Template simple)

Créez un fichier `devops-news/templates/backend.yaml`.
Nous allons prendre votre YAML du Lab 1 et remplacer les valeurs fixes par des variables.

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: {{ .Release.Name }}-backend # Le nom sera dynamique (ex: my-release-backend)
  labels:
    app: {{ .Release.Name }}-backend
spec:
  replicas: {{ .Values.backend.replicas }} # Variable depuis values.yaml
  selector:
    matchLabels:
      app: {{ .Release.Name }}-backend
  template:
    metadata:
      labels:
        app: {{ .Release.Name }}-backend
    spec:
      containers:
      - name: api
        # Construction dynamique du nom de l'image
        image: "{{ .Values.images.repoAccount }}/devops-news-api:{{ .Values.images.tags.backend }}"
        ports:
        - containerPort: 5000
        env:
        - name: REDIS_HOST
          value: "{{ .Release.Name }}-redis"
        - name: LOG_LEVEL
          value: "{{ .Values.backend.logLevel }}"
---
apiVersion: v1
kind: Service
metadata:
  name: {{ .Release.Name }}-backend
spec:
  type: {{ .Values.backend.serviceType }}
  selector:
    app: {{ .Release.Name }}-backend
  ports:
    - port: 5000
      targetPort: 5000

```

### 3.2 La Logique Conditionnelle (Redis)

Helm permet de faire des `if`. Imaginons qu'on veuille pouvoir désactiver Redis (pour des tests).
Créez `devops-news/templates/redis.yaml`.

```yaml
{{- if .Values.redis.enabled }} # Si redis.enabled est true, on génère ce bloc
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: {{ .Release.Name }}-redis
spec:
  serviceName: "{{ .Release.Name }}-redis"
  replicas: 1
  selector:
    matchLabels:
      app: {{ .Release.Name }}-redis
  template:
    metadata:
      labels:
        app: {{ .Release.Name }}-redis
    spec:
      containers:
      - name: redis
        image: redis:6.0-alpine
        command: ["redis-server", "--requirepass", "{{ .Values.redis.password }}"]
        volumeMounts:
        - name: data
          mountPath: /data
  volumeClaimTemplates:
  - metadata:
      name: data
    spec:
      accessModes: [ "ReadWriteOnce" ]
      storageClassName: "standard-rwo"
      resources:
        requests:
          storage: {{ .Values.redis.storage }}
---
apiVersion: v1
kind: Service
metadata:
  name: {{ .Release.Name }}-redis
spec:
  ports:
  - port: 6379
  selector:
    app: {{ .Release.Name }}-redis
{{- end }}

```

### 3.3 À vous de jouer (Frontend)

Créez le fichier `devops-news/templates/frontend.yaml`.
Essayez de le faire vous-même en vous inspirant du backend.

- L'image doit utiliser `.Values.images.tags.frontend`.
- Le service doit être de type `LoadBalancer`.

---

## Étape 4 : Installation et Debug

Avant d'installer, on vérifie toujours ce que Helm va générer.

### 4.1 Dry Run (Simulation)

```bash
# --debug affiche le YAML généré
# ./devops-news est le dossier du chart
helm install test-release ./devops-news --dry-run --debug

```

_Si vous avez des erreurs de syntaxe, Helm vous dira à quelle ligne._

### 4.2 Installation Réelle

Installons l'application dans un namespace dédié.

```bash
kubectl create ns helm-lab
# Syntaxe : helm install <NOM_RELEASE> <DOSSIER_CHART>
helm install news-v1 ./devops-news -n helm-lab

```

👉 **Vérification :**

```bash
helm list -n helm-lab
kubectl get all -n helm-lab

```

---

## Étape 5 : Le Cycle de Vie (Upgrade & Rollback)

C'est ici que Helm brille. Le client vous demande de passer à 5 réplicas pour le backend et de changer la version de l'image.

### 5.1 Upgrade

Au lieu de modifier les fichiers YAML, on modifie la "Release". On peut le faire de deux façons :

1. Modifier `values.yaml` et réappliquer.
2. Surcharger via la ligne de commande (plus rapide pour tester).

```bash
# On change le tag de l'image et le nombre de replicas à la volée
helm upgrade news-v1 ./devops-news \
  --set backend.replicas=5 \
  --set images.tags.backend=v2 \
  -n helm-lab

```

Vérifiez que les pods sont en train de changer :

```bash
kubectl get pods -n helm-lab -w

```

### 5.2 History & Rollback

"Oups ! La version v2 est buggée, il faut revenir en arrière immédiatement !"

1. Regardez l'historique :

```bash
helm history news-v1 -n helm-lab

```

_Vous verrez Révision 1 (Install) et Révision 2 (Upgrade)._ 2. Annulez le changement (Retour vers le futur) :

```bash
helm rollback news-v1 1 -n helm-lab

```

_Helm remet instantanément la configuration exacte de la Révision 1._

---

## 🏆 Conclusion de la Formation

En 4 heures, vous avez parcouru l'évolution du déploiement moderne :

| Niveau | Outil              | Philosophie          | Avantage                                 | Inconvénient                    |
| ------ | ------------------ | -------------------- | ---------------------------------------- | ------------------------------- |
| **0**  | **Docker Compose** | Tout sur une machine | Simple pour le dév                       | Pas scalable, pas résilient     |
| **1**  | **K8s Natif**      | Objets atomiques     | Scalable, Résilient                      | Verbeux, difficile à maintenir  |
| **2**  | **Kustomize**      | Patchs & Overlays    | Gestion multi-env (Dev/Prod)             | Répétitif si structure complexe |
| **3**  | **Helm**           | Templates & Packages | Distribution, Logique complexe, Rollback | Courbe d'apprentissage (Go Tpl) |

**Pour aller plus loin :** Regardez **ArgoCD**. C'est un outil qui surveille votre dépôt Git et lance les commandes Helm/Kustomize automatiquement à votre place (GitOps).
