data "archive_file" "contact_zip" {
  type        = "zip"
  source_file = "${path.module}/../contact/contact_handler.py"
  output_path = "${path.module}/contact.zip"
}

# Execution role: Lambda may borrow it; it may send email + write logs
resource "aws_iam_role" "contact_form" {
  name = "ContactForm-tf-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy" "contact_form" {
  name = "ContactFormPolicy-tf"
  role = aws_iam_role.contact_form.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "SendInquiryEmail"
        Effect   = "Allow"
        Action   = "ses:SendEmail"
        Resource = "arn:aws:ses:us-east-1:288581186506:identity/brett.manzke@gmail.com"
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

# The function itself
resource "aws_lambda_function" "contact_form" {
  function_name = "ContactForm-tf"
  role          = aws_iam_role.contact_form.arn
  handler       = "contact_handler.lambda_handler"
  runtime       = "python3.12"

  filename         = data.archive_file.contact_zip.output_path
  source_code_hash = data.archive_file.contact_zip.output_base64sha256

  memory_size = 128
  timeout     = 10

  environment {
    variables = {
      RECIPIENT_EMAIL = "brett.manzke@gmail.com"
    }
  }
}

# The public door: an HTTP API with one route
resource "aws_apigatewayv2_api" "contact" {
  name          = "StemAndStarsContact-tf"
  protocol_type = "HTTP"

  cors_configuration {
    allow_origins = ["https://stemandstars.com"]
    allow_methods = ["POST", "OPTIONS"]
    allow_headers = ["content-type"]
  }
}

resource "aws_apigatewayv2_integration" "contact" {
  api_id                 = aws_apigatewayv2_api.contact.id
  integration_type       = "AWS_PROXY"
  integration_uri        = aws_lambda_function.contact_form.invoke_arn
  payload_format_version = "2.0"
}

resource "aws_apigatewayv2_route" "contact" {
  api_id    = aws_apigatewayv2_api.contact.id
  route_key = "POST /contact"
  target    = "integrations/${aws_apigatewayv2_integration.contact.id}"
}

resource "aws_apigatewayv2_stage" "contact" {
  api_id      = aws_apigatewayv2_api.contact.id
  name        = "$default"
  auto_deploy = true
}

# API Gateway is allowed to invoke the function
resource "aws_lambda_permission" "allow_apigw" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.contact_form.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.contact.execution_arn}/*/*"
}

output "contact_endpoint" {
  value = "${aws_apigatewayv2_api.contact.api_endpoint}/contact"
}