#!/bin/sh
# cleaner.sh — Supprime les news plus vieilles que MAX_AGE_SECONDS (défaut : 3600s = 1h)

set -e

MAX_AGE=${MAX_AGE_SECONDS:-3600}
REDIS_HOST="${REDIS_HOST:-localhost}"
REDIS_PORT="${REDIS_PORT:-6379}"
REDIS_PASSWORD="${REDIS_PASSWORD:-}"

AUTH_FLAG=""
if [ -n "$REDIS_PASSWORD" ]; then
  AUTH_FLAG="-a $REDIS_PASSWORD"
fi

REDIS="redis-cli -h $REDIS_HOST -p $REDIS_PORT $AUTH_FLAG --no-auth-warning"
NEWS_KEY="devops_news"

echo "[cleaner] Demarrage — suppression des news > ${MAX_AGE}s"

NOW=$(date +%s)
LEN=$($REDIS LLEN "$NEWS_KEY")

if [ "$LEN" -eq 0 ]; then
  echo "[cleaner] Aucune news en base. Rien a faire."
  exit 0
fi

echo "[cleaner] $LEN news trouvees. Analyse..."

DELETED=0
# Parcours de la liste du plus ancien (fin) au plus recent (debut)
IDX=$((LEN - 1))
while [ "$IDX" -ge 0 ]; do
  ENTRY=$($REDIS LINDEX "$NEWS_KEY" "$IDX")
  # Extraire le timestamp du JSON avec sed (pas de jq sur alpine de base)
  TS=$(echo "$ENTRY" | sed -n 's/.*"timestamp"[[:space:]]*:[[:space:]]*\([0-9]*\).*/\1/p')

  if [ -z "$TS" ]; then
    IDX=$((IDX - 1))
    continue
  fi

  AGE=$((NOW - TS))
  if [ "$AGE" -gt "$MAX_AGE" ]; then
    $REDIS LREM "$NEWS_KEY" 1 "$ENTRY" > /dev/null
    DELETED=$((DELETED + 1))
    # Apres suppression, la liste est plus courte, on ne decremente pas IDX
    IDX=$((IDX - 1))
  else
    IDX=$((IDX - 1))
  fi
done

echo "[cleaner] Termine — $DELETED news supprimee(s)."
