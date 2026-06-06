# `terraform-aws-static-site` — Execution Plan

> Self-contained build plan. Inherits shared standards from the master plan.

## Goal

End-to-end Terraform IaC that provisions the canonical "static site on AWS"
stack: S3 (private, OAI-fronted) + CloudFront + ACM + Route53. Reusable as a
**module** so consumers wire it into their own root config in ~15 lines.

Bonus narrative: Aleksandar can later use this exact module to host
`chapkanov-dev` if Vercel-as-default is reconsidered. Not a goal of v1.

**Sells:** Terraform, AWS, IaC, CloudFront, S3, ACM, Route53, GitHub Actions.

## Scope (must-haves)

1. Terraform module under `modules/static-site/` with these resources:
   - S3 bucket (private; bucket-policy granting only the OAC its `s3:GetObject`)
   - CloudFront distribution with default root object, SPA-friendly 404→index rewrite, HTTPS only, gzip+brotli
   - Origin Access Control (modern replacement for OAI)
   - ACM certificate **in `us-east-1`** (CloudFront requirement) with DNS-validated cert via Route53
   - Route53 ALIAS record(s) pointing to the CloudFront distribution
2. `examples/basic/` — minimal root config consuming the module with one custom domain
3. Remote state pattern documented in README (S3 backend + DynamoDB lock) — but
   the example uses `local` backend by default so anyone can `terraform plan` it
4. Outputs: bucket name, CloudFront domain name, distribution ID, A-record FQDN,
   bucket regional domain name
5. Variables documented inline + via `terraform-docs` auto-generated section
6. `.github/workflows/ci.yml`: `terraform fmt -check`, `tflint`, `terraform validate`, `tfsec` (or `checkov`)
7. README with full architecture diagram

## Out of scope

