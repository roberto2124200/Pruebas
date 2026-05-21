terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

# Región AWS
provider "aws" {
  region = "us-east-2"
}

# Zonas de disponibilidad disponibles
data "aws_availability_zones" "available" {
  state = "available"
}

# VPC principal
resource "aws_vpc" "main" {
  cidr_block           = "10.20.0.0/20"
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = "terraform-vpc"
  }
}

# Internet Gateway creado en la misma VPC
resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "igw-terraform"
  }
}

# Subred pública 1
resource "aws_subnet" "subred1" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.20.0.0/24"
  availability_zone       = data.aws_availability_zones.available.names[0]
  map_public_ip_on_launch = true

  tags = {
    Name = "subred1-terraform"
  }
}

# Subred pública 2
resource "aws_subnet" "subred2" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.20.1.0/24"
  availability_zone       = data.aws_availability_zones.available.names[1]
  map_public_ip_on_launch = true

  tags = {
    Name = "subred2-terraform"
  }
}

# Tabla de rutas pública
resource "aws_route_table" "public_rt" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }

  tags = {
    Name = "rt-public-terraform"
  }
}

# Asociación de subred 1 a tabla pública
resource "aws_route_table_association" "subred1_assoc" {
  subnet_id      = aws_subnet.subred1.id
  route_table_id = aws_route_table.public_rt.id
}

# Asociación de subred 2 a tabla pública
resource "aws_route_table_association" "subred2_assoc" {
  subnet_id      = aws_subnet.subred2.id
  route_table_id = aws_route_table.public_rt.id
}

# Security Group único para SSH y HTTP
resource "aws_security_group" "sg_terraform" {
  name        = "sg-terraform-ssh-http"
  description = "Permite trafico SSH y HTTP"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "SSH desde Internet"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "HTTP desde Internet"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "Salida hacia Internet"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "sg-terraform-ssh-http"
  }
}

# Bucket S3 público
# Se usa bucket_prefix porque el nombre exacto "test-terraform" puede estar ocupado globalmente.
resource "aws_s3_bucket" "public_bucket" {
  bucket_prefix = "test-terraform-"
  force_destroy = true

  tags = {
    Name = "test-terraform-publico"
  }
}

# Control de propiedad del bucket
resource "aws_s3_bucket_ownership_controls" "public_bucket" {
  bucket = aws_s3_bucket.public_bucket.id

  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

# Permitir política pública en el bucket
resource "aws_s3_bucket_public_access_block" "public_bucket" {
  bucket = aws_s3_bucket.public_bucket.id

  block_public_acls       = false
  ignore_public_acls      = false
  block_public_policy     = false
  restrict_public_buckets = false
}

# Política pública de lectura para los objetos del bucket
resource "aws_s3_bucket_policy" "public_read" {
  bucket = aws_s3_bucket.public_bucket.id

  depends_on = [
    aws_s3_bucket_public_access_block.public_bucket
  ]

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "PublicReadGetObject"
        Effect    = "Allow"
        Principal = "*"
        Action    = "s3:GetObject"
        Resource  = "${aws_s3_bucket.public_bucket.arn}/*"
      }
    ]
  })
}

# Versionamiento del bucket
resource "aws_s3_bucket_versioning" "public_bucket" {
  bucket = aws_s3_bucket.public_bucket.id

  versioning_configuration {
    status = "Enabled"
  }
}

# Cifrado por defecto del bucket
resource "aws_s3_bucket_server_side_encryption_configuration" "public_bucket" {
  bucket = aws_s3_bucket.public_bucket.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# Outputs
output "vpc_id" {
  value = aws_vpc.main.id
}

output "internet_gateway_id" {
  value = aws_internet_gateway.main.id
}

output "subred1_id" {
  value = aws_subnet.subred1.id
}

output "subred2_id" {
  value = aws_subnet.subred2.id
}

output "route_table_id" {
  value = aws_route_table.public_rt.id
}

output "security_group_id" {
  value = aws_security_group.sg_terraform.id
}

output "bucket_name" {
  value = aws_s3_bucket.public_bucket.bucket
}