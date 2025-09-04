# AWS Infrastructure Deployment Script for Step 3 Project (PowerShell)
# This script automates the deployment of Jenkins infrastructure on Windows

param(
    [Parameter(Mandatory=$true)]
    [ValidateSet("deploy", "cleanup", "destroy")]
    [string]$Action
)

# Colors for output
$Colors = @{
    Red = "Red"
    Green = "Green" 
    Yellow = "Yellow"
    Blue = "Blue"
}

function Write-Info {
    param([string]$Message)
    Write-Host "[INFO] $Message" -ForegroundColor $Colors.Blue
}

function Write-Success {
    param([string]$Message)
    Write-Host "[SUCCESS] $Message" -ForegroundColor $Colors.Green
}

function Write-Warning {
    param([string]$Message)
    Write-Host "[WARNING] $Message" -ForegroundColor $Colors.Yellow
}

function Write-Error {
    param([string]$Message)
    Write-Host "[ERROR] $Message" -ForegroundColor $Colors.Red
}

function Test-Prerequisites {
    Write-Info "Checking prerequisites..."
    
    $missingTools = @()
    
    if (!(Get-Command terraform -ErrorAction SilentlyContinue)) {
        $missingTools += "terraform"
    }
    
    if (!(Get-Command aws -ErrorAction SilentlyContinue)) {
        $missingTools += "aws-cli"
    }
    
    if (!(Get-Command ansible -ErrorAction SilentlyContinue)) {
        $missingTools += "ansible"
    }
    
    if (!(Get-Command ssh-keygen -ErrorAction SilentlyContinue)) {
        $missingTools += "ssh-keygen"
    }
    
    if ($missingTools.Count -gt 0) {
        Write-Error "Missing required tools: $($missingTools -join ', ')"
        Write-Info "Please install the missing tools and try again."
        exit 1
    }
    
    Write-Success "All prerequisites are installed"
}

function New-SSHKey {
    $keyPath = "$env:USERPROFILE\.ssh\jenkins-step3-key"
    $keyDir = Split-Path $keyPath
    
    if (!(Test-Path $keyDir)) {
        New-Item -ItemType Directory -Path $keyDir -Force | Out-Null
    }
    
    if (!(Test-Path $keyPath)) {
        Write-Info "Generating SSH key pair..."
        $date = Get-Date -Format "yyyyMMdd"
        ssh-keygen -t rsa -b 4096 -f $keyPath -N '""' -C "jenkins-step3-$date"
        Write-Success "SSH key pair generated: $keyPath"
    } else {
        Write-Info "SSH key already exists: $keyPath"
    }
    
    return $keyPath
}

function Test-AWSCredentials {
    Write-Info "Checking AWS credentials..."
    
    try {
        $identity = aws sts get-caller-identity --output text --query 'Account' 2>$null
        if ($LASTEXITCODE -ne 0) {
            throw "AWS CLI command failed"
        }
        Write-Success "AWS credentials configured (Account: $identity)"
    } catch {
        Write-Error "AWS credentials not configured properly"
        Write-Info "Please configure AWS credentials using 'aws configure' or environment variables"
        exit 1
    }
}

function Deploy-S3Backend {
    Write-Info "Deploying S3 backend for Terraform state..."
    
    Push-Location "s3-backend"
    
    try {
        terraform init
        terraform plan -out=tfplan
        terraform apply tfplan
        
        # Get outputs
        $bucketName = terraform output -raw s3_bucket_name
        $tableName = terraform output -raw dynamodb_table_name
        
        Write-Success "S3 backend deployed successfully"
        Write-Info "Bucket: $bucketName"
        Write-Info "DynamoDB Table: $tableName"
        
        Pop-Location
        
        # Update backend configuration in main infrastructure
        Write-Info "Updating backend configuration in infrastructure..."
        
        $mainTfPath = "infrastructure\main.tf"
        $content = Get-Content $mainTfPath -Raw
        
        $content = $content -replace '# bucket.*', "bucket         = `"$bucketName`""
        $content = $content -replace '# key.*', 'key            = "jenkins-infrastructure/terraform.tfstate"'
        $content = $content -replace '# region.*', 'region         = "us-east-1"'
        $content = $content -replace '# dynamodb_table.*', "dynamodb_table = `"$tableName`""
        $content = $content -replace '# encrypt.*', 'encrypt        = true'
        
        Set-Content $mainTfPath -Value $content
        
        Write-Success "Backend configuration updated"
        
        return @{
            BucketName = $bucketName
            TableName = $tableName
        }
    } finally {
        Pop-Location
    }
}

function New-TerraformVars {
    param([string]$SSHKeyPath)
    
    $publicKey = Get-Content "$SSHKeyPath.pub" -Raw
    $publicKey = $publicKey.Trim()
    
    Write-Info "Creating terraform.tfvars file..."
    
    Push-Location "infrastructure"
    
    try {
        $tfvarsContent = @"
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
ssh_public_key = "$publicKey"
"@
        
        Set-Content "terraform.tfvars" -Value $tfvarsContent
        Write-Success "terraform.tfvars created"
    } finally {
        Pop-Location
    }
}

function Deploy-Infrastructure {
    param([string]$SSHKeyPath)
    
    Write-Info "Deploying main infrastructure..."
    
    Push-Location "infrastructure"
    
    try {
        terraform init
        terraform plan -out=tfplan
        terraform apply tfplan
        
        # Get outputs
        $masterIP = terraform output -raw jenkins_master_public_ip
        $workerIP = terraform output -raw jenkins_worker_private_ip
        
        Write-Success "Infrastructure deployed successfully"
        Write-Info "Jenkins Master Public IP: $masterIP"
        Write-Info "Jenkins Worker Private IP: $workerIP"
        
        Pop-Location
        
        # Update Ansible inventory
        Write-Info "Updating Ansible inventory..."
        
        $inventoryContent = @"
[jenkins_master]
jenkins-master ansible_host=$masterIP ansible_user=ec2-user ansible_ssh_private_key_file=$SSHKeyPath

[jenkins_worker]
jenkins-worker ansible_host=$workerIP ansible_user=ec2-user ansible_ssh_private_key_file=$SSHKeyPath ansible_ssh_common_args='-o ProxyJump=ec2-user@$masterIP'

[all:vars]
ansible_ssh_common_args='-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null'
ansible_python_interpreter=/usr/bin/python3
"@
        
        Set-Content "ansible\inventory" -Value $inventoryContent
        Write-Success "Ansible inventory updated"
        
        return @{
            MasterIP = $masterIP
            WorkerIP = $workerIP
        }
    } finally {
        Pop-Location
    }
}

function Install-Jenkins {
    Write-Info "Configuring Jenkins with Ansible..."
    Write-Info "Waiting for instances to be ready..."
    Start-Sleep 60
    
    Push-Location "ansible"
    
    try {
        # Test connectivity
        Write-Info "Testing connectivity to Jenkins master..."
        ansible jenkins_master -m ping -i inventory
        
        # Run Jenkins setup playbook
        Write-Info "Running Jenkins setup playbook..."
        ansible-playbook -i inventory jenkins-setup.yml
        
        Write-Success "Jenkins configured successfully"
    } finally {
        Pop-Location
    }
}

function Show-ConnectionInfo {
    param([string]$MasterIP, [string]$SSHKeyPath)
    
    Write-Info "Deployment completed! Here's how to connect:"
    
    Write-Success "Jenkins Access Information:"
    Write-Host "  Web Interface: http://$MasterIP" -ForegroundColor White
    Write-Host "  Direct Jenkins: http://$MasterIP`:8080" -ForegroundColor White
    Write-Host "  SSH to Master: ssh -i $SSHKeyPath ec2-user@$MasterIP" -ForegroundColor White
    
    Write-Info "Next steps:"
    Write-Host "  1. Access Jenkins web interface" -ForegroundColor White
    Write-Host "  2. Complete initial setup wizard" -ForegroundColor White
    Write-Host "  3. Add Jenkins worker node" -ForegroundColor White
    Write-Host "  4. Create and run your pipeline" -ForegroundColor White
}

function Start-Deployment {
    Write-Info "Starting AWS Jenkins Infrastructure Deployment"
    Write-Info "=============================================="
    
    # Check prerequisites
    Test-Prerequisites
    Test-AWSCredentials
    
    # Generate SSH key
    $sshKeyPath = New-SSHKey
    
    # Deploy S3 backend
    $backendInfo = Deploy-S3Backend
    
    # Create Terraform variables
    New-TerraformVars -SSHKeyPath $sshKeyPath
    
    # Deploy infrastructure
    $infraInfo = Deploy-Infrastructure -SSHKeyPath $sshKeyPath
    
    # Configure Jenkins
    Install-Jenkins
    
    # Display connection info
    Show-ConnectionInfo -MasterIP $infraInfo.MasterIP -SSHKeyPath $sshKeyPath
    
    Write-Success "Deployment completed successfully!"
}

function Start-Cleanup {
    Write-Info "Starting infrastructure cleanup..."
    
    # Destroy main infrastructure
    if (Test-Path "infrastructure") {
        Push-Location "infrastructure"
        try {
            if (Test-Path "terraform.tfstate") {
                Write-Info "Destroying main infrastructure..."
                terraform destroy -auto-approve
            }
        } finally {
            Pop-Location
        }
    }
    
    # Destroy S3 backend
    if (Test-Path "s3-backend") {
        Push-Location "s3-backend"
        try {
            if (Test-Path "terraform.tfstate") {
                Write-Info "Destroying S3 backend..."
                terraform destroy -auto-approve
            }
        } finally {
            Pop-Location
        }
    }
    
    Write-Success "Cleanup completed"
}

# Main execution
switch ($Action) {
    "deploy" {
        Start-Deployment
    }
    { $_ -in "cleanup", "destroy" } {
        Start-Cleanup
    }
}
