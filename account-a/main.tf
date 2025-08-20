terraform {
  required_version = ">= 1.5"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region  = var.aws_region
  profile = var.aws_profile_a
}

# Data sources
data "aws_availability_zones" "available" {
  state = "available"
}

# VPC A
resource "aws_vpc" "vpc_a" {
  cidr_block           = var.vpc_a_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name = "vpc-a-droppy"
  }
}

# Internet Gateway
resource "aws_internet_gateway" "igw_a" {
  vpc_id = aws_vpc.vpc_a.id

  tags = {
    Name = "igw-vpc-a"
  }
}

# Public Subnets (2)
resource "aws_subnet" "public_a" {
  count                   = 2
  vpc_id                  = aws_vpc.vpc_a.id
  cidr_block              = "10.0.${count.index + 1}.0/24"
  availability_zone       = data.aws_availability_zones.available.names[count.index]
  map_public_ip_on_launch = true

  tags = {
    Name = "public-subnet-a-${count.index + 1}"
    Type = "Public"
  }
}

# Private Load Balancer Subnets (2)
resource "aws_subnet" "private_lb_a" {
  count             = 2
  vpc_id            = aws_vpc.vpc_a.id
  cidr_block        = "10.0.${count.index + 10}.0/24"
  availability_zone = data.aws_availability_zones.available.names[count.index]

  tags = {
    Name = "private-lb-subnet-a-${count.index + 1}"
    Type = "Private-LB"
  }
}

# Private ECS Subnets (2)
resource "aws_subnet" "private_ecs_a" {
  count             = 2
  vpc_id            = aws_vpc.vpc_a.id
  cidr_block        = "10.0.${count.index + 20}.0/24"
  availability_zone = data.aws_availability_zones.available.names[count.index]

  tags = {
    Name = "private-ecs-subnet-a-${count.index + 1}"
    Type = "Private-ECS"
  }
}

# Intra Subnets (2) - Isolated for EFS
resource "aws_subnet" "intra_a" {
  count             = 2
  vpc_id            = aws_vpc.vpc_a.id
  cidr_block        = "10.0.${count.index + 30}.0/24"
  availability_zone = data.aws_availability_zones.available.names[count.index]

  tags = {
    Name = "intra-subnet-a-${count.index + 1}"
    Type = "Intra"
  }
}

# NAT Gateway
resource "aws_eip" "nat_a" {
  domain = "vpc"
  tags = {
    Name = "nat-eip-a"
  }
}

resource "aws_nat_gateway" "nat_a" {
  allocation_id = aws_eip.nat_a.id
  subnet_id     = aws_subnet.public_a[0].id

  tags = {
    Name = "nat-gateway-a"
  }

  depends_on = [aws_internet_gateway.igw_a]
}

# Route Tables
resource "aws_route_table" "public_a" {
  vpc_id = aws_vpc.vpc_a.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw_a.id
  }

  tags = {
    Name = "rt-public-a"
  }
}

resource "aws_route_table" "private_a" {
  vpc_id = aws_vpc.vpc_a.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.nat_a.id
  }

  tags = {
    Name = "rt-private-a"
  }
}

resource "aws_route_table" "intra_a" {
  vpc_id = aws_vpc.vpc_a.id

  tags = {
    Name = "rt-intra-a"
  }
}

# Route Table Associations
resource "aws_route_table_association" "public_a" {
  count          = 2
  subnet_id      = aws_subnet.public_a[count.index].id
  route_table_id = aws_route_table.public_a.id
}

resource "aws_route_table_association" "private_lb_a" {
  count          = 2
  subnet_id      = aws_subnet.private_lb_a[count.index].id
  route_table_id = aws_route_table.private_a.id
}

resource "aws_route_table_association" "private_ecs_a" {
  count          = 2
  subnet_id      = aws_subnet.private_ecs_a[count.index].id
  route_table_id = aws_route_table.private_a.id
}

resource "aws_route_table_association" "intra_a" {
  count          = 2
  subnet_id      = aws_subnet.intra_a[count.index].id
  route_table_id = aws_route_table.intra_a.id
}

# Security Groups
resource "aws_security_group" "alb_sg" {
  name        = "alb-sg"
  description = "Security group for internal ALB"
  vpc_id      = aws_vpc.vpc_a.id

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = [var.vpc_a_cidr, var.vpc_b_cidr]
  }

  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = [var.vpc_a_cidr, var.vpc_b_cidr]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "alb-security-group"
  }
}

