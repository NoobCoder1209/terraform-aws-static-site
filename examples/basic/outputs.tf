output "bucket_name" {
  description = "ID of the origin S3 bucket."
  value       = module.static_site.bucket_name
}

output "bucket_regional_domain" {
  description = "Regional domain name of the origin bucket."
  value       = module.static_site.bucket_regional_domain
}

output "cloudfront_domain" {
  description = "*.cloudfront.net hostname assigned to the distribution."
  value       = module.static_site.cloudfront_domain
}

output "cloudfront_distribution_id" {
  description = "Distribution ID; pass to invalidation tooling."
  value       = module.static_site.cloudfront_distribution_id
}

output "fqdn" {
  description = "Primary FQDN configured on the distribution."
  value       = module.static_site.fqdn
}
