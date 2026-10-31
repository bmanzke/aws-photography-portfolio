# ---------------------------------------------------------------
# IAM role the -tf Lambda borrows when it runs (its "execution role")
# ---------------------------------------------------------------
resource "aws_iam_role" "photo_pipeline" {
  name = "PhotoPipeline-tf-role"

  # Trust policy: only the Lambda service may borrow this role
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

# The permissions themselves - the Appendix C policy, pointed at the -tf stack
resource "aws_iam_role_policy" "photo_pipeline" {
  name = "PhotoPipelinePolicy-tf"
  role = aws_iam_role.photo_pipeline.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "ReadOriginals"
        Effect   = "Allow"
        Action   = "s3:GetObject"
        Resource = "arn:aws:s3:::brettmanzke-photo-originals-tf/*"
      },
      {
        Sid      = "WriteWebsite"
        Effect   = "Allow"
        Action   = "s3:PutObject"
        Resource = "arn:aws:s3:::stemandstars-tf.com/*"
      },
      {
        Sid      = "CatalogAccess"
        Effect   = "Allow"
        Action   = ["dynamodb:PutItem", "dynamodb:Scan"]
        Resource = aws_dynamodb_table.photo_catalog.arn
      },
      {
        Sid      = "WriteLogs"
        Effect   = "Allow"
        Action   = ["logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents"]
        Resource = "*"
      }
    ]
  })
}
