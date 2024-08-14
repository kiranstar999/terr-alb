resource "aws_vpc" "hfvpc" {
  cidr_block       = "10.0.0.0/24"
  instance_tenancy = "default"

  tags = {
    Name = "hfvpc"
  }
}
resource "aws_subnet" "public-subnet-1a" {
  vpc_id            = aws_vpc.hfvpc.id
  cidr_block        = "10.0.0.0/26"
  availability_zone = "us-east-1a"
  tags = {
    Name = "public-subnet-1a"
  }
}
resource "aws_subnet" "public-subnet-1b" {
  vpc_id            = aws_vpc.hfvpc.id
  cidr_block        = "10.0.0.64/26"
  availability_zone = "us-east-1b"
  tags = {
    Name = "public-subnet-1b"
  }
}
resource "aws_subnet" "private-subnet-1a" {
  vpc_id            = aws_vpc.hfvpc.id
  cidr_block        = "10.0.0.128/26"
  availability_zone = "us-east-1a"
  tags = {
    Name = "private-subnet-1a"
  }
}
resource "aws_subnet" "private-subnet-1b" {
  vpc_id            = aws_vpc.hfvpc.id
  cidr_block        = "10.0.0.192/26"
  availability_zone = "us-east-1b"
  tags = {
    Name = "private-subnet-1b"
  }
}
resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.hfvpc.id

  tags = {
    Name = "igw"
  }
}
resource "aws_route_table" "public-rt" {
  vpc_id = aws_vpc.hfvpc.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }
  tags = {
    Name = "public-rt"
  }
}
resource "aws_eip" "eip" {
  tags = {
    Name = "eip"
  }
}
resource "aws_nat_gateway" "nat" {
  allocation_id = aws_eip.eip.id
  subnet_id     = aws_subnet.public-subnet-1b.id
  tags = {
    Name = "nat"
  }
}
resource "aws_route_table" "private-rt" {
  vpc_id = aws_vpc.hfvpc.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_nat_gateway.nat.id
  }
  tags = {
    Name = "private-rt"
  }
  depends_on = [aws_nat_gateway.nat]
}

resource "aws_route_table_association" "a" {
  subnet_id      = aws_subnet.public-subnet-1a.id
  route_table_id = aws_route_table.public-rt.id
}
resource "aws_route_table_association" "b" {
  subnet_id      = aws_subnet.public-subnet-1b.id
  route_table_id = aws_route_table.public-rt.id
}
resource "aws_route_table_association" "pa" {
  subnet_id      = aws_subnet.private-subnet-1a.id
  route_table_id = aws_route_table.private-rt.id
}
resource "aws_route_table_association" "pb" {
  subnet_id      = aws_subnet.private-subnet-1b.id
  route_table_id = aws_route_table.private-rt.id
}
resource "aws_security_group" "public-sg" {
  name        = "allow 22,80 allow"
  description = "Allow TLS inbound traffic"
  vpc_id      = aws_vpc.hfvpc.id

  ingress {
    description = "allow 22"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    description = "allow 80"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port        = 0
    to_port          = 0
    protocol         = "-1"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }

  tags = {
    Name = "public-sg"
  }
}
resource "aws_security_group" "private-sg" {
  name        = "allow 22,80"
  description = "Allow TLS inbound traffic"
  vpc_id      = aws_vpc.hfvpc.id

  ingress {
    description = "allow 22"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["10.0.0.0/26", "10.0.0.64/26"]
  }
  ingress {
    description = "allow 3306"
    from_port   = 3306
    to_port     = 3306
    protocol    = "tcp"
    cidr_blocks = ["10.0.0.0/26", "10.0.0.64/26"]
  }
  egress {
    from_port        = 0
    to_port          = 0
    protocol         = "-1"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }

  tags = {
    Name = "private-sg"
  }
}
resource "aws_instance" "pubIns" {
  ami                         = "ami-005f9685cb30f234b" # us-west-2
  instance_type               = "t2.micro"
  subnet_id                   = aws_subnet.public-subnet-1a.id
  key_name                    = "Jan23"
  security_groups             = [aws_security_group.public-sg.id]
  associate_public_ip_address = true
  user_data                   = <<EOF
  #!/bin/bash
  yum update -y
  yum install httpd -y
  systemctl restart httpd
  echo "Welcome to server - $(hostname -f)" > /var/www/html/index.html
  EOF
  tags = {
    Name = "pubIns"
  }
}
resource "aws_instance" "PriIns" {
  ami             = "ami-005f9685cb30f234b" # us-west-2
  instance_type   = "t2.micro"
  subnet_id       = aws_subnet.private-subnet-1a.id
  key_name        = "Jan23"
  security_groups = [aws_security_group.private-sg.id]
  user_data       = <<EOF
  #!/bin/bash
  yum update -y
  yum install mysql -y
  systemctl restart mysql
  EOF
  tags = {
    Name = "PriIns"
  }
  depends_on = [aws_nat_gateway.nat, aws_route_table_association.pb]
}
resource "aws_lb" "alb" {
  name               = "Application-lb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.public-sg.id]
  subnets            = [aws_subnet.public-subnet-1a.id, aws_subnet.public-subnet-1b.id]

  tags = {
    Environment = "alb"
  }
}
resource "aws_lb_target_group" "webtg" {
  name     = "web-lb-tg"
  port     = 80
  protocol = "HTTP"
  vpc_id   = aws_vpc.hfvpc.id
}
resource "aws_lb_target_group_attachment" "test" {
  target_group_arn = aws_lb_target_group.webtg.arn
  target_id        = aws_instance.pubIns.id
  port             = 80
  depends_on       = [aws_lb_target_group.webtg]
}
resource "aws_lb_listener" "front_end" {
  load_balancer_arn = aws_lb.alb.arn
  port              = "80"
  protocol          = "HTTP"
  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.webtg.arn
  }
  depends_on = [aws_lb_target_group_attachment.test]
}