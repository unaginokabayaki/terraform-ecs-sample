# ==========================================
# AWS Provider Configuration
# ==========================================
# 東京リージョン(ap-northeast-1)を使用
provider "aws" {
  region = "ap-northeast-1"
}

# ==========================================
# Variables
# ==========================================
variable "project_name" {
  description = "Project name for resource naming"
  type        = string
  default     = "ecs-handson"
}

variable "vpc_cidr" {
  description = "CIDR block for VPC"
  type        = string
  default     = "10.1.0.0/16"
}

variable "ecs_task_cpu" {
  description = "CPU units for ECS task (256 = 0.25 vCPU)"
  type        = string
  default     = "256"
  # Note: Fargateでは 256, 512, 1024, 2048, 4096 のいずれかを指定
}

variable "ecs_task_memory" {
  description = "Memory for ECS task in MB"
  type        = string
  default     = "512"
  # Note: CPU値に応じて選択可能なメモリ値が制限される
  # CPU 256: 512, 1024, 2048
  # CPU 512: 1024 ~ 4096 (1GBごと)
}

variable "ecs_desired_count" {
  description = "Desired number of ECS tasks"
  type        = number
  default     = 2
  # Note: 本番環境では最低2以上を推奨(可用性確保のため)
}

# ==========================================
# VPC & Network
# ==========================================

# メインVPC
resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true  # ECSタスクがDNS名を取得するために必須
  enable_dns_support   = true  # VPC内でのDNS解決を有効化

  tags = {
    Name = "${var.project_name}-vpc"
  }
}

# インターネットゲートウェイ
# パブリックサブネットからインターネットへの通信を可能にする
resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "${var.project_name}-igw"
  }
}

# パブリックサブネット 1a
# Note: 本番環境ではプライベートサブネットの使用を推奨
resource "aws_subnet" "public_1a" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.1.1.0/24"  # 256個のIPアドレス
  availability_zone       = "ap-northeast-1a"
  map_public_ip_on_launch = true  # ECSタスクにパブリックIPを自動割り当て

  tags = {
    Name = "${var.project_name}-public-1a"
  }
}

# パブリックサブネット 1c
# Multi-AZ構成で可用性を向上
resource "aws_subnet" "public_1c" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.1.2.0/24"
  availability_zone       = "ap-northeast-1c"
  map_public_ip_on_launch = true

  tags = {
    Name = "${var.project_name}-public-1c"
  }
}

# パブリックサブネット用ルートテーブル
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  # デフォルトルート: すべてのトラフィックをIGWに転送
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }

  tags = {
    Name = "${var.project_name}-public-rt"
  }
}

# ルートテーブルをサブネットに関連付け
resource "aws_route_table_association" "public_1a" {
  subnet_id      = aws_subnet.public_1a.id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table_association" "public_1c" {
  subnet_id      = aws_subnet.public_1c.id
  route_table_id = aws_route_table.public.id
}

# ==========================================
# Security Groups
# ==========================================

# ALB用セキュリティグループ
# インターネットからのHTTPトラフィックを受け付ける
resource "aws_security_group" "alb" {
  name        = "${var.project_name}-alb-sg"
  description = "Security group for ALB"
  vpc_id      = aws_vpc.main.id

  # インバウンドルール: HTTP(80)を全て許可
  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow HTTP from internet"
    # Note: 本番環境ではHTTPS(443)の使用を推奨
  }

  # アウトバウンドルール: 全て許可
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"  # 全プロトコル
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow all outbound traffic"
  }

  tags = {
    Name = "${var.project_name}-alb-sg"
  }
}

# ECSタスク用セキュリティグループ
# ALBからのトラフィックのみを許可
resource "aws_security_group" "ecs_tasks" {
  name        = "${var.project_name}-tasks-sg"
  description = "Security group for ECS tasks"
  vpc_id      = aws_vpc.main.id

  # インバウンドルール: ALBからのHTTP通信のみ許可
  ingress {
    from_port       = 80
    to_port         = 80
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]  # ALBのSGのみ許可
    description     = "Allow traffic from ALB"
  }

  # アウトバウンドルール: 全て許可
  # ECRからのイメージ取得、CloudWatchへのログ送信などに必要
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow all outbound traffic"
  }

  tags = {
    Name = "${var.project_name}-tasks-sg"
  }
}

