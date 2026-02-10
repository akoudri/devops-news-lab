# DevOps-News Lab

Un monorepo de formation pour apprendre **Kubernetes**, **Kustomize** et **Helm** de manière progressive, en déployant une application complète étape par étape.

## Le projet

**DevOps-News** est une application web simple composée de quatre services :

- **Frontend** — Interface statique servie par Nginx, avec reverse proxy vers le backend
- **Backend** — API REST en Flask (Python) pour gérer des articles
- **Redis** — Base de données clé-valeur pour le stockage des articles
- **Cleaner** — Script shell de maintenance qui supprime les articles expirés

L'objectif est d'utiliser cette application comme support concret pour migrer progressivement d'un `docker-compose.yml` vers un déploiement Kubernetes industrialisé avec Helm.

## Architecture

```
Browser → Nginx (:80) → /api/* → Flask backend (:5000) → Redis
```

| Service  | Technologie   | Rôle                                |
|----------|---------------|-------------------------------------|
| Frontend | Nginx         | Sert le HTML et proxy `/api/`       |
| Backend  | Flask (Python) | API REST (`/news`, `/health`)       |
| Redis    | Redis Alpine  | Stockage des articles (liste JSON)  |
| Cleaner  | Shell script  | Suppression des articles expirés    |

## Parcours de formation

Les labs sont conçus pour être suivis dans l'ordre. Chaque lab s'appuie sur les acquis du précédent et introduit un niveau d'abstraction supplémentaire.

| Lab | Sujet | Durée estimée | Description |
|-----|-------|---------------|-------------|
| [Lab 1](labs/lab1.md) | Kubernetes natif | 1h30 - 1h45 | Traduire le `docker-compose.yml` en ressources Kubernetes (Deployments, StatefulSet, Services, CronJob) |
| [Lab 2](labs/lab2.md) | Kustomize | 45min - 1h00 | Structurer les manifests avec le système Base & Overlays pour gérer plusieurs environnements (Dev/Prod) |
| [Lab 3](labs/lab3.md) | Helm | 1h00 - 1h15 | Packager l'application en Chart Helm avec templates, variables et gestion du cycle de vie (upgrade, rollback) |

### Progression

```
Docker Compose  →  Kubernetes natif  →  Kustomize  →  Helm
   (Lab 0)            (Lab 1)           (Lab 2)      (Lab 3)
   Simple            Scalable          Multi-env    Distributable
```

## Démarrage rapide

```bash
# Lancer l'application en local avec Docker Compose
docker compose up --build
```

L'application est accessible sur http://localhost:8080.

## Solutions

Les solutions complètes de chaque lab sont disponibles dans le dossier `k8s/` :

```text
k8s/
├── 01-manual/                        # Solutions Lab 1 — Kubernetes natif
│   ├── 01-secret.yaml                #   Secret Redis (Base64)
│   ├── 02-configmap.yaml             #   ConfigMap backend
│   ├── 03-redis.yaml                 #   StatefulSet + Service Redis
│   ├── 04-backend.yaml               #   Deployment + ClusterIP backend
│   ├── 05-frontend.yaml              #   Deployment + LoadBalancer frontend
│   └── 06-cleaner.yaml               #   CronJob cleaner
│
├── 02-kustomize/                     # Solutions Lab 2 — Kustomize
│   ├── base/                         #   Ressources communes
│   │   ├── 03-redis.yaml
│   │   ├── 04-backend.yaml
│   │   ├── 05-frontend.yaml
│   │   ├── 06-cleaner.yaml
│   │   └── kustomization.yaml
│   └── overlays/                     #   Variantes par environnement
│       ├── dev/
│       │   └── kustomization.yaml    #     1 replica, LOG_LEVEL=DEBUG, namespace dev-news
│       └── prod/
│           └── kustomization.yaml    #     3 backends, 2 frontends, resource limits, namespace prod-news
│
└── 03-helm/                          # Solutions Lab 3 — Helm
    └── devops-news/                  #   Chart Helm
        ├── Chart.yaml
        ├── values.yaml
        ├── charts/
        └── templates/
            ├── backend.yaml
            ├── frontend.yaml
            ├── redis.yaml
            └── cleaner.yaml
```

## Pré-requis

- Docker et Docker Compose
- Un cluster Kubernetes (GKE recommandé pour les labs)
- `kubectl` configuré
- `helm` installé (pour le Lab 3)
