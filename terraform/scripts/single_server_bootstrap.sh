#!/bin/bash
# first boot — os, postgres, node, pm2, monitoring binaries (app deploy via cicd)
set -euo pipefail

DB_NAME="${db_name}"
DB_USER="${db_user}"
DB_PASSWORD="${db_password}"
GRAFANA_ADMIN_PASSWORD="${grafana_admin_password}"

export DEBIAN_FRONTEND=noninteractive

echo "==> Bootstrap: updating packages..."
apt-get update -y
apt-get install -y git curl wget nginx postgresql postgresql-contrib build-essential unzip gpg

# postgres user + database
sudo -u postgres psql -tc "SELECT 1 FROM pg_roles WHERE rolname='${DB_USER}'" | grep -q 1 || \
  sudo -u postgres psql -c "CREATE USER ${DB_USER} WITH PASSWORD '${DB_PASSWORD}';"
sudo -u postgres psql -tc "SELECT 1 FROM pg_database WHERE datname='${DB_NAME}'" | grep -q 1 || \
  sudo -u postgres psql -c "CREATE DATABASE ${DB_NAME} OWNER ${DB_USER};"
sudo -u postgres psql -d "$DB_NAME" -c "GRANT ALL ON SCHEMA public TO ${DB_USER};"
sudo -u postgres psql -d "$DB_NAME" -c "ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON TABLES TO ${DB_USER};"

PG_VERSION=$(psql -V | awk '{print $3}' | cut -d. -f1)
PG_HBA="/etc/postgresql/${PG_VERSION}/main/pg_hba.conf"
grep -q "127.0.0.1/32" "$PG_HBA" || \
  sed -i "/^# IPv4 local connections:/a host    all             all             127.0.0.1/32            md5" "$PG_HBA"
systemctl restart postgresql
systemctl enable postgresql

# node 20 + pm2
curl -fsSL https://deb.nodesource.com/setup_20.x | bash -
apt-get install -y nodejs
npm install -g pm2

# app dirs
mkdir -p /opt/bmi-app/backend /opt/bmi-app/backend/logs /var/www/bmi-health-tracker
chown -R ubuntu:ubuntu /opt/bmi-app

# backend .env for cicd (preserve credentials)
cat > /opt/bmi-app/backend/.env <<EOF
PORT=3000
DATABASE_URL=postgresql://${DB_USER}:${DB_PASSWORD}@localhost:5432/${DB_NAME}
DB_USER=${DB_USER}
DB_PASSWORD=${DB_PASSWORD}
DB_NAME=${DB_NAME}
DB_HOST=localhost
DB_PORT=5432
NODE_ENV=production
FRONTEND_URL=http://localhost
EOF
chmod 600 /opt/bmi-app/backend/.env
chown ubuntu:ubuntu /opt/bmi-app/backend/.env

# grafana admin password store for setup-monitoring.sh
mkdir -p /etc/bmi
echo "${GRAFANA_ADMIN_PASSWORD}" > /etc/bmi/grafana_admin_password
chmod 600 /etc/bmi/grafana_admin_password

# monitoring dirs
mkdir -p /etc/prometheus /var/lib/prometheus /etc/loki /etc/promtail /tmp/loki/chunks /tmp/loki/rules /tmp/loki/boltdb-shipper-active /tmp/loki/boltdb-shipper-cache
useradd --no-create-home --shell /bin/false prometheus 2>/dev/null || true
useradd --no-create-home --shell /bin/false loki 2>/dev/null || true
useradd --no-create-home --shell /bin/false node_exporter 2>/dev/null || true
chown -R prometheus:prometheus /etc/prometheus /var/lib/prometheus
chown -R loki:loki /tmp/loki

# pm2 startup for ubuntu
sudo -u ubuntu env PATH="$PATH" pm2 startup systemd -u ubuntu --hp /home/ubuntu || true

echo "==> Bootstrap complete. Waiting for CI/CD deploy."
