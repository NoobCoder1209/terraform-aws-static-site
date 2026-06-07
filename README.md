# terraform-aws-static-site

> Production-grade static site on AWS in one Terraform module — private S3 bucket, CloudFront distribution with Origin Access Control, ACM certificate in `us-east-1`, Route53 ALIAS records.

[![ci](https://github.com/NoobCoder1209/terraform-aws-static-site/actions/workflows/ci.yml/badge.svg)](https://github.com/NoobCoder1209/terraform-aws-static-site/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

## What it shows

- **Modern Origin Access Control (OAC)** — SigV4-signed S3 origin access; the legacy OAI is gone for good.
- **Cross-region ACM via aliased provider** — clean `configuration_aliases` declaration in the child module; consumer wires `aws.us_east_1` explicitly. No provider blocks inside the module.
- **SPA-friendly 404 rewrite** — optional `spa_mode` flag rewrites 403/404 to `/index.html` (200) so client-side routers Just Work.
- **Tight bucket policy** — `s3:GetObject` granted to `cloudfront.amazonaws.com` *only*, scoped by `AWS:SourceArn` to the distribution.
- **AWS-managed CloudFront policies** — `CachingOptimized` + `SecurityHeadersPolicy` referenced by ID; no hand-rolled cache or header config.
- **Route53 ALIAS A + AAAA** for the apex and every SAN, plus dedup-aware DNS validation records (avoids the duplicate-key trap when SANs overlap a wildcard).
- **WAFv2 hook** — `web_acl_id` variable wired to the distribution; pass an ARN or leave null.
- **Static-analysis CI** — `terraform fmt`, `terraform validate`, `tflint --recursive` (with the AWS plugin), and `tfsec`. SARIF uploads to the Security tab when GitHub Advanced Security is available.

## Skills demonstrated

Terraform · AWS · IaC · CloudFront · S3 · ACM · Route53 · GitHub Actions

## Quick start

```sh
git clone https://github.com/NoobCoder1209/terraform-aws-static-site
cd terraform-aws-static-site/examples/basic
cp terraform.tfvars.example terraform.tfvars
# edit terraform.tfvars: set domain_name, hosted_zone_id, region
terraform init
terraform plan
```

`terraform plan` requires a real Route53 hosted zone for the domain. CI runs `terraform validate` only and never executes `apply`.

## Module usage

```hcl
provider "aws" {
  region = "eu-central-1"
}

# CloudFront viewer certificates must live in us-east-1.
provider "aws" {
  alias  = "us_east_1"
  region = "us-east-1"
}

module "static_site" {
  source = "github.com/NoobCoder1209/terraform-aws-static-site//modules/static-site?ref=v0.1.0"

  providers = {
    aws           = aws
    aws.us_east_1 = aws.us_east_1
  }

  domain_name       = "www.example.com"
  subject_alt_names = ["example.com"]
  hosted_zone_id    = "Z00000000000000000000"

  tags = {
    Project = "marketing-site"
    Env     = "prod"
  }
}
```

See [`modules/static-site/README.md`](./modules/static-site/README.md) for the full inputs/outputs table.

## Remote state

The example uses the `local` backend so anyone can clone and `plan`. For real consumers, an S3 + DynamoDB backend pattern looks like:

```hcl
terraform {
  backend "s3" {
    bucket         = "my-tfstate-bucket"
    key            = "static-site/prod.tfstate"
    region         = "eu-central-1"
    dynamodb_table = "my-tfstate-locks"
    encrypt        = true
  }
}
```

The bucket and lock table are out of scope for this module — bootstrap them separately (e.g. with `hashicorp/terraform-aws-modules/terraform-aws-s3-bucket` + a one-shot `aws_dynamodb_table` resource) so the state backend doesn't depend on the very state it stores.

## Architecture

```
                ┌──────────────────────┐
                │   Route53 (ALIAS)    │
                │   A + AAAA → CDN     │
                └──────────┬───────────┘
                           │
                ┌──────────▼───────────┐    ┌─────────────────────┐
                │  CloudFront          │◄───│ ACM (us-east-1)     │
                │  HTTPS, gzip+brotli, │    │ DNS-validated       │
                │  SPA 404 rewrite,    │    └─────────────────────┘
                │  managed policies    │
                └──────────┬───────────┘
                           │ OAC (SigV4)
                ┌──────────▼───────────┐
                │  S3 (private)        │
                │  BucketOwnerEnforced │
                │  AES256, no ACLs     │
                └──────────────────────┘
```

A `terraform plan` capture is intentionally NOT included in this repo; reproducing one requires a real Route53 hosted zone and AWS credentials. See [`docs/screenshots/README.md`](./docs/screenshots/README.md) for instructions to capture your own.

## CI

Runs on every push and pull request:

| Step | Tool | Purpose |
|---|---|---|
| `terraform fmt -check -recursive` | Terraform 1.10 | Formatting drift |
| `terraform init -backend=false` | Terraform | Provider resolution (module + example) |
| `terraform validate` | Terraform | Type-check the example |
| `tflint --recursive` | TFLint v0.x + AWS plugin | Lint rules + AWS-specific checks |
| `tfsec` | tfsec | Static security analysis, SARIF output |

No AWS credentials are configured. `terraform plan/apply` against AWS is intentionally out of scope.

## Repository layout

```
.
├── modules/
│   └── static-site/        # the module
│       ├── main.tf
│       ├── variables.tf
│       ├── outputs.tf
│       ├── versions.tf
│       └── README.md
├── examples/
│   └── basic/              # minimal consumer
│       ├── main.tf
│       ├── variables.tf
│       ├── outputs.tf
│       ├── versions.tf
│       ├── terraform.tfvars.example
│       └── .terraform.lock.hcl
├── .github/workflows/ci.yml
├── .tflint.hcl
└── docs/
```

## License

[MIT](./LICENSE).
