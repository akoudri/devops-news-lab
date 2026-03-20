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

Le dépôt contient deux parcours de labs indépendants. Au sein de chaque parcours, les labs sont conçus pour être suivis dans l'ordre.

### Parcours Kubernetes (`labs/k8s/`)

Migrer progressivement de Docker Compose vers un déploiement Kubernetes industrialisé.

| Lab | Sujet | Durée estimée | Description |
|-----|-------|---------------|-------------|
| [Lab 1](labs/k8s/lab1.md) | Kubernetes natif | 1h30 - 1h45 | Traduire le `docker-compose.yml` en ressources Kubernetes (Deployments, StatefulSet, Services, CronJob) |
| [Lab 2](labs/k8s/lab2.md) | Kustomize | 45min - 1h00 | Structurer les manifests avec le système Base & Overlays pour gérer plusieurs environnements (Dev/Prod) |
| [Lab 3](labs/k8s/lab3.md) | Helm | 1h00 - 1h15 | Packager l'application en Chart Helm avec templates, variables et gestion du cycle de vie (upgrade, rollback) |

### Parcours Helm (`labs/helm/`)

Formation approfondie à Helm, de la découverte au GitOps avec Argo CD. Voir le [README dédié](labs/helm/README.md) pour plus de détails.

| Lab | Sujet | Durée estimée | Description |
|-----|-------|---------------|-------------|
| [Lab 1](labs/helm/lab1.md) | Découverte & Prise en main | 45min - 1h00 | Installer Helm, explorer Artifact Hub, déployer un chart communautaire et manipuler le cycle de vie d'une release |
| [Lab 2](labs/helm/lab2.md) | Personnalisation par environnement | 1h00 - 1h15 | Déployer DevOps-News avec un chart et expérimenter les stratégies de personnalisation (values, multi-env) |
| [Lab 3](labs/helm/lab3.md) | Chart from scratch | 1h30 - 2h00 | Créer de zéro le chart Helm complet de DevOps-News (lab autonome avec solution en annexe) |
| [Lab 4](labs/helm/lab4.md) | Templating avancé | 1h15 - 1h30 | Helpers, conditions, boucles `range`, scope `with`, pipelines et fichiers externes |
| [Lab 5](labs/helm/lab5.md) | Qualité & Sécurité | 1h15 - 1h30 | Schéma de validation, NOTES.txt, tests Helm, hooks de cycle de vie et gestion des secrets |
| [Lab 6](labs/helm/lab6.md) | Tests Unitaires | 1h15 - 1h30 | Tests Unitaires avec HelmTest |
| [Lab 7](labs/helm/lab7.md) | Intégration avec Kustomize | 1h00 - 1h15 | Post-rendering et approche hybride Helm + Kustomize |
| [Lab 8](labs/helm/lab8.md) | GitOps avec Argo CD | 1h15 - 1h30 | Déploiement déclaratif, self-healing, drift detection et secrets GitOps-compatible |
| [Lab 9](labs/helm/lab9.md) | Umbrella Chart & Helmfile | 1h30 - 2h00 | Orchestration multi-services : chart parapluie et gestion déclarative multi-releases |

**Durée totale estimée :** 11h - 12h

## Démarrage rapide

```bash
# Lancer l'application en local avec Docker Compose
docker compose up --build
```

L'application est accessible sur http://localhost:8080.

## Pré-requis

- Docker et Docker Compose
- Un cluster Kubernetes (GKE recommandé pour les labs)
- `kubectl` configuré
- `helm` installé (parcours K8s Lab 3 + parcours Helm)
- `kustomize` installé (parcours Helm Lab 6)
- `argocd` CLI installé (parcours Helm Lab 8)
- `helmfile` installé (parcours Helm Lab 9)
