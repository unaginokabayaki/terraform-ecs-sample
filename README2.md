# ECS Fargate + ALB ハンズオン環境構築 (Terraform)

このプロジェクトは、AWS 上に **ECS Fargate + ALB** 構成のシンプルなコンテナ実行環境を構築する Terraform サンプルです。
学習・検証・ハンズオン用の最小構成として、すべてパブリックサブネット上にデプロイします。

---

## 構成概要

### アーキテクチャ図（論理構成）

```
[Internet]
   │
   ▼
(Internet Gateway)
   │
   ▼
┌────────────────────────────┐
│ Public Subnet (10.1.1.0/24, 10.1.2.0/24) │
│   ├─ Application Load Balancer (HTTP:80) │
│   └─ ECS Tasks (Fargate, Public IP)      │
└────────────────────────────┘
```

* ALBがHTTP(80)でリクエストを受け、ECSタスクに転送します。
* タスクはECRに保存されたDockerイメージを使用します。
* CloudWatch Logsにログを出力します。

---

## 主なリソース

| カテゴリ           | リソース                                                                                    | 内容                                    |
| -------------- | --------------------------------------------------------------------------------------- | ------------------------------------- |
| VPC / Network  | `aws_vpc.main`, `aws_subnet.public_*`, `aws_route_table.public`                         | パブリックVPCとサブネット、IGW、ルートテーブルを構成         |
| Security Group | `aws_security_group.alb`, `aws_security_group.ecs_tasks`                                | ALB用 (80番公開) と ECSタスク用 (ALBからの通信のみ許可) |
| ALB            | `aws_lb.main`, `aws_lb_target_group.main`, `aws_lb_listener.main`                       | インターネット公開用のALB構成                      |
| ECS            | `aws_ecs_cluster.main`, `aws_ecs_task_definition.main`, `aws_ecs_service.main`          | Fargateを使用したECSサービス構成                 |
| ECR            | `aws_ecr_repository.main`, `aws_ecr_lifecycle_policy.main`                              | コンテナイメージのリポジトリとライフサイクルポリシー            |
| IAM            | `aws_iam_role.ecs_task_execution`, `aws_iam_role.ecs_task`                              | ECSタスク実行用およびタスク用ロール                   |
| Logs           | `aws_cloudwatch_log_group.ecs`                                                          | CloudWatch Logs 出力設定                  |
| Outputs        | `alb_dns_name`, `alb_url`, `ecr_repository_url`, `ecs_cluster_name`, `ecs_service_name` | 構築後に確認可能な出力値                          |

---

## Terraform 実行環境

| 項目           | 値                   |
| ------------ | ------------------- |
| Terraform    | >= 1.5              |
| AWS Provider | >= 5.0              |
| リージョン        | ap-northeast-1 (東京) |
| 実行環境         | ECS Fargate         |

---

## デプロイ手順

1. **初期化**

   ```bash
   terraform init
   ```

2. **プラン確認**

   ```bash
   terraform plan
   ```

3. **デプロイ**

   ```bash
   terraform apply
   ```

4. **出力確認**

   ```bash
   terraform output
   ```

   出力される ALB URL にアクセスして、動作を確認します。

   ```
   alb_url = http://<ALB-DNS-NAME>
   ```

---

## セキュリティグループ設定

| 対象     | 通信方向    | ポート    | 許可元 / 宛先  | 説明                       |
| ------ | ------- | ------ | --------- | ------------------------ |
| ALB SG | Ingress | TCP 80 | 0.0.0.0/0 | インターネットからのHTTP許可         |
| ALB SG | Egress  | All    | 0.0.0.0/0 | 全アウトバウンド許可               |
| ECS SG | Ingress | TCP 80 | ALB SG    | ALBからのHTTP許可             |
| ECS SG | Egress  | All    | 0.0.0.0/0 | 全アウトバウンド許可（ECR/Logs送信用途） |

---

## 出力値 (terraform output)

| 名称                   | 内容              |
| -------------------- | --------------- |
| `alb_dns_name`       | ALBのDNS名        |
| `alb_url`            | ALBのHTTPアクセスURL |
| `ecr_repository_url` | ECRリポジトリのURL    |
| `ecs_cluster_name`   | ECSクラスタ名        |
| `ecs_service_name`   | ECSサービス名        |

---

## 注意事項

* この構成は **ハンズオン用の簡易構成** です。
  本番環境では以下の対策を推奨します。

  * ECSタスクをPrivateサブネットに配置
  * NAT GatewayまたはVPCエンドポイントを利用
  * HTTPS(443)対応およびACM証明書導入
* ALBのPublic IPは固定ではありません。DNS名を利用してください。

---

## 発展構成例

| 拡張内容          | 説明                            |
| ------------- | ----------------------------- |
| Privateサブネット化 | ECSをPrivateサブネットに移動し、NAT経由で通信 |
| HTTPS対応       | ACM証明書を発行し、443ポートリスナー追加       |
| VPCエンドポイント導入  | ECR・CloudWatch Logs通信を閉域化     |
| CI/CD統合       | GitHub Actionsなどを用いた自動デプロイ    |

---

© 2025 ECS Hands-on Template
