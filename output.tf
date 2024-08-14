output "alb_name" {
  value = aws_lb.alb.id
}
output "pubIns_ip" {
  value = aws_instance.pubIns.public_ip
}
