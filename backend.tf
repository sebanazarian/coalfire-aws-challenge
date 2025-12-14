terraform {
  backend "s3" {
    bucket         = "coalfire-challenge-terraform-state"
    key            = "infrastructure/terraform.tfstate"
    region         = "us-east-1"
    encrypt        = true
    dynamodb_table = "coalfire-challenge-terraform-locks"
    profile        = "coalfire-challenge"
  }
}