# ==========================================
# Application Load Balancer
# ==========================================

# ALB本体
resource "aws_lb" "main" {
  name               = "${var.project_name}-alb"
  internal           = false  # インターネット向けALB
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb.id]
  subnets            = [aws_subnet.public_1a.id, aws_subnet.public_1c.id]

  # Note: 削除保護を有効にする場合
  # enable_deletion_protection = true

  tags = {
    Name = "${var.project_name}-alb"
  }
}

# ターゲットグループ
# ALBからのトラフィックを転送する先を定義
resource "aws_lb_target_group" "main" {
  name        = "${var.project_name}-tg"
  port        = 80
  protocol    = "HTTP"
  vpc_id      = aws_vpc.main.id
  target_type = "ip"  # Fargateでは必ず"ip"を指定

  # ヘルスチェック設定
  health_check {
    path                = "/"
    healthy_threshold   = 2    # 2回連続成功でHealthy
    unhealthy_threshold = 10   # 10回連続失敗でUnhealthy
    timeout             = 60   # タイムアウト(秒)
    interval            = 120  # チェック間隔(秒)
    matcher             = "200"  # 正常とみなすHTTPステータスコード
    
    # Note: 上記設定は初回起動時のコンテナ起動時間を考慮した設定
    # アプリケーションが軽量な場合は以下を推奨:
    # timeout = 5, interval = 30, unhealthy_threshold = 3
  }

  # Note: デプロイ時のダウンタイムを最小化
  # deregistration_delay = 30

  tags = {
    Name = "${var.project_name}-tg"
  }
}

# リスナー
# ALBで受け取ったトラフィックをターゲットグループに転送
resource "aws_lb_listener" "main" {
  load_balancer_arn = aws_lb.main.arn
  port              = "80"
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.main.arn
  }

  # Note: HTTPSを使用する場合
  # port = "443"
  # protocol = "HTTPS"
  # certificate_arn = aws_acm_certificate.main.arn
}

# ==========================================
# ECR (Elastic Container Registry)
# ==========================================

# Dockerイメージを保存するリポジトリ
resource "aws_ecr_repository" "main" {
  name                 = "${var.project_name}-app"
  image_tag_mutability = "MUTABLE"  # タグの上書きを許可

  # プッシュ時にイメージスキャンを実行
  image_scanning_configuration {
    scan_on_push = true  # 脆弱性スキャンを有効化
  }

  # Note: 開発環境でのみ使用
  # force_delete = true

  tags = {
    Name = "${var.project_name}-app"
  }
}

# ECRライフサイクルポリシー
# 古いイメージを自動削除してストレージコストを削減
resource "aws_ecr_lifecycle_policy" "main" {
  repository = aws_ecr_repository.main.name

  policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Keep last 10 images"
        selection = {
          tagStatus   = "any"
          countType   = "imageCountMoreThan"
          countNumber = 10  # 最新10個のイメージを保持
        }
        action = {
          type = "expire"
        }
      }
    ]
  })
}

# ==========================================
# IAM Roles
# ==========================================

# ECSタスク実行ロール
# ECRからのイメージ取得、CloudWatchへのログ送信に使用
resource "aws_iam_role" "ecs_task_execution" {
  name = "${var.project_name}-task-execution-role"

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

  tags = {
    Name = "${var.project_name}-task-execution-role"
  }
}

