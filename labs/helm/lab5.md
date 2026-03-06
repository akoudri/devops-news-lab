# Lab Helm 5 — Qualité & Sécurité

## 🎯 Objectif

Un chart qui fonctionne n'est pas forcément un chart de qualité. Dans ce lab, vous allez enrichir le chart `devops-news` avec les mécanismes de qualité et de sécurité indispensables en production : validation par schéma, fichier `NOTES.txt`, tests Helm, hooks de cycle de vie, et gestion sécurisée des secrets.

**Module couvert :** 6 (Sécurité, Qualité et Tests)

**Temps estimé :** 1h15 - 1h30

---

## 📋 Pré-requis

1. Avoir terminé le Lab 4.
2. Travailler sur une copie du chart `devops-news-v2` produit au Lab 4 :
```bash
cp -r helm/devops-news-v2 helm/devops-news-v3
cd helm/
```

---

## Étape 1 : Validation statique avec `helm lint`

`helm lint` est la première ligne de défense. Il analyse statiquement votre chart **avant** tout déploiement.

### 1.1 État initial

```bash
helm lint ./devops-news-v3
```

Notez les éventuels avertissements existants. `helm lint` distingue :
- **[ERROR]** : Le chart ne peut pas être installé.
- **[WARNING]** : Bonne pratique non respectée (ex: icône manquante, description vide).
- **[INFO]** : Information non bloquante.

### 1.2 Corriger les avertissements courants

Ajoutez les champs manquants dans `Chart.yaml` :

```yaml
icon: https://raw.githubusercontent.com/helm/helm/main/docs/logos/helm.png
home: https://github.com/votre-org/devops-news
sources:
  - https://github.com/votre-org/devops-news
```

Relancez `helm lint` et vérifiez que les avertissements disparaissent.

### 1.3 Aller plus loin avec `kube-linter`

`kube-linter` est un outil externe qui vérifie des règles de sécurité que `helm lint` ne couvre pas.

```bash
# Installation
curl -sLO https://github.com/stackrox/kube-linter/releases/latest/download/kube-linter-linux.tar.gz
tar -xzf kube-linter-linux.tar.gz
sudo mv kube-linter /usr/local/bin/

# Générer le YAML puis l'analyser
helm template test ./devops-news-v3 | kube-linter lint -
```

Exemples de règles vérifiées par `kube-linter` :
- Absence de `securityContext` (ne pas tourner en root)
- Utilisation du tag `latest` (interdit en prod)
- Absence de `readinessProbe` et `livenessProbe`
- Absence de limites de ressources

> **Pour ce lab :** Prenez note des erreurs signalées par `kube-linter` mais ne les corrigez pas toutes — nous nous concentrons sur les mécanismes Helm. L'objectif est de comprendre le type d'analyse possible.

---

## Étape 2 : Schéma de validation — `values.schema.json`

Helm permet de définir un schéma JSON pour valider les valeurs saisies par l'utilisateur **avant** le déploiement. C'est une protection essentielle pour les charts distribués à d'autres équipes.

### 2.1 Créer `devops-news-v3/values.schema.json`

```json
{
  "$schema": "https://json-schema.org/draft/2020-12/schema",
  "title": "DevOps-News Chart Values",
  "type": "object",
  "properties": {
    "backend": {
      "type": "object",
      "properties": {
        "replicas": {
          "type": "integer",
          "minimum": 1,
          "maximum": 10,
          "description": "Nombre de réplicas pour le backend Flask"
        },
        "logLevel": {
          "type": "string",
          "enum": ["DEBUG", "INFO", "WARNING", "ERROR"],
          "description": "Niveau de log Flask"
        }
      },
      "required": ["replicas", "logLevel"]
    },
    "redis": {
      "type": "object",
      "properties": {
        "enabled": {
          "type": "boolean"
        },
        "password": {
          "type": "string",
          "minLength": 8,
          "description": "Mot de passe Redis (minimum 8 caractères)"
        },
        "storage": {
          "type": "string",
          "pattern": "^[0-9]+(Mi|Gi)$",
          "description": "Taille du PVC Redis (ex: 1Gi, 500Mi)"
        }
      },
      "required": ["password"]
    }
  }
}
```

