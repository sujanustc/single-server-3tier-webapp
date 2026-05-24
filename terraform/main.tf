resource "aws_vpc" "sujan_main" {
    cidr_block           = "10.0.0.0/16"
    enable_dns_hostnames = true

    tags = {
        Name = "sujan_ostad-vpc"
    }
}

#++++++++++++internet Gateway+++++++++

resource "aws_internet_gateway" "sujan_igw" {
    vpc_id = aws_vpc.sujan_main.id

    tags = {
        Name = "sujan_ostad-igw"
    }
}

#++++++++++++Public Subnet +++++++++

resource "aws_subnet" "sujan_public_subnet_1" {
    vpc_id                  = aws_vpc.sujan_main.id
    cidr_block              = "10.0.1.0/24"
    map_public_ip_on_launch = true

    tags = {
        Name = "sujan_public_subnet_1"
    }
}

resource "aws_subnet" "sujan_private_subnet_1" {
    vpc_id                  = aws_vpc.sujan_main.id
    cidr_block              = "10.0.11.0/24"
    map_public_ip_on_launch = false

    tags = {
        Name = "sujan_private_subnet_1"
    }
}

resource "aws_eip" "sujan_nat_eip" {
    domain = "vpc"
}

resource "aws_nat_gateway" "sujan_nat" {
    allocation_id = aws_eip.sujan_nat_eip.id
    subnet_id     = aws_subnet.sujan_public_subnet_1.id

    tags = {
        Name = "sujan_ostad-nat"
    }
}

resource "aws_route_table" "sujan_public_rt" {
    vpc_id = aws_vpc.sujan_main.id

    route {
        cidr_block = "0.0.0.0/0"
        gateway_id = aws_internet_gateway.sujan_igw.id
    }
}

resource "aws_route_table" "sujan_private_rt" {
    vpc_id = aws_vpc.sujan_main.id

    route {
        cidr_block     = "0.0.0.0/0"
        nat_gateway_id = aws_nat_gateway.sujan_nat.id
    }
}

resource "aws_route_table_association" "sujan_public_assoc" {
    subnet_id      = aws_subnet.sujan_public_subnet_1.id
    route_table_id = aws_route_table.sujan_public_rt.id
}

resource "aws_route_table_association" "sujan_private_assoc" {
    subnet_id      = aws_subnet.sujan_private_subnet_1.id
    route_table_id = aws_route_table.sujan_private_rt.id
}

resource "aws_security_group" "sujan_bastion_ostad_sg" {
    name   = "sujan_bastion_ostad_sg"
    vpc_id = aws_vpc.sujan_main.id

    ingress {
        description = "ssh access"
        from_port   = 22
        to_port     = 22
        protocol    = "tcp"
        cidr_blocks = ["0.0.0.0/0"]
    }

    ingress {
        description = "http access"
        from_port   = 80
        to_port     = 80
        protocol    = "tcp"
        cidr_blocks = ["0.0.0.0/0"]
    }

    ingress {
        description = "https access"
        from_port   = 443
        to_port     = 443
        protocol    = "tcp"
        cidr_blocks = ["0.0.0.0/0"]
    }

    egress {
        from_port   = 0
        to_port     = 0
        protocol    = "-1"
        cidr_blocks = ["0.0.0.0/0"]
    }
}

resource "aws_security_group" "sujan_private_ostad_sg" {
    name   = "sujan_private_ostad_sg"
    vpc_id = aws_vpc.sujan_main.id

    ingress {
        description     = "ssh access"
        from_port       = 22
        to_port         = 22
        protocol        = "tcp"
        security_groups = [aws_security_group.sujan_bastion_ostad_sg.id]
    }

    ingress {
        description     = "api access"
        from_port       = 3000
        to_port         = 3000
        protocol        = "tcp"
        security_groups = [aws_security_group.sujan_bastion_ostad_sg.id]
    }

    egress {
        from_port   = 0
        to_port     = 0
        protocol    = "-1"
        cidr_blocks = ["0.0.0.0/0"]
    }
}

resource "aws_instance" "sujan_private_ostad" {
    ami                    = "ami-07a00cf47dbbc844c"
    instance_type          = "t2.small"
    subnet_id              = aws_subnet.sujan_private_subnet_1.id
    vpc_security_group_ids = [aws_security_group.sujan_private_ostad_sg.id]
    key_name               = var.key_pair_name

    user_data = templatefile("${path.module}/scripts/sujan_backend_bootstrap.sh", {
        db_name      = var.db_name
        db_user      = var.db_user
        db_password  = var.db_password
        git_repo_url = var.git_repo_url
    })

    tags = {
        Name = "sujan_private_ostad"
    }
}

resource "aws_instance" "sujan_bastion_ostad" {
    ami                    = "ami-07a00cf47dbbc844c"
    instance_type          = "t2.small"
    subnet_id              = aws_subnet.sujan_public_subnet_1.id
    vpc_security_group_ids = [aws_security_group.sujan_bastion_ostad_sg.id]
    key_name               = var.key_pair_name

    user_data = templatefile("${path.module}/scripts/sujan_frontend_bootstrap.sh", {
        backend_private_ip = aws_instance.sujan_private_ostad.private_ip
    })

    tags = {
        Name = "sujan_bastion_ostad"
    }

    depends_on = [aws_instance.sujan_private_ostad]
}

output "sujan_bastion_ostad_ip" {
    value = aws_instance.sujan_bastion_ostad.public_ip
}

output "sujan_private_ip" {
    value = aws_instance.sujan_private_ostad.private_ip
}