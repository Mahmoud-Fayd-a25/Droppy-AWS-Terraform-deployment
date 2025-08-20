output "vpc_b_id" {
  description = "ID of VPC B"
  value       = aws_vpc.vpc_b.id
}

output "jumphost_public_ip" {
  description = "Public IP of the jump host"
  value       = aws_instance.jumphost.public_ip
}

output "jumphost_private_ip" {
  description = "Private IP of the jump host"
  value       = aws_instance.jumphost.private_ip
}

output "route53_zone_id" {
  description = "Route53 private hosted zone ID"
  value       = aws_route53_zone.droppy_zone.zone_id
}

output "vpc_peering_connection_id" {
  description = "VPC Peering Connection ID"
  value       = aws_vpc_peering_connection.vpc_peering.id
}

output "droppy_url" {
  description = "Droppy application URL"
  value       = "http://app.droppy.lan"
}