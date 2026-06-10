data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"]

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

resource "aws_vpc" "main" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name = "${var.project_name}-vpc"
  }
}

resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "${var.project_name}-igw"
  }
}

resource "aws_subnet" "public" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = "${var.aws_region}a"
  map_public_ip_on_launch = true

  tags = {
    Name = "${var.project_name}-public-subnet"
  }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }

  tags = {
    Name = "${var.project_name}-public-rt"
  }
}

resource "aws_route_table_association" "public" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.public.id
}

resource "aws_security_group" "app_monitoring" {
  name        = "${var.project_name}-app-monitoring-sg"
  description = "Security group for single EC2 app and monitoring stack"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.allowed_ssh_cidr]
  }

  ingress {
    description = "HTTP"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "HTTPS"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "Grafana"
    from_port   = 3001
    to_port     = 3001
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "Prometheus"
    from_port   = 9090
    to_port     = 9090
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "Loki"
    from_port   = 3100
    to_port     = 3100
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.project_name}-app-monitoring-sg"
  }
}

resource "aws_eip" "app" {
  domain = "vpc"

  tags = {
    Name = "${var.project_name}-eip"
  }
}

resource "aws_instance" "app_server" {
  ami                         = data.aws_ami.ubuntu.id
  instance_type               = var.instance_type
  subnet_id                   = aws_subnet.public.id
  vpc_security_group_ids      = [aws_security_group.app_monitoring.id]
  key_name                    = var.key_pair_name
  associate_public_ip_address = true

  user_data = templatefile("${path.module}/scripts/single_server_bootstrap.sh", {
    db_name               = var.db_name
    db_user               = var.db_user
    db_password           = var.db_password
    grafana_admin_password = var.grafana_admin_password
  })

  root_block_device {
    volume_size = 30
    volume_type = "gp3"
  }

  tags = {
    Name = "${var.project_name}-app-server"
  }
}

resource "aws_eip_association" "app" {
  instance_id   = aws_instance.app_server.id
  allocation_id = aws_eip.app.id
}

output "ec2_public_ip" {
  description = "Public IP of the application server"
  value       = aws_eip.app.public_ip
}

output "ec2_private_ip" {
  description = "Private IP of the application server"
  value       = aws_instance.app_server.private_ip
}

output "app_url" {
  description = "URL of the BMI Health Tracker application"
  value       = "http://${aws_eip.app.public_ip}"
}

output "grafana_url" {
  description = "URL of the Grafana dashboard"
  value       = "http://${aws_eip.app.public_ip}:3001"
}

output "prometheus_url" {
  description = "URL of the Prometheus UI"
  value       = "http://${aws_eip.app.public_ip}:9090"
}

output "loki_url" {
  description = "URL of the Loki API"
  value       = "http://${aws_eip.app.public_ip}:3100"
}

output "ssh_command" {
  description = "SSH command to connect to the server"
  value       = "ssh -i <your-key.pem> ubuntu@${aws_eip.app.public_ip}"
}
