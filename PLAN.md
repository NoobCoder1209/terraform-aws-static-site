# `terraform-aws-static-site` — Execution Plan

## How to use this plan

You are the build session for this repo. Read this file end-to-end, then start executing immediately.

**Working agreement:**

1. **Start without waiting.** Begin Phase 1 in the *Subagent playbook* below.
2. **Always ask the user about business decisions and business logic.** Sample domain placeholder, README copy, optional WAF inclusion, whether the user will actually use this module to host `chapkanov-dev`. The "Business decisions" section below lists them.
3. **Ask the user when you are genuinely blocked.**
4. **Do not ask the user about engineering details.** Variable shape, output names, file layout — your call.
5. **Use subagents aggressively.** Default to the playbook below.
6. **TaskCreate / TaskUpdate everything.**
7. **Pattern 3 only.** No `terraform apply` against AWS in this repo. README ships `terraform plan` screenshots only. Never commit a real account ID or ARN.
8. **Follow shared standards** (MIT, README, CI, topics, private until verified).
9. **All `Agent` tool calls must pass `model: "opus"`.**
10. **Off-limits forever:** SAP-internal Terraform patterns, GCP/Hyperspace specifics, `~/.claude/`, RCA content. Module is generic AWS.

## Subagent playbook (this repo)

Heavy on linter/validator subagents. 3 in research, 2 in review.

**Phase 1 — Research (parallel):**
- `Explore` (Opus): "Find current best-practice Terraform module shape for static-site (S3 + CloudFront + ACM us-east-1 + Route53 + OAC). Cite the AWS provider docs version 5.50+ and a reputable community module. Return a 200-word architecture summary."
- `Explore` (Opus): "Find the canonical pattern for cross-region ACM via aliased provider in a child module (consumer must pass `providers = { aws.us_east_1 = ... }`). Return a working example."
- `Explore` (Opus): "Find current `tfsec` / `checkov` / `tflint` GitHub Actions setup, including SARIF upload, for a Terraform repo with a module + example. Return a working CI workflow."

**Phase 2 — Design (single):**
- `Plan` (Opus): "Given research and this PLAN.md, propose the module's file layout, variable list with types/defaults, and outputs. Return as a checklist."

**Phase 3 — Build:** main session writes `main.tf`, `variables.tf`, `outputs.tf`, example, CI.

**Phase 4 — Review (parallel):**
- `code-reviewer` (Opus): "Review for: bucket policy correctness with OAC, ACM us-east-1 wiring, SPA mode 404 rewrite, Route53 ALIAS records (A + AAAA), tfsec/checkov findings, no hardcoded ARNs / accounts. High effort."
- `tester` (Opus): "Verify `terraform fmt -check`, `validate`, `tflint`, `tfsec` all clean. Confirm `terraform plan` from the example produces a sane plan against fake-but-valid inputs."

**Phase 5 — Polish:** capture `terraform plan` screenshot with account-ID redacted, ask user before flipping public.

---

## Goal

End-to-end Terraform IaC that provisions the canonical "static site on AWS"
stack: S3 (private, OAC-fronted) + CloudFront + ACM + Route53. Reusable as a
**module** so consumers wire it into their own root config in ~15 lines.

**Sells:** Terraform, AWS, IaC, CloudFront, S3, ACM, Route53, GitHub Actions.

## Business decisions to ask the user about

- **Sample domain placeholder in the example** — `example.com` (recommended) vs a future `chapkanov.dev`.
- **Whether to include a `web_acl_id` variable** that's wired but unused without a real WAF — recommend yes, costs nothing, signals depth.
- **Whether the user wants to actually use this module to deploy `chapkanov-dev`** later — affects example tone, doesn't change the v1 module.

## Scope (must-haves)

1. Terraform module under `modules/static-site/` with these resources:
   - S3 bucket (private; bucket policy granting only the OAC)
   - CloudFront distribution with default root object, SPA-friendly 404→index rewrite, HTTPS only, gzip+brotli
   - Origin Access Control (modern replacement for OAI)
   - ACM certificate **in `us-east-1`**, DNS-validated via Route53
   - Route53 ALIAS A + AAAA records pointing at CloudFront
2. `examples/basic/` — minimal root config consuming the module with one custom domain
3. Remote state pattern documented in README (S3 backend + DynamoDB lock); example uses `local` backend so anyone can `plan` it
4. Outputs: bucket name, CloudFront domain, distribution ID, FQDN, bucket regional domain
5. Variables documented inline + via `terraform-docs`
6. CI: `terraform fmt -check`, `tflint`, `terraform validate`, `tfsec`
7. README with architecture diagram

## Out of scope

- No `apply` in CI
- No multi-region replication
- No CloudFront Functions / Lambda@Edge code
- No real WAF rules (variable hook only)
- No site content publishing
- No Terraform registry publication

## Tech stack

- **Terraform:** v1.7+
- **Provider:** `hashicorp/aws` v5.50+ (us-east-1 alias for ACM, primary configurable)
- **Linters:** `terraform fmt`, `tflint`, `tfsec`
- **Docs:** `terraform-docs`
- **CI:** GitHub Actions

## File tree

