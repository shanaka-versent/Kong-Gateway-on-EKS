# EKS Kong Gateway POC - NLB Module Outputs
# @author Shanaka Jayasundera - shanakaj@gmail.com

output "nlb_arn" {
  description = "Internal NLB ARN (used by CloudFront VPC Origin)"
  value       = aws_lb.internal.arn
}

output "nlb_dns_name" {
  description = "Internal NLB DNS name"
  value       = aws_lb.internal.dns_name
}

output "nlb_zone_id" {
  description = "Internal NLB Route53 zone ID"
  value       = aws_lb.internal.zone_id
}

output "nlb_name" {
  description = "Internal NLB name"
  value       = aws_lb.internal.name
}

output "target_group_arn" {
  description = "Kong target group ARN (used by TargetGroupBinding CRD)"
  value       = aws_lb_target_group.kong.arn
}

output "security_group_id" {
  description = "NLB security group ID"
  value       = aws_security_group.nlb.id
}
