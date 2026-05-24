#!/bin/bash
set -e

# Update package lists
sudo apt-get update -y

# Install PostgreSQL, git, curl, build-essential
sudo apt-get install -y postgresql postgresql-contrib git curl build-essential

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

# Get PostgreSQL version dynamically
PG_VERSION=$(psql -V | awk '{print $3}' | cut -d. -f1)

# Configure PostgreSQL to accept connections locally
PG_HBA="/etc/postgresql/$PG_VERSION/main/pg_hba.conf"
sudo sed -i "/^# IPv4 local connections:/a host    all             all             127.0.0.1/32            md5" $PG_HBA

# Restart PostgreSQL to apply settings
sudo systemctl restart postgresql

# Clone repo to /tmp to apply migrations
cd /tmp
rm -rf repo
git clone ${git_repo_url} repo
cd repo/backend/migrations

# Apply migrations
PGPASSWORD=$DB_PASSWORD psql -h localhost -U $DB_USER -d $DB_NAME -f 001_create_measurements.sql
PGPASSWORD=$DB_PASSWORD psql -h localhost -U $DB_USER -d $DB_NAME -f 002_add_measurement_date.sql

# Install Node.js (v20 LTS) via NodeSource
curl -fsSL https://deb.nodesource.com/setup_20.x | sudo -E bash -
sudo apt-get install -y nodejs

# Install PM2 globally
sudo npm install -g pm2

# Create directory and set permissions
sudo mkdir -p /opt/bmi-app
sudo chown -R ubuntu:ubuntu /opt/bmi-app

# Copy application source (clone to permanent folder)
cd /opt
sudo rm -rf bmi-app
git clone ${git_repo_url} bmi-app
sudo chown -R ubuntu:ubuntu /opt/bmi-app

# Configure backend environment variables (connecting to local database)
cd /opt/bmi-app/backend
cat > .env <<EOF
DATABASE_URL=postgresql://${db_user}:${db_password}@localhost:5432/${db_name}
DB_USER=${db_user}
DB_PASSWORD=${db_password}
DB_NAME=${db_name}
DB_HOST=localhost
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
