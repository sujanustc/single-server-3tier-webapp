#!/bin/bash
# setup monitoring — node_exporter, prometheus, loki, promtail, grafana (idempotent)
set -euo pipefail

DEPLOY_DIR="${DEPLOY_DIR:-/tmp/bmi-deploy}"
MONITORING_SRC="${DEPLOY_DIR}/monitoring"
NODE_EXPORTER_VERSION="1.7.0"
PROMETHEUS_VERSION="2.45.0"
LOKI_VERSION="2.9.4"
PROMTAIL_VERSION="2.9.4"

echo "==> Setting up monitoring stack..."

install_node_exporter() {
  if [ -x /usr/local/bin/node_exporter ]; then
    echo "    Node Exporter already installed"
    return
  fi
  cd /tmp
  wget -q "https://github.com/prometheus/node_exporter/releases/download/v${NODE_EXPORTER_VERSION}/node_exporter-${NODE_EXPORTER_VERSION}.linux-amd64.tar.gz"
  tar -xf "node_exporter-${NODE_EXPORTER_VERSION}.linux-amd64.tar.gz"
  sudo mv "node_exporter-${NODE_EXPORTER_VERSION}.linux-amd64/node_exporter" /usr/local/bin/
  sudo useradd --no-create-home --shell /bin/false node_exporter 2>/dev/null || true
  sudo tee /etc/systemd/system/node_exporter.service > /dev/null <<'EOF'
[Unit]
Description=Node Exporter
After=network.target

[Service]
User=node_exporter
Group=node_exporter
Type=simple
ExecStart=/usr/local/bin/node_exporter --web.listen-address=127.0.0.1:9100

[Install]
WantedBy=multi-user.target
EOF
}

install_prometheus() {
  if [ -x /usr/local/bin/prometheus ]; then
    echo "    Prometheus already installed"
    return
  fi
  cd /tmp
  wget -q "https://github.com/prometheus/prometheus/releases/download/v${PROMETHEUS_VERSION}/prometheus-${PROMETHEUS_VERSION}.linux-amd64.tar.gz"
  tar -xf "prometheus-${PROMETHEUS_VERSION}.linux-amd64.tar.gz"
  sudo mv "prometheus-${PROMETHEUS_VERSION}.linux-amd64/prometheus" /usr/local/bin/
  sudo mv "prometheus-${PROMETHEUS_VERSION}.linux-amd64/promtool" /usr/local/bin/
  sudo mkdir -p /etc/prometheus /var/lib/prometheus
  sudo mv "prometheus-${PROMETHEUS_VERSION}.linux-amd64/consoles" /etc/prometheus/
  sudo mv "prometheus-${PROMETHEUS_VERSION}.linux-amd64/console_libraries" /etc/prometheus/
  sudo useradd --no-create-home --shell /bin/false prometheus 2>/dev/null || true
  sudo chown -R prometheus:prometheus /etc/prometheus /var/lib/prometheus
  sudo tee /etc/systemd/system/prometheus.service > /dev/null <<'EOF'
[Unit]
Description=Prometheus
Wants=network-online.target
After=network-online.target

[Service]
User=prometheus
Group=prometheus
Type=simple
ExecStart=/usr/local/bin/prometheus \
    --config.file=/etc/prometheus/prometheus.yml \
    --storage.tsdb.path=/var/lib/prometheus/ \
    --web.console.templates=/etc/prometheus/consoles \
    --web.console.libraries=/etc/prometheus/console_libraries \
    --web.listen-address=0.0.0.0:9090

[Install]
WantedBy=multi-user.target
EOF
}

install_loki() {
  if [ -x /usr/local/bin/loki ]; then
    echo "    Loki already installed"
    return
  fi
  cd /tmp
  wget -q "https://github.com/grafana/loki/releases/download/v${LOKI_VERSION}/loki-linux-amd64.zip"
  sudo apt-get install -y unzip 2>/dev/null || true
  unzip -o "loki-linux-amd64.zip"
  sudo mv loki-linux-amd64 /usr/local/bin/loki
  sudo chmod +x /usr/local/bin/loki
  sudo useradd --no-create-home --shell /bin/false loki 2>/dev/null || true
  sudo mkdir -p /etc/loki /tmp/loki/chunks /tmp/loki/rules /tmp/loki/boltdb-shipper-active /tmp/loki/boltdb-shipper-cache
  sudo chown -R loki:loki /tmp/loki
  sudo tee /etc/systemd/system/loki.service > /dev/null <<'EOF'
[Unit]
Description=Loki
After=network.target

[Service]
User=loki
Group=loki
Type=simple
ExecStart=/usr/local/bin/loki -config.file=/etc/loki/loki-config.yml

[Install]
WantedBy=multi-user.target
EOF
}

