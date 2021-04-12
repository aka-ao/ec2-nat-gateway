# AWS基本設定
provider "aws" {
  access_key = var.aws_access_key
  secret_key = var.aws_secret_key
  region     = "ap-northeast-1"
}

resource "aws_vpc" "main" {
  cidr_block = "10.0.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support = true
  tags = {
    Name = "nat-gateway-vpc"
  }
}

resource "aws_subnet" "public-subnet" {
  cidr_block = "10.0.20.0/24"
  availability_zone = "ap-northeast-1a"
  vpc_id = aws_vpc.main.id
  map_public_ip_on_launch = true
  tags = {
    Name = "natgw-public"
  }
}

resource "aws_subnet" "private-subnet" {
  cidr_block = "10.0.10.0/24"
  availability_zone = "ap-northeast-1a"
  vpc_id = aws_vpc.main.id
  map_public_ip_on_launch = false
  tags = {
    Name = "natgw-private"
  }
}

resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "natgw"
  }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id
  tags = {
    Name = "public-rt"
  }
}

resource "aws_route" "public" {
  route_table_id = aws_route_table.public.id
  gateway_id = aws_internet_gateway.main.id
  destination_cidr_block = "0.0.0.0/0"
}

resource "aws_route_table_association" "public" {
  route_table_id = aws_route_table.public.id
  subnet_id = aws_subnet.public-subnet.id
}

resource "aws_route_table" "private_1a" {
  vpc_id = aws_vpc.main.id
  tags = {
    Name = "private-rt"
  }
}

resource "aws_eip" "nat_1a" {
  vpc = true
  depends_on = [aws_internet_gateway.main]
  tags = {
    Name = "natgw-1a"
  }
}

resource "aws_nat_gateway" "nat_1a" {
  subnet_id     = aws_subnet.public-subnet.id
  allocation_id = aws_eip.nat_1a.id
  depends_on = [aws_internet_gateway.main]

  tags = {
    Name = "natgw-1a"
  }
}

resource "aws_route" "private_a1" {
  destination_cidr_block = "0.0.0.0/0"
  route_table_id = aws_route_table.private_1a.id
  nat_gateway_id = aws_nat_gateway.nat_1a.id
}

resource "aws_route_table_association" "private" {
  subnet_id = aws_subnet.private-subnet.id
  route_table_id = aws_route_table.private_1a.id
}

resource "aws_key_pair" "nat-gateway" {
  public_key = file("~/.ssh/id_rsa.pub")
}

resource "aws_security_group" "natgw-sg" {
  vpc_id = aws_vpc.main.id
  name = "natgw-sg"
  ingress {
    from_port = 80
    protocol = "TCP"
    to_port = 80
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port = 22
    protocol = "TCP"
    to_port = 22
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port       = 0
    to_port         = 0
    protocol        = "-1"
    cidr_blocks     = ["0.0.0.0/0"]
  }
}

resource "aws_instance" "ec2" {
  ami           = "ami-0bc8ae3ec8e338cbc"
  instance_type = "t2.micro"
  subnet_id     = aws_subnet.private-subnet.id
  key_name      = aws_key_pair.nat-gateway.id
  tags = {
    Name = "nat-gateway-ec2"
  }
  security_groups = [aws_security_group.natgw-sg.id]

  user_data = <<EOF
  #!/bin/bash
  sudo yum install -y httpd
  sudo yum install -y mysql
  sudo systemctl start httpd
  sudo systemctl enable httpd
  sudo usermod -a -G apache ec2-user
  sudo chown -R ec2-user:apache /var/www
  sudo chmod 2775 /var/www
  find /var/www -type d -exec chmod 2775 {} \;
  find /var/www -type f -exec chmod 0664 {} \;
  echo `hostname` > /var/www/html/index.html
  EOF
}


resource "aws_instance" "public" {
  ami           = "ami-0bc8ae3ec8e338cbc"
  instance_type = "t2.micro"
  subnet_id     = aws_subnet.public-subnet.id
  key_name      = aws_key_pair.nat-gateway.id
  tags = {
    Name = "nat-gateway-ec2-public"
  }
  security_groups = [aws_security_group.natgw-sg.id]
}

resource "aws_eip" "public" {
  vpc = true
  instance = aws_instance.public.id
  depends_on = [aws_instance.public]
}