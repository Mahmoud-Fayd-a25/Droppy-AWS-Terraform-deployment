output "vpc_a_id" {
  description = "ID of VPC A"
  value       = aws_vpc.vpc_a.id
}

output "vpc_a_cidr" {
  description = "CIDR block of VPC A"
  value       = aws_vpc.vpc_a.cidr_block
}

output "public_route_table_id" {
  description = "ID of public route table"
  value       = aws_route_table.public_a.id
}

output "private_route_table_id" {
  description = "ID of private route table"
  value       = aws_route_table.private_a.id
}

output "alb_dns_name" {
  description = "DNS name of the ALB"
  value       = aws_lb.droppy_alb.dns_name
}

output "alb_zone_id" {
  description = "Zone ID of the ALB"
  value       = aws_lb.droppy_alb.zone_id
}

output "alb_arn" {
  description = "ARN of the ALB"
  value       = aws_lb.droppy_alb.arn
}
