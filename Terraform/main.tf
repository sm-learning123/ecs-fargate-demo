# Provider configuration
provider "aws" {
  region = var.ecs-demo["region"]
}

# Terraform settings
terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 4.59.0"
    }
  }
}

terraform {
  backend "s3" {
    bucket  = "tfstate-backup-9"
    key     = "terraform.tfstate"
    region  = var.ecs-demo["region"]
    encrypt = true
  }
}

# VPC config
resource "aws_default_vpc" "default" {
  tags = {
    Name = "Default VPC"
  }
}

data "aws_subnets" "demo-subnet" {
  filter {
    name   = "vpc-id"
    values = [aws_default_vpc.default.id]
  }
}

#IAM configuration

data "aws_iam_policy_document" "ecs-task-execution-role" {
  version = "2012-10-17"
  statement {
    sid     = ""
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }
  }
}

# ECS task execution role
resource "aws_iam_role" "ecs-task-execution-role" {
  name               = "myECcsTaskExecutionRole"
  assume_role_policy = data.aws_iam_policy_document.ecs-task-execution-role.json
}

# ECS task execution role policy attachment
resource "aws_iam_role_policy_attachment" "ecs-task-execution-role" {
  role       = aws_iam_role.ecs-task-execution-role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

# security group
resource "aws_security_group" "demo-sg" {
  name        = "demo security group"
  description = "allow inbound access"
  vpc_id      = aws_default_vpc.default.id

  ingress {
    protocol    = "tcp"
    from_port   = 80
    to_port     = 80
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    protocol    = "tcp"
    from_port   = 3000
    to_port     = 3000
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    protocol    = "-1"
    from_port   = 0
    to_port     = 0
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# ECS configuration

resource "aws_ecs_cluster" "demo-ecs-cluster" {
  name = "demo-ecs-cluster"
}

resource "aws_ecs_task_definition" "demo-ecs-task-definition" {
  family                   = "demo-ecs-task-definition"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = 512
  memory                   = 1024
  execution_role_arn       = aws_iam_role.ecs-task-execution-role.arn
  task_role_arn            = aws_iam_role.ecs-task-execution-role.arn
  container_definitions = jsonencode([{
    name      = "demoapp"
    image     = "${data.aws_ecr_repository.demoapp.repository_url}:latest"
    essential = true
    portMappings = [{
      protocol      = "tcp"
      containerPort = 3000
      hostPort      = 3000
    }]
  }])
}

resource "aws_ecs_service" "demo-ecs-service" {
  name            = "demo-ecs-service"
  cluster         = aws_ecs_cluster.demo-ecs-cluster.id
  task_definition = aws_ecs_task_definition.demo-ecs-task-definition.arn
  desired_count   = 2
  launch_type     = "FARGATE"

  network_configuration {
    security_groups  = [aws_security_group.demo-sg.id]
    subnets          = data.aws_subnets.demo-subnet.ids
    assign_public_ip = true
  }
  load_balancer {
    target_group_arn = aws_lb_target_group.demo-lb.arn
    container_name   = "demoapp"
    container_port   = 3000
  }

  depends_on = [aws_iam_role_policy_attachment.ecs-task-execution-role]
}

data "aws_ecr_repository" "demoapp" {
  name = "demoapp"
}



resource "aws_lb" "default" {
  name               = "demo-lb"
  subnets            = data.aws_subnets.demo-subnet.ids
  security_groups    = [aws_security_group.demo-sg.id]
  internal           = false
  ip_address_type    = "ipv4"
  load_balancer_type = "application"
  tags = {
    Environment = "demo-lb"
  }
}

resource "aws_lb_target_group" "demo-lb" {
  name        = "demo-lb"
  port        = 80
  protocol    = "HTTP"
  vpc_id      = aws_default_vpc.default.id
  target_type = "ip"
  stickiness {
    enabled = true
    type    = "lb_cookie"
  }
  health_check {
    path                = "/"
    healthy_threshold   = 6
    unhealthy_threshold = 2
    timeout             = 2
    interval            = 5
    matcher             = "200,302"
  }
}

resource "aws_lb_listener" "demo-lb" {
  load_balancer_arn = aws_lb.default.id
  port              = "80"
  protocol          = "HTTP"

  default_action {
    target_group_arn = aws_lb_target_group.demo-lb.arn
    type             = "forward"
  }
}
