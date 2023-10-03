# Configure the AWS Provider
provider "aws" {
  region  = "us-west-1"
  profile = "myprofile"
}


# Create a VPC
resource "aws_vpc" "fargate_vpc" {
  cidr_block = "10.0.0.0/16"

  tags = {
    Name = "fargate-vpc"
  }
}


# create internet gateway
resource "aws_internet_gateway" "gw" {
  vpc_id = aws_vpc.fargate_vpc.id

  tags = {
    Name = "GW"
  }
}


# create route tables
resource "aws_route_table" "fargate_rt" {
  vpc_id = aws_vpc.fargate_vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.gw.id
  }

  route {
    ipv6_cidr_block = "::/0"
    gateway_id      = aws_internet_gateway.gw.id
  }

  tags = {
    Name = "fargate-rt"
  }
}


# create subnets
resource "aws_subnet" "subnet_1" {
  vpc_id            = aws_vpc.fargate_vpc.id
  cidr_block        = "10.0.1.0/24"
  availability_zone = "us-west-1a" # Replace with your desired AZ
}

resource "aws_subnet" "subnet_2" {
  vpc_id            = aws_vpc.fargate_vpc.id
  cidr_block        = "10.0.2.0/24"
  availability_zone = "us-west-1c" # Replace with your desired AZ
}


# Associate route table with subnet
resource "aws_route_table_association" "a" {
  subnet_id      = aws_subnet.subnet_1.id
  route_table_id = aws_route_table.fargate_rt.id
}

resource "aws_route_table_association" "b" {
  subnet_id      = aws_subnet.subnet_2.id
  route_table_id = aws_route_table.fargate_rt.id
}


# create security groups
resource "aws_security_group" "allow_web" {
  name        = "allow_web_traffic"
  description = "Allow TLS inbound traffic"
  vpc_id      = aws_vpc.fargate_vpc.id

  ingress {
    description = "HTTPS from VPC"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "HTTP from VPC"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "SSH from VPC"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }


  tags = {
    Name = "allow_web"
  }
}


# create amazon ecs cluster
resource "aws_ecs_cluster" "fargate_cluster" {
  name = "my-fargate-cluster"
}


# create amazon ecs task definition
resource "aws_ecs_task_definition" "fargate_task" {
  family                   = "my-fargate-task"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = "256" # CPU units
  memory                   = "512" # Memory in MiB

  execution_role_arn = aws_iam_role.ecs_execution_role.arn

  container_definitions = jsonencode([{
    "name" : "my-container",
    "image" : "nginx:latest",
    "portMappings" : [{
      "containerPort" : 80,
      "hostPort" : 80
    }]
  }])
}


# amazom iam role
resource "aws_iam_role" "ecs_execution_role" {
  name = "ecs_execution_role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Sid    = ""
        Principal = {
          Service = "ecs-tasks.amazonaws.com"
        }
      }
    ]
  })
}


resource "aws_ecs_service" "my_service" {
  name            = "my-fargate-service"
  cluster         = aws_ecs_cluster.fargate_cluster.id
  task_definition = aws_ecs_task_definition.fargate_task.arn
  launch_type     = "FARGATE"

  network_configuration {
    subnets         = [aws_subnet.subnet_1.id]          # Replace with your subnet IDs
    security_groups = [aws_security_group.allow_web.id] # Replace with your security group IDs
  }

  depends_on = [aws_iam_role.ecs_execution_role]
}



