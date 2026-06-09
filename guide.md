# Guide — `terraform-aws-static-site`

> Last verified: as of commit `1c5c6bb` (main HEAD before this PR), 2026-06-09. Ran every CI-equivalent step locally on macOS arm64 with Terraform v1.15.5 and `terraform-docs v0.24.0`: `terraform fmt -check -recursive` clean, `terraform init -backend=false` succeeded for both `modules/static-site/` and `examples/basic/`, `terraform validate` returned "Success! The configuration is valid." against the example, and `terraform-docs -c .terraform-docs.yml --output-check modules/static-site` reported the README is up to date. The credential-bound step (`terraform plan` against AWS) was NOT run — see [Demo verification status](#demo-verification-status) below.

This document is for someone who has never touched the repo. It covers what the module does, how to exercise the demo end-to-end, what every directory contains, and how to recover from common failure modes.

## Table of contents

1. [What this repo is](#what-this-repo-is)
2. [Prerequisites](#prerequisites)
3. [Run the demo end-to-end](#run-the-demo-end-to-end)
4. [What each directory and file does](#what-each-directory-and-file-does)
5. [Environment variables and secrets](#environment-variables-and-secrets)
6. [How to verify the demo worked](#how-to-verify-the-demo-worked)
7. [Common failure modes and fixes](#common-failure-modes-and-fixes)
8. [Demo verification status](#demo-verification-status)
9. [README screenshot status](#readme-screenshot-status)

---

## What this repo is

A reusable Terraform module that provisions a static-site stack on AWS:

- Private S3 bucket (BucketOwnerEnforced, public access blocked, AES256, lifecycle aborting incomplete multipart uploads after 7 days)
- CloudFront distribution with Origin Access Control (SigV4)
- ACM certificate in `us-east-1` (DNS-validated through Route53, SAN-dedup-aware)
- Route53 ALIAS A + AAAA records for the apex and every SAN
- Optional SPA mode (403/404 → `/index.html` 200) and optional WAFv2 hook

The module lives in `modules/static-site/`. A consuming root module that wires it up lives in `examples/basic/`. The repo is intentionally **Pattern 3** — no `terraform apply` runs in CI, and the README ships no real account ID or ARN.

## Prerequisites

You only need a few of these depending on how far you want to go:

| Goal | Required tools |
|---|---|
| Inspect / read the code | git |
| Run the static-analysis demo (no AWS account) | git, Terraform 1.7+ (CI uses 1.10.5) |
| Run the full demo with `terraform plan` | All of the above + AWS credentials + a real Route53 hosted zone you own |
| Regenerate the module README | `terraform-docs` v0.24.0 |
| Match what CI runs locally | `tflint` v0.50+, `tfsec` |

Quickest setup on macOS:

```sh
brew install terraform terraform-docs tflint tfsec
```

On Linux:

```sh
# Terraform
curl -fsSL https://apt.releases.hashicorp.com/gpg | sudo apt-key add -
sudo apt-add-repository "deb [arch=amd64] https://apt.releases.hashicorp.com $(lsb_release -cs) main"
sudo apt-get update && sudo apt-get install terraform

# terraform-docs (matches the version pinned in CI)
curl -sSLo terraform-docs.tar.gz \
  https://terraform-docs.io/dl/v0.24.0/terraform-docs-v0.24.0-linux-amd64.tar.gz
tar -xzf terraform-docs.tar.gz terraform-docs
sudo mv terraform-docs /usr/local/bin/

# tflint
curl -sSL https://raw.githubusercontent.com/terraform-linters/tflint/master/install_linux.sh | bash
```

## Run the demo end-to-end

The full demo has two layers — a **no-credentials** layer that anyone can run, and an **AWS-credentialed** layer that requires a real Route53 zone.

### Layer 1 — no AWS account (matches CI)

```sh
git clone https://github.com/NoobCoder1209/terraform-aws-static-site
cd terraform-aws-static-site

# 1. Format check
terraform fmt -check -recursive

# 2. Resolve provider versions for the module (does not contact AWS)
terraform -chdir=modules/static-site init -backend=false

# 3. Resolve provider versions for the example
terraform -chdir=examples/basic init -backend=false

# 4. Type-check the example. The module standalone CANNOT be validated
#    directly — it declares `configuration_aliases = [aws.us_east_1]`
#    and there is no provider config in the module to satisfy that
#    alias. Validate via the example, which IS the supported path.
terraform -chdir=examples/basic validate

# 5. (Optional, if installed) Lint the whole tree.
tflint --init && tflint --recursive --format=compact

# 6. (Optional, if installed) Static security scan.
tfsec .

# 7. (Optional, if installed) Confirm the module's auto-generated
#    inputs/outputs table is in sync with variables.tf and outputs.tf.
terraform-docs -c .terraform-docs.yml --output-check modules/static-site
```

### Layer 2 — `terraform plan` against AWS

This requires AWS credentials with read access to ACM, CloudFront, IAM, Route53, and S3, plus a real Route53 public hosted zone you own. `example.com` is reserved by IANA and never resolves; you must replace it.

```sh
cd examples/basic

cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars:
#   - region:           your preferred AWS region for the S3 bucket
#   - domain_name:      a hostname inside YOUR Route53 zone (e.g. www.your-domain.com)
#   - subject_alt_names: extra hostnames inside the same zone (or [])
#   - hosted_zone_id:   the ID of YOUR Route53 zone

# Authenticate with AWS in the way that suits you:
aws sso login --profile <your-sandbox-profile>
export AWS_PROFILE=<your-sandbox-profile>
# OR set AWS_ACCESS_KEY_ID / AWS_SECRET_ACCESS_KEY directly

terraform plan -out tfplan.binary
terraform show -no-color tfplan.binary
```

`terraform plan` is read-only and never creates or destroys anything. There is no `apply` step in this guide on purpose.

## What each directory and file does

```
.
├── README.md                       Public-facing pitch + usage snippet + architecture diagram
├── guide.md                        THIS FILE — onboarding for new contributors / reviewers
├── LICENSE                         MIT license
├── .gitignore                      Terraform working dirs, state, user tfvars (allows .tfvars.example)
├── .tflint.hcl                     Pins tflint AWS plugin v0.47.0 + recommended terraform preset
├── .terraform-docs.yml             Drives the auto-generated inputs/outputs section in the module README
├── .github/
│   └── workflows/
│       └── ci.yml                  Static analysis only — fmt, validate, tflint, tfsec, terraform-docs check
├── modules/
│   └── static-site/                THE MODULE
│       ├── main.tf                 S3 + OAC + CloudFront + ACM + Route53 resources
│       ├── variables.tf            All 9 input variables with descriptions and validation
│       ├── outputs.tf              5 outputs (bucket_name, cloudfront_domain, distribution_id, fqdn, regional_domain)
│       ├── versions.tf             terraform >=1.7, aws >=5.50 <6.0, configuration_aliases = [aws.us_east_1]
│       └── README.md               Module reference; inputs/outputs auto-generated between markers
├── examples/
│   └── basic/                      MINIMAL CONSUMER OF THE MODULE
│       ├── main.tf                 Two providers (default + us_east_1 alias) wired into a single module call
│       ├── variables.tf            region, domain_name, subject_alt_names, hosted_zone_id, tags
│       ├── outputs.tf              Re-exposes every module output
│       ├── versions.tf             terraform >=1.7, aws >=5.50 <6.0 (NO configuration_aliases — root modules don't use that)
│       ├── terraform.tfvars.example  Template values; copy to terraform.tfvars before running plan
│       ├── .terraform.lock.hcl     Committed for reproducible CI runs (consumer root owns the lock)
│       └── README.md               Example-specific quick start
└── docs/
    ├── architecture.png            Mermaid-rendered architecture diagram embedded in the root README
    ├── architecture.mmd            Source for architecture.png; edit + re-render with `mmdc`
    └── screenshots/
        └── README.md               How to capture a redacted `terraform plan` screenshot when needed
```

## Environment variables and secrets

Layer 1 (no AWS account) needs **none**.

Layer 2 (`terraform plan` against AWS) needs AWS credentials. The exact mechanism is up to you; Terraform's AWS provider honours the standard credential chain:

| Mechanism | How |
|---|---|
| AWS SSO (recommended for sandbox accounts) | `aws sso login --profile <p>` then `export AWS_PROFILE=<p>` |
| Static keys | `export AWS_ACCESS_KEY_ID=…` and `export AWS_SECRET_ACCESS_KEY=…` |
| Instance / container role | Just run from an EC2 instance / ECS task that has the role attached |
| `~/.aws/credentials` profile | `export AWS_PROFILE=<p>` |

**Do not commit any of these.** `terraform.tfvars` is gitignored; `.aws/credentials` lives in `$HOME` and never enters the repo. If you accidentally commit a credential, rotate it first, then scrub history (see `~/.claude/rules/git-safety-standards.md` for the exact procedure if applicable).

There are NO repository secrets configured in GitHub Actions — CI runs only static analysis and never assumes an AWS role. The `GITHUB_TOKEN` referenced in the workflow is the built-in token GitHub Actions provides automatically; nothing for you to set.

## How to verify the demo worked

### Layer 1 expected output

| Step | Expected result |
|---|---|
| `terraform fmt -check -recursive` | Exit 0, no output |
| `terraform -chdir=modules/static-site init -backend=false` | "Terraform has been successfully initialized!" |
| `terraform -chdir=examples/basic init -backend=false` | "Terraform has been successfully initialized!" |
| `terraform -chdir=examples/basic validate` | "Success! The configuration is valid." |
| `tflint --recursive --format=compact` | Exit 0, no output (or warnings about unused vars in stretch examples) |
| `tfsec .` | Some advisory findings on access logging are expected and acceptable for v0.1 (CI runs with `soft_fail: true`) |
| `terraform-docs -c .terraform-docs.yml --output-check modules/static-site` | "modules/static-site/README.md is up to date" |

### Layer 2 expected output

A successful `terraform plan` produces a "Plan: N to add, 0 to change, 0 to destroy" line at the bottom. For this module with `domain_name` only and **no SANs**, expect **13 resources** to be created — 6 S3 resources (bucket + 5 sibling configurations including the policy), 1 Origin Access Control, 1 CloudFront distribution, 1 ACM certificate + 1 ACM certificate validation, 1 DNS validation Route53 record, and 2 ALIAS records (A + AAAA for the apex). Add 2 more ALIAS records per SAN (a SAN that does not overlap an existing wildcard also adds 1 DNS validation record). SPA mode does NOT add resources — it's a `dynamic "custom_error_response"` block inside the existing CloudFront distribution.

If you see a `Plan: 0 to add` line, something is wrong — see common failure modes below.

## Common failure modes and fixes

### `Error: Module module.static_site does not declare a provider named "aws.us_east_1"`

The consumer's `module` block is missing the `providers = { aws.us_east_1 = aws.us_east_1 }` mapping, or the consumer never declared a `provider "aws" { alias = "us_east_1" ... }` block. See `examples/basic/main.tf` for the canonical wiring.

### `Error: Provider configuration not present` when running `terraform validate` directly inside `modules/static-site/`

Expected. Child modules with `configuration_aliases` cannot be validated standalone — the alias slot has no provider configuration to satisfy it. Validate via the example instead:

```sh
terraform -chdir=examples/basic validate
```

### `Error: reading Route 53 Hosted Zone (Z00000000000000000000): NoSuchHostedZone`

(Wording approximate; the AWS provider varies the casing slightly between versions.) Your `hosted_zone_id` in `terraform.tfvars` is the placeholder. Replace it with a real zone ID you own (`aws route53 list-hosted-zones --query 'HostedZones[].Id' --output table`).

### `Error: error creating ACM Certificate: ValidationException: ... not authorized`

ACM certificates for CloudFront must be created in `us-east-1`. The module handles this via the aliased provider — but only if the consumer wires both `aws` and `aws.us_east_1` into the `providers` map. Re-check `examples/basic/main.tf`.

### `terraform-docs` CI step fails with "Uncommitted change(s) has been found!"

You changed a variable or output in `modules/static-site/` without regenerating the README. Run:

```sh
terraform-docs -c .terraform-docs.yml modules/static-site
git add modules/static-site/README.md
```

Then commit. CI will pass next push.

### `tflint --init` rate-limited

Anonymous GitHub API hits the rate limit at 60/hour. Set `GITHUB_TOKEN`:

```sh
export GITHUB_TOKEN=<your-token-or-gh-cli-token>
tflint --init
```

CI does this automatically via `${{ github.token }}`.

### `terraform plan` says `Plan: 0 to add, 0 to change, 0 to destroy`

Something in your tfvars matches existing AWS resources by name and Terraform thinks it's already managed. Most often: a previous `terraform apply` left state behind. Wipe local state:

```sh
rm -rf examples/basic/.terraform examples/basic/terraform.tfstate*
terraform -chdir=examples/basic init -backend=false
terraform -chdir=examples/basic plan
```

(This is safe for this module because no `apply` runs in CI — your local state is the only state.)

### Mermaid diagram doesn't render in `docs/architecture.mmd` after edits

The committed PNG is generated from the `.mmd` source via `mmdc` (mermaid-cli). After editing the source, regenerate:

```sh
npx -y @mermaid-js/mermaid-cli@latest -i docs/architecture.mmd -o docs/architecture.png -b white -w 1400
```

Then commit both files.

---

## Demo verification status

**Status: PARTIAL.** Every step that does not require AWS credentials has been run on this machine on 2026-06-09 against commit `1c5c6bb`. The output is captured at the top of this file under "Last verified".

**Step that was NOT run:** `terraform plan` against a live AWS account with a real Route53 zone (Layer 2 above). Reason: this session has no AWS sandbox profile configured and no Route53 zone to point at. Reproducing it requires resources that only the repo owner controls.

**To complete the verification yourself, run** (one shell session, ~2 minutes):

```sh
cd examples/basic

# 1. Make sure you have a Route53 zone ready
aws route53 list-hosted-zones --query 'HostedZones[?Config.PrivateZone==`false`].[Id,Name]' --output table
# Note the zone ID and a matching domain name from the output.

# 2. Configure the example
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars:
#   region            = "<your-region>"
#   domain_name       = "<host-inside-your-zone>"
#   hosted_zone_id    = "<id-from-step-1-without-the-/hostedzone/-prefix>"
#   subject_alt_names = []

# 3. Authenticate
aws sso login --profile <your-sandbox-profile>
export AWS_PROFILE=<your-sandbox-profile>

# 4. Plan
terraform init
terraform plan
```

Expected: a clean `Plan: 15 to add, 0 to change, 0 to destroy` (or 15 + 2 per SAN). If it succeeds, please update this file's "Last verified" line at the top to confirm Layer 2 was exercised.

## README screenshot status

**Status: NO demo screenshot in the README. ARCHITECTURE diagram present.**

The root README embeds `docs/architecture.png` (a Mermaid-rendered architecture diagram), which conveys the module's component layout. It does NOT include a `terraform plan` screenshot, which is the closest thing to a "demo" output for a Pattern 3 Terraform module.

**This omission is deliberate.** Reproducing a meaningful `terraform plan` screenshot requires AWS credentials and a real Route53 zone — the same blockers that prevent autonomous Layer 2 verification. The repo deliberately ships no real account ID or ARN, and a hand-redacted screenshot adds a hand-edit risk for marginal informational value when the architecture diagram already exists.

`docs/screenshots/README.md` documents the recording recipe in full. Summary, if you want to add one:

```sh
# 1. Complete Layer 2 verification above.
# 2. With AWS_PROFILE still set:
cd examples/basic
terraform plan -no-color > tfplan.txt
# 3. Open tfplan.txt in a fixed-width viewer (any terminal, or VS Code with
#    Word Wrap off and a monospace font). Capture a screenshot showing the
#    "Terraform will perform the following actions:" header through the
#    "Plan: N to add, 0 to change, 0 to destroy" line.
# 4. Redact:
#    - Any 12-digit AWS account ID anywhere in ARNs → <account-id>
#    - Any real Route53 zone ID if you don't want it public → Z<redacted>
#    - Any real bucket-randomness suffix → <bucket-suffix>
# 5. Save as docs/screenshots/tf-plan.png and add an `![tf plan](...)`
#    embed to the root README under the existing "## Plan output" heading.
```

The exact one-line recording scenario, if you want to capture it manually:

> Open a 120-column terminal, `cd examples/basic`, run `terraform plan`, scroll to show "Plan: N to add" through the trailing newline, capture the visible terminal pane, redact the 12-digit account ID and any real zone ID, save as `docs/screenshots/tf-plan.png`.
