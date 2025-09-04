
terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.1"
    }
  }
  required_version = ">= 1.0"
  
  # Backend configuration - update with your bucket name after S3 backend creation
  backend "s3" {
     bucket         = "jenkins-step3-terraform-state-53ce5f8b"  
     key            = "jenkins-infrastructure/terraform.tfstate"
     region         = "us-east-1"
     dynamodb_table = "jenkins-step3-terraform-state-lock"  
     encrypt        = true
  }
}


provider "aws" {
  region = var.aws_region
}


data "aws_availability_zones" "available" {
  state = "available"
}


data "aws_ami" "amazon_linux" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["amzn2-ami-hvm-*-x86_64-gp2"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}


resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name        = "${var.project_name}-vpc"
    Environment = var.environment
  }
}


resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name        = "${var.project_name}-igw"
    Environment = var.environment
  }
}

# Create public subnet for Jenkins master
resource "aws_subnet" "public" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = var.public_subnet_cidr
  availability_zone       = data.aws_availability_zones.available.names[0]
  map_public_ip_on_launch = true

  tags = {
    Name        = "${var.project_name}-public-subnet"
    Environment = var.environment
    Type        = "Public"
  }
}

# Create private subnet for Jenkins worker
resource "aws_subnet" "private" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = var.private_subnet_cidr
  availability_zone = data.aws_availability_zones.available.names[0]

  tags = {
    Name        = "${var.project_name}-private-subnet"
    Environment = var.environment
    Type        = "Private"
  }
}

# Create Elastic IP for NAT Gateway
resource "aws_eip" "nat" {
  domain = "vpc"

  tags = {
    Name        = "${var.project_name}-nat-eip"
    Environment = var.environment
  }

  depends_on = [aws_internet_gateway.main]
}

# Create NAT Gateway
resource "aws_nat_gateway" "main" {
  allocation_id = aws_eip.nat.id
  subnet_id     = aws_subnet.public.id

  tags = {
    Name        = "${var.project_name}-nat-gateway"
    Environment = var.environment
  }

  depends_on = [aws_internet_gateway.main]
}

# Create route table for public subnet
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }

  tags = {
    Name        = "${var.project_name}-public-rt"
    Environment = var.environment
  }
}

# Create route table for private subnet
resource "aws_route_table" "private" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.main.id
  }

  tags = {
    Name        = "${var.project_name}-private-rt"
    Environment = var.environment
  }
}

# Associate public subnet with public route table
resource "aws_route_table_association" "public" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.public.id
}

# Associate private subnet with private route table
resource "aws_route_table_association" "private" {
  subnet_id      = aws_subnet.private.id
  route_table_id = aws_route_table.private.id
}

# Security group for Jenkins master (public subnet)
resource "aws_security_group" "jenkins_master" {
  name_prefix = "${var.project_name}-jenkins-master-"
  vpc_id      = aws_vpc.main.id

  # SSH access
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "SSH access"
  }

  # HTTP access for Nginx
  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "HTTP access"
  }

  # HTTPS access for Nginx
  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "HTTPS access"
  }

  # Jenkins port (for direct access if needed)
  ingress {
    from_port   = 8080
    to_port     = 8080
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
    description = "Jenkins web interface"
  }

  # Jenkins agent port
  ingress {
    from_port   = 50000
    to_port     = 50000
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
    description = "Jenkins agent communication"
  }

  # All outbound traffic
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name        = "${var.project_name}-jenkins-master-sg"
    Environment = var.environment
  }
}

# Security group for Jenkins worker (private subnet)
resource "aws_security_group" "jenkins_worker" {
  name_prefix = "${var.project_name}-jenkins-worker-"
  vpc_id      = aws_vpc.main.id

  # SSH access from public subnet
  ingress {
    from_port       = 22
    to_port         = 22
    protocol        = "tcp"
    security_groups = [aws_security_group.jenkins_master.id]
    description     = "SSH access from Jenkins master"
  }

  # Jenkins agent communication
  ingress {
    from_port       = 0
    to_port         = 65535
    protocol        = "tcp"
    security_groups = [aws_security_group.jenkins_master.id]
    description     = "Jenkins agent communication"
  }

  # All outbound traffic
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name        = "${var.project_name}-jenkins-worker-sg"
    Environment = var.environment
  }
}

