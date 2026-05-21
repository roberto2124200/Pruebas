terraform {
  backend "s3" {
    bucket       = "terraform-state-roberto-2124200-us-east-2"
    key          = "pruebas/terraform.tfstate"
    region       = "us-east-2"
    encrypt      = true
    use_lockfile = true
  }
}