output "bucket_name" {
  description = "ID of the origin S3 bucket."
  value       = aws_s3_bucket.this.id
}

output "bucket_regional_domain" {
  description = "Regional domain name of the origin bucket; useful for cross-account audits."
  value       = aws_s3_bucket.this.bucket_regional_domain_name
}

output "cloudfront_domain" {
  description = "*.cloudfront.net hostname assigned to the distribution."
  value       = aws_cloudfront_distribution.this.domain_name
}

output "cloudfront_distribution_id" {
  description = "Distribution ID; pass to invalidation tooling."
  value       = aws_cloudfront_distribution.this.id
}

output "fqdn" {
  description = "Primary FQDN configured on the distribution."
  value       = var.domain_name
}
