provider "aws" {
  profile = "default"
  region  = "eu-west-2"
}

resource "aws_vpc" "target" {
  cidr_block = "10.0.0.0/24"
  tags = {
    Name = var.name[0]
  }
}

resource "aws_vpc" "agent" {
  cidr_block           = "10.100.100.0/24"
  tags = {
    Name = var.name[1]
  }
}

resource "aws_subnet" "targetSubnet" {
  vpc_id                  = aws_vpc.target.id
  cidr_block              = "10.0.0.0/26"
  map_public_ip_on_launch = true
  availability_zone       = "eu-west-2a"
  tags = {
    Name = var.name[0]
  }
}

resource "aws_subnet" "agentSubnet" {
  vpc_id                  = aws_vpc.agent.id
  cidr_block              = "10.100.100.0/26"
  map_public_ip_on_launch = true
  availability_zone       = "eu-west-2a" # Required as Interface endpoint not supported in AZ1 and AZ3
  tags = {
    Name = var.name[1]
  }
}

resource "aws_internet_gateway" "targetIGW" {
  vpc_id = aws_vpc.target.id
  tags = {
    Name = var.name[0]
  }
}

resource "aws_internet_gateway" "agentIGW" {
  vpc_id = aws_vpc.agent.id
  tags = {
    Name = var.name[1]
  }
}

resource "aws_route" "targetInetAccess" {
  route_table_id         = aws_vpc.target.main_route_table_id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.targetIGW.id
}

resource "aws_route" "agentInetAccess" {
  route_table_id         = aws_vpc.agent.main_route_table_id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.agentIGW.id
}

resource "aws_security_group" "agentEndpointSG" {
  name   = "agentEndpointSG"
  vpc_id = aws_vpc.agent.id

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [aws_subnet.agentSubnet.cidr_block] # In [] because it's a list
  }
  tags = {
    Name = var.name[1]
  }
}

resource "aws_security_group" "targetAmiSG" {
  name   = "targetAmiSG"
  vpc_id = aws_vpc.target.id

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["82.68.125.46/32", aws_subnet.agentSubnet.cidr_block, aws_subnet.targetSubnet.cidr_block]
  }
  tags = {
    Name = var.name[0]
  }
}

resource "aws_security_group" "agentAmiSG" {
  name   = "agentAmiSG"
  vpc_id = aws_vpc.agent.id

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["82.68.125.46/32"]
  }
  tags = {
    Name = var.name[1]
  }
}

resource "aws_lb" "privateLinkNLB" {
  name               = "privateLinkNLB"
  internal           = true
  load_balancer_type = "network"
  subnets            = [aws_subnet.targetSubnet.id]
}

resource "aws_lb_target_group" "targetTG" {
  name     = "targetTG"
  port     = 22
  protocol = "TCP"
  vpc_id   = aws_vpc.target.id
  health_check {
    port     = 22
    protocol = "TCP"
  }
}

resource "aws_lb_target_group_attachment" "targetAttach" {
  target_group_arn = aws_lb_target_group.targetTG.arn
  target_id        = aws_instance.targetEC2.id
  port             = 22
}

resource "aws_lb_listener" "privateLinkNLB" {
  load_balancer_arn = aws_lb.privateLinkNLB.arn
  port              = "22"
  protocol          = "TCP"
  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.targetTG.arn
  }
}

resource "aws_vpc_endpoint_service" "targetEndpoint" {
  acceptance_required        = false
  network_load_balancer_arns = [aws_lb.privateLinkNLB.arn]
}

resource "aws_vpc_endpoint" "agentEndpoint" {
  vpc_id              = aws_vpc.agent.id
  service_name        = aws_vpc_endpoint_service.targetEndpoint.service_name
  vpc_endpoint_type   = "Interface"
  security_group_ids  = [aws_security_group.agentEndpointSG.id]
  subnet_ids          = [aws_subnet.agentSubnet.id]
}

resource "aws_key_pair" "chrisKey" {
  key_name   = "chrisKey"
  public_key = "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQC5maRkyxqPSYagtBpg00tNnTvjdYvnKTIworAp0mceVFxefDu/8Zw/dSrznq0Jz1fzbKXSElf05wKEO6TCV6Wy2bMG1BvTgiyDA/BXUwcyKnu3sJwUY2KzRGvvGIFlTboRhI3C+E5qijTwyINfcNUFRvYZtCm6BrfCO5762sJezMLYUIFnQjqNgjBx7ezDP4/u1h7EEBdqUd8MhaYloszQMymfFf2hkLd53yubwOUw0V7VMmZuuBvUmto1sQl7W9+amHCqkoDwN9lOetQxE8gIDZ+FvEe8SPIMolX70XDGvIJL09Ne8Xq85EhBb55BYwM5rIa+ZnVQOTkwyzHcQJ1r chris@3waremac.localnet"
}

resource "aws_instance" "targetEC2" {
  ami                    = "ami-0271d331ac7dab654"
  instance_type          = "t2.micro"
  subnet_id              = aws_subnet.targetSubnet.id
  vpc_security_group_ids = [aws_security_group.targetAmiSG.id]
  key_name               = aws_key_pair.chrisKey.id
  tags = {
    Name = var.name[0]
  }
}

resource "aws_instance" "agentEC2" {
  ami                    = "ami-0271d331ac7dab654"
  instance_type          = "t2.micro"
  subnet_id              = aws_subnet.agentSubnet.id
  vpc_security_group_ids = [aws_security_group.agentAmiSG.id]
  key_name               = aws_key_pair.chrisKey.id
  tags = {
    Name = var.name[1]
  }
}
