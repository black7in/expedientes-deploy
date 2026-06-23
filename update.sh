#!/bin/bash
# ─────────────────────────────────────────────────────────────────────────────
#  update.sh — Actualiza el sistema jalando los últimos cambios de GitHub
#
#  Uso:
#    bash update.sh                        # Rama por defecto (develop / master)
#    bash update.sh --branch feature/sprint3   # Rama específica para ambos repos
#    bash update.sh --seed                 # Actualiza y corre seeders
#    bash update.sh --branch feature/sprint3 --seed
# ─────────────────────────────────────────────────────────────────────────────

set -e

DEPLOY_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_DIR="$HOME/expedientes-app"
AI_DIR="$HOME/expedientes-ai"
TSJ_DIR="$HOME/tsj_jurisprudencia"

BRANCH_APP="develop"
BRANCH_AI="master"
RUN_SEED=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --branch) BRANCH_APP="$2"; BRANCH_AI="$2"; shift 2 ;;
    --seed)   RUN_SEED=true; shift ;;
    *) echo "Opción desconocida: $1"; exit 1 ;;
  esac
done

echo "→ Pulling expedientes-app ($BRANCH_APP)..."
cd "$APP_DIR" && git fetch origin && git checkout "$BRANCH_APP" && git pull origin "$BRANCH_APP"

echo "→ Pulling expedientes-ai ($BRANCH_AI)..."
cd "$AI_DIR" && git fetch origin && git checkout "$BRANCH_AI" && git pull origin "$BRANCH_AI"

if [ -d "$TSJ_DIR" ]; then
  echo "→ Pulling tsj_jurisprudencia (main)..."
  cd "$TSJ_DIR" && git fetch origin && git checkout main && git pull origin main
  TSJ_SERVICES="tsj tsj_postgres"
else
  echo "→ tsj_jurisprudencia no encontrado, omitiendo."
  TSJ_SERVICES=""
fi

echo "→ Rebuilding images (con caché)..."
cd "$DEPLOY_DIR" && docker compose build app queue nginx ai $TSJ_SERVICES

echo "→ Restarting containers..."
docker compose up -d app queue nginx ai $TSJ_SERVICES

echo "→ Corriendo migraciones..."
sleep 5
docker compose exec app php artisan migrate --force

if [ "$RUN_SEED" = true ]; then
  echo "→ Corriendo seeders..."
  docker compose exec app php artisan db:seed --force
fi

echo ""
echo "✓ Deploy completado."
