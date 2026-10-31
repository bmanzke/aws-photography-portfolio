# ---------------------------------------------------------------
# Package the Python code: Terraform zips lambda_function.py from
# the repo's /lambda folder every time the code changes.
# ---------------------------------------------------------------
data "archive_file" "lambda_zip" {
  type        = "zip"
  source_file = "${path.module}/../lambda/lambda_function.py"
  output_path = "${path.module}/lambda.zip"
}

# ---------------------------------------------------------------
# The function itself - twin of the console-built PhotoPipeline
# ---------------------------------------------------------------
resource "aws_lambda_function" "photo_pipeline" {
  function_name = "PhotoPipeline-tf"
  role          = aws_iam_role.photo_pipeline.arn
  handler       = "lambda_function.lambda_handler"
  runtime       = "python3.12"

  filename         = data.archive_file.lambda_zip.output_path
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256

  layers      = ["arn:aws:lambda:us-east-1:770693421928:layer:Klayers-p312-Pillow:12"]
  memory_size = 512
  timeout     = 60

  environment {
    variables = {
      WEBSITE_BUCKET = aws_s3_bucket.website.id
      TABLE_NAME     = aws_dynamodb_table.photo_catalog.name
    }
  }
}

# ---------------------------------------------------------------
# The trigger: S3 (originals-tf) is allowed to invoke the function,
# and the bucket is told to send every object-create event.
# ---------------------------------------------------------------
resource "aws_lambda_permission" "allow_s3" {
  statement_id  = "AllowS3Invoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.photo_pipeline.function_name
  principal     = "s3.amazonaws.com"
  source_arn    = aws_s3_bucket.originals.arn
}

resource "aws_s3_bucket_notification" "originals_trigger" {
  bucket = aws_s3_bucket.originals.id

  lambda_function {
    lambda_function_arn = aws_lambda_function.photo_pipeline.arn
    events              = ["s3:ObjectCreated:*"]
  }

  # The permission must exist before S3 will accept the notification
  depends_on = [aws_lambda_permission.allow_s3]
}
