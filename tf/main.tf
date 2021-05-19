variable "REGION" {}
variable "ACCOUNT_ID" {}
variable "ENVIRONMENT" {}
variable "LAMBDA_ZIP_PATH" {}
variable "DRY_RUN" {}
variable "HOSTED_ZONE" {}
variable "HOOK_VALIDATION_TOKEN" {}
variable "SNYK_TOKEN" {}

module "lambda" {
  source          = "./modules/"
  LAMBDA_ZIP_PATH = var.LAMBDA_ZIP_PATH
  ACCOUNT_ID      = var.ACCOUNT_ID
  REGION          = var.REGION
  DRY_RUN         = var.DRY_RUN
  HOSTED_ZONE     = var.HOSTED_ZONE

  // NOTE: These should be passed in at deploy time to prevent secrets from being leaked
  HOOK_VALIDATION_TOKEN = var.HOOK_VALIDATION_TOKEN
  SNYK_TOKEN            = var.SNYK_TOKEN
}

provider "aws" {
  region = "us-east-1"
}

terraform {
  backend "s3" {
    encrypt = "true"
    region  = "us-east-1"
  }
}