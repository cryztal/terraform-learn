terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 4.16"
    }
  }

  required_version = ">= 1.2.0"
}

provider "aws" {
}


# Fetch latest Ubuntu and Amazon Linux AMI
data "aws_ami" "ubuntu" {
  most_recent = true
  owners = ["099720109477"] # Canonical

  filter {
    name = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }
}

data "aws_ami" "amazon_linux" {
  most_recent = true
  owners = ["amazon"]

  filter {
    name = "name"
    values = ["amzn2-ami-ecs-hvm-2.0.202*-x86_64-ebs"]
  }
}

################################################################################
# Get list of available AZs
################################################################################
data "aws_availability_zones" "available_zones" {
  state = "available"
}

################################################################################
# Create the VPC
################################################################################
resource "aws_vpc" "app_vpc" {
  cidr_block           = var.vpc_cidr_block
  enable_dns_hostnames = var.enable_dns_hostnames

  tags = {
    Name = "app-vpc"
  }
}

################################################################################
# Create the internet gateway
################################################################################
resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.app_vpc.id

  tags = {
    Name = "main-igw"
  }
}

################################################################################
# Create Subnet
################################################################################
resource "aws_subnet" "main_subnet" {
  vpc_id     = aws_vpc.app_vpc.id
  cidr_block = var.vpc_cidr_block
  availability_zone = data.aws_availability_zones.available_zones.names[1]  # Adjust to your region
  map_public_ip_on_launch  = true
  tags = {
    Name = "main-subnet"
  }
}

################################################################################
# Create the public route table
################################################################################
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.app_vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }
  tags = {
    Name = "public-route-table"
  }
}

################################################################################
# Assign the private route table to the private subnet
################################################################################
resource "aws_route_table_association" "public_association" {
  subnet_id      = aws_subnet.main_subnet.id
  route_table_id = aws_route_table.public.id
}

################################################################################
# Create a security group for the Ubuntu instance
################################################################################
resource "aws_security_group" "ubuntu_sg" {
  vpc_id = aws_vpc.app_vpc.id
  name   = "ubuntu-sg"

  ingress {
    from_port = 22
    to_port   = 22
    protocol  = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port = 80
    to_port   = 80
    protocol  = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port = 443
    to_port   = 443
    protocol  = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port = -1
    to_port   = -1
    protocol  = "icmp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port = 0
    to_port   = 0
    protocol  = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "ubuntu-sg"
  }
}

################################################################################
# Create a security group for the Amazon Linux instance
################################################################################
resource "aws_security_group" "amazon_linux_sg" {
  vpc_id = aws_vpc.app_vpc.id
  name   = "amazon-linux-sg"

  ingress {
    from_port = 22
    to_port   = 22
    protocol  = "tcp"
    cidr_blocks = [aws_subnet.main_subnet.cidr_block]
  }

  ingress {
    from_port = 80
    to_port   = 80
    protocol  = "tcp"
    cidr_blocks = [aws_subnet.main_subnet.cidr_block]
  }

  ingress {
    from_port = 443
    to_port   = 443
    protocol  = "tcp"
    cidr_blocks = [aws_subnet.main_subnet.cidr_block]
  }

  ingress {
    from_port = -1
    to_port   = -1
    protocol  = "icmp"
    cidr_blocks = [aws_subnet.main_subnet.cidr_block]
  }

  egress {
    from_port = 0
    to_port   = 0
    protocol  = "-1"
    cidr_blocks = [aws_subnet.main_subnet.cidr_block]
  }

  tags = {
    Name = "amazon-linux-sg"
  }
}


# Ubuntu EC2 instance
resource "aws_instance" "ubuntu" {
  ami           = data.aws_ami.ubuntu.id
  instance_type = "t2.micro"
  subnet_id     = aws_subnet.main_subnet.id
  vpc_security_group_ids = [aws_security_group.ubuntu_sg.id]
  associate_public_ip_address  = true

  tags = {
    Name = "Ubuntu"
  }
  user_data = <<-EOF
    #!/bin/bash
    sudo apt update -y
    sudo apt install nginx -y
    sudo systemctl enable nginx
    sudo systemctl start nginx
    echo "<h1>Hello World</h1>" > /var/www/html/index.html
    echo "<p>OS: $(uname -a)</p>" >> /var/www/html/index.html
    curl -fsSL https://get.docker.com -o get-docker.sh
    sh get-docker.sh
    sudo usermod -aG docker ubuntu
  EOF
}

# Amazon Linux EC2 instance
resource "aws_instance" "amazon_linux" {
  ami           = data.aws_ami.amazon_linux.id
  instance_type = "t2.micro"
  subnet_id     = aws_subnet.main_subnet.id
  vpc_security_group_ids = [aws_security_group.amazon_linux_sg.id]

  tags = {
    Name = "Amazon-Linux"
  }
  user_data = <<-EOF
    #!/bin/bash
    sudo yum update -y
  EOF
}

# Output EC2 details
output "ubuntu_instance_public_ip" {
  value = aws_instance.ubuntu.public_ip
}

output "amazon_linux_instance_private_ip" {
  value = aws_instance.amazon_linux.private_ip
}
