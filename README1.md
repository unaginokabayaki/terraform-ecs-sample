# ECS Fargate ハンズオン環境

AWS ECS Fargate を使用したコンテナアプリケーションのデプロイ環境を Terraform で構築します。
※claudeで作成しました。

## 📋 目次

- [アーキテクチャ](#アーキテクチャ)
- [前提条件](#前提条件)
- [構成リソース](#構成リソース)
- [デプロイ手順](#デプロイ手順)
- [運用](#運用)
- [トラブルシューティング](#トラブルシューティング)
- [クリーンアップ](#クリーンアップ)

## 🏗️ アーキテクチャ

```
Internet
    |
    v
[Application Load Balancer]
    |
    +--- Public Subnet (ap-northeast-1a)
    |        |
    |        v
    |    [ECS Task (Fargate)]
    |
    +--- Public Subnet (ap-northeast-1c)
             |
             v
         [ECS Task (Fargate)]
```

### 主要コンポーネント

- **VPC**: 10.1.0.0/16 CIDR ブロック
- **Public Subnets**: 2つのアベイラビリティゾーン (1a, 1c)
- **ALB**: HTTP (ポート80) でトラフィックを受け付け
- **ECS Fargate**: サーバーレスコンテナ実行環境
- **ECR**: Docker イメージリポジトリ
- **CloudWatch Logs**: コンテナログの保存 (7日間保持)

## 📦 前提条件

### 必要なツール

- [Terraform](https://www.terraform.io/downloads.html) >= 1.0
- [AWS CLI](https://aws.amazon.com/cli/) >= 2.0
- [Docker](https://www.docker.com/get-started) >= 20.10
- AWS アカウントと適切な IAM 権限

### AWS 権限

以下のサービスに対する権限が必要です:
- VPC, Subnet, Internet Gateway, Route Table
- Security Group
- Application Load Balancer
- ECS (Cluster, Service, Task Definition)
- ECR
- IAM Role
- CloudWatch Logs

### AWS CLI の設定

```bash
aws configure
# AWS Access Key ID: <your-access-key>
# AWS Secret Access Key: <your-secret-key>
# Default region name: ap-northeast-1
# Default output format: json
```

## 🔧 構成リソース

| リソース | 数量 | 説明 |
|---------|------|------|
| VPC | 1 | 10.1.0.0/16 |
| Public Subnet | 2 | Multi-AZ 構成 |
| Internet Gateway | 1 | インターネット接続 |
| ALB | 1 | HTTP ロードバランサー |
| Target Group | 1 | ECS タスク用 |
| Security Group | 2 | ALB 用 + ECS タスク用 |
| ECS Cluster | 1 | Fargate クラスター |
| ECS Service | 1 | タスク数: 2 (デフォルト) |
| ECR Repository | 1 | Docker イメージ保存 |
| CloudWatch Log Group | 1 | ログ保持期間: 7日 |

## 🚀 デプロイ手順

### 1. リポジトリのクローン

```bash
git clone <your-repository-url>
cd <repository-name>
```

### 2. Terraform の初期化

```bash
terraform init
```

### 3. インフラストラクチャのデプロイ

```bash
# 実行計画の確認
terraform plan

# デプロイ実行
terraform apply
```

実行後、以下の出力が表示されます:
```
alb_url = "http://ecs-handson-alb-xxxxxxxxxx.ap-northeast-1.elb.amazonaws.com"
ecr_repository_url = "xxxxxxxxxxxx.dkr.ecr.ap-northeast-1.amazonaws.com/ecs-handson-app"
ecs_cluster_name = "ecs-handson-cluster"
ecs_service_name = "ecs-handson-service"
```

### 4. Docker イメージのビルドとプッシュ

#### 4.1 ECR へのログイン

```bash
aws ecr get-login-password --region ap-northeast-1 | \
  docker login --username AWS --password-stdin \
  $(terraform output -raw ecr_repository_url | cut -d'/' -f1)
```

#### 4.2 Docker イメージのビルド

サンプル Dockerfile:
```dockerfile
FROM nginx:alpine
COPY index.html /usr/share/nginx/html/
EXPOSE 80
CMD ["nginx", "-g", "daemon off;"]
```

サンプル index.html:
```html
<!DOCTYPE html>
<html>
<head>
    <title>ECS Handson</title>
</head>
<body>
    <h1>Hello from ECS Fargate!</h1>
    <p>This container is running on AWS ECS Fargate.</p>
</body>
</html>
```

```bash
# イメージのビルド
docker build -t ecs-handson-app .

# タグ付け
docker tag ecs-handson-app:latest "$(terraform output -raw ecr_repository_url):latest"

# ログイン
aws ecr get-login-password --region ap-northeast-1 | docker login --username AWS --password-stdin <アカウントID>.dkr.ecr.ap-northeast-1.amazonaws.com/

# ECR へプッシュ
docker push "$(terraform output -raw ecr_repository_url):latest"
```

### 5. ECS サービスの更新

新しいイメージをプッシュした後、ECS サービスを更新:

```bash
aws ecs update-service \
  --cluster $(terraform output -raw ecs_cluster_name) \
  --service $(terraform output -raw ecs_service_name) \
  --force-new-deployment
```

### 6. アプリケーションへのアクセス

```bash
# ALB の URL を取得
terraform output alb_url

# ブラウザでアクセス、またはcurlで確認
curl $(terraform output -raw alb_url)
```

⚠️ **注意**: 初回デプロイ後、ALB のヘルスチェックが通過するまで 2-3 分かかる場合があります。

## 🔄 運用

### スケーリング

タスク数を変更する場合:

```bash
# terraform.tfvars を作成
echo 'ecs_desired_count = 4' > terraform.tfvars

# 適用
terraform apply
```

または、AWS CLI で直接変更:

```bash
aws ecs update-service \
  --cluster $(terraform output -raw ecs_cluster_name) \
  --service $(terraform output -raw ecs_service_name) \
  --desired-count 4
```

### ログの確認

```bash
# CloudWatch Logs で確認
aws logs tail /ecs/ecs-handson-app --follow
```

または AWS コンソールから:
1. CloudWatch → ロググループ → `/ecs/ecs-handson-app`
2. 最新のログストリームを選択

### リソース使用状況の確認

```bash
# ECS タスクの状態確認
aws ecs describe-services \
  --cluster $(terraform output -raw ecs_cluster_name) \
  --services $(terraform output -raw ecs_service_name)

# 実行中のタスク一覧
aws ecs list-tasks \
  --cluster $(terraform output -raw ecs_cluster_name) \
  --service-name $(terraform output -raw ecs_service_name)
```

## 🔍 トラブルシューティング

### ALB から 503 エラーが返る

**原因**:
- ECS タスクが起動していない
- ヘルスチェックが失敗している
- セキュリティグループの設定ミス

**確認方法**:
```bash
# ターゲットグループのヘルス状態確認
aws elbv2 describe-target-health \
  --target-group-arn $(aws elbv2 describe-target-groups \
    --names ecs-handson-tg \
    --query 'TargetGroups[0].TargetGroupArn' \
    --output text)

# ECS タスクのログ確認
aws logs tail /ecs/ecs-handson-app --follow
```

### ECS タスクが起動しない

**原因**:
- ECR にイメージがプッシュされていない
- タスク定義のメモリ/CPU が不足
- IAM ロールの権限不足

**確認方法**:
```bash
# ECR にイメージが存在するか確認
aws ecr describe-images \
  --repository-name ecs-handson-app

# ECS タスクのエラーを確認
aws ecs describe-tasks \
  --cluster $(terraform output -raw ecs_cluster_name) \
  --tasks $(aws ecs list-tasks \
    --cluster $(terraform output -raw ecs_cluster_name) \
    --service-name $(terraform output -raw ecs_service_name) \
    --query 'taskArns[0]' \
    --output text)
```

### Docker イメージがプッシュできない

**原因**:
- ECR へのログインが切れている
- リポジトリ名が間違っている

**解決方法**:
```bash
# 再度 ECR にログイン
aws ecr get-login-password --region ap-northeast-1 | \
  docker login --username AWS --password-stdin \
  $(terraform output -raw ecr_repository_url | cut -d'/' -f1)

# イメージ名とタグを確認
docker images
```

### ヘルスチェックのタイムアウト

現在の設定では、ヘルスチェックが非常に寛容です:
- Timeout: 60秒
- Interval: 120秒
- Unhealthy threshold: 10回

アプリケーションが軽量な場合は、以下の設定を推奨:
```hcl
health_check {
  timeout             = 5
  interval            = 30
  unhealthy_threshold = 3
}
```

## 🧹 クリーンアップ

### リソースの削除

```bash
# Terraform で作成したリソースを削除
terraform destroy
```

⚠️ **注意**: ECR リポジトリにイメージが残っている場合、削除が失敗します。

### 手動で ECR イメージを削除

```bash
# ECR リポジトリ内の全イメージを削除
aws ecr batch-delete-image \
  --repository-name ecs-handson-app \
  --image-ids "$(aws ecr list-images \
    --repository-name ecs-handson-app \
    --query 'imageIds[*]' \
    --output json)"

# 再度 Terraform で削除
terraform destroy
```

## 📝 カスタマイズ

### 変数のカスタマイズ

`terraform.tfvars` ファイルを作成:

```hcl
project_name       = "my-ecs-app"
vpc_cidr           = "10.2.0.0/16"
ecs_task_cpu       = "512"
ecs_task_memory    = "1024"
ecs_desired_count  = 4
```

### セキュリティの強化

**推奨事項**:
1. プライベートサブネットの追加
2. NAT Gateway の導入
3. ALB に HTTPS (SSL/TLS) を設定
4. WAF の導入
5. VPC Flow Logs の有効化

## 📚 参考リンク

- [AWS ECS ドキュメント](https://docs.aws.amazon.com/ecs/)
- [Terraform AWS Provider](https://registry.terraform.io/providers/hashicorp/aws/latest/docs)
- [AWS Fargate の料金](https://aws.amazon.com/fargate/pricing/)

## 📄 ライセンス

このプロジェクトは MIT ライセンスの下で公開されています。

## 🤝 コントリビューション

Issue や Pull Request を歓迎します!