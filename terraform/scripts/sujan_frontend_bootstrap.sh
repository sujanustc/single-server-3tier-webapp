#!/bin/bash
set -e

# Update package lists
sudo apt-get update -y

# Install Nginx and git
sudo apt-get install -y nginx git

# Create Nginx virtual host configuration to proxy to backend private IP
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

    # Proxy API requests to private backend server
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

# Create Nginx root directory
sudo mkdir -p /var/www/bmi-health-tracker
sudo chown -R www-data:www-data /var/www/bmi-health-tracker

# Enable the website and disable the default Nginx page
sudo ln -sf /etc/nginx/sites-available/bmi-health-tracker /etc/nginx/sites-enabled/bmi-health-tracker
sudo rm -f /etc/nginx/sites-enabled/default

# Restart Nginx to apply configuration
sudo systemctl restart nginx
sudo systemctl enable nginx
