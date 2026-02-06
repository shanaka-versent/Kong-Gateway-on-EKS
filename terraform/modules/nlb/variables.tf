# EKS Kong Gateway POC - NLB Module Variables
# @author Shanaka Jayasundera - shanakaj@gmail.com

variable "name_prefix" {
  description = "Prefix for resource names"
  type        = string
}

variable "vpc_id" {
  description = "VPC ID"
  type        = string
}

variable "vpc_cidr" {
  description = "VPC CIDR block for security group egress rules"
  type        = string
}

variable "private_subnet_ids" {
  description = "Private subnet IDs for NLB placement"
  type        = list(string)
}

variable "health_check_path" {
  description = "Health check path for Kong Gateway"
  type        = string
  default     = "/healthz/ready"
}

variable "health_check_port" {
  description = "Kong Gateway status port for health checks"
  type        = number
  default     = 8100
}

variable "enable_cross_zone_load_balancing" {
  description = "Enable cross-zone load balancing for the NLB"
  type        = bool
  default     = true
}

variable "tags" {
  description = "Tags for resources"
  type        = map(string)
  default     = {}
}
