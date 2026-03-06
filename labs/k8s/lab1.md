# Lab 1 : De Docker Compose à Kubernetes Natif

## 🎯 Objectif

Dans ce premier atelier, vous allez "traduire" l'application **DevOps-News** (actuellement définie dans un simple `docker-compose.yml`) vers une architecture Kubernetes robuste et scalable sur GKE.

**Temps estimé :** 1h30 - 1h45

## 📋 Pré-requis

1. Se placer dans le dossier : `cd k8s/01-manual`.

---

## Architecture Cible

Voici ce que nous allons construire :

- **Configuration** : Séparée du code (ConfigMaps & Secrets).
- **Base de données (Redis)** : Un **StatefulSet** avec un disque persistant (**PVC**).
- **Backend (API)** : Un **Deployment** accessible uniquement en interne (**ClusterIP**).
- **Frontend (Web)** : Un **Deployment** exposé sur internet (**LoadBalancer**).
- **Maintenance** : Un **CronJob** qui tourne périodiquement.

---

## Étape 1 : La Configuration (ConfigMap & Secret)

Avant de lancer les applications, nous devons stocker les données de configuration.

### 1.1 Le Secret (Mot de passe Redis)

Dans Kubernetes, les données sensibles ne doivent pas être en clair.
Créez un fichier `01-secret.yaml`.

> **Astuce :** Un Secret doit être encodé en Base64.
> Exécutez : `echo -n "supersecret" | base64` pour obtenir la valeur.

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: redis-secret
type: Opaque
data:
  password: <VOTRE_CHAINE_BASE64_ICI>
```

### 1.2 La ConfigMap (Variables d'env)

Pour les données non sensibles (comme le niveau de log), utilisez une ConfigMap.
Créez un fichier `02-configmap.yaml`.

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: backend-config
data:
  LOG_LEVEL: "DEBUG"
  # Ajoutez ici d'autres variables si nécessaire
```

👉 **Action :** Appliquez ces fichiers : `kubectl apply -f .`

---

## Étape 2 : La Base de Données (StatefulSet)

Redis a besoin de stocker des données sur un disque. Si le Pod redémarre, les données ne doivent pas être perdues. Pour cela, nous utilisons un **StatefulSet** plutôt qu'un Deployment.

Créez un fichier `03-redis.yaml`.

### Points clés à compléter :

1. **Service :** Il doit être de type `ClusterIP` (ou Headless) pour que le backend puisse lui parler.
2. **Volume :** Utilisez `volumeClaimTemplates` pour demander automatiquement un disque à Google Cloud.

```yaml
apiVersion: v1
kind: Service
metadata:
  name: redis
spec:
  ports:
    - port: 6379
  selector:
    app: redis
---
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: redis
spec:
  serviceName: "redis"
  replicas: 1
  selector:
    matchLabels:
      app: redis
  template:
    metadata:
      labels:
        app: redis
    spec:
      containers:
        - name: redis
          image: redis:6.0-alpine
          command:
            [
              "redis-server",
              "--requirepass",
              "$(REDIS_PASSWORD)",
              "--appendonly",
              "yes",
            ]
          env:
            - name: REDIS_PASSWORD
              valueFrom:
                secretKeyRef:
                  name: redis-secret
                  key: password
          volumeMounts:
            - name: redis-data
              mountPath: /data
  # C'est ici que la magie du stockage opère :
  volumeClaimTemplates:
    - metadata:
        name: redis-data
      spec:
        accessModes: ["ReadWriteOnce"]
        storageClassName: "standard-rwo" # Classe de stockage standard GKE
        resources:
          requests:
            storage: 1Gi
```

👉 **Action :** Appliquez et vérifiez que le PVC est créé : `kubectl get pvc`.

---

## Étape 3 : Le Backend (Deployment & ClusterIP)

L'API est "stateless" (sans état). Nous utilisons donc un **Deployment**.

Créez un fichier `04-backend.yaml`.

### Consignes :

