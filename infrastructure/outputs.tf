output "vpc_id" {
  description = "ID of the VPC"
  value       = aws_vpc.main.id
}

output "public_subnet_id" {
  description = "ID of the public subnet"
  value       = aws_subnet.public.id
}

output "private_subnet_id" {
  description = "ID of the private subnet"
  value       = aws_subnet.private.id
}

output "internet_gateway_id" {
  description = "ID of the Internet Gateway"
  value       = aws_internet_gateway.main.id
}

output "nat_gateway_id" {
  description = "ID of the NAT Gateway"
  value       = aws_nat_gateway.main.id
}

output "jenkins_master_instance_id" {
  description = "ID of the Jenkins master instance"
  value       = aws_instance.jenkins_master.id
}

output "jenkins_master_public_ip" {
  description = "Public IP of the Jenkins master instance"
  value       = aws_instance.jenkins_master.public_ip
}

output "jenkins_master_private_ip" {
  description = "Private IP of the Jenkins master instance"
  value       = aws_instance.jenkins_master.private_ip
}

output "jenkins_worker_instance_id" {
  description = "ID of the Jenkins worker spot instance"
  value       = aws_spot_instance_request.jenkins_worker.spot_instance_id
}

output "jenkins_worker_private_ip" {
  description = "Private IP of the Jenkins worker instance"
  value       = aws_spot_instance_request.jenkins_worker.private_ip
}

output "security_group_jenkins_master_id" {
  description = "ID of the Jenkins master security group"
  value       = aws_security_group.jenkins_master.id
}

output "security_group_jenkins_worker_id" {
  description = "ID of the Jenkins worker security group"
  value       = aws_security_group.jenkins_worker.id
}

output "ssh_connection_jenkins_master" {
  description = "SSH connection command for Jenkins master"
  value       = "ssh -i ~/.ssh/your-key.pem ec2-user@${aws_instance.jenkins_master.public_ip}"
}

output "jenkins_web_url" {
  description = "URL to access Jenkins web interface"
  value       = "http://${aws_instance.jenkins_master.public_ip}"
}