```
terraform-aws-static-site/
  README.md
  PLAN.md
  LICENSE
  .gitignore                  ← .terraform/, *.tfstate*, *.tfvars (allow .tfvars.example)
  modules/static-site/
    README.md
    main.tf
    variables.tf
    outputs.tf
    versions.tf
    providers.tf              ← aliased "us-east-1" provider for ACM
  examples/basic/
    README.md
    main.tf
    variables.tf
    outputs.tf
    terraform.tfvars.example
  .github/workflows/ci.yml
  docs/
    architecture.png
    screenshots/tf-plan.png
```

## Step-by-step build

### 1. Module skeleton

```hcl
terraform { required_version = ">= 1.7.0" }
required_providers { aws = { source = "hashicorp/aws", version = "~> 5.50" } }
```

`providers.tf` declares an aliased `us-east-1` provider; consumer passes `providers = { aws.us_east_1 = aws.us_east_1 }`.

### 2. Variables

```hcl
variable "domain_name"        { type = string }
variable "subject_alt_names"  { type = list(string) default = [] }
variable "hosted_zone_id"     { type = string }
variable "bucket_name"        { type = string default = null }
variable "price_class"        { type = string default = "PriceClass_100" }
variable "default_root_object"{ type = string default = "index.html" }
variable "spa_mode"           { type = bool default = true }
variable "tags"               { type = map(string) default = {} }
variable "web_acl_id"         { type = string default = null }
```

### 3. Resources (key behaviour)

- **S3 bucket**: BucketOwnerEnforced, public access block all on, AES256 SSE, versioning disabled, abort multipart > 7 days.
- **OAC**: SigV4, always sign.
- **Bucket policy**: `s3:GetObject` to `Service: cloudfront.amazonaws.com` with `AWS:SourceArn` matching the distribution.
- **ACM in us-east-1** with `domain_name` + `subject_alt_names`. DNS validation Route53 records auto-created. `aws_acm_certificate_validation` blocks until issued.
- **CloudFront**:
  - Single S3 origin via OAC
  - Aliases = `[domain_name] + subject_alt_names`
  - Viewer cert = validated ACM, sni-only, TLSv1.2_2021
  - Default cache behaviour: redirect-to-https, GET+HEAD, AWS managed `CachingOptimized`, response policy `SecurityHeadersPolicy`
  - `custom_error_response`: when `var.spa_mode`, 403/404 → `/index.html` 200
  - Compress = true
  - `web_acl_id = var.web_acl_id`
- **Route53**: A + AAAA ALIAS for `domain_name` and each SAN.

### 4. Outputs

```hcl
output "bucket_name"               { value = aws_s3_bucket.this.id }
output "cloudfront_domain"         { value = aws_cloudfront_distribution.this.domain_name }
output "cloudfront_distribution_id"{ value = aws_cloudfront_distribution.this.id }
output "fqdn"                      { value = aws_route53_record.a.fqdn }
output "bucket_regional_domain"    { value = aws_s3_bucket.this.bucket_regional_domain_name }
```

### 5. Example (`examples/basic/`)

Two providers (default + us-east-1 alias). Module call passes them. `terraform.tfvars.example` with `region`, `domain_name`, `hosted_zone_id`.

### 6. CI

- Checkout
- `hashicorp/setup-terraform@v3`
- `terraform fmt -check -recursive`
- `cd modules/static-site && terraform init -backend=false && terraform validate`
- `cd examples/basic && terraform init -backend=false && terraform validate`
- `terraform-linters/setup-tflint@v4` + `tflint --recursive`
- `aquasecurity/tfsec-action@v1.0.3`

No `terraform plan` against AWS.

### 7. Docs

`terraform-docs markdown table modules/static-site/` embedded between markers. Same for `examples/basic`.

### 8. README

1. Title — *terraform-aws-static-site — Production-grade static site on AWS in one module*
2. Demo — `docs/screenshots/tf-plan.png`
3. Architecture — `docs/architecture.png`
4. What it shows — modern OAC, cross-region ACM, SPA 404 rewrites, provider aliasing
5. Skills demonstrated — Terraform, AWS, IaC, CloudFront, S3, ACM, Route53, GitHub Actions
6. Quick start: `cd examples/basic && cp terraform.tfvars.example terraform.tfvars && terraform init && terraform plan`
7. Inputs / Outputs — auto-generated tables
8. Remote state suggestion — S3 + DynamoDB lock snippet
9. License — MIT

### 9. Polish + flip public

Topics: `terraform`, `aws`, `iac`, `cloudfront`, `s3`, `route53`, `acm`, `static-site`, `terraform-module`. Ask user before flipping.

## Verification

- [ ] `terraform fmt -check -recursive` clean
- [ ] `terraform validate` clean in module + example
- [ ] `tflint --recursive` clean (or warnings explained)
- [ ] `tfsec` / `checkov` clean (or waivers `# tfsec:ignore:...`)
- [ ] `terraform-docs` no diff in committed README
- [ ] Plan screenshot, account ID redacted (`<account-id>`)
- [ ] No hardcoded user paths or ARNs (per `path-portability-standards`)
- [ ] Topics + description set
- [ ] Module reusable: fresh consumer with `domain_name` + `hosted_zone_id` can `init/plan`

## Stretch (defer)

- CloudFront Function for path rewrite / basic auth
- Lambda@Edge for header injection
- WAF web ACL companion module
- OIDC + sandbox-account apply (costs money — skip)
