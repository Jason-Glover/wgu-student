terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

data "aws_availability_zones" "available" {
  state = "available"
}

resource "aws_vpc" "clinic" {
  # checkov:skip=CKV2_AWS_11: ADD REASON
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = "${var.project_name}-vpc"
  }
}

resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.clinic.id

  tags = {
    Name = "${var.project_name}-igw"
  }
}

resource "aws_subnet" "public" {
  vpc_id            = aws_vpc.clinic.id
  cidr_block        = var.public_subnet_cidr
  availability_zone = data.aws_availability_zones.available.names[0]

  tags = {
    Name = "${var.project_name}-public"
    Tier = "public"
  }
}

resource "aws_subnet" "app" {
  vpc_id            = aws_vpc.clinic.id
  cidr_block        = var.app_subnet_cidr
  availability_zone = data.aws_availability_zones.available.names[0]

  tags = {
    Name = "${var.project_name}-app"
    Tier = "private-app"
  }
}

resource "aws_subnet" "mgmt" {
  vpc_id            = aws_vpc.clinic.id
  cidr_block        = var.mgmt_subnet_cidr
  availability_zone = data.aws_availability_zones.available.names[0]

  tags = {
    Name = "${var.project_name}-mgmt"
    Tier = "private-mgmt"
  }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.clinic.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }

  tags = {
    Name = "${var.project_name}-public-rt"
  }
}

resource "aws_route_table" "private" {
  vpc_id = aws_vpc.clinic.id

  tags = {
    Name = "${var.project_name}-private-rt"
  }
}

resource "aws_route_table_association" "public_assoc" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table_association" "app_assoc" {
  subnet_id      = aws_subnet.app.id
  route_table_id = aws_route_table.private.id
}

resource "aws_route_table_association" "mgmt_assoc" {
  subnet_id      = aws_subnet.mgmt.id
  route_table_id = aws_route_table.private.id
}

resource "aws_security_group" "bastion" {
  name        = "${var.project_name}-bastion-sg"
  description = "Bastion access"
  vpc_id      = aws_vpc.clinic.id

  ingress {
    description = "Admin SSH from trusted CIDR"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.trusted_admin_cidr]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.project_name}-bastion-sg"
  }
}

resource "aws_security_group" "app" {
  name        = "${var.project_name}-app-sg"
  description = "Application access from on-prem and bastion"
  vpc_id      = aws_vpc.clinic.id

  ingress {
    description = "HTTPS from on-prem"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = [var.onprem_cidr]
  }

  ingress {
    description = "HTTP from on-prem"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = [var.onprem_cidr]
  }

  ingress {
    description     = "SSH from bastion"
    from_port       = 22
    to_port         = 22
    protocol        = "tcp"
    security_groups = [aws_security_group.bastion.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.project_name}-app-sg"
  }
}

resource "aws_security_group" "mgmt" {
  name        = "${var.project_name}-mgmt-sg"
  description = "Management subnet controls"
  vpc_id      = aws_vpc.clinic.id

  ingress {
    description = "SSH from on-prem admin subnet"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.onprem_cidr]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.project_name}-mgmt-sg"
  }
}

resource "aws_security_group" "ssm_vpce" {
  name        = "${var.project_name}-ssm-vpce-sg"
  description = "Security group for SSM VPC endpoints"
  vpc_id      = aws_vpc.clinic.id

  ingress {
    description = "HTTPS for SSM endpoints"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.project_name}-ssm-vpce-sg"
  }
}

resource "aws_vpc_endpoint" "ssm" {
  vpc_id              = aws_vpc.clinic.id
  service_name        = "com.amazonaws.${var.aws_region}.ssm"
  vpc_endpoint_type   = "Interface"
  private_dns_enabled = true
  subnet_ids          = [aws_subnet.app.id, aws_subnet.mgmt.id]
  security_group_ids  = [aws_security_group.ssm_vpce.id]

  tags = {
    Name = "${var.project_name}-ssm-endpoint"
  }
}

resource "aws_vpc_endpoint" "ec2messages" {
  vpc_id              = aws_vpc.clinic.id
  service_name        = "com.amazonaws.${var.aws_region}.ec2messages"
  vpc_endpoint_type   = "Interface"
  private_dns_enabled = true
  subnet_ids          = [aws_subnet.app.id, aws_subnet.mgmt.id]
  security_group_ids  = [aws_security_group.ssm_vpce.id]

  tags = {
    Name = "${var.project_name}-ec2messages-endpoint"
  }
}

resource "aws_vpc_endpoint" "ssmmessages" {
  vpc_id              = aws_vpc.clinic.id
  service_name        = "com.amazonaws.${var.aws_region}.ssmmessages"
  vpc_endpoint_type   = "Interface"
  private_dns_enabled = true
  subnet_ids          = [aws_subnet.app.id, aws_subnet.mgmt.id]
  security_group_ids  = [aws_security_group.ssm_vpce.id]

  tags = {
    Name = "${var.project_name}-ssmmessages-endpoint"
  }
}

