terraform {
  required_version = ">= 1.7.0"

  required_providers {
    aws = {
      source                = "hashicorp/aws"
      version               = ">= 5.50, < 6.0"
      configuration_aliases = [aws.us_east_1]
    }
  }
}
