output "public_ip" {
  value = aws_instance.main.public_ip
}

output "valheim_private_key" {
  value     = tls_private_key.main.private_key_pem
  sensitive = true
}
