#!/bin/bash
# deploy app — backend, frontend, nginx, pm2, migrations
set -euo pipefail

DEPLOY_DIR="${DEPLOY_DIR:-/tmp/bmi-deploy}"
APP_ROOT="/opt/bmi-app"
BACKEND_DIR="$APP_ROOT/backend"
FRONTEND_DIR="/var/www/bmi-health-tracker"
ENV_FILE="$BACKEND_DIR/.env"

echo "==> Deploying BMI application..."

sudo mkdir -p "$APP_ROOT" "$BACKEND_DIR" "$FRONTEND_DIR"
sudo chown -R ubuntu:ubuntu "$APP_ROOT"

# backend
if [ -f "$DEPLOY_DIR/backend.tar.gz" ]; then
  echo "==> Extracting backend..."
  tar -xzf "$DEPLOY_DIR/backend.tar.gz" -C "$BACKEND_DIR"
fi

# keep existing .env from bootstrap; only create if missing
if [ ! -f "$ENV_FILE" ]; then
  echo "==> Creating backend .env from bootstrap defaults..."
  PUBLIC_IP=$(curl -sf http://169.254.169.254/latest/meta-data/public-ipv4 2>/dev/null || echo "http://localhost")
  cat > "$ENV_FILE" <<EOF
PORT=3000
DATABASE_URL=postgresql://bmi_user:changeme@localhost:5432/bmidb
NODE_ENV=production
FRONTEND_URL=http://${PUBLIC_IP}
EOF
  chmod 600 "$ENV_FILE"
  echo "WARNING: .env created with defaults — ensure DATABASE_URL matches bootstrap credentials"
fi

# update FRONTEND_URL for CORS if public IP available
PUBLIC_IP=$(curl -sf http://169.254.169.254/latest/meta-data/public-ipv4 2>/dev/null || true)
if [ -n "$PUBLIC_IP" ] && [ -f "$ENV_FILE" ]; then
  if grep -q "^FRONTEND_URL=" "$ENV_FILE"; then
    sed -i "s|^FRONTEND_URL=.*|FRONTEND_URL=http://${PUBLIC_IP}|" "$ENV_FILE"
  else
    echo "FRONTEND_URL=http://${PUBLIC_IP}" >> "$ENV_FILE"
  fi
fi

# run sql migrations in order
if [ -d "$BACKEND_DIR/migrations" ] && [ -f "$ENV_FILE" ]; then
  echo "==> Running database migrations..."
  set -a
  # shellcheck disable=SC1090
  source "$ENV_FILE"
  set +a
  for migration in $(ls "$BACKEND_DIR"/migrations/*.sql 2>/dev/null | sort); do
    echo "    Applying $(basename "$migration")..."
    PGPASSWORD="$DB_PASSWORD" psql -h "${DB_HOST:-localhost}" -U "${DB_USER:-bmi_user}" -d "${DB_NAME:-bmidb}" -f "$migration" 2>&1 || true
  done
fi

# npm install + pm2
echo "==> Installing backend dependencies..."
cd "$BACKEND_DIR"
npm install --production

sudo mkdir -p "$BACKEND_DIR/logs"
sudo chown -R ubuntu:ubuntu "$BACKEND_DIR"

echo "==> Starting backend with PM2..."
if pm2 describe bmi-backend > /dev/null 2>&1; then
  pm2 restart bmi-backend
else
  pm2 start ecosystem.config.js || pm2 start src/server.js --name bmi-backend --env production
fi
pm2 save

# frontend
if [ -f "$DEPLOY_DIR/frontend.tar.gz" ]; then
  echo "==> Extracting frontend..."
  sudo rm -rf "${FRONTEND_DIR:?}"/*
  sudo tar -xzf "$DEPLOY_DIR/frontend.tar.gz" -C "$FRONTEND_DIR"
  sudo chown -R www-data:www-data "$FRONTEND_DIR"
  sudo chmod -R 755 "$FRONTEND_DIR"
fi

# nginx — single server, proxy /api to localhost:3000
echo "==> Configuring Nginx..."
sudo tee /etc/nginx/sites-available/bmi-health-tracker > /dev/null <<'NGINX'
server {
    listen 80;
    server_name _;

    root /var/www/bmi-health-tracker;
    index index.html;

    location / {
        try_files $uri $uri/ /index.html;
    }

    location /api/ {
        proxy_pass http://127.0.0.1:3000;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_cache_bypass $http_upgrade;
    }

    add_header X-Frame-Options "SAMEORIGIN";
    add_header X-Content-Type-Options "nosniff";
    add_header X-XSS-Protection "1; mode=block";
}
NGINX

sudo ln -sf /etc/nginx/sites-available/bmi-health-tracker /etc/nginx/sites-enabled/bmi-health-tracker
sudo rm -f /etc/nginx/sites-enabled/default
sudo nginx -t
sudo systemctl reload nginx

echo "==> Application deploy complete."