# Key pair for EC2 instances
resource "aws_key_pair" "main" {
  key_name   = "${var.project_name}-keypair"
  public_key = var.ssh_public_key

  tags = {
    Name        = "${var.project_name}-keypair"
    Environment = var.environment
  }
}

# User data script for Jenkins master
locals {
  jenkins_master_user_data = <<-EOF
    #!/bin/bash
    yum update -y
    yum install -y git python3 python3-pip
    
    # Install Ansible
    pip3 install ansible
    
    # Create ansible user
    useradd -m ansible
    echo "ansible ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers
    
    # Setup SSH key for ansible user
    mkdir -p /home/ansible/.ssh
    echo "${var.ssh_public_key}" >> /home/ansible/.ssh/authorized_keys
    chown -R ansible:ansible /home/ansible/.ssh
    chmod 700 /home/ansible/.ssh
    chmod 600 /home/ansible/.ssh/authorized_keys
    
    # Install Docker (for potential use in Jenkins pipelines)
    amazon-linux-extras install docker -y
    systemctl start docker
    systemctl enable docker
    usermod -a -G docker ec2-user
    
    # Install Java 11 (required for Jenkins)
    yum install -y java-11-openjdk java-11-openjdk-devel
    
    echo "Jenkins master initialization complete" > /var/log/user-data.log
  EOF

  jenkins_worker_user_data = <<-EOF
    #!/bin/bash
    yum update -y
    yum install -y git python3 python3-pip
    
    # Install Java 11 (required for Jenkins agent)
    yum install -y java-11-openjdk java-11-openjdk-devel
    
    # Install Docker
    amazon-linux-extras install docker -y
    systemctl start docker
    systemctl enable docker
    usermod -a -G docker ec2-user
    
    # Create jenkins user
    useradd -m jenkins
    usermod -a -G docker jenkins
    
    # Setup SSH key for ec2-user and jenkins user
    mkdir -p /home/jenkins/.ssh
    echo "${var.ssh_public_key}" >> /home/jenkins/.ssh/authorized_keys
    chown -R jenkins:jenkins /home/jenkins/.ssh
    chmod 700 /home/jenkins/.ssh
    chmod 600 /home/jenkins/.ssh/authorized_keys
    
    echo "Jenkins worker initialization complete" > /var/log/user-data.log
  EOF
}

# Jenkins Master EC2 instance (on-demand)
resource "aws_instance" "jenkins_master" {
  ami                    = data.aws_ami.amazon_linux.id
  instance_type          = var.jenkins_master_instance_type
  key_name               = aws_key_pair.main.key_name
  subnet_id              = aws_subnet.public.id
  vpc_security_group_ids = [aws_security_group.jenkins_master.id]
  
  user_data = base64encode(local.jenkins_master_user_data)

  root_block_device {
    volume_type = "gp3"
    volume_size = 8
    encrypted   = true
    tags = {
      Name = "${var.project_name}-jenkins-master-root"
    }
  }

  tags = {
    Name        = "${var.project_name}-jenkins-master"
    Environment = var.environment
    Type        = "Jenkins-Master"
  }
}

# Launch template removed - using direct spot instance configuration

# Jenkins Worker EC2 spot instance
resource "aws_spot_instance_request" "jenkins_worker" {
  spot_price                      = var.spot_price
  wait_for_fulfillment           = true
  spot_type                      = "one-time"
  instance_interruption_behavior = "terminate"
  
  # Direct instance configuration (instead of launch template)
  ami           = data.aws_ami.amazon_linux.id
  instance_type = var.jenkins_worker_instance_type
  key_name      = aws_key_pair.main.key_name
  subnet_id     = aws_subnet.private.id
  vpc_security_group_ids = [aws_security_group.jenkins_worker.id]
  
  user_data = base64encode(local.jenkins_worker_user_data)

  root_block_device {
    volume_type = "gp3"
    volume_size = 8
    encrypted   = true
  }

  tags = {
    Name        = "${var.project_name}-jenkins-worker-spot"
    Environment = var.environment
    Type        = "Jenkins-Worker"
  }
}
