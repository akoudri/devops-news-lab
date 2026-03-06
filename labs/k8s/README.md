# Labs Kubernetes — DevOps-News

Parcours de labs pratiques pour apprendre Kubernetes, basés sur l'application **DevOps-News** (Flask + Redis + Nginx). L'objectif est de migrer progressivement d'un `docker-compose.yml` vers un déploiement Kubernetes industrialisé.

## Progression

| Lab | Sujet | Durée |
|-----|-------|-------|
| [Lab 1](lab1.md) | Kubernetes natif | 1h30 - 1h45 |
| [Lab 2](lab2.md) | Kustomize (Base & Overlays) | 45min - 1h |
| [Lab 3](lab3.md) | Helm (packaging & cycle de vie) | 1h - 1h15 |

```
Docker Compose  →  Kubernetes natif  →  Kustomize  →  Helm
                      (Lab 1)           (Lab 2)      (Lab 3)
                     Scalable          Multi-env    Distributable
```

**Durée totale estimée :** 3h15 - 4h00

## Pré-requis

- Cluster GKE opérationnel avec `kubectl` configuré
- `helm` installé (Lab 3)

## Organisation des fichiers

```
k8s/
├── README.md          ← Ce fichier
├── lab1.md            ← Lab 1 : De Docker Compose à Kubernetes natif
├── lab2.md            ← Lab 2 : Refactoring avec Kustomize
└── lab3.md            ← Lab 3 : Packaging avec Helm
```
