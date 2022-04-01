# terraform {
#   cloud {
#     organization = "klinz-sandbox"

#     workspaces {
#       name = "bastion-host"
#     }
#   }
# }

provider "aws" {
  region = var.aws_region

  # profile = "spad"
}


# resource "aws_key_pair" "key-pair" {
#   # key file for ssh
#   key_name = "mykey"

#   # todo create s3 bucket to keep all the keys
#   public_key = file("~/.ssh/id_rsa.pub")
# }


resource "tls_private_key" "dev_key" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "aws_key_pair" "generated_key" {
  key_name   = var.generated_key_name
  public_key = tls_private_key.dev_key.public_key_openssh

  provisioner "local-exec" { # Generate "terraform-key-pair.pem" in current directory
    command = <<-EOT
      echo '${tls_private_key.dev_key.private_key_pem}' > ./'${var.generated_key_name}'.pem
      chmod 400 ./'${var.generated_key_name}'.pem
    EOT
  }

}

resource "aws_vpc" "bostion-vpc" {

  cidr_block = var.vpc_cidr_block

  enable_dns_hostnames = true

  tags = local.common_tags

}

data "aws_availability_zones" "available" {}


# public subnet
resource "aws_subnet" "subnet1" {

  depends_on = [
    aws_vpc.bostion-vpc
  ]

  vpc_id = aws_vpc.bostion-vpc.id

  cidr_block = var.vpc_subnets_cidr_blocks[0]

  availability_zone = data.aws_availability_zones.available.names[0]

  map_public_ip_on_launch = var.enable_map_public_ip

  tags = local.common_tags

}

# private subnet
resource "aws_subnet" "subnet2-private" {

  depends_on = [
    aws_vpc.bostion-vpc,
    aws_subnet.subnet1
  ]

  vpc_id = aws_vpc.bostion-vpc.id

  cidr_block = var.vpc_subnets_cidr_blocks[1]

  availability_zone = data.aws_availability_zones.available.names[1]
}

#Internet gateway
resource "aws_internet_gateway" "internet-gateway" {

  depends_on = [
    aws_vpc.bostion-vpc,
    aws_subnet.subnet1,
    aws_subnet.subnet2-private
  ]

  vpc_id = aws_vpc.bostion-vpc.id

  tags = local.common_tags

}

resource "aws_route_table" "route-table" {

  depends_on = [
    aws_vpc.bostion-vpc,
    aws_internet_gateway.internet-gateway
  ]
  vpc_id = aws_vpc.bostion-vpc.id

  route {
    cidr_block = var.allow_anywhere
    gateway_id = aws_internet_gateway.internet-gateway.id
  }

  tags = local.common_tags

}

resource "aws_route_table_association" "rt-association" {

  depends_on = [
    aws_vpc.bostion-vpc,
    aws_subnet.subnet1,
    aws_subnet.subnet2-private,
    aws_route_table.route-table
  ]
  subnet_id = aws_subnet.subnet1.id

  route_table_id = aws_route_table.route-table.id
}

resource "aws_security_group" "public-instance-sg" {

  depends_on = [
    aws_vpc.bostion-vpc,
    aws_subnet.subnet1,
    aws_subnet.subnet2-private
  ]

  description = var.bostion-server-sg-description

  name = "jump-host-sg"

  vpc_id = aws_vpc.bostion-vpc.id

  ingress {
    cidr_blocks = [var.allow_anywhere]
    description = "http"
    from_port   = 80
    #ipv6_cidr_blocks = [ "value" ]
    #prefix_list_ids = [ "value" ]
    protocol = "tcp"
    #security_groups = [ "value" ]
    self    = false
    to_port = 80
  }

  ingress {
    description = "Ping"
    from_port   = 0
    to_port     = 0
    protocol    = "ICMP"
    cidr_blocks = [var.allow_anywhere]
  }

  ingress {
    description = " ssh connection"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.allow_anywhere]
  }

  egress {
    description = "send data out from public host"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = [var.allow_anywhere]
  }
}

resource "aws_security_group" "private-instance" {

  depends_on = [
    aws_vpc.bostion-vpc,
    aws_subnet.subnet1,
    aws_subnet.subnet2-private,
    aws_security_group.public-instance-sg
  ]

  name        = "private-instance-sg"
  description = " private instance sg will only be accessed from public intance within vpc"
  vpc_id      = aws_vpc.bostion-vpc.id

  ingress {
    from_port       = 22
    to_port         = 22
    protocol        = "tcp"
    security_groups = [aws_security_group.public-instance-sg.id]
    description     = "Access to private instance"
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = [var.allow_anywhere]
    description = "send data to anywhere"
  }
}

resource "aws_security_group" "bastion-sg" {

  depends_on = [
    aws_vpc.bostion-vpc,
    aws_subnet.subnet1,
    aws_subnet.subnet2-private
  ]


  name        = "bastion-host-sg"
  vpc_id      = aws_vpc.bostion-vpc.id
  description = "bastion-host-sg"

  ingress {
    description = "data from Bastion Host"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = [var.allow_anywhere]
  }
}

resource "aws_instance" "public-instance" {
  ami           = var.ami_type
  instance_type = var.instance_type
  subnet_id     = aws_subnet.subnet1.id


  #Please create a key and upload it to aws console
  key_name               = var.generated_key_name
  vpc_security_group_ids = [aws_security_group.public-instance-sg.id]

  tags = local.common_tags


  # connection {
  #   type        = "ssh"
  #   user        = "ec2-user"
  #   private_key = file("./${var.generated_key_name}.pem")
  #   host        = aws_instance.public-instance.public_ip
  # }


  # provisioner "remote-exec" {
  #   inline = [
  #     "sudo yum update -y",
  #     "echo 'welcome' > welcome.txt "
  #   ]
  # }
}

resource "aws_instance" "private-instance" {
  depends_on = [
    aws_instance.public-instance
  ]

  ami           = var.ami_type
  instance_type = var.instance_type
  subnet_id     = aws_subnet.subnet2-private.id


  vpc_security_group_ids = [aws_security_group.private-instance.id]

  tags = local.common_tags

}


# Creating an AWS instance for the Bastion Host, It should be launched in the public Subnet!
resource "aws_instance" "Bastion-Host" {

  ami           = var.ami_type
  instance_type = var.instance_type
  subnet_id     = aws_subnet.subnet1.id

  # Keyname and security group are obtained from the reference of their instances created above!
  key_name = var.generated_key_name

  # Security group ID's
  vpc_security_group_ids = [aws_security_group.public-instance-sg.id]
  tags                   = local.common_tags
}


