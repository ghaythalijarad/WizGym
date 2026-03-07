variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}

variable "aws_profile" {
  description = "AWS CLI profile"
  type        = string
  default     = "wizgym-prod"
}

variable "github_repo" {
  description = "GitHub repository in org/repo format"
  type        = string
  default     = "ghaythalijarad/WizGym"
}

variable "landing_s3_bucket" {
  description = "S3 bucket name for the landing page"
  type        = string
  default     = "wizgym-landing-prod"
}
