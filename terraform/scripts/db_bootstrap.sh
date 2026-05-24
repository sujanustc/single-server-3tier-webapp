#!/bin/bash
set -e

# Update packages
sudo apt-get update -y

# Install PostgreSQL, git, and wget
sudo apt-get install -y postgresql postgresql-contrib git wget

# Start and enable PostgreSQL
sudo systemctl start postgresql
sudo systemctl enable postgresql

# Create Database and User
DB_NAME="${db_name}"
DB_USER="${db_user}"
DB_PASSWORD="${db_password}"

sudo -u postgres psql -c "CREATE USER $DB_USER WITH PASSWORD '$DB_PASSWORD';"
sudo -u postgres psql -c "CREATE DATABASE $DB_NAME OWNER $DB_USER;"
sudo -u postgres psql -d "$DB_NAME" -c "GRANT ALL ON SCHEMA public TO $DB_USER;"
sudo -u postgres psql -d "$DB_NAME" -c "ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON TABLES TO $DB_USER;"

# Get installed PostgreSQL version dynamically
PG_VERSION=$(psql -V | awk '{print $3}' | cut -d. -f1)

# Allow remote connections in postgresql.conf
sudo sed -i "s/#listen_addresses = 'localhost'/listen_addresses = '*'/g" /etc/postgresql/$PG_VERSION/main/postgresql.conf

# Add rule in pg_hba.conf to accept connections from VPC CIDR
PG_HBA="/etc/postgresql/$PG_VERSION/main/pg_hba.conf"
sudo sed -i "/^# IPv4 local connections:/a host    all             all             10.0.0.0/16            md5" $PG_HBA

# Restart PostgreSQL to apply settings
sudo systemctl restart postgresql

# Clone repo to temp directory to apply migrations
cd /tmp
git clone ${git_repo_url} repo
cd repo/backend/migrations

# Apply SQL migrations
PGPASSWORD=$DB_PASSWORD psql -h localhost -U $DB_USER -d $DB_NAME -f 001_create_measurements.sql
PGPASSWORD=$DB_PASSWORD psql -h localhost -U $DB_USER -d $DB_NAME -f 002_add_measurement_date.sql

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
