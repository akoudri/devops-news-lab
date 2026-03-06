# Lab Helm 6 — Tests Unitaires avec `helm-unittest`

## 🎯 Objectif

Un chart Helm sans tests est un chart non maintenable. Dans ce lab, vous allez écrire une suite de tests unitaires complète pour le chart `devops-news` : tester les cas nominaux, les cas limites, les conditions (`if`) et les boucles (`range`). Ces tests s'intègrent ensuite dans un pipeline CI/CD pour garantir que chaque modification du chart ne casse pas le comportement attendu.

**Module couvert :** 6 (Qualité & Sécurité — `helm-unittest`)

**Temps estimé :** 1h15 - 1h30

---

## 📋 Pré-requis

1. Avoir terminé le Lab 4 (chart `devops-news-v2` avec helpers et templating avancé).
2. Se placer dans le dossier : `cd helm/`

---

## Contexte : Pourquoi tester les templates ?

Un template Helm est du code. Comme tout code, il peut contenir des régressions :

- Vous ajoutez une condition `{{- if }}` et elle casse le rendu Redis quand `redis.enabled: false`.
- Vous refactorisez un helper et le nom des ressources change silencieusement.
- Un collègue modifie une valeur par défaut dans `values.yaml` et deux pods perdent leur variable d'environnement `REDIS_PASSWORD`.

`helm-unittest` permet de **piéger ces régressions avant le déploiement**, sans cluster, en quelques secondes.

---

## Étape 1 : Installation du plugin

```bash
helm plugin install https://github.com/helm-unittest/helm-unittest.git
```

Vérifier l'installation :

```bash
helm unittest --help
```

> **Note CI/CD :** Dans un pipeline GitHub Actions ou GitLab CI, `helm-unittest` est disponible comme image Docker officielle : `helmunittest/helm-unittest`. Aucune installation manuelle requise.

---

## Étape 2 : Structure des tests

`helm-unittest` cherche les fichiers de test dans le dossier `tests/` à la racine du chart, avec le suffixe `_test.yaml`.

```bash
mkdir -p devops-news-v2/tests/
```

Structure finale visée :

```
devops-news-v2/
└── tests/
    ├── backend_test.yaml
    ├── frontend_test.yaml
    ├── redis_test.yaml
    └── cleaner_test.yaml
```

---

## Étape 3 : Anatomie d'un test

Chaque fichier de test est composé de **suites** (`suite`), contenant des **cas de test** (`tests`). Voici le squelette :

```yaml
suite: "Nom de la suite de tests"

# Valeurs appliquées à TOUS les tests de cette suite (optionnel)
values:
  - ../values.yaml

tests:
  - it: "Description du test (phrase complète)"
    # Valeurs spécifiques à CE test (écrasent les valeurs du haut)
    set:
      backend.replicas: 3
    # Les assertions à vérifier
    asserts:
      - equal:
          path: spec.replicas
          value: 3
```

Les **types d'assertion** disponibles :