resource "aws_instance" "bastion" {
  ami                         = var.ami_id
  instance_type               = var.instance_type
  subnet_id                   = aws_subnet.public.id
  vpc_security_group_ids      = [aws_security_group.bastion.id]
  associate_public_ip_address = true
  key_name                    = var.key_name
  iam_instance_profile        = aws_iam_instance_profile.ec2_ssm_instance_profile.name

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
  }

  root_block_device {
    encrypted   = true
    volume_type = "gp3"
  }

  tags = {
    Name = "${var.project_name}-bastion"
    Role = "bastion"
  }
}

resource "aws_eip" "bastion" {
  domain = "vpc"

  tags = {
    Name = "${var.project_name}-bastion-eip"
  }
}

resource "aws_eip_association" "bastion" {
  instance_id   = aws_instance.bastion.id
  allocation_id = aws_eip.bastion.id
}

resource "aws_iam_role" "ec2_ssm_role" {
  name = "${var.project_name}-ec2-ssm-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "ec2_ssm_role_attachment" {
  role       = aws_iam_role.ec2_ssm_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_role_policy_attachment" "ec2_ssm_cloudwatch_agent_attachment" {
  role       = aws_iam_role.ec2_ssm_role.name
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"
}

resource "aws_iam_instance_profile" "ec2_ssm_instance_profile" {
  name = "${var.project_name}-ec2-ssm-profile"
  role = aws_iam_role.ec2_ssm_role.name
}

resource "aws_instance" "app" {
  ami                    = var.ami_id
  instance_type          = var.instance_type
  subnet_id              = aws_subnet.app.id
  vpc_security_group_ids = [aws_security_group.app.id]
  key_name               = var.key_name
  iam_instance_profile   = aws_iam_instance_profile.ec2_ssm_instance_profile.name

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
  }

  root_block_device {
    encrypted   = true
    volume_type = "gp3"
  }

  tags = {
    Name = "${var.project_name}-app"
    Role = "application"
  }
}

resource "aws_instance" "mgmt" {
  ami                    = var.ami_id
  instance_type          = var.instance_type
  subnet_id              = aws_subnet.mgmt.id
  vpc_security_group_ids = [aws_security_group.mgmt.id]
  key_name               = var.key_name
  iam_instance_profile   = aws_iam_instance_profile.ec2_ssm_instance_profile.name

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
  }

  root_block_device {
    encrypted   = true
    volume_type = "gp3"
  }

  tags = {
    Name = "${var.project_name}-mgmt"
    Role = "management"
  }
}

resource "aws_customer_gateway" "onprem" {
  bgp_asn    = 65000
  ip_address = var.customer_gateway_ip
  type       = "ipsec.1"

  tags = {
    Name = "${var.project_name}-customer-gateway"
  }
}

resource "aws_vpn_gateway" "vgw" {
  vpc_id = aws_vpc.clinic.id

  tags = {
    Name = "${var.project_name}-vgw"
  }
}

resource "aws_vpn_gateway_route_propagation" "private" {
  vpn_gateway_id = aws_vpn_gateway.vgw.id
  route_table_id = aws_route_table.private.id
}

resource "aws_vpn_connection" "site_to_site" {
  vpn_gateway_id      = aws_vpn_gateway.vgw.id
  customer_gateway_id = aws_customer_gateway.onprem.id
  type                = "ipsec.1"
  static_routes_only  = true

  tunnel1_preshared_key = var.tunnel1_preshared_key
  tunnel2_preshared_key = var.tunnel2_preshared_key

  tags = {
    Name = "${var.project_name}-s2s"
  }
}

resource "aws_vpn_connection_route" "onprem_route" {
  vpn_connection_id      = aws_vpn_connection.site_to_site.id
  destination_cidr_block = var.onprem_cidr
}

resource "aws_cloudwatch_log_group" "vpc_flow_logs" {
  name              = "/aws/vpc/flowlogs/${var.project_name}"
  retention_in_days = 30

  tags = {
    Name = "${var.project_name}-flowlogs"
  }
}

resource "aws_iam_role" "flow_logs_role" {
  name = "${var.project_name}-flowlogs-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "vpc-flow-logs.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_role_policy" "flow_logs_policy" {
  name = "${var.project_name}-flowlogs-policy"
  role = aws_iam_role.flow_logs_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogDelivery",
          "logs:DeleteLogDelivery",
          "logs:DescribeLogGroups",
          "logs:DescribeLogStreams",
          "logs:PutLogEvents",
          "logs:CreateLogStream"
        ]
        Resource = "*"
      }
    ]
  })
}

resource "aws_flow_log" "vpc_flow_log" {
  iam_role_arn         = aws_iam_role.flow_logs_role.arn
  log_destination      = aws_cloudwatch_log_group.vpc_flow_logs.arn
  traffic_type         = "ALL"
  vpc_id               = aws_vpc.clinic.id
  log_destination_type = "cloud-watch-logs"

  tags = {
    Name = "${var.project_name}-vpc-flow-log"
  }
}

output "bastion_eip" {
  value = aws_eip.bastion.public_ip
}

output "app_private_ip" {
  value = aws_instance.app.private_ip
}

output "mgmt_private_ip" {
  value = aws_instance.mgmt.private_ip
}

output "vpn_tunnel1_address" {
  value = aws_vpn_connection.site_to_site.tunnel1_address
}

output "vpn_tunnel2_address" {
  value = aws_vpn_connection.site_to_site.tunnel2_address
}

output "flow_log_group_name" {
  value = aws_cloudwatch_log_group.vpc_flow_logs.name
}