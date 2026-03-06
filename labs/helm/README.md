# Labs Helm — DevOps-News

Parcours de labs pratiques pour la formation Helm, basés sur l'application **DevOps-News** (Flask + Redis + Nginx).

## Progression

| Lab | Module(s) | Sujet | Durée |
|-----|-----------|-------|-------|
| [Lab 1](lab1.md) | 1 + 2 | Découverte & Prise en main | 45min - 1h |
| [Lab 2](lab2.md) | 3 | Personnalisation par environnement | 1h - 1h15 |
| [Lab 3](lab3.md) | 4 | Chart DevOps-News from scratch + Dépendances + OCI *(autonome)* | 2h - 2h30 |
| [Lab 4](lab4.md) | 5 | Templating avancé (helpers, range, with, pipelines) | 1h15 - 1h30 |
| [Lab 5](lab5.md) | 6 | Qualité & Sécurité (lint, schéma, tests, hooks, secrets) | 1h15 - 1h30 |
| [Lab 6](lab6.md) | 6 | Tests unitaires avec `helm-unittest` | 1h15 - 1h30 |
| [Lab 7](lab7.md) | 7 | Intégration avec Kustomize (post-rendering, hybride) | 1h - 1h15 |
| [Lab 8](lab8.md) | 8 | GitOps avec Argo CD (drift avancé, self-healing, secrets) | 1h30 - 2h |


**Durée totale estimée :** 10h - 12h

## Pré-requis

- Cluster GKE opérationnel avec `kubectl` configuré
- `helm` installé (Lab 1 couvre l'installation)
- `kustomize` installé (Lab 7)
- `argocd` CLI installé (Lab 8)
- Accès à un dépôt Git (Lab 8)

## Organisation des fichiers

```
helm/
├── README.md               ← Ce fichier
├── lab1.md                 ← Lab 1
├── lab2.md                 ← Lab 2
├── lab3.md                 ← Lab 3 (avec solution en annexe)
├── lab4.md                 ← Lab 4
├── lab5.md                 ← Lab 5
├── lab6.md                 ← Lab 6
├── lab7.md                 ← Lab 7
├── lab8.md                 ← Lab 8
├── values-dev.yaml         ← Valeurs Dev (Lab 2)
├── values-prod.yaml        ← Valeurs Prod (Lab 2)
├── values-common.yaml      ← Valeurs communes (Lab 2)
├── devops-news/            ← Chart produit au Lab 3 (étapes 1-7)
├── devops-news-subchart/   ← Chart avec sous-chart Bitnami Redis (Lab 3, étape 8)
├── devops-news-v2/         ← Chart produit au Lab 4 (+ tests unitaires Lab 6)
├── devops-news-v3/         ← Chart produit au Lab 5
├── post-render/            ← Scripts post-renderer (Lab 7)
└── environments/           ← Applications Argo CD dev/prod (Lab 8)
```
