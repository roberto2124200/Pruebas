# Definición del proveedor
provider "aws" {

    region = "us-east-2"
}


# Datos del recurso AWS
resource "aws_vpc" "main" {

    cidr_block = "10.20.0.0/20"
    enable_dns_hostnames =  true
    tags = {
        Name = "youtube-vpc"
    }
  
}