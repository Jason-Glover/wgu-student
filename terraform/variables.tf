variable "project_name" {
  description = "Prefix used for naming AWS resources"
  type        = string
}

variable "aws_region" {
  description = "AWS region for deployment"
  type        = string
}

variable "vpc_cidr" {
  description = "CIDR block for the AWS VPC"
  type        = string

  validation {
    condition     = can(cidrhost(var.vpc_cidr, 0))
    error_message = "vpc_cidr must be a valid IPv4 CIDR block."
  }
}

variable "public_subnet_cidr" {
  description = "CIDR block for the public subnet"
  type        = string

  validation {
    condition     = can(cidrhost(var.public_subnet_cidr, 0))
    error_message = "public_subnet_cidr must be a valid IPv4 CIDR block."
  }
}

variable "app_subnet_cidr" {
  description = "CIDR block for the application subnet"
  type        = string

  validation {
    condition     = can(cidrhost(var.app_subnet_cidr, 0))
    error_message = "app_subnet_cidr must be a valid IPv4 CIDR block."
  }
}

variable "mgmt_subnet_cidr" {
  description = "CIDR block for the management subnet"
  type        = string

  validation {
    condition     = can(cidrhost(var.mgmt_subnet_cidr, 0))
    error_message = "mgmt_subnet_cidr must be a valid IPv4 CIDR block."
  }
}

variable "onprem_cidr" {
  description = "CIDR block for the on-premises network reachable across the VPN"
  type        = string

  validation {
    condition     = can(cidrhost(var.onprem_cidr, 0))
    error_message = "onprem_cidr must be a valid IPv4 CIDR block."
  }
}

variable "trusted_admin_cidr" {
  description = "Public client CIDR allowed to SSH to the bastion host"
  type        = string

  validation {
    condition     = can(cidrhost(var.trusted_admin_cidr, 0))
    error_message = "trusted_admin_cidr must be a valid IPv4 CIDR block such as 203.0.113.10/32."
  }
}

variable "customer_gateway_ip" {
  description = "Static public IP address of the on-premises VPN device"
  type        = string

  validation {
    condition     = can(regex("^([0-9]{1,3}\\.){3}[0-9]{1,3}$", var.customer_gateway_ip))
    error_message = "customer_gateway_ip must be a valid IPv4 address without CIDR notation."
  }
}

variable "ami_id" {
  description = "AMI ID used for all EC2 instances"
  type        = string
}

variable "instance_type" {
  description = "EC2 instance type used for bastion, app, and management hosts"
  type        = string
  default     = "t3.micro"
}

variable "key_name" {
  description = "Existing EC2 key pair name used for SSH access"
  type        = string
}

variable "tunnel1_preshared_key" {
  description = "Pre-shared key for VPN tunnel 1"
  type        = string
  sensitive   = true
}

variable "tunnel2_preshared_key" {
  description = "Pre-shared key for VPN tunnel 2"
  type        = string
  sensitive   = true
}