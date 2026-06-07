variable "region" {
  type        = string
  default     = "eu-central-1"
  description = "Primary AWS region for the S3 bucket and Route53 client. ACM is always pinned to us-east-1 by the module."
}

variable "domain_name" {
  type        = string
  description = "Primary FQDN to serve (e.g. www.example.com)."
}

variable "subject_alt_names" {
  type        = list(string)
  default     = []
  description = "Extra FQDNs added as ACM SANs and CloudFront aliases."
}

variable "hosted_zone_id" {
  type        = string
  description = "Route53 hosted zone that owns domain_name and every SAN."
}

variable "tags" {
  type        = map(string)
  default     = { Project = "terraform-aws-static-site-example" }
  description = "Tags merged onto every taggable resource."
}