### 2.2 Tester la validation

```bash
# ✅ Valeur correcte
helm template test ./devops-news-v3 --set backend.replicas=3

# ❌ Type incorrect (string au lieu d'entier)
helm template test ./devops-news-v3 --set backend.replicas=abc

# ❌ Valeur hors enum
helm template test ./devops-news-v3 --set backend.logLevel=VERBOSE

# ❌ Mot de passe trop court
helm template test ./devops-news-v3 --set redis.password=abc

# ❌ Valeur hors limite
helm template test ./devops-news-v3 --set backend.replicas=20
```

Helm doit rejeter les valeurs invalides avec un message d'erreur clair, avant même de contacter le cluster.

---

## Étape 3 : Le fichier `NOTES.txt`

`NOTES.txt` est affiché automatiquement après chaque `helm install` ou `helm upgrade`. C'est le guide de démarrage rapide de votre chart.

### 3.1 Créer `devops-news-v3/templates/NOTES.txt`

```
🚀 DevOps-News {{ .Chart.AppVersion }} déployé avec succès !
Release : {{ .Release.Name }}
Namespace : {{ .Release.Namespace }}

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

📡 Accéder à l'application :

{{- if eq .Values.frontend.service.type "LoadBalancer" }}

  Attendez l'assignation de l'IP externe :
    kubectl get svc {{ include "devops-news.fullname" (dict "root" . "component" "frontend") }} \
      --namespace {{ .Release.Namespace }} -w

  Une fois l'IP assignée, ouvrez : http://<EXTERNAL-IP>

{{- else if eq .Values.frontend.service.type "ClusterIP" }}

  Le service est accessible en interne uniquement.
  Utilisez un port-forward pour tester :
    kubectl port-forward svc/{{ include "devops-news.fullname" (dict "root" . "component" "frontend") }} \
      8080:80 --namespace {{ .Release.Namespace }}

  Puis ouvrez : http://localhost:8080

{{- end }}

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

🔧 Commandes utiles :

  # Voir les logs du backend
  kubectl logs -l app.kubernetes.io/name=backend -n {{ .Release.Namespace }} -f

  # Vérifier la santé de l'API
  kubectl port-forward svc/{{ include "devops-news.fullname" (dict "root" . "component" "backend") }} \
    5001:5000 -n {{ .Release.Namespace }} &
  curl http://localhost:5001/health

  # Historique et rollback
  helm history {{ .Release.Name }} -n {{ .Release.Namespace }}
  helm rollback {{ .Release.Name }} <REVISION> -n {{ .Release.Namespace }}

{{- if .Values.cleaner.enabled }}

  # Déclencher le nettoyage manuellement
  kubectl create job --from=cronjob/{{ include "devops-news.fullname" (dict "root" . "component" "cleaner") }} \
    manual-clean -n {{ .Release.Namespace }}
{{- end }}
```

### 3.2 Tester l'affichage des NOTES

```bash
kubectl create namespace devops-news-lab5

helm install news ./devops-news-v3 --namespace devops-news-lab5
```

Le contenu de `NOTES.txt` s'affiche immédiatement après l'installation. Pour le réafficher à tout moment :

```bash
helm status news -n devops-news-lab5
```

---

## Étape 4 : Tests Helm

Les tests Helm permettent de **valider que l'application fonctionne** après installation, pas seulement que le YAML est valide.

### 4.1 Créer le dossier de tests

```bash
mkdir -p devops-news-v3/templates/tests
```

### 4.2 Créer le test de santé backend

Créez `devops-news-v3/templates/tests/test-backend-health.yaml` :

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: {{ include "devops-news.fullname" (dict "root" . "component" "test-backend-health") }}
  labels:
    {{- include "devops-news.labels" (dict "root" . "component" "test") | nindent 4 }}
  annotations:
    # Cette annotation indique à Helm que ce Pod est un test
    "helm.sh/hook": test
    # Nettoyer le Pod après le test
    "helm.sh/hook-delete-policy": before-hook-creation,hook-succeeded
spec:
  restartPolicy: Never
  containers:
    - name: health-check
      image: curlimages/curl:latest
      command:
        - sh
        - -c
        - |
          echo "Test de santé du backend DevOps-News..."
          RESPONSE=$(curl -s -o /dev/null -w "%{http_code}" \
            http://{{ include "devops-news.fullname" (dict "root" . "component" "backend") }}:{{ .Values.backend.service.port }}/health)
          echo "Code HTTP reçu : $RESPONSE"
          if [ "$RESPONSE" = "200" ]; then
            echo "✅ Backend opérationnel"
            exit 0
          else
            echo "❌ Backend non opérationnel (code $RESPONSE)"
            exit 1
          fi
```

### 4.3 Créer le test de connectivité Redis

Créez `devops-news-v3/templates/tests/test-redis-connectivity.yaml` :

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: {{ include "devops-news.fullname" (dict "root" . "component" "test-redis") }}
  labels:
    {{- include "devops-news.labels" (dict "root" . "component" "test") | nindent 4 }}
  annotations:
    "helm.sh/hook": test
    "helm.sh/hook-delete-policy": before-hook-creation,hook-succeeded
spec:
  restartPolicy: Never
  containers:
    - name: redis-check
      image: redis:6.0-alpine
      env:
        - name: REDIS_PASSWORD
          valueFrom:
            secretKeyRef:
              name: {{ include "devops-news.redisSecretName" . }}
              key: password
      command:
        - sh
        - -c
        - |
          echo "Test de connectivité Redis..."
          RESULT=$(redis-cli \
            -h {{ include "devops-news.fullname" (dict "root" . "component" "redis") }} \
            -p {{ .Values.redis.service.port }} \
            -a "$REDIS_PASSWORD" \
            --no-auth-warning PING)
          echo "Réponse Redis : $RESULT"
          if [ "$RESULT" = "PONG" ]; then
            echo "✅ Redis accessible"
            exit 0
          else
            echo "❌ Redis inaccessible"
            exit 1
          fi
```

### 4.4 Exécuter les tests

```bash
helm test news -n devops-news-lab5
```

Helm lance les Pods de test, attend leur code de sortie (0 = succès, autre = échec) et affiche le résultat. En cas d'échec, inspectez les logs :

```bash
kubectl logs -n devops-news-lab5 \
  $(kubectl get pods -n devops-news-lab5 -l "helm.sh/chart" -o jsonpath='{.items[0].metadata.name}')
```

---

## Étape 5 : Les Hooks Helm

Les hooks permettent d'exécuter des actions à des moments précis du cycle de vie d'une release.

### 5.1 Hook `pre-upgrade` — Sauvegarde avant mise à jour

Créez `devops-news-v3/templates/hooks/pre-upgrade-backup.yaml` :

```yaml
apiVersion: batch/v1
kind: Job
metadata:
  name: {{ include "devops-news.fullname" (dict "root" . "component" "pre-upgrade-backup") }}
  labels:
    {{- include "devops-news.labels" (dict "root" . "component" "backup") | nindent 4 }}
  annotations:
    # S'exécute AVANT l'upgrade, pas à l'install
    "helm.sh/hook": pre-upgrade
    # Gestion du poids (ordre d'exécution si plusieurs hooks)
    "helm.sh/hook-weight": "0"
    # Nettoyage automatique après succès
    "helm.sh/hook-delete-policy": before-hook-creation,hook-succeeded
spec:
  template:
    spec:
      restartPolicy: OnFailure
      containers:
        - name: backup
          image: redis:6.0-alpine
          env:
            - name: REDIS_PASSWORD
              valueFrom:
                secretKeyRef:
                  name: {{ include "devops-news.redisSecretName" . }}
                  key: password
          command:
            - sh
            - -c
            - |
              echo "[pre-upgrade] Sauvegarde des données Redis avant upgrade..."
              COUNT=$(redis-cli \
                -h {{ include "devops-news.fullname" (dict "root" . "component" "redis") }} \
                -p {{ .Values.redis.service.port }} \
                -a "$REDIS_PASSWORD" \
                --no-auth-warning LLEN devops_news)
              echo "[pre-upgrade] $COUNT news en base avant la mise à jour."
              echo "[pre-upgrade] Sauvegarde simulée terminée ✅"
              # En production : redis-cli BGSAVE ou snapshot vers un bucket GCS
```

### 5.2 Déclencher le hook

```bash
# Simuler un upgrade pour déclencher le hook pre-upgrade
helm upgrade news ./devops-news-v3 \
  --namespace devops-news-lab5 \
  --set backend.replicas=3

# Observer le job de backup créé par le hook
kubectl get jobs -n devops-news-lab5
kubectl logs -n devops-news-lab5 job/news-pre-upgrade-backup
```

### 5.3 Les différents hooks disponibles

| Hook | Déclencheur |
|------|-------------|
| `pre-install` | Avant la création des ressources du chart |
| `post-install` | Après la création de toutes les ressources |
| `pre-upgrade` | Avant l'application d'un upgrade |
| `post-upgrade` | Après l'upgrade |
| `pre-delete` | Avant la suppression des ressources |
| `post-delete` | Après la suppression |
| `pre-rollback` | Avant un rollback |

---

## Étape 6 : Gestion sécurisée des secrets

Le mot de passe Redis est actuellement stocké en clair dans `values.yaml`. Ce n'est **jamais** acceptable pour un dépôt Git partagé.

### 6.1 Comprendre le problème

```bash
# Les Secrets Kubernetes ne sont que encodés en Base64, pas chiffrés
kubectl get secret news-redis-secret -n devops-news-lab5 -o jsonpath='{.data.password}' | base64 -d
```

Vous voyez le mot de passe en clair. N'importe qui avec accès au cluster peut le lire.

### 6.2 Solution 1 : Injection à l'installation (sans stocker dans Git)

```bash
# On passe le secret uniquement en ligne de commande — jamais dans un fichier versionné
helm upgrade news ./devops-news-v3 \
  --namespace devops-news-lab5 \
  --set redis.password="$(openssl rand -base64 32)"
```

**Problème :** À chaque upgrade, si on ne re-spécifie pas le mot de passe, il est réinitialisé à la valeur par défaut de `values.yaml`.

### 6.3 Solution 2 : `--reuse-values`

```bash
# Conserver toutes les valeurs du dernier upgrade, y compris le password
helm upgrade news ./devops-news-v3 \
  --namespace devops-news-lab5 \
  --reuse-values \
  --set backend.replicas=2
```

### 6.4 Solution 3 (recommandée) : External Secrets Operator

En production, l'approche recommandée est de ne **jamais** faire passer le secret par Helm. À la place, le chart crée un objet `ExternalSecret` qui demande à un opérateur d'aller chercher la valeur dans un coffre-fort (GCP Secret Manager, AWS Secrets Manager, HashiCorp Vault).

Voici à quoi ressemblerait un tel objet dans un template Helm :

```yaml
{{- if .Values.redis.externalSecret.enabled }}
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: {{ include "devops-news.redisSecretName" . }}
spec:
  refreshInterval: 1h
  secretStoreRef:
    name: {{ .Values.redis.externalSecret.secretStore }}
    kind: ClusterSecretStore
  target:
    name: {{ include "devops-news.redisSecretName" . }}
  data:
    - secretKey: password
      remoteRef:
        key: {{ .Values.redis.externalSecret.secretPath }}
{{- end }}
```

> **Note :** L'implémentation complète de l'External Secrets Operator sort du périmètre de ce lab. L'objectif est de comprendre l'architecture.

---

## ✅ Validation finale

```bash
# Lint final
helm lint ./devops-news-v3

# Tests fonctionnels
helm test news -n devops-news-lab5 --logs
```

1. `helm lint` : zéro erreur, zéro warning.
2. `helm test` : tous les tests passent.
3. Les NOTES s'affichent correctement après installation.
4. Le hook `pre-upgrade` se déclenche lors d'un `helm upgrade`.
5. Le schéma JSON rejette les valeurs invalides.

---

## Nettoyage

```bash
helm uninstall news -n devops-news-lab5
kubectl delete namespace devops-news-lab5
```
