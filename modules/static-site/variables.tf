variable "domain_name" {
  type        = string
  description = "Primary FQDN served by CloudFront (e.g. www.example.com). Becomes the certificate CN and the first CloudFront alias."

  validation {
    condition     = can(regex("^[a-z0-9.-]+\\.[a-z]{2,}$", var.domain_name))
    error_message = "domain_name must be a lowercase FQDN (letters, digits, dots, dashes)."
  }
}

variable "subject_alt_names" {
  type        = list(string)
  default     = []
  description = "Extra FQDNs added as ACM SANs and CloudFront aliases. Wildcards (*.example.com) are supported."
}

variable "hosted_zone_id" {
  type        = string
  description = "Route53 public hosted zone ID that owns domain_name and every SAN. ACM DNS-validation records and the ALIAS records are written here."

  validation {
    condition     = can(regex("^Z[A-Z0-9]{12,21}$", var.hosted_zone_id))
    error_message = "hosted_zone_id must look like Z123ABC... (13–22 chars, uppercase + digits)."
  }
}

variable "bucket_name" {
  type        = string
  default     = null
  description = "Optional S3 bucket name override. When null, the module derives a unique bucket_prefix from domain_name."
}

variable "price_class" {
  type        = string
  default     = "PriceClass_100"
  description = "CloudFront price class. PriceClass_100 covers NA + EU; PriceClass_200 adds Asia + ME; PriceClass_All adds South America + Oceania."

  validation {
    condition     = contains(["PriceClass_All", "PriceClass_200", "PriceClass_100"], var.price_class)
    error_message = "price_class must be PriceClass_All, PriceClass_200, or PriceClass_100."
  }
}

variable "default_root_object" {
  type        = string
  default     = "index.html"
  description = "Object served at /."
}

variable "spa_mode" {
  type        = bool
  default     = true
  description = "When true, CloudFront rewrites 403 and 404 responses to /index.html with HTTP 200 so client-side routers can take over."
}

variable "tags" {
  type        = map(string)
  default     = {}
  description = "Tags merged onto every taggable resource."
}

variable "web_acl_id" {
  type        = string
  default     = null
  description = "Optional AWS WAFv2 web ACL ARN attached to the distribution. Leave null to skip WAF."
}