# AWS管理ポリシーをアタッチ
# ECR、CloudWatch Logs、Secrets Managerへのアクセス権限を付与
resource "aws_iam_role_policy_attachment" "ecs_task_execution" {
  role       = aws_iam_role.ecs_task_execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

# ECSタスクロール
# コンテナ内のアプリケーションが使用するロール
resource "aws_iam_role" "ecs_task" {
  name = "${var.project_name}-task-role"

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

  # Note: アプリケーションがAWSサービス(S3, DynamoDBなど)にアクセスする場合、
  # ここに必要なポリシーをアタッチする

  tags = {
    Name = "${var.project_name}-task-role"
  }
}

# ==========================================
# CloudWatch Logs
# ==========================================

# ECSタスクのログを保存するロググループ
resource "aws_cloudwatch_log_group" "ecs" {
  name              = "/ecs/${var.project_name}-app"
  retention_in_days = 7  # ログ保持期間(日)

  # Note: 本番環境では30日以上を推奨
  # コスト削減のため、不要なログは短期間で削除

  tags = {
    Name = "${var.project_name}-logs"
  }
}

# ==========================================
# ECS Cluster
# ==========================================

# ECSクラスター
resource "aws_ecs_cluster" "main" {
  name = "${var.project_name}-cluster"

  # Container Insightsを有効化
  # タスクレベルのメトリクスを収集
  setting {
    name  = "containerInsights"
    value = "enabled"
  }

  # Note: Container Insightsは追加料金が発生するため、
  # 開発環境では無効化することも検討

  tags = {
    Name = "${var.project_name}-cluster"
  }
}

# ==========================================
# ECS Task Definition
# ==========================================

# タスク定義
# コンテナの構成を定義
resource "aws_ecs_task_definition" "main" {
  family                   = "${var.project_name}-app"
  network_mode             = "awsvpc"  # Fargateでは必須
  requires_compatibilities = ["FARGATE"]
  cpu                      = var.ecs_task_cpu
  memory                   = var.ecs_task_memory
  execution_role_arn       = aws_iam_role.ecs_task_execution.arn
  task_role_arn            = aws_iam_role.ecs_task.arn

  # コンテナ定義
  container_definitions = jsonencode([
    {
      name  = "app"
      image = "${aws_ecr_repository.main.repository_url}:latest"

      # ポートマッピング
      portMappings = [
        {
          containerPort = 80
          hostPort      = 80
          protocol      = "tcp"
        }
      ]

      # CloudWatch Logsの設定
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.ecs.name
          "awslogs-region"        = "ap-northeast-1"
          "awslogs-stream-prefix" = "ecs"
        }
      }

      essential = true  # このコンテナが停止したらタスク全体を停止

      # Note: 環境変数を設定する場合
      # environment = [
      #   {
      #     name  = "ENV_VAR_NAME"
      #     value = "value"
      #   }
      # ]

      # Note: Secrets Managerから機密情報を取得する場合
      # secrets = [
      #   {
      #     name      = "DB_PASSWORD"
      #     valueFrom = "arn:aws:secretsmanager:region:account:secret:name"
      #   }
      # ]
    }
  ])

  tags = {
    Name = "${var.project_name}-task-definition"
  }
}

# ==========================================
# ECS Service
# ==========================================

# ECSサービス
# タスクを継続的に実行し、desired_count を維持
resource "aws_ecs_service" "main" {
  name            = "${var.project_name}-service"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.main.arn
  desired_count   = var.ecs_desired_count
  launch_type     = "FARGATE"

  # ネットワーク設定
  network_configuration {
    subnets          = [aws_subnet.public_1a.id, aws_subnet.public_1c.id]
    security_groups  = [aws_security_group.ecs_tasks.id]
    assign_public_ip = true  # パブリックサブネットではtrueが必要
  }

  # ロードバランサー設定
  load_balancer {
    target_group_arn = aws_lb_target_group.main.arn
    container_name   = "app"
    container_port   = 80
  }

  # Note: デプロイ設定を追加する場合
  # deployment_configuration {
  #   maximum_percent         = 200  # ローリングアップデート時の最大タスク数
  #   minimum_healthy_percent = 100  # 最小稼働タスク数
  # }

  # ALBリスナーが作成されるまで待機
  depends_on = [aws_lb_listener.main]

  # Note: サービスがタスクを起動する前にターゲットグループが
  # 準備完了していることを確認

  tags = {
    Name = "${var.project_name}-service"
  }
}

# ==========================================
# Outputs
# ==========================================

# ALBのDNS名
output "alb_dns_name" {
  description = "DNS name of the Application Load Balancer"
  value       = aws_lb.main.dns_name
}

# ALBのURL
output "alb_url" {
  description = "URL of the Application Load Balancer"
  value       = "http://${aws_lb.main.dns_name}"
}

# ECRリポジトリURL
output "ecr_repository_url" {
  description = "URL of the ECR repository"
  value       = aws_ecr_repository.main.repository_url
}

# ECSクラスター名
output "ecs_cluster_name" {
  description = "Name of the ECS cluster"
  value       = aws_ecs_cluster.main.name
}

# ECSサービス名
output "ecs_service_name" {
  description = "Name of the ECS service"
  value       = aws_ecs_service.main.name
}