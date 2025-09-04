#!/bin/bash

# AWS Infrastructure Deployment Script for Step 3 Project
# This script automates the deployment of Jenkins infrastructure

set -e  # Exit on any error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print colored output
print_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Function to check if required tools are installed
check_prerequisites() {
    print_info "Checking prerequisites..."
    
    local missing_tools=()
    
    if ! command -v terraform &> /dev/null; then
        missing_tools+=("terraform")
    fi
    
    if ! command -v aws &> /dev/null; then
        missing_tools+=("aws-cli")
    fi
    
    if ! command -v ansible &> /dev/null; then
        missing_tools+=("ansible")
    fi
    
    if ! command -v ssh-keygen &> /dev/null; then
        missing_tools+=("ssh-keygen")
    fi
    
    if [ ${#missing_tools[@]} -ne 0 ]; then
        print_error "Missing required tools: ${missing_tools[*]}"
        print_info "Please install the missing tools and try again."
        exit 1
    fi
    
    print_success "All prerequisites are installed"
}

# Function to generate SSH key if it doesn't exist
generate_ssh_key() {
    local key_path="$HOME/.ssh/jenkins-step3-key"
    
    if [ ! -f "$key_path" ]; then
        print_info "Generating SSH key pair..."
        ssh-keygen -t rsa -b 4096 -f "$key_path" -N "" -C "jenkins-step3-$(date +%Y%m%d)"
        print_success "SSH key pair generated: $key_path"
    else
        print_info "SSH key already exists: $key_path"
    fi
    
    echo "$key_path"
}

# Function to check AWS credentials
check_aws_credentials() {
    print_info "Checking AWS credentials..."
    
    if ! aws sts get-caller-identity &> /dev/null; then
        print_error "AWS credentials not configured properly"
        print_info "Please configure AWS credentials using 'aws configure' or environment variables"
        exit 1
    fi
    
    local identity=$(aws sts get-caller-identity --output text --query 'Account')
    print_success "AWS credentials configured (Account: $identity)"
}

# Function to deploy S3 backend
deploy_s3_backend() {
    print_info "Deploying S3 backend for Terraform state..."
    
    cd s3-backend
    
    terraform init
    terraform plan -out=tfplan
    terraform apply tfplan
    
    # Get outputs
    local bucket_name=$(terraform output -raw s3_bucket_name)
    local table_name=$(terraform output -raw dynamodb_table_name)
    
    print_success "S3 backend deployed successfully"
    print_info "Bucket: $bucket_name"
    print_info "DynamoDB Table: $table_name"
    
    cd ..
    
    # Update backend configuration in main infrastructure
    print_info "Updating backend configuration in infrastructure..."
    
    sed -i.bak "s|# bucket.*|bucket         = \"$bucket_name\"|g" infrastructure/main.tf
    sed -i.bak "s|# key.*|key            = \"jenkins-infrastructure/terraform.tfstate\"|g" infrastructure/main.tf
    sed -i.bak "s|# region.*|region         = \"us-east-1\"|g" infrastructure/main.tf
    sed -i.bak "s|# dynamodb_table.*|dynamodb_table = \"$table_name\"|g" infrastructure/main.tf
    sed -i.bak "s|# encrypt.*|encrypt        = true|g" infrastructure/main.tf
    
    print_success "Backend configuration updated"
}

# Function to create terraform.tfvars
create_terraform_vars() {
    local ssh_key_path="$1"
    local public_key=$(cat "${ssh_key_path}.pub")
    
    print_info "Creating terraform.tfvars file..."
    
    cd infrastructure
    
    cat > terraform.tfvars << EOF
aws_region    = "us-east-1"
project_name  = "jenkins-step3"
environment   = "dev"

# Network configuration
vpc_cidr            = "10.0.0.0/16"
public_subnet_cidr  = "10.0.1.0/24"
private_subnet_cidr = "10.0.2.0/24"

# Instance configuration (Free tier eligible)
jenkins_master_instance_type = "t2.micro"
jenkins_worker_instance_type = "t2.micro"
spot_price                   = "0.01"

# SSH Key
ssh_public_key = "${public_key}"
EOF
    
    cd ..
    print_success "terraform.tfvars created"
}

# Function to deploy infrastructure
deploy_infrastructure() {
    print_info "Deploying main infrastructure..."
    
    cd infrastructure
    
    terraform init
    terraform plan -out=tfplan
    terraform apply tfplan
    
    # Get outputs
    local master_ip=$(terraform output -raw jenkins_master_public_ip)
    local worker_ip=$(terraform output -raw jenkins_worker_private_ip)
    
    print_success "Infrastructure deployed successfully"
    print_info "Jenkins Master Public IP: $master_ip"
    print_info "Jenkins Worker Private IP: $worker_ip"
    
    cd ..
    
    # Update Ansible inventory
    print_info "Updating Ansible inventory..."
    
    cd ansible
    
    cat > inventory << EOF
[jenkins_master]
jenkins-master ansible_host=$master_ip ansible_user=ec2-user ansible_ssh_private_key_file=$ssh_key_path

[jenkins_worker]
jenkins-worker ansible_host=$worker_ip ansible_user=ec2-user ansible_ssh_private_key_file=$ssh_key_path ansible_ssh_common_args='-o ProxyJump=ec2-user@$master_ip'

[all:vars]
ansible_ssh_common_args='-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null'
ansible_python_interpreter=/usr/bin/python3
EOF
    
    cd ..
    print_success "Ansible inventory updated"
}

# Function to configure Jenkins with Ansible
configure_jenkins() {
    print_info "Configuring Jenkins with Ansible..."
    print_info "Waiting for instances to be ready..."
    sleep 60
    
    cd ansible
    
    # Test connectivity
    print_info "Testing connectivity to Jenkins master..."
    ansible jenkins_master -m ping -i inventory
    
    # Run Jenkins setup playbook
    print_info "Running Jenkins setup playbook..."
    ansible-playbook -i inventory jenkins-setup.yml
    
    cd ..
    print_success "Jenkins configured successfully"
}

# Function to display connection information
display_connection_info() {
    print_info "Deployment completed! Here's how to connect:"
    
    cd infrastructure
    local master_ip=$(terraform output -raw jenkins_master_public_ip)
    cd ..
    
    print_success "Jenkins Access Information:"
    echo "  Web Interface: http://$master_ip"
    echo "  Direct Jenkins: http://$master_ip:8080"
    echo "  SSH to Master: ssh -i $ssh_key_path ec2-user@$master_ip"
    
    print_info "Next steps:"
    echo "  1. Access Jenkins web interface"
    echo "  2. Complete initial setup wizard"
    echo "  3. Add Jenkins worker node"
    echo "  4. Create and run your pipeline"
}

# Main deployment function
main() {
    print_info "Starting AWS Jenkins Infrastructure Deployment"
    print_info "=============================================="
    
    # Check prerequisites
    check_prerequisites
    check_aws_credentials
    
    # Generate SSH key
    ssh_key_path=$(generate_ssh_key)
    
    # Deploy S3 backend
    deploy_s3_backend
    
    # Create Terraform variables
    create_terraform_vars "$ssh_key_path"
    
    # Deploy infrastructure
    deploy_infrastructure
    
    # Configure Jenkins
    configure_jenkins
    
    # Display connection info
    display_connection_info
    
    print_success "Deployment completed successfully!"
}

# Cleanup function
cleanup() {
    print_info "Starting infrastructure cleanup..."
    
    # Destroy main infrastructure
    if [ -d "infrastructure" ]; then
        cd infrastructure
        if [ -f "terraform.tfstate" ]; then
            print_info "Destroying main infrastructure..."
            terraform destroy -auto-approve
        fi
        cd ..
    fi
    
    # Destroy S3 backend
    if [ -d "s3-backend" ]; then
        cd s3-backend
        if [ -f "terraform.tfstate" ]; then
            print_info "Destroying S3 backend..."
            terraform destroy -auto-approve
        fi
        cd ..
    fi
    
    print_success "Cleanup completed"
}

# Check command line arguments
case "${1:-}" in
    "deploy")
        main
        ;;
    "cleanup"|"destroy")
        cleanup
        ;;
    *)
        echo "Usage: $0 {deploy|cleanup}"
        echo "  deploy  - Deploy the complete infrastructure"
        echo "  cleanup - Destroy all resources"
        exit 1
        ;;
esac