- L'image est : `pueblo2708/devops-news-api:latest`
- Il doit se connecter à Redis via les variables d'environnement.
- **Important :** Le `REDIS_HOST` est tout simplement le nom du service Redis créé à l'étape précédente (`redis`).

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: backend
spec:
  replicas: 2 # On veut de la haute disponibilité !
  selector:
    matchLabels:
      app: backend
  template:
    metadata:
      labels:
        app: backend
    spec:
      containers:
        - name: api
          image: pueblo2708/devops-news-api:latest
          ports:
            - containerPort: 5000
          env:
            - name: REDIS_HOST
              value: "redis"
            - name: REDIS_PASSWORD
              valueFrom:
                secretKeyRef:
                  name: redis-secret
                  key: password
          # Ajoutez ici la référence à la ConfigMap pour LOG_LEVEL
---
apiVersion: v1
kind: Service
metadata:
  name: backend
spec:
  type: ClusterIP # Accessible uniquement dans le cluster
  selector:
    app: backend
  ports:
    - port: 5000
      targetPort: 5000
```

---

## Étape 4 : Le Frontend (Deployment & LoadBalancer)

C'est la seule partie accessible depuis Internet. Sur GKE, le type `LoadBalancer` va provisionner une véritable adresse IP publique Google Cloud.

Créez un fichier `05-frontend.yaml`.

### Consignes :

- Image : `pueblo2708/devops-news-front:latest`
- Le Nginx interne est configuré pour rediriger les requêtes `/api` vers `http://backend:5000`. C'est le DNS interne de Kubernetes qui résout le nom `backend`.

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: frontend
spec:
  replicas: 1
  selector:
    matchLabels:
      app: frontend
  template:
    metadata:
      labels:
        app: frontend
    spec:
      containers:
        - name: web
          image: pueblo2708/devops-news-front:latest
          ports:
            - containerPort: 80
---
apiVersion: v1
kind: Service
metadata:
  name: frontend
spec:
  type: LoadBalancer # C'est ce qui nous donne l'IP Publique
  selector:
    app: frontend
  ports:
    - port: 80
      targetPort: 80
```

👉 **Action :** Appliquez le fichier. Lancez `kubectl get svc -w` et attendez que l'**EXTERNAL-IP** apparaisse (cela peut prendre 1 à 2 minutes).

---

## Étape 5 : Le Nettoyage (CronJob)

Enfin, transformons le script de nettoyage en tâche planifiée.
Créez un fichier `06-cleaner.yaml`.

### Consignes :

- Image : `pueblo2708/devops-news-cleaner:latest`
- Planification : Toutes les 2 minutes (`*/2 * * * *`).

```yaml
apiVersion: batch/v1
kind: CronJob
metadata:
  name: news-cleaner
spec:
  schedule: "*/2 * * * *"
  jobTemplate:
    spec:
      template:
        spec:
          restartPolicy: OnFailure
          containers:
            - name: cleaner
              image: pueblo2708/devops-news-cleaner:latest
              env:
                - name: REDIS_HOST
                  value: "redis"
                - name: REDIS_PASSWORD
                  valueFrom:
                    secretKeyRef:
                      name: redis-secret
                      key: password
```

---

## ✅ Validation Finale

Nous allons maintenant vérifier le fonctionnement de notre application

1. Ouvrez l'**IP externe** du frontend dans votre navigateur.
2. Ajoutez une news (Titre : "Kubernetes Rocks", Lien : "k8s.io").
3. Vérifiez que la news s'affiche.
4. **Test de persistance :**

- Tuez le pod Redis : `kubectl delete pod redis-0`.
- Attendez qu'il revienne : `kubectl get pod -w`.
- Rechargez la page web. La news est-elle toujours là ? (Si oui, le PVC fonctionne !).

5. **Test du CronJob :**

- Attendez 2 minutes ou déclenchez-le manuellement :
  `kubectl create job --from=cronjob/news-cleaner manual-clean-01`
- Vérifiez que les news anciennes ont été supprimées.

👏 **Bravo !** Vous avez migré une application Docker Compose vers Kubernetes natif.
