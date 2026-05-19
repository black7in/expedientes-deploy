#!/bin/bash
# ─────────────────────────────────────────────────────────────────────────────
#  update.sh — Actualiza el sistema jalando los últimos cambios de GitHub
#
#  Uso:
#    bash update.sh          # Solo actualiza
#    bash update.sh --seed   # Actualiza y corre seeders (primer deploy / demo)
# ─────────────────────────────────────────────────────────────────────────────

set -e

DEPLOY_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_DIR="$HOME/expedientes-app"
AI_DIR="$HOME/expedientes-ai"

echo "→ Pulling expedientes-app (develop)..."
cd "$APP_DIR" && git pull origin develop

echo "→ Pulling expedientes-ai (master)..."
cd "$AI_DIR" && git pull origin master

echo "→ Rebuilding images (con caché)..."
cd "$DEPLOY_DIR" && docker compose build app queue nginx ai

echo "→ Restarting containers..."
docker compose up -d app queue nginx ai

echo "→ Esperando que app esté lista..."
sleep 5

if [ "$1" = "--seed" ]; then
  echo "→ Corriendo seeders..."
  docker compose exec app php artisan db:seed --force
fi

echo ""
echo "✓ Deploy completado."
