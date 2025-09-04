variable "aws_region" {
  description = "AWS region for resources"
  type        = string
  default     = "us-east-1"
}

variable "project_name" {
  description = "Name of the project"
  type        = string
  default     = "jenkins-step3"
}

variable "environment" {
  description = "Environment name"
  type        = string
  default     = "dev"
}

variable "vpc_cidr" {
  description = "CIDR block for VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "public_subnet_cidr" {
  description = "CIDR block for public subnet"
  type        = string
  default     = "10.0.1.0/24"
}

variable "private_subnet_cidr" {
  description = "CIDR block for private subnet"
  type        = string
  default     = "10.0.2.0/24"
}

variable "jenkins_master_instance_type" {
  description = "Instance type for Jenkins master"
  type        = string
  default     = "t2.micro"  # Free tier eligible
}

variable "jenkins_worker_instance_type" {
  description = "Instance type for Jenkins worker"
  type        = string
  default     = "t2.micro"  # Free tier eligible
}

variable "spot_price" {
  description = "Maximum spot price for Jenkins worker"
  type        = string
  default     = "0.01"  # Very low price for cost optimization
}

variable "ssh_public_key" {
  description = "SSH public key for EC2 access"
  type        = string
  # Add your public key here or provide via terraform.tfvars
  # default     = "ssh-rsa AAAAB3NzaC1yc2E... your-email@domain.com"
}
