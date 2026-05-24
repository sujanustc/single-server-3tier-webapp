variable "aws_region" {
  description = "AWS region to deploy resources"
  type        = string
  default     = "us-east-1"
}

variable "project_name" {
  description = "Name of the project"
  type        = string
  default     = "bmi-health-tracker"
}

variable "instance_type" {
  description = "EC2 instance type"
  type        = string
  default     = "t2.micro"
}

variable "key_name" {
  description = "Name of the SSH key pair to access the EC2 instance"
  type        = string
}


variable "key_pair_name" {
  description = "Name of the SSH key pair to access the EC2 instance"
  type        = string
}

variable "db_password" {
  description = "Password for the PostgreSQL database"
  type        = string
  sensitive   = true
}

variable "db_name" {
  description = "Name of the PostgreSQL database"
  type        = string
  default     = "bmidb"
}

variable "db_user" {
  description = "Username for the PostgreSQL database"
  type        = string
  default     = "bmi_user"
}

variable "git_repo_url" {
  description = "Git repository URL for cloning the application"
  type        = string
  default     = "https://github.com/sujanustc/single-server-3tier-webapp.git"
}


variable "aws_access_key" {
  description = "AWS Access Key ID"
  type        = string
  sensitive   = true
}

variable "aws_secret_key" {
  description = "AWS Secret Access Key"
  type        = string
  sensitive   = true
}
