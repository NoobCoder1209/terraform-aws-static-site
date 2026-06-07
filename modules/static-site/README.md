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

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| bucket\_name | Optional S3 bucket name override. When null, the module derives a unique bucket\_prefix from domain\_name. | `string` | `null` | no |
| default\_root\_object | Object served at /. | `string` | `"index.html"` | no |
| domain\_name | Primary FQDN served by CloudFront (e.g. www.example.com). Becomes the certificate CN and the first CloudFront alias. | `string` | n/a | yes |
| hosted\_zone\_id | Route53 public hosted zone ID that owns domain\_name and every SAN. ACM DNS-validation records and the ALIAS records are written here. | `string` | n/a | yes |
| price\_class | CloudFront price class. PriceClass\_100 covers NA + EU; PriceClass\_200 adds Asia + ME; PriceClass\_All adds South America + Oceania. | `string` | `"PriceClass_100"` | no |
| spa\_mode | When true, CloudFront rewrites 403 and 404 responses to /index.html with HTTP 200 so client-side routers can take over. | `bool` | `true` | no |
| subject\_alt\_names | Extra FQDNs added as ACM SANs and CloudFront aliases. Wildcards (*.example.com) are supported. | `list(string)` | `[]` | no |
| tags | Tags merged onto every taggable resource. | `map(string)` | `{}` | no |
| web\_acl\_id | Optional AWS WAFv2 web ACL ARN attached to the distribution. Leave null to skip WAF. | `string` | `null` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| bucket\_name | ID of the origin S3 bucket. |
| bucket\_regional\_domain | Regional domain name of the origin bucket; useful for cross-account audits. |
| cloudfront\_distribution\_id | Distribution ID; pass to invalidation tooling. |
| cloudfront\_domain | *.cloudfront.net hostname assigned to the distribution. |
| fqdn | Primary FQDN configured on the distribution. |
<!-- END_TF_DOCS -->
