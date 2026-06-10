# BMI Health Tracker — DevOps Monitoring & Deployment Solution

Complete DevOps solution for the **BMI & Health Tracker** 3-tier web application with **Terraform** infrastructure provisioning, **GitHub Actions** CI/CD, and a full observability stack (**Grafana**, **Prometheus**, **Loki**, **Promtail**, **Node Exporter**) on a single AWS EC2 instance.

---

## Table of Contents

- [Architecture](#architecture)
- [Repository Structure](#repository-structure)
- [Prerequisites](#prerequisites)
- [Phase A: Terraform Infrastructure](#phase-a-terraform-infrastructure)
- [Phase B: GitHub Secrets](#phase-b-github-secrets)
- [Phase C: CI/CD Deployment](#phase-c-cicd-deployment)
- [Monitoring Access](#monitoring-access)
- [Grafana Dashboard](#grafana-dashboard)
- [Submission Checklist](#submission-checklist)
- [Troubleshooting](#troubleshooting)

---

## Architecture

All application and monitoring services run on **one EC2 instance** in a public subnet:

```
                     ┌──────────────────────────────┐
                     │         INTERNET             │
                     └──────────────┬───────────────┘
                                    │ HTTP :80 / Grafana :3001
                                    ▼
┌─────────────────────────────────────────────────────────────────────────┐
│                    AWS VPC (10.0.0.0/16)                                │
│  ┌───────────────────────────────────────────────────────────────────┐  │
│  │   PUBLIC SUBNET (10.0.1.0/24)                                     │  │
│  │                                                                   │  │
│  │   Single EC2 Instance (t2.medium)                                 │  │
│  │   ┌─────────────────────────────────────────────────────────────┐ │  │
│  │   │  Nginx :80          → React SPA + /api proxy                │ │  │
│  │   │  Express + PM2 :3000 → Backend API                          │ │  │
│  │   │  PostgreSQL :5432   → Database (localhost only)             │ │  │
│  │   │  Node Exporter :9100 → System metrics (localhost)           │ │  │
│  │   │  Prometheus :9090   → Metrics store                         │ │  │
│  │   │  Loki :3100         → Log aggregation                       │ │  │
│  │   │  Promtail           → Log shipper → Loki                    │ │  │
│  │   │  Grafana :3001      → Dashboards (CPU/Mem/Disk/Net + Logs)  │ │  │
│  │   └─────────────────────────────────────────────────────────────┘ │  │
│  └───────────────────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────────────────┘

GitHub Actions (push to main) ──SSH/SCP──► EC2 deploy scripts
```

**Data flow:**
- **Metrics:** Node Exporter → Prometheus → Grafana
- **Logs:** Syslog / Nginx / PM2 logs → Promtail → Loki → Grafana
- **App:** Browser → Nginx → Express API → PostgreSQL

---

## Repository Structure

| Path | Description |
|------|-------------|
| [terraform/](terraform/) | Terraform VPC, EC2, security groups, bootstrap |
| [.github/workflows/deploy.yml](.github/workflows/deploy.yml) | CI/CD pipeline |
| [monitoring/](monitoring/) | Prometheus, Loki, Promtail, Grafana configs + dashboard JSON |
| [scripts/](scripts/) | `deploy-app.sh`, `setup-monitoring.sh` |
| [backend/](backend/) | Express.js API |
| [frontend/](frontend/) | React + Vite SPA |
| [backend/migrations/](backend/migrations/) | PostgreSQL schema migrations |
| [docs/screenshots/](docs/screenshots/) | Submission screenshots |

---

## Prerequisites

- AWS account with permissions for EC2, VPC, EIP
- AWS SSH key pair created in target region
- GitHub repository with Actions enabled
- Terraform >= 1.5.0 installed locally
- Node.js 20 (for local development)

---

## Phase A: Terraform Infrastructure

1. Navigate to the terraform directory:

```bash
cd terraform
```

2. Copy and fill in variables:

```bash
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars with your values
```

Required variables in `terraform.tfvars`:

| Variable | Description |
|----------|-------------|
| `key_pair_name` | Existing AWS EC2 key pair name |
| `db_password` | PostgreSQL password |
| `grafana_admin_password` | Grafana admin password |
| `aws_access_key` | AWS access key |
| `aws_secret_key` | AWS secret key |

3. Provision infrastructure:

```bash
terraform init
terraform plan
terraform apply
```

4. Note the outputs:

| Output | Use |
|--------|-----|
| `ec2_public_ip` | GitHub secret `EC2_HOST`, app URL |
| `ec2_private_ip` | Reference only |
| `app_url` | BMI application |
| `grafana_url` | Grafana dashboard |
| `prometheus_url` | Prometheus UI |
| `loki_url` | Loki API |

**Security group ports (public):**

| Port | Service |
|------|---------|
| 22 | SSH |
| 80 | Nginx (app) |
| 443 | HTTPS (reserved) |
| 3001 | Grafana |
| 9090 | Prometheus |
| 3100 | Loki |

---

## Phase B: GitHub Secrets

Go to **Settings → Secrets and variables → Actions** and add:

| Secret | Value |
|--------|-------|
| `SSH_PRIVATE_KEY` | Full contents of your `.pem` key file |
| `EC2_HOST` | Terraform output `ec2_public_ip` |

---

## Phase C: CI/CD Deployment

Push to `main` or trigger manually via **Actions → Deploy 3-Tier Application with Monitoring → Run workflow**.

The pipeline will:

1. Build the React frontend
2. Package frontend, backend, monitoring configs, and deploy scripts
3. SCP artifacts to EC2 via SSH
4. Run `scripts/deploy-app.sh` (app, nginx, pm2, migrations)
5. Run `scripts/setup-monitoring.sh` (Prometheus, Loki, Promtail, Grafana, Node Exporter)
6. Run post-deploy health checks

Manual trigger:

```bash
git add .
git commit -m "deploy: update application and monitoring"
git push origin main
```

---

## Monitoring Access

After successful deployment:

| Service | URL | Credentials |
|---------|-----|-------------|
| Application | `http://<EC2_PUBLIC_IP>` | — |
| Grafana | `http://<EC2_PUBLIC_IP>:3001` | `admin` / your `grafana_admin_password` |
| Prometheus | `http://<EC2_PUBLIC_IP>:9090` | — |
| Loki | `http://<EC2_PUBLIC_IP>:3100` | — |

Grafana datasources (auto-provisioned):
- **Prometheus** → `http://localhost:9090`
- **Loki** → `http://localhost:3100`

---

## Grafana Dashboard

Dashboard JSON export: [monitoring/grafana/dashboards/system-monitoring.json](monitoring/grafana/dashboards/system-monitoring.json)

**Panels included:**

| Panel | Source |
|-------|--------|
| CPU Usage (%) | Node Exporter via Prometheus |
| Memory Usage (%) | Node Exporter via Prometheus |
| Disk Usage (%) | Node Exporter via Prometheus |
| Network Traffic (RX/TX) | Node Exporter via Prometheus |
| System Logs | Loki (syslog, nginx, pm2, auth) |

Dashboard is auto-loaded via Grafana provisioning on each deploy.

---

## Submission Checklist

Upload this repository to GitHub and capture screenshots for:

- [ ] **Terraform deployment** — `terraform apply` success output → save to `docs/screenshots/terraform_apply.png`
- [ ] **CI/CD pipeline** — green GitHub Actions run → `docs/screenshots/github_actions.png`
- [ ] **Grafana dashboard** — CPU, Memory, Disk, Network panels → `docs/screenshots/grafana_dashboard.png`
- [ ] **Loki logs** — log panel in Grafana showing system/nginx/pm2 logs → `docs/screenshots/loki_logs.png`

**Repository must include:**

- [x] Terraform configuration files (`terraform/`)
- [x] CI/CD pipeline (`.github/workflows/deploy.yml`)
- [x] Grafana dashboard JSON (`monitoring/grafana/dashboards/system-monitoring.json`)
- [x] Documentation (this README)

---

## Troubleshooting

### Check service status on EC2

```bash
ssh -i your-key.pem ubuntu@<EC2_PUBLIC_IP>
sudo systemctl status nginx postgresql node_exporter prometheus loki promtail grafana-server
pm2 status
```

### Health check commands

```bash
curl http://localhost:3000/health          # Backend
curl http://localhost:3001/api/health      # Grafana
curl http://localhost:9090/-/healthy       # Prometheus
curl http://localhost:3100/ready           # Loki
curl http://localhost/                      # Frontend via Nginx
```

### Common issues

| Problem | Fix |
|---------|-----|
| Grafana empty dashboard | Wait 2–3 min for Node Exporter metrics; check Prometheus targets at `:9090/targets` |
| No logs in Loki | Verify Promtail: `sudo systemctl status promtail`; check `/var/log/syslog` exists |
| Backend 502 | `pm2 restart bmi-backend`; check `.env` DATABASE_URL |
| CI/CD SSH fails | Verify `EC2_HOST` and `SSH_PRIVATE_KEY` secrets; check SG port 22 |
| Port 3000 conflict | Grafana runs on **3001**; backend stays on **3000** |

### Re-run monitoring setup manually

```bash
cd /tmp/bmi-deploy
DEPLOY_DIR=/tmp/bmi-deploy bash scripts/setup-monitoring.sh
```

---

## Local Development

```bash
# Backend
cd backend && npm install && npm run dev

# Frontend (separate terminal)
cd frontend && npm install && npm run dev
# Opens http://localhost:5173, proxies /api to :3000
```

---

**Last Updated:** June 2026