| Assertion | Description |
|---|---|
| `equal` | La valeur au chemin donné est exactement égale |
| `notEqual` | La valeur au chemin donné est différente |
| `matchRegex` | La valeur correspond à une regex |
| `contains` | La liste contient l'élément donné |
| `notContains` | La liste ne contient pas l'élément donné |
| `isNull` | Le champ est absent ou null |
| `isNotNull` | Le champ est présent et non null |
| `isKind` | La ressource est du type Kubernetes attendu |
| `hasDocuments` | Le nombre de documents YAML générés est correct |
| `failedTemplate` | Le template doit échouer (test d'erreur) |

---

## Étape 4 : Tests du Backend

Créez `devops-news-v2/tests/backend_test.yaml` :

```yaml
suite: "Backend — Deployment et Service"

templates:
  - "templates/backend.yaml"

tests:

  # ── Cas nominal ──────────────────────────────────────────────────
  - it: "doit créer un Deployment et un Service"
    asserts:
      - hasDocuments:
          count: 2
      - isKind:
          of: Deployment
        documentIndex: 0
      - isKind:
          of: Service
        documentIndex: 1

  - it: "le Deployment doit avoir le bon nombre de réplicas par défaut"
    asserts:
      - equal:
          path: spec.replicas
          value: 2
        documentIndex: 0

  - it: "le nom du Deployment doit inclure le nom de la release"
    release:
      name: my-release
    asserts:
      - equal:
          path: metadata.name
          value: my-release-backend
        documentIndex: 0

  # ── Variables d'environnement ────────────────────────────────────
  - it: "doit injecter REDIS_HOST avec le nom de la release"
    release:
      name: production
    asserts:
      - contains:
          path: spec.template.spec.containers[0].env
          content:
            name: REDIS_HOST
            value: "production-redis"
        documentIndex: 0

  - it: "doit injecter LOG_LEVEL depuis les values"
    set:
      backend.logLevel: "DEBUG"
    asserts:
      - contains:
          path: spec.template.spec.containers[0].env
          content:
            name: LOG_LEVEL
            value: "DEBUG"
        documentIndex: 0

  - it: "doit référencer le Secret Redis pour REDIS_PASSWORD"
    release:
      name: test
    asserts:
      - contains:
          path: spec.template.spec.containers[0].env
          content:
            name: REDIS_PASSWORD
            valueFrom:
              secretKeyRef:
                name: test-redis-secret
                key: password
        documentIndex: 0

  # ── Image Docker ─────────────────────────────────────────────────
  - it: "doit construire le nom d'image avec le compte et le tag"
    set:
      images.repoAccount: "myorg"
      images.tags.backend: "v2.1"
    asserts:
      - equal:
          path: spec.template.spec.containers[0].image
          value: "myorg/devops-news-api:v2.1"
        documentIndex: 0

  # ── Surcharge des réplicas ───────────────────────────────────────
  - it: "doit respecter la valeur de réplicas surchargée"
    set:
      backend.replicas: 5
    asserts:
      - equal:
          path: spec.replicas
          value: 5
        documentIndex: 0

  # ── Service ──────────────────────────────────────────────────────
  - it: "le Service doit être de type ClusterIP par défaut"
    asserts:
      - equal:
          path: spec.type
          value: ClusterIP
        documentIndex: 1

  - it: "le Service doit exposer le bon port"
    asserts:
      - equal:
          path: spec.ports[0].port
          value: 5000
        documentIndex: 1

  # ── Variables d'environnement supplémentaires (extraEnv) ─────────
  - it: "doit injecter les extraEnv quand elles sont définies"
    set:
      backend.extraEnv:
        - name: FEATURE_X
          value: "enabled"
        - name: SENTRY_DSN
          value: "https://sentry.io/123"
    asserts:
      - contains:
          path: spec.template.spec.containers[0].env
          content:
            name: FEATURE_X
            value: "enabled"
        documentIndex: 0
      - contains:
          path: spec.template.spec.containers[0].env
          content:
            name: SENTRY_DSN
            value: "https://sentry.io/123"
        documentIndex: 0

  - it: "ne doit pas avoir d'extraEnv quand la liste est vide"
    set:
      backend.extraEnv: []
    asserts:
      - notContains:
          path: spec.template.spec.containers[0].env
          content:
            name: FEATURE_X
            value: "enabled"
        documentIndex: 0
```

### Lancer les tests du backend

```bash
helm unittest devops-news-v2 --file tests/backend_test.yaml
```

Tous les tests doivent passer. Corrigez les éventuels échecs avant de continuer.

---

## Étape 5 : Tests Redis (conditions)

Créez `devops-news-v2/tests/redis_test.yaml` :

```yaml
suite: "Redis — StatefulSet, Service et Secret"

tests:

  # ── Activation conditionnelle ────────────────────────────────────
  - it: "doit créer le StatefulSet Redis quand redis.enabled est true"
    template: "templates/redis.yaml"
    set:
      redis.enabled: true
    asserts:
      - hasDocuments:
          count: 2    # Service + StatefulSet
      - isKind:
          of: StatefulSet
        documentIndex: 1

  - it: "ne doit rien générer quand redis.enabled est false"
    template: "templates/redis.yaml"
    set:
      redis.enabled: false
    asserts:
      - hasDocuments:
          count: 0

  - it: "ne doit pas créer le Secret Redis quand redis.enabled est false"
    template: "templates/redis-secret.yaml"
    set:
      redis.enabled: false
    asserts:
      - hasDocuments:
          count: 0

  # ── Configuration du stockage ────────────────────────────────────
  - it: "doit utiliser la taille de stockage configurée"
    template: "templates/redis.yaml"
    set:
      redis.enabled: true
      redis.storage: "5Gi"
    asserts:
      - equal:
          path: spec.volumeClaimTemplates[0].spec.resources.requests.storage
          value: "5Gi"
        documentIndex: 1

  - it: "doit utiliser la storageClassName configurée"
    template: "templates/redis.yaml"
    set:
      redis.enabled: true
      redis.storageClassName: "premium-rwo"
    asserts:
      - equal:
          path: spec.volumeClaimTemplates[0].spec.storageClassName
          value: "premium-rwo"
        documentIndex: 1

  # ── Secret ───────────────────────────────────────────────────────
  - it: "le Secret doit encoder le mot de passe en base64"
    template: "templates/redis-secret.yaml"
    set:
      redis.enabled: true
      redis.password: "mysecretpassword"
    asserts:
      - equal:
          path: data.password
          # "mysecretpassword" encodé en base64
          value: "bXlzZWNyZXRwYXNzd29yZA=="
```

```bash
helm unittest devops-news-v2 \
  --file tests/redis_test.yaml
```

---

## Étape 6 : Tests du Cleaner (CronJob conditionnel)

Créez `devops-news-v2/tests/cleaner_test.yaml` :

```yaml
suite: "Cleaner — CronJob conditionnel"

templates:
  - "templates/cleaner.yaml"

tests:

  - it: "doit créer le CronJob quand cleaner.enabled est true"
    set:
      cleaner.enabled: true
    asserts:
      - hasDocuments:
          count: 1
      - isKind:
          of: CronJob

  - it: "ne doit rien générer quand cleaner.enabled est false"
    set:
      cleaner.enabled: false
    asserts:
      - hasDocuments:
          count: 0

  - it: "doit utiliser le schedule configuré"
    set:
      cleaner.enabled: true
      cleaner.schedule: "0 3 * * *"
    asserts:
      - equal:
          path: spec.schedule
          value: "0 3 * * *"

  - it: "doit injecter MAX_AGE_SECONDS depuis les values"
    set:
      cleaner.enabled: true
      cleaner.maxAgeSeconds: 7200
    asserts:
      - contains:
          path: spec.jobTemplate.spec.template.spec.containers[0].env
          content:
            name: MAX_AGE_SECONDS
            value: "7200"

  - it: "doit avoir restartPolicy à OnFailure"
    set:
      cleaner.enabled: true
    asserts:
      - equal:
          path: spec.jobTemplate.spec.template.spec.restartPolicy
          value: OnFailure
```

---

## Étape 7 : Tests des Labels (helpers)

Ce test vérifie que votre `_helpers.tpl` produit les labels standards corrects sur toutes les ressources.

Créez `devops-news-v2/tests/labels_test.yaml` :

```yaml
suite: "Labels standards — vérification des helpers"

tests:

  - it: "le Deployment backend doit avoir les labels app.kubernetes.io standards"
    template: "templates/backend.yaml"
    release:
      name: myapp
    asserts:
      - equal:
          path: metadata.labels["app.kubernetes.io/name"]
          value: backend
        documentIndex: 0
      - equal:
          path: metadata.labels["app.kubernetes.io/instance"]
          value: myapp
        documentIndex: 0
      - equal:
          path: metadata.labels["app.kubernetes.io/managed-by"]
          value: Helm
        documentIndex: 0

  - it: "le nom du Deployment doit être release-backend (trunc à 63 chars)"
    template: "templates/backend.yaml"
    release:
      # Nom volontairement long pour tester le trunc
      name: "this-is-a-very-long-release-name-that-exceeds"
    asserts:
      - matchRegex:
          path: metadata.name
          pattern: "^.{1,63}$"
        documentIndex: 0

  - it: "les selectorLabels doivent correspondre entre Deployment et Service"
    template: "templates/backend.yaml"
    release:
      name: test
    asserts:
      # Les selector du Service doivent cibler les labels du pod
      - equal:
          path: spec.selector["app.kubernetes.io/name"]
          value: backend
        documentIndex: 1
      - equal:
          path: spec.selector["app.kubernetes.io/instance"]
          value: test
        documentIndex: 1
```

---

## Étape 8 : Lancer la suite complète

```bash
# Lancer tous les tests du chart en une commande
helm unittest devops-news-v2

# Mode verbose (affiche chaque test individuellement)
helm unittest devops-news-v2 --verbose

# Générer un rapport JUnit (pour l'intégration CI/CD)
helm unittest devops-news-v2 --output-type JUnit --output-file test-results.xml
cat test-results.xml
```

La sortie doit ressembler à :

```
### Chart [ devops-news ] devops-news-v2

 PASS  Backend — Deployment et Service     tests/backend_test.yaml
 PASS  Redis — StatefulSet et Secret       tests/redis_test.yaml
 PASS  Cleaner — CronJob conditionnel      tests/cleaner_test.yaml
 PASS  Labels standards                    tests/labels_test.yaml

Charts:      1 passed, 0 failed
Test Suites: 4 passed, 0 failed
Tests:       24 passed, 0 failed
```

---

## Étape 9 : Intégration dans un pipeline CI/CD

### 9.1 GitHub Actions

Créez `.github/workflows/helm-test.yml` dans votre dépôt :

```yaml
name: Helm Unit Tests

on:
  push:
    paths:
      - 'helm/devops-news-v2/**'
  pull_request:
    paths:
      - 'helm/devops-news-v2/**'

jobs:
  unittest:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Install Helm
        uses: azure/setup-helm@v4

      - name: Run helm-unittest
        run: |
          docker run --rm \
            -v $(pwd)/helm:/apps \
            helmunittest/helm-unittest \
            devops-news-v2 \
            --output-type JUnit \
            --output-file /apps/test-results.xml

      - name: Publish test results
        uses: EnricoMi/publish-unit-test-result-action@v2
        if: always()
        with:
          files: helm/test-results.xml
```

### 9.2 Placer `helm unittest` dans la chaîne de validation

L'ordre recommandé dans un pipeline CI Helm :

```
1. helm lint          ← Syntaxe et structure
2. helm unittest      ← Logique des templates (ce lab)
3. helm template      ← Rendu final sans cluster
4. helm install --dry-run  ← Validation côté API server
5. helm push (OCI)    ← Publication (Lab 3, Étape 9)
```

---

## ✅ Validation finale

```bash
helm unittest devops-news-v2 --verbose
```

Vérifiez que :

1. Toutes les suites passent (zéro `FAIL`).
2. Le test `redis.enabled: false` confirme bien `hasDocuments: 0`.
3. Le test de base64 du Secret passe avec le bon encodage.
4. Le rapport JUnit est généré sans erreur.

**Défi bonus :** Écrivez un test qui vérifie que le schéma JSON (`values.schema.json` du Lab 5) rejette bien une valeur `backend.replicas: 0` (en dessous du `minimum: 1`). Utilisez l'assertion `failedTemplate`.

```yaml
- it: "doit échouer si backend.replicas est inférieur à 1"
  set:
    backend.replicas: 0
  asserts:
    - failedTemplate:
        errorMessage: "backend.replicas"
```

---

## Nettoyage

Aucun cluster utilisé dans ce lab — aucun nettoyage nécessaire.

```bash
# Optionnel : supprimer le rapport JUnit
rm -f helm/test-results.xml
```
