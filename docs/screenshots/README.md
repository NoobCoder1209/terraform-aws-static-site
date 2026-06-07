# How to capture a `terraform plan` screenshot

This module is intentionally Pattern 3 — no `terraform apply` runs in CI, no real
AWS account is wired in, and there is no committed plan capture. Reproducing one
requires:

1. **A real Route53 public hosted zone.** `example.com` is reserved by IANA and
   never resolves; you need a domain you control (or a delegated subdomain).
2. **AWS credentials** with read access to ACM, CloudFront, IAM, Route53, and S3.
   A read-only sandbox account is sufficient — `plan` makes no destructive calls.

## Steps

```sh
cd examples/basic
cp terraform.tfvars.example terraform.tfvars
# edit terraform.tfvars: set hosted_zone_id to a real zone you own,
# domain_name to a host inside that zone (e.g. www.your-domain.com),
# and region to your preferred AWS region.

aws sso login --profile <your-sandbox-profile>
export AWS_PROFILE=<your-sandbox-profile>

terraform init
terraform plan -out tfplan.binary

# Render the plan to a screen-friendly fixed-width view:
terraform show -no-color tfplan.binary > tfplan.txt
```

Take a screenshot of the `terraform plan` output (or `tfplan.txt` opened in a
fixed-width viewer). Before committing it, redact:

- The 12-digit AWS account ID anywhere in ARNs → `<account-id>`
- Any real bucket-randomness suffix that ties back to your account → `<bucket-suffix>`
- Any real Route53 zone ID if you don't want it public → `Z<redacted>`

Save the screenshot as `docs/screenshots/tf-plan.png` and reference it from the
repository README.

## Why this isn't shipped today

This is a portfolio module, not a deployment. Wiring a real account just to
generate a screenshot adds a paid AWS dependency to a free-to-clone repo, and
any redaction step is a hand-edit risk. The architecture diagram in the root
README conveys the same information without the redaction burden.