- No actual `apply` in CI (nobody's funding the AWS side, and Pattern 3 = no live demos)
- No multi-region replication
- No CloudFront Functions / Lambda@Edge code
- No WAF rules (toggleable hook only — variable `web_acl_id` accepted but unused without a real WAF)
- No CI/CD-the-website (the module is the deliverable; deploying content is the consumer's problem)
- No Terraform registry publication

## Tech stack

- **Terraform:** v1.7+
- **Provider:** `hashicorp/aws` v5.x (us-east-1 alias for ACM, primary region configurable)
- **Linters:** `terraform fmt`, `tflint`, `tfsec`
- **Docs:** `terraform-docs` (markdown table inserted into README)
- **CI:** GitHub Actions

## File tree

```
terraform-aws-static-site/
  README.md
  PLAN.md
  LICENSE
  .gitignore                  ← .terraform/, *.tfstate*, *.tfvars (allowlist .tfvars.example)
  modules/
    static-site/
      README.md               ← module-level docs (terraform-docs auto)
      main.tf                 ← S3 bucket, OAC, CloudFront, ACM, Route53
      variables.tf
      outputs.tf
      versions.tf
      providers.tf            ← aliased "us-east-1" provider for ACM
  examples/
    basic/
      README.md
      main.tf                 ← module "site" {...}
      variables.tf
      outputs.tf
      terraform.tfvars.example
  .github/
    workflows/
      ci.yml
  docs/
    architecture.png          ← simple diagram (S3 ← OAC ← CF ← Route53 ← user)
    screenshots/
      tf-plan.png             ← screenshot of plan output for the GIF/screenshot slot
```

## Step-by-step build

### 1. Module skeleton

`versions.tf`:
```hcl
terraform { required_version = ">= 1.7.0" }
required_providers {
  aws = { source = "hashicorp/aws", version = "~> 5.50" }
}
```

`providers.tf` declares an aliased `us-east-1` provider — the consumer must
pass it through `providers = { aws.us_east_1 = aws.us_east_1 }`. Document
this clearly in the example.

### 2. Variables

```hcl
variable "domain_name"        { type = string }              # e.g. "chapkanov.dev"
variable "subject_alt_names"  { type = list(string) default = [] } # e.g. ["www.chapkanov.dev"]
variable "hosted_zone_id"     { type = string }              # existing zone
variable "bucket_name"        { type = string default = null }    # defaults to domain_name
variable "price_class"        { type = string default = "PriceClass_100" }
variable "default_root_object" { type = string default = "index.html" }
variable "spa_mode"           { type = bool default = true } # 404 → /index.html for SPAs
variable "tags"               { type = map(string) default = {} }
variable "web_acl_id"         { type = string default = null }
```

### 3. Resources (key behaviour notes)

- **S3 bucket**: ACLs disabled, BucketOwnerEnforced, public access block all on.
  Server-side encryption AES256 by default. Versioning **disabled** (the
  consumer ships content; versioning is their call). Lifecycle rule: abort
  multipart uploads after 7 days.
- **OAC** (`aws_cloudfront_origin_access_control`): SigV4, always sign.
- **Bucket policy** restricts `s3:GetObject` to `Service: cloudfront.amazonaws.com`
  with `AWS:SourceArn` matching the distribution.
- **ACM cert** in `us-east-1` with `domain_name` + `subject_alt_names`. DNS
  validation Route53 records created for each domain. `aws_acm_certificate_validation`
  blocks until issued.
- **CloudFront distribution**:
  - Single S3 origin via OAC
  - Aliases = `[domain_name] + subject_alt_names`
  - Viewer cert = the validated ACM cert, sni-only, TLSv1.2_2021
  - Default cache behaviour: redirect-to-https, GET+HEAD, AWS managed cache
    policy `CachingOptimized`, response policy `SecurityHeadersPolicy`
  - `custom_error_response`: when `var.spa_mode` is true, 403 and 404 → `/index.html` with 200
  - Compress = true
  - `web_acl_id = var.web_acl_id` (works whether null or a real ACL ARN)
- **Route53**: A + AAAA ALIAS records for `domain_name` and each SAN, pointing
  at the CloudFront distribution.

### 4. Outputs

```hcl
output "bucket_name"               { value = aws_s3_bucket.this.id }
output "cloudfront_domain"         { value = aws_cloudfront_distribution.this.domain_name }
output "cloudfront_distribution_id"{ value = aws_cloudfront_distribution.this.id }
output "fqdn"                      { value = aws_route53_record.a.fqdn }
output "bucket_regional_domain"    { value = aws_s3_bucket.this.bucket_regional_domain_name }
```

### 5. Example (`examples/basic/`)

```hcl
terraform {
  required_providers { aws = { source = "hashicorp/aws", version = "~> 5.50" } }
}

provider "aws" { region = var.region }
provider "aws" { alias = "us_east_1" region = "us-east-1" }

module "site" {
  source            = "../../modules/static-site"
  providers         = { aws.us_east_1 = aws.us_east_1 }
  domain_name       = var.domain_name
  subject_alt_names = ["www.${var.domain_name}"]
  hosted_zone_id    = var.hosted_zone_id
  tags              = { project = "static-site-demo" }
}

output "fqdn" { value = module.site.fqdn }
```

`terraform.tfvars.example`:
```
region          = "eu-central-1"
domain_name     = "example.com"
hosted_zone_id  = "Z123456EXAMPLE"
```

### 6. CI

`.github/workflows/ci.yml`:
- Checkout
- `hashicorp/setup-terraform@v3`
- `terraform fmt -check -recursive`
- `cd modules/static-site && terraform init -backend=false && terraform validate`
- `cd examples/basic && terraform init -backend=false && terraform validate`
- `terraform-linters/setup-tflint@v4` + `tflint --recursive`
- `aquasecurity/tfsec-action@v1.0.3` (or `bridgecrewio/checkov-action`)

Do **not** run `terraform plan` against AWS in CI — no creds, no need.

### 7. Docs

Run `terraform-docs markdown table modules/static-site/ > /tmp/inputs.md`,
embed via `<!-- BEGIN_TF_DOCS -->` markers in the module README so the bot
keeps it fresh. Same for examples/basic.

### 8. README (root)

1. **Title** — *terraform-aws-static-site — Production-grade static site on AWS in one module*
2. **Demo** — `docs/screenshots/tf-plan.png` of a clean plan (no apply needed)
3. **Architecture** — `docs/architecture.png` (S3 ← OAC ← CloudFront ← Route53 ← user; ACM in us-east-1)
4. **What it shows**:
   - Modern OAC pattern (not legacy OAI)
   - Cross-region ACM in us-east-1 done right
   - SPA-friendly 404 rewrites
   - Provider aliasing in modules
5. **Skills demonstrated** — Terraform, AWS, IaC, CloudFront, S3, ACM, Route53, GitHub Actions
6. **Quick start**:
   ```bash
   cd examples/basic
   cp terraform.tfvars.example terraform.tfvars
   terraform init && terraform plan
   ```
7. **Inputs / Outputs** — auto-generated tables (terraform-docs)
8. **Remote state suggestion** — S3 + DynamoDB lock snippet
9. **License** — MIT

### 9. Polish + flip public

Topics: `terraform`, `aws`, `iac`, `cloudfront`, `s3`, `route53`, `acm`,
`static-site`, `terraform-module`. Flip public.

## Verification

- [ ] `terraform fmt -check -recursive` clean
- [ ] `terraform validate` clean in module + example
- [ ] `tflint --recursive` clean (or warnings explained in README)
- [ ] `tfsec` / `checkov` clean (or waivers documented inline with `# tfsec:ignore:...`)
- [ ] `terraform-docs` produces no diff in committed README
- [ ] Plan output screenshot in repo, real, no real account ID exposed (replace with `<account-id>`)
- [ ] No hardcoded user paths or ARNs (per `path-portability-standards.md`)
- [ ] Topics + description set
- [ ] Module truly reusable: a fresh consumer with `domain_name` + `hosted_zone_id` can `init/plan` end-to-end

## Stretch (defer)

- Optional CloudFront Function for path rewrite / basic auth
- Optional Lambda@Edge for header injection
- WAF web ACL companion module
- Apply via OIDC + a public sandbox account (not happening — costs money)

v2 — not in v1 scope.
