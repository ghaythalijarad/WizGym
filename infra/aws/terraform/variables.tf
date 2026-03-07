variable "project_name" {
  description = "Project slug used in resource names."
  type        = string
  default     = "wizgym"
}

variable "environment" {
  description = "Deployment environment name."
  type        = string
  default     = "prod"
}

variable "aws_region" {
  description = "AWS region for all resources."
  type        = string
  default     = "us-east-1"
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC."
  type        = string
  default     = "10.40.0.0/16"
}

variable "container_port" {
  description = "Backend container port."
  type        = number
  default     = 3000
}

variable "backend_image_tag" {
  description = "Container image tag deployed by ECS task definition."
  type        = string
  default     = "latest"
}

variable "desired_count" {
  description = "Desired number of backend tasks."
  type        = number
  default     = 1
}

variable "min_task_count" {
  description = "Minimum autoscaling count."
  type        = number
  default     = 1
}

variable "max_task_count" {
  description = "Maximum autoscaling count."
  type        = number
  default     = 4
}

variable "ecs_task_cpu" {
  description = "Fargate task CPU units."
  type        = string
  default     = "512"
}

variable "ecs_task_memory" {
  description = "Fargate task memory in MB."
  type        = string
  default     = "1024"
}

variable "log_retention_days" {
  description = "CloudWatch log retention."
  type        = number
  default     = 14
}

variable "db_name" {
  description = "PostgreSQL database name."
  type        = string
  default     = "gymos"
}

variable "db_username" {
  description = "PostgreSQL master username."
  type        = string
  default     = "gymos_admin"
}

variable "postgres_engine_version" {
  description = "RDS PostgreSQL engine version."
  type        = string
  default     = "16.4"
}

variable "rds_instance_class" {
  description = "RDS instance class."
  type        = string
  default     = "db.t4g.micro"
}

variable "rds_allocated_storage" {
  description = "Initial RDS storage (GB)."
  type        = number
  default     = 20
}

variable "rds_max_allocated_storage" {
  description = "Maximum autoscaled RDS storage (GB)."
  type        = number
  default     = 100
}

variable "rds_backup_retention_days" {
  description = "RDS backup retention in days."
  type        = number
  default     = 7
}

variable "rds_multi_az" {
  description = "Enable Multi-AZ for RDS."
  type        = bool
  default     = false
}

variable "rds_skip_final_snapshot" {
  description = "Skip final snapshot on destroy."
  type        = bool
  default     = true
}

variable "rds_deletion_protection" {
  description = "Enable deletion protection for RDS."
  type        = bool
  default     = false
}

variable "redis_node_type" {
  description = "ElastiCache Redis node type."
  type        = string
  default     = "cache.t4g.micro"
}

variable "redis_engine_version" {
  description = "ElastiCache Redis engine version."
  type        = string
  default     = "7.1"
}

variable "acm_certificate_arn" {
  description = "Optional ACM certificate ARN for HTTPS listener."
  type        = string
  default     = ""
}

variable "otpiq_api_key" {
  description = "OTPIQ API key injected into ECS task."
  type        = string
  sensitive   = true
}

variable "otpiq_base_url" {
  description = "OTPIQ API base URL."
  type        = string
  default     = "https://api.otpiq.com/api"
}

variable "otpiq_provider" {
  description = "OTPIQ delivery provider."
  type        = string
  default     = "whatsapp-sms"
}

variable "otpiq_sender_id" {
  description = "Optional OTPIQ sender ID."
  type        = string
  default     = ""
}

variable "otpiq_mock_mode" {
  description = "Enable OTPIQ mock mode."
  type        = bool
  default     = false
}

variable "phone_otp_length" {
  description = "OTP length."
  type        = number
  default     = 6
}

variable "phone_otp_ttl_seconds" {
  description = "OTP expiration in seconds."
  type        = number
  default     = 300
}

variable "phone_otp_max_attempts" {
  description = "Maximum OTP attempts."
  type        = number
  default     = 5
}

variable "phone_otp_rate_limit_seconds" {
  description = "OTP request cooldown."
  type        = number
  default     = 45
}

variable "common_tags" {
  description = "Common tags applied to all resources."
  type        = map(string)
  default     = {}
}

variable "github_repo" {
  description = "GitHub repository in org/repo format (e.g., ghaythalijarad/WizGym)."
  type        = string
  default     = "ghaythalijarad/WizGym"
}

variable "landing_s3_bucket" {
  description = "S3 bucket name for the landing page."
  type        = string
  default     = "wizgym-landing-prod"
}
