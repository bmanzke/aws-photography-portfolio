# ---------------------------------------------------------------------------
# Step 21 CI/CD: GitHub Actions deploys the site using OIDC (no stored keys).
# GitHub proves "I am bmanzke/aws-photography-portfolio" with a short-lived
# token; AWS lets that token assume github-deploy-role, which can ONLY sync
# the website bucket and invalidate this one distribution. Nothing else.
# ---------------------------------------------------------------------------

resource "aws_iam_openid_connect_provider" "github" {
  url             = "https://token.actions.githubusercontent.com"
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = ["6938fd4d98bab03faadb97b34396831e3780aea1"]
}

resource "aws_iam_role" "github_deploy" {
  name = "github-deploy-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Federated = aws_iam_openid_connect_provider.github.arn
      }
      Action = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = {
          "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
        }
        # GitHub's sub claim now embeds numeric IDs (found via CloudTrail,
        # Oct 31 2026): repo:<owner>@<owner-id>/<repo>@<repo-id>:ref:...
        StringLike = {
          "token.actions.githubusercontent.com:sub" = "repo:bmanzke@214350599/aws-photography-portfolio@1440835875:*"
        }
      }
    }]
  })
}

resource "aws_iam_role_policy" "github_deploy" {
  name = "GitHubDeployPolicy"
  role = aws_iam_role.github_deploy.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "ListSiteBucket"
        Effect   = "Allow"
        Action   = ["s3:ListBucket"]
        Resource = [aws_s3_bucket.website.arn]
      },
      {
        Sid    = "SyncSiteFiles"
        Effect = "Allow"
        Action = [
          "s3:PutObject",
          "s3:DeleteObject",
          "s3:GetObject"
        ]
        Resource = ["${aws_s3_bucket.website.arn}/*"]
      },
      {
        Sid      = "InvalidateSite"
        Effect   = "Allow"
        Action   = ["cloudfront:CreateInvalidation"]
        Resource = [aws_cloudfront_distribution.website.arn]
      }
    ]
  })
}

output "github_deploy_role_arn" {
  value = aws_iam_role.github_deploy.arn
}
