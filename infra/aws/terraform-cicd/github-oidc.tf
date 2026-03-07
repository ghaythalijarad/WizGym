# GitHub Actions OIDC — AWS Deploy Role
# Lightweight config: only creates the OIDC provider + deploy role.
# Does NOT create VPC, ECS, RDS, etc. (those are in the legacy terraform/ folder).

data "aws_caller_identity" "current" {}

# ── OIDC Provider ────────────────────────────────────────────────────────────

resource "aws_iam_openid_connect_provider" "github_actions" {
  url             = "https://token.actions.githubusercontent.com"
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = ["6938fd4d98bab03faadb97b34396831e3780aea1"]

  tags = {
    Project   = "wizgym"
    ManagedBy = "terraform"
  }
}

# ── Deploy Role ──────────────────────────────────────────────────────────────

resource "aws_iam_role" "github_actions_deploy" {
  name = "wizgym-github-actions-deploy"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Federated = aws_iam_openid_connect_provider.github_actions.arn
        }
        Action = "sts:AssumeRoleWithWebIdentity"
        Condition = {
          StringEquals = {
            "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
          }
          StringLike = {
            "token.actions.githubusercontent.com:sub" = "repo:${var.github_repo}:*"
          }
        }
      }
    ]
  })

  tags = {
    Project     = "wizgym"
    Environment = "prod"
    ManagedBy   = "terraform"
  }
}

# ── Deploy Policy ────────────────────────────────────────────────────────────

resource "aws_iam_role_policy" "github_actions_deploy" {
  name = "wizgym-deploy-policy"
  role = aws_iam_role.github_actions_deploy.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "CloudFormationSAMStack"
        Effect = "Allow"
        Action = ["cloudformation:*"]
        Resource = "arn:aws:cloudformation:${var.aws_region}:${data.aws_caller_identity.current.account_id}:stack/sam-app/*"
      },
      {
        Sid    = "S3SAMBucket"
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject",
          "s3:ListBucket",
          "s3:GetBucketLocation",
          "s3:CreateBucket",
        ]
        Resource = [
          "arn:aws:s3:::aws-sam-cli-managed-default-*",
          "arn:aws:s3:::aws-sam-cli-managed-default-*/*",
        ]
      },
      {
        Sid    = "S3LandingBucket"
        Effect = "Allow"
        Action = [
          "s3:PutObject",
          "s3:DeleteObject",
          "s3:ListBucket",
          "s3:GetBucketLocation",
        ]
        Resource = [
          "arn:aws:s3:::${var.landing_s3_bucket}",
          "arn:aws:s3:::${var.landing_s3_bucket}/*",
        ]
      },
      {
        Sid    = "LambdaManage"
        Effect = "Allow"
        Action = ["lambda:*"]
        Resource = "arn:aws:lambda:${var.aws_region}:${data.aws_caller_identity.current.account_id}:function:sam-app-*"
      },
      {
        Sid      = "APIGateway"
        Effect   = "Allow"
        Action   = ["apigateway:*"]
        Resource = "*"
      },
      {
        Sid    = "IAMPassRole"
        Effect = "Allow"
        Action = [
          "iam:GetRole",
          "iam:PassRole",
          "iam:CreateRole",
          "iam:DeleteRole",
          "iam:AttachRolePolicy",
          "iam:DetachRolePolicy",
          "iam:PutRolePolicy",
          "iam:DeleteRolePolicy",
          "iam:GetRolePolicy",
          "iam:TagRole",
          "iam:UntagRole",
        ]
        Resource = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/sam-app-*"
      },
      {
        Sid      = "CloudFrontInvalidation"
        Effect   = "Allow"
        Action   = ["cloudfront:CreateInvalidation"]
        Resource = "*"
      },
      {
        Sid    = "CloudFormationDescribe"
        Effect = "Allow"
        Action = [
          "cloudformation:DescribeStacks",
          "cloudformation:ListStacks",
        ]
        Resource = "*"
      },
    ]
  })
}

# ── Outputs ──────────────────────────────────────────────────────────────────

output "github_actions_role_arn" {
  description = "Set this as AWS_DEPLOY_ROLE_ARN in GitHub repo secrets"
  value       = aws_iam_role.github_actions_deploy.arn
}
