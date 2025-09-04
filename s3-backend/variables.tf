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