install_promtail() {
  if [ -x /usr/local/bin/promtail ]; then
    echo "    Promtail already installed"
    return
  fi
  cd /tmp
  wget -q "https://github.com/grafana/loki/releases/download/v${PROMTAIL_VERSION}/promtail-linux-amd64.zip"
  unzip -o "promtail-linux-amd64.zip"
  sudo mv promtail-linux-amd64 /usr/local/bin/promtail
  sudo chmod +x /usr/local/bin/promtail
  sudo useradd --no-create-home --shell /bin/false promtail 2>/dev/null || true
  sudo mkdir -p /etc/promtail
  sudo tee /etc/systemd/system/promtail.service > /dev/null <<'EOF'
[Unit]
Description=Promtail
After=network.target loki.service

[Service]
User=root
Group=root
Type=simple
ExecStart=/usr/local/bin/promtail -config.file=/etc/promtail/promtail-config.yml

[Install]
WantedBy=multi-user.target
EOF
}

install_grafana() {
  if systemctl list-unit-files | grep -q grafana-server; then
    echo "    Grafana already installed"
    return
  fi
  sudo mkdir -p /etc/apt/keyrings/
  wget -q -O - https://apt.grafana.com/gpg.key | gpg --dearmor | sudo tee /etc/apt/keyrings/grafana.gpg > /dev/null
  echo "deb [signed-by=/etc/apt/keyrings/grafana.gpg] https://apt.grafana.com stable main" | sudo tee /etc/apt/sources.list.d/grafana.list
  sudo apt-get update -y
  sudo apt-get install -y grafana
}

# install binaries if missing
install_node_exporter
install_prometheus
install_loki
install_promtail
install_grafana

# copy configs from repo artifact
if [ -d "$MONITORING_SRC" ]; then
  echo "==> Deploying monitoring configs..."
  sudo cp "$MONITORING_SRC/prometheus/prometheus.yml" /etc/prometheus/prometheus.yml
  sudo chown prometheus:prometheus /etc/prometheus/prometheus.yml

  sudo cp "$MONITORING_SRC/loki/loki-config.yml" /etc/loki/loki-config.yml
  sudo chown loki:loki /etc/loki/loki-config.yml

  sudo cp "$MONITORING_SRC/promtail/promtail-config.yml" /etc/promtail/promtail-config.yml

  sudo mkdir -p /etc/grafana/provisioning/datasources /etc/grafana/provisioning/dashboards /etc/grafana/dashboards
  sudo cp "$MONITORING_SRC/grafana/provisioning/datasources/datasources.yml" /etc/grafana/provisioning/datasources/
  sudo cp "$MONITORING_SRC/grafana/provisioning/dashboards/dashboards.yml" /etc/grafana/provisioning/dashboards/
  sudo cp "$MONITORING_SRC/grafana/dashboards/system-monitoring.json" /etc/grafana/dashboards/
  sudo chown -R grafana:grafana /etc/grafana/provisioning /etc/grafana/dashboards
fi

# grafana on 3001 — avoid backend port clash
sudo mkdir -p /etc/grafana
if ! grep -q "^http_port = 3001" /etc/grafana/grafana.ini 2>/dev/null; then
  sudo sed -i 's/^;http_port = 3000/http_port = 3001/' /etc/grafana/grafana.ini 2>/dev/null || \
    echo -e "\n[server]\nhttp_port = 3001" | sudo tee -a /etc/grafana/grafana.ini > /dev/null
fi

# set admin password from bootstrap file if present
if [ -f /etc/bmi/grafana_admin_password ]; then
  GRAFANA_PASS=$(sudo cat /etc/bmi/grafana_admin_password)
  sudo grafana-cli admin reset-admin-password "$GRAFANA_PASS" 2>/dev/null || true
fi

# ensure log dirs exist for promtail
sudo mkdir -p /opt/bmi-app/backend/logs
sudo touch /var/log/nginx/access.log /var/log/nginx/error.log 2>/dev/null || true

echo "==> Restarting monitoring services..."
sudo systemctl daemon-reload
for svc in node_exporter prometheus loki promtail grafana-server; do
  sudo systemctl enable "$svc" 2>/dev/null || true
  sudo systemctl restart "$svc"
done

echo "==> Monitoring setup complete."
