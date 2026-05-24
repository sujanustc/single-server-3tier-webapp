#!/bin/bash
set -e

# Update packages
sudo apt-get update -y

# Install git, curl, wget, build-essential
sudo apt-get install -y git curl wget build-essential

# Install Node.js (v20 LTS) via NodeSource
curl -fsSL https://deb.nodesource.com/setup_20.x | sudo -E bash -
sudo apt-get install -y nodejs

# Install PM2 globally
sudo npm install -g pm2

# Create directory and set permissions
sudo mkdir -p /opt/bmi-app
sudo chown -R ubuntu:ubuntu /opt/bmi-app

# Clone repo to /opt/bmi-app
cd /opt
sudo rm -rf bmi-app  # ensure it's clean if directory already exists
git clone ${git_repo_url} bmi-app
sudo chown -R ubuntu:ubuntu /opt/bmi-app

# Configure environment variables
cd /opt/bmi-app/backend
cat > .env <<EOF
DATABASE_URL=postgresql://${db_user}:${db_password}@${db_host}:5432/${db_name}
DB_USER=${db_user}
DB_PASSWORD=${db_password}
DB_NAME=${db_name}
DB_HOST=${db_host}
DB_PORT=5432
PORT=3000
NODE_ENV=production
CORS_ORIGIN=*
EOF

chmod 600 .env

# Install backend dependencies
npm install --production

# Start backend using PM2
pm2 start src/server.js --name bmi-backend --env production
pm2 save

# Setup PM2 to run on startup
sudo env PATH=$PATH:$(which node) $(which pm2) startup systemd -u ubuntu --hp /home/ubuntu
pm2 save

# Install Node Exporter for Prometheus monitoring
cd /tmp
wget -q https://github.com/prometheus/node_exporter/releases/download/v1.7.0/node_exporter-1.7.0.linux-amd64.tar.gz
tar -xf node_exporter-1.7.0.linux-amd64.tar.gz
sudo mv node_exporter-1.7.0.linux-amd64/node_exporter /usr/local/bin/
sudo useradd --no-create-home --shell /bin/false node_exporter || true

# Setup Node Exporter Service
sudo tee /etc/systemd/system/node_exporter.service > /dev/null <<EOF
[Unit]
Description=Node Exporter
After=network.target

[Service]
User=node_exporter
Group=node_exporter
Type=simple
ExecStart=/usr/local/bin/node_exporter

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
sudo systemctl start node_exporter
sudo systemctl enable node_exporter
