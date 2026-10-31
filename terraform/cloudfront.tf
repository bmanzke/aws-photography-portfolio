# ---------------------------------------------------------------
# CloudFront for the -tf stack: OAC + distribution + bucket policy
# Step 20 switchover: the real domain + ACM certificate now live
# here (they were freed from the hand-built distribution first).
# ---------------------------------------------------------------

# Look up things that already exist outside Terraform

data "aws_acm_certificate" "site" {
  domain      = "stemandstars.com"
  statuses    = ["ISSUED"]
  most_recent = true
}

data "aws_route53_zone" "site" {
  name = "stemandstars.com."
}

resource "aws_cloudfront_origin_access_control" "website" {
  name                              = "stemandstars-tf-oac"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

resource "aws_cloudfront_distribution" "website" {
  enabled             = true
  default_root_object = "index.html"
  comment             = "stemandstars-tf"
  aliases             = ["stemandstars.com", "www.stemandstars.com"]

  origin {
    domain_name              = aws_s3_bucket.website.bucket_regional_domain_name
    origin_id                = "website-s3"
    origin_access_control_id = aws_cloudfront_origin_access_control.website.id
  }

  default_cache_behavior {
    allowed_methods        = ["GET", "HEAD"]
    cached_methods         = ["GET", "HEAD"]
    target_origin_id       = "website-s3"
    viewer_protocol_policy = "redirect-to-https"
    cache_policy_id        = "658327ea-f89d-4fab-a63d-7e88639e58f6" # AWS managed: CachingOptimized
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  viewer_certificate {
    acm_certificate_arn      = data.aws_acm_certificate.site.arn
    ssl_support_method       = "sni-only"
    minimum_protocol_version = "TLSv1.2_2021"
  }
}

# DNS: point the domain (and www) at this distribution
resource "aws_route53_record" "apex" {
  zone_id = data.aws_route53_zone.site.zone_id
  name    = "stemandstars.com"
  type    = "A"

  alias {
    name                   = aws_cloudfront_distribution.website.domain_name
    zone_id                = aws_cloudfront_distribution.website.hosted_zone_id
    evaluate_target_health = false
  }
}

resource "aws_route53_record" "www" {
  zone_id = data.aws_route53_zone.site.zone_id
  name    = "www.stemandstars.com"
  type    = "A"

  alias {
    name                   = aws_cloudfront_distribution.website.domain_name
    zone_id                = aws_cloudfront_distribution.website.hosted_zone_id
    evaluate_target_health = false
  }
}

# Only this distribution may read the -tf website bucket
resource "aws_s3_bucket_policy" "website" {
  bucket = aws_s3_bucket.website.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid       = "AllowCloudFrontRead"
      Effect    = "Allow"
      Principal = { Service = "cloudfront.amazonaws.com" }
      Action    = "s3:GetObject"
      Resource  = "${aws_s3_bucket.website.arn}/*"
      Condition = {
        StringEquals = {
          "AWS:SourceArn" = aws_cloudfront_distribution.website.arn
        }
      }
    }]
  })
}

# Put the gallery page itself into the -tf website bucket
resource "aws_s3_object" "index_html" {
  bucket       = aws_s3_bucket.website.id
  key          = "index.html"
  source       = "${path.module}/../site/index.html"
  content_type = "text/html"
  etag         = filemd5("${path.module}/../site/index.html")
}

output "tf_site_address" {
  description = "The -tf stack's CloudFront address"
  value       = "https://${aws_cloudfront_distribution.website.domain_name}"
}
