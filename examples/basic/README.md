# examples/basic

Minimal consumer of `modules/static-site`. Wires the default AWS provider and
the required `us_east_1` aliased provider into the module, then exposes the
module outputs verbatim.

## Quick start

```sh
cp terraform.tfvars.example terraform.tfvars
# edit terraform.tfvars: replace example.com / placeholder zone ID with real values
terraform init
terraform plan
```

`terraform plan` requires an existing Route53 public hosted zone for the
domain. CI runs `terraform validate` only and never executes `apply`.

## Inputs

| Name | Type | Default | Description |
|---|---|---|---|
| `region` | `string` | `"eu-central-1"` | Primary AWS region. ACM is always pinned to us-east-1 by the module. |
| `domain_name` | `string` | _required_ | Primary FQDN (e.g. `www.example.com`). |
| `subject_alt_names` | `list(string)` | `[]` | Extra FQDNs added as ACM SANs and CloudFront aliases. |
| `hosted_zone_id` | `string` | _required_ | Route53 hosted zone ID. |
| `tags` | `map(string)` | `{ Project = "terraform-aws-static-site-example" }` | Tags merged onto every taggable resource. |

## Outputs

Re-exposes every output from `modules/static-site`: `bucket_name`,
`bucket_regional_domain`, `cloudfront_domain`, `cloudfront_distribution_id`,
`fqdn`.