resource "aws_security_group" "ecs_sg" {
  name        = "ecs-sg"
  description = "Security group for ECS tasks"
  vpc_id      = aws_vpc.vpc_a.id

  ingress {
    from_port       = 8989
    to_port         = 8989
    protocol        = "tcp"
    security_groups = [aws_security_group.alb_sg.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "ecs-security-group"
  }
}

resource "aws_security_group" "efs_sg" {
  name        = "efs-sg"
  description = "Security group for EFS"
  vpc_id      = aws_vpc.vpc_a.id

  ingress {
    from_port       = 2049
    to_port         = 2049
    protocol        = "tcp"
    security_groups = [aws_security_group.ecs_sg.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "efs-security-group"
  }
}

# EFS File System
resource "aws_efs_file_system" "droppy_efs" {
  creation_token = "droppy-efs"
  encrypted      = true

  tags = {
    Name = "droppy-efs"
  }
}

resource "aws_efs_mount_target" "droppy_efs_mt" {
  count           = 2
  file_system_id  = aws_efs_file_system.droppy_efs.id
  subnet_id       = aws_subnet.intra_a[count.index].id
  security_groups = [aws_security_group.efs_sg.id]
}

# Application Load Balancer
resource "aws_lb" "droppy_alb" {
  name               = "droppy-internal-alb"
  internal           = true
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb_sg.id]
  subnets            = aws_subnet.private_lb_a[*].id

  tags = {
    Name = "droppy-internal-alb"
  }
}

resource "aws_lb_target_group" "droppy_tg" {
  name        = "droppy-tg"
  port        = 8989
  protocol    = "HTTP"
  vpc_id      = aws_vpc.vpc_a.id
  target_type = "ip"

  health_check {
    enabled             = true
    healthy_threshold   = 2
    interval            = 30
    matcher             = "200"
    path                = "/"
    port                = "traffic-port"
    protocol            = "HTTP"
    timeout             = 5
    unhealthy_threshold = 2
  }

  tags = {
    Name = "droppy-target-group"
  }
}

resource "aws_lb_listener" "droppy_listener" {
  load_balancer_arn = aws_lb.droppy_alb.arn
  port              = "80"
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.droppy_tg.arn
  }
}

# ECS Cluster
resource "aws_ecs_cluster" "droppy_cluster" {
  name = "droppy-cluster"

  setting {
    name  = "containerInsights"
    value = "enabled"
  }

  tags = {
    Name = "droppy-cluster"
  }
}

# IAM Roles
resource "aws_iam_role" "ecs_execution_role" {
  name = "ecs-execution-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ecs-tasks.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "ecs_execution_role_policy" {
  role       = aws_iam_role.ecs_execution_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

resource "aws_iam_role" "ecs_task_role" {
  name = "ecs-task-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ecs-tasks.amazonaws.com"
        }
      }
    ]
  })
}

# CloudWatch Logs
resource "aws_cloudwatch_log_group" "droppy_logs" {
  name              = "/ecs/droppy"
  retention_in_days = 7

  tags = {
    Name = "droppy-logs"
  }
}

# ECS Task Definition
resource "aws_ecs_task_definition" "droppy_task" {
  family                   = "droppy"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = 256
  memory                   = 512
  execution_role_arn       = aws_iam_role.ecs_execution_role.arn
  task_role_arn            = aws_iam_role.ecs_task_role.arn

  container_definitions = jsonencode([
    {
      name  = "droppy"
      image = "ghcr.io/droppyjs/droppy:latest"
      portMappings = [
        {
          containerPort = 8989
          protocol      = "tcp"
        }
      ]
      mountPoints = [
        {
          sourceVolume  = "droppy-config"
          containerPath = "/config"
          readOnly      = false
        },
        {
          sourceVolume  = "droppy-data"
          containerPath = "/files"
          readOnly      = false
        }
      ]
      environment = [
        {
          name  = "NODE_ENV"
          value = "production"
        }
      ]
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.droppy_logs.name
          "awslogs-region"        = var.aws_region
          "awslogs-stream-prefix" = "ecs"
        }
      }
      essential = true
      healthCheck = {
        command = [
          "CMD-SHELL",
          "curl -f http://localhost:8989/ || exit 1"
        ]
        interval    = 30
        timeout     = 5
        retries     = 3
        startPeriod = 60
      }
    }
  ])

  volume {
    name = "droppy-config"
    efs_volume_configuration {
      file_system_id = aws_efs_file_system.droppy_efs.id
      root_directory = "/config"
    }
  }

  volume {
    name = "droppy-data"
    efs_volume_configuration {
      file_system_id = aws_efs_file_system.droppy_efs.id
      root_directory = "/files"
    }
  }

  tags = {
    Name = "droppy-task-definition"
  }
}

# ECS Service
resource "aws_ecs_service" "droppy_service" {
  name            = "droppy-service"
  cluster         = aws_ecs_cluster.droppy_cluster.id
  task_definition = aws_ecs_task_definition.droppy_task.arn
  desired_count   = 2
  launch_type     = "FARGATE"

  network_configuration {
    subnets         = aws_subnet.private_ecs_a[*].id
    security_groups = [aws_security_group.ecs_sg.id]
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.droppy_tg.arn
    container_name   = "droppy"
    container_port   = 8989
  }

  depends_on = [aws_lb_listener.droppy_listener]

  tags = {
    Name = "droppy-service"
  }
}
