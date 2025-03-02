resource "aws_vpc" "main" {
  cidr_block = "10.50.0.0/16"

  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = "main-vpc"
  }
}

resource "aws_subnet" "fargate_subnet" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.50.1.0/24"
  availability_zone       = "us-east-1a"
  map_public_ip_on_launch = true

  tags = {
    Name = "fargate_subnet"
  }
}
resource "aws_internet_gateway" "gw" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "main-igw"
  }
}
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.gw.id
  }

  tags = {
    Name = "public-route-table"
  }
}


resource "aws_route_table_association" "public_assoc" {
  subnet_id      = aws_subnet.fargate_subnet.id
  route_table_id = aws_route_table.public.id
}



resource "aws_ecs_cluster" "fargate_cluster" {
  name = "fargate-cluster"
}

resource "aws_ecs_task_definition" "grafana_task" {
  family                   = "grafana-task"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = "512"
  memory                   = "1024"

  execution_role_arn = aws_iam_role.ecs_task_execution_role.arn

  container_definitions = jsonencode([
    {
      name  = "grafana"
      image = "grafana/grafana:latest"
      portMappings = [
        {
          containerPort = 3000
        }
      ]
    }
  ])
}

resource "aws_ecs_task_definition" "nginx_task" {
  family                   = "nginx-task"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = "512"
  memory                   = "1024"

  execution_role_arn = aws_iam_role.ecs_task_execution_role.arn

  container_definitions = jsonencode([
    {
      name  = "nginx"
      image = "nginx:latest"
      portMappings = [
        {
          containerPort = 80
        }
      ]
    }
  ])
}

resource "aws_ecs_service" "grafana_service" {
  name            = "grafana-service"
  cluster        = aws_ecs_cluster.fargate_cluster.id
  task_definition = aws_ecs_task_definition.grafana_task.arn
  launch_type     = "FARGATE"

  network_configuration {
    subnets         = [aws_subnet.fargate_subnet.id]
    security_groups = [aws_security_group.allow_all.id]
    assign_public_ip = true
  }

  desired_count = 1
}

resource "aws_ecs_service" "nginx_service" {
  name            = "nginx-service"
  cluster        = aws_ecs_cluster.fargate_cluster.id
  task_definition = aws_ecs_task_definition.nginx_task.arn
  launch_type     = "FARGATE"

  network_configuration {
    subnets         = [aws_subnet.fargate_subnet.id]
    security_groups = [aws_security_group.allow_all.id]
    assign_public_ip = true
  }

  desired_count = 1
}

resource "aws_security_group" "allow_all" {
  name_prefix = "allow-all"
  vpc_id      = aws_vpc.main.id

  ingress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_iam_role" "ecs_task_execution_role" {
  name = "ecsTaskExecutionRole"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "ecs-tasks.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "ecs_task_execution_policy" {
  role       = aws_iam_role.ecs_task_execution_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}