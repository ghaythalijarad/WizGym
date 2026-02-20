output "aws_region" {
  description = "AWS region where resources are deployed."
  value       = var.aws_region
}

output "vpc_id" {
  description = "VPC ID."
  value       = aws_vpc.main.id
}

output "public_subnet_ids" {
  description = "Public subnet IDs."
  value       = [aws_subnet.public_a.id, aws_subnet.public_b.id]
}

output "alb_dns_name" {
  description = "Public ALB DNS."
  value       = aws_lb.backend.dns_name
}

output "api_base_url" {
  description = "Base URL to call the API."
  value       = "http://${aws_lb.backend.dns_name}/api/v1"
}

output "ecr_repository_url" {
  description = "ECR repository URL for backend image pushes."
  value       = aws_ecr_repository.backend.repository_url
}

output "ecs_cluster_name" {
  description = "ECS cluster name."
  value       = aws_ecs_cluster.main.name
}

output "ecs_service_name" {
  description = "ECS service name."
  value       = aws_ecs_service.backend.name
}

output "ecs_task_definition_arn" {
  description = "Current ECS task definition ARN."
  value       = aws_ecs_task_definition.backend.arn
}

output "ecs_security_group_id" {
  description = "ECS service security group ID."
  value       = aws_security_group.ecs.id
}

output "rds_endpoint" {
  description = "RDS host:port."
  value       = "${aws_db_instance.main.address}:${aws_db_instance.main.port}"
}

output "redis_endpoint" {
  description = "Redis host:port."
  value       = "${aws_elasticache_replication_group.main.primary_endpoint_address}:${aws_elasticache_replication_group.main.port}"
}

output "backend_secret_arn" {
  description = "Secrets Manager secret ARN with backend env values."
  value       = aws_secretsmanager_secret.backend_env.arn
}
