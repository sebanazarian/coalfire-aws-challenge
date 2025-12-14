output "vpc_id" {
  description = "ID of the VPC"
  value       = module.vpc.vpc_id
}

output "alb_dns_name" {
  description = "DNS name of the Application Load Balancer"
  value       = aws_lb.main.dns_name
}

output "alb_zone_id" {
  description = "Zone ID of the Application Load Balancer"
  value       = aws_lb.main.zone_id
}

output "images_bucket_name" {
  description = "Name of the images S3 bucket"
  value       = module.images_bucket.id
}

output "logs_bucket_name" {
  description = "Name of the logs S3 bucket"
  value       = module.logs_bucket.id
}

output "standalone_instance_id" {
  description = "ID of the standalone EC2 instance"
  value       = aws_instance.standalone.id
}

output "asg_name" {
  description = "Name of the Auto Scaling Group"
  value       = aws_autoscaling_group.main.name
}
