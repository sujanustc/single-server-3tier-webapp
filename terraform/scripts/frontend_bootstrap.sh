#!/bin/bash
set -e

# Update packages
sudo apt-get update -y

# Install git, curl, wget, build-essential, nginx, apt-transport-https, software-properties-common
sudo apt-get install -y git curl wget build-essential nginx apt-transport-https software-properties-common

# Install Node.js (v20 LTS) via NodeSource
curl -fsSL https://deb.nodesource.com/setup_20.x | sudo -E bash -
sudo apt-get install -y nodejs

# Create directory and set permissions
sudo mkdir -p /opt/bmi-app
sudo chown -R ubuntu:ubuntu /opt/bmi-app

# Clone repo to /opt/bmi-app
cd /opt
sudo rm -rf bmi-app  # ensure it's clean if directory already exists
git clone ${git_repo_url} bmi-app
sudo chown -R ubuntu:ubuntu /opt/bmi-app

# Build React application
cd /opt/bmi-app/frontend
npm install
npm run build

# Deploy to Nginx root directory
sudo mkdir -p /var/www/bmi-health-tracker
sudo rm -rf /var/www/bmi-health-tracker/*
sudo cp -r dist/* /var/www/bmi-health-tracker/
sudo chown -R www-data:www-data /var/www/bmi-health-tracker
sudo chmod -R 755 /var/www/bmi-health-tracker

# Write Nginx configuration to point to Backend Private IP
sudo tee /etc/nginx/sites-available/bmi-health-tracker > /dev/null <<EOF
server {
    listen 80;
    server_name _;

    root /var/www/bmi-health-tracker;
    index index.html;

    # React SPA - serve index.html for all non-file routes
    location / {
        try_files \$uri \$uri/ /index.html;
    }

    # Proxy API requests to Backend Instance
    location /api/ {
        proxy_pass http://${backend_private_ip}:3000;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_cache_bypass \$http_upgrade;
    }

    # Security headers
    add_header X-Frame-Options "SAMEORIGIN";
    add_header X-Content-Type-Options "nosniff";
    add_header X-XSS-Protection "1; mode=block";
}
EOF

# Enable the website and remove the default site
sudo ln -sf /etc/nginx/sites-available/bmi-health-tracker /etc/nginx/sites-enabled/bmi-health-tracker
sudo rm -f /etc/nginx/sites-enabled/default
sudo nginx -t
sudo systemctl restart nginx
sudo systemctl enable nginx

# --- Monitoring Setup (Prometheus & Grafana) ---

# Install Node Exporter on Frontend
cd /tmp
wget -q https://github.com/prometheus/node_exporter/releases/download/v1.7.0/node_exporter-1.7.0.linux-amd64.tar.gz
tar -xf node_exporter-1.7.0.linux-amd64.tar.gz
sudo mv node_exporter-1.7.0.linux-amd64/node_exporter /usr/local/bin/
sudo useradd --no-create-home --shell /bin/false node_exporter || true

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

# Install Prometheus
cd /tmp
wget -q https://github.com/prometheus/prometheus/releases/download/v2.45.0/prometheus-2.45.0.linux-amd64.tar.gz
tar -xf prometheus-2.45.0.linux-amd64.tar.gz
sudo mv prometheus-2.45.0.linux-amd64/prometheus /usr/local/bin/
sudo mv prometheus-2.45.0.linux-amd64/promtool /usr/local/bin/
sudo mkdir -p /etc/prometheus /var/lib/prometheus
sudo mv prometheus-2.45.0.linux-amd64/consoles /etc/prometheus
sudo mv prometheus-2.45.0.linux-amd64/console_libraries /etc/prometheus
sudo useradd --no-create-home --shell /bin/false prometheus || true
sudo chown -R prometheus:prometheus /etc/prometheus /var/lib/prometheus

# Create Prometheus Config Scraping all Instances
sudo tee /etc/prometheus/prometheus.yml > /dev/null <<EOF
global:
  scrape_interval: 15s

scrape_configs:
  - job_name: 'prometheus'
    static_configs:
      - targets: ['localhost:9090']

  - job_name: 'frontend-node'
    static_configs:
      - targets: ['localhost:9100']

  - job_name: 'backend-node'
    static_configs:
      - targets: ['${backend_private_ip}:9100']

  - job_name: 'database-node'
    static_configs:
      - targets: ['${database_private_ip}:9100']
EOF

sudo chown prometheus:prometheus /etc/prometheus/prometheus.yml

# Setup Prometheus Service
sudo tee /etc/systemd/system/prometheus.service > /dev/null <<EOF
[Unit]
Description=Prometheus
Wants=network-online.target
After=network-online.target

[Service]
User=prometheus
Group=prometheus
Type=simple
ExecStart=/usr/local/bin/prometheus \\
    --config.file /etc/prometheus/prometheus.yml \\
    --storage.tsdb.path /var/lib/prometheus/ \\
    --web.console.templates=/etc/prometheus/consoles \\
    --web.console.libraries=/etc/prometheus/console_libraries

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
sudo systemctl start prometheus
sudo systemctl enable prometheus

# Install Grafana
sudo mkdir -p /etc/apt/keyrings/
wget -q -O - https://apt.grafana.com/gpg.key | gpg --dearmor | sudo tee /etc/apt/keyrings/grafana.gpg > /dev/null
echo "deb [signed-by=/etc/apt/keyrings/grafana.gpg] https://apt.grafana.com stable main" | sudo tee -a /etc/apt/sources.list.d/grafana.list
sudo apt-get update
sudo apt-get install -y grafana
sudo systemctl start grafana-server
sudo systemctl enable grafana-server
