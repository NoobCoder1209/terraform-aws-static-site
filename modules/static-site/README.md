# modules/static-site

Terraform module that provisions a private S3 bucket fronted by CloudFront
with Origin Access Control, a DNS-validated ACM certificate in `us-east-1`,
and Route53 ALIAS records (A + AAAA) for the apex and every SAN.

## Architecture

- **S3**: private bucket, `BucketOwnerEnforced`, all four public-access flags
  set, AES256 SSE with a bucket key, lifecycle rule aborting incomplete
  multipart uploads after 7 days.
- **OAC**: SigV4, always-sign. Bucket policy grants `s3:GetObject` to
  `cloudfront.amazonaws.com` scoped by `AWS:SourceArn` to the distribution.
- **CloudFront**: HTTPS-only viewer policy, gzip + brotli compression,
  AWS-managed `CachingOptimized` and `SecurityHeadersPolicy`, optional WAFv2
  hook, optional SPA mode rewriting 403/404 to `/index.html` (200).
- **ACM**: certificate in `us-east-1` via aliased provider, DNS-validated
  through Route53. SAN records deduped by `domain_name`.
- **Route53**: A + AAAA ALIAS records pointing at the CloudFront domain for
  the apex and every SAN.

## Provider wiring

CloudFront requires its viewer certificate in `us-east-1`. This module
declares an aliased `aws.us_east_1` provider via `configuration_aliases` and
expects the consumer to pass it explicitly:

```hcl
provider "aws" {
  region = "eu-central-1"
}

provider "aws" {
  alias  = "us_east_1"
  region = "us-east-1"
}

module "site" {
  source = "github.com/<owner>/terraform-aws-static-site//modules/static-site?ref=v0.1.0"

  providers = {
    aws           = aws
    aws.us_east_1 = aws.us_east_1
  }

  domain_name    = "www.example.com"
  hosted_zone_id = "Z123ABC..."
}
```

<!-- BEGIN_TF_DOCS -->
## Inputs

| Name | Type | Default | Required |
|---|---|---|---|
| `domain_name` | `string` | n/a | yes |
| `hosted_zone_id` | `string` | n/a | yes |
| `subject_alt_names` | `list(string)` | `[]` | no |
| `bucket_name` | `string` | `null` | no |
| `price_class` | `string` | `"PriceClass_100"` | no |
| `default_root_object` | `string` | `"index.html"` | no |
| `spa_mode` | `bool` | `true` | no |
| `tags` | `map(string)` | `{}` | no |
| `web_acl_id` | `string` | `null` | no |

## Outputs

| Name | Description |
|---|---|
| `bucket_name` | ID of the origin S3 bucket. |
| `bucket_regional_domain` | Regional domain name of the origin bucket. |
| `cloudfront_domain` | `*.cloudfront.net` hostname assigned to the distribution. |
| `cloudfront_distribution_id` | Distribution ID; pass to invalidation tooling. |
| `fqdn` | Primary FQDN configured on the distribution. |
<!-- END_TF_DOCS -->
