terraform {
  backend "s3" {
    bucket = "terraform-backend-ue1"
    key    = "valheim/terraform.tfstate"
    region = "us-east-1"
  }
}
