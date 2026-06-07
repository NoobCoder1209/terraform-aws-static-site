provider "aws" {
  region = var.region
}

# CloudFront requires the ACM certificate in us-east-1.
provider "aws" {
  alias  = "us_east_1"
  region = "us-east-1"
}

module "static_site" {
  source = "../../modules/static-site"

  providers = {
    aws           = aws
    aws.us_east_1 = aws.us_east_1
  }

  domain_name       = var.domain_name
  subject_alt_names = var.subject_alt_names
  hosted_zone_id    = var.hosted_zone_id
  tags              = var.tags
}
