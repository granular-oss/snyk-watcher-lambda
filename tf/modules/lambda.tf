variable "ACCOUNT_ID" {}
variable "REGION" { default = "us-east-1" }
variable "LAMBDA_ZIP_PATH" {}
variable "DRY_RUN" {}
variable "HOOK_VALIDATION_TOKEN" {}
variable "SNYK_TOKEN" {}

resource "aws_lambda_function" "snyk_watcher" {
  filename         = var.LAMBDA_ZIP_PATH
  source_code_hash = filesha256(var.LAMBDA_ZIP_PATH)
  function_name    = "snyk-watcher"
  handler          = "snyk-watcher.lambda_handler"
  role             = "arn:aws:iam::${var.ACCOUNT_ID}:role/REPLACE_ME"
  memory_size      = 192
  runtime          = "python3.8"
  timeout          = 600

  environment {
    variables = {
      HOOK_VALIDATION_TOKEN = var.HOOK_VALIDATION_TOKEN
      DRY_RUN               = var.DRY_RUN
      SNYK_TOKEN            = var.SNYK_TOKEN
      ENCRYPTED_VARS        = "HOOK_VALIDATION_TOKEN,SNYK_TOKEN"
    }
  }

  tags = {
    Name                  = "snyk-watcher Lambda"
    App                   = "snyk-watcher"
  }
}

resource "aws_cloudwatch_log_group" "snyk_watcher_log_group" {
  name              = "/aws/lambda/snyk-watcher"
  retention_in_days = 7

  tags = {
    Name                  = "snyk-watcher Log Group"
    App                   = "snyk-watcher"
  }
}

// Allow API gateway to access the lambda
resource "aws_lambda_permission" "snyk_watcher_allow_apigw" {
  depends_on    = [aws_cloudwatch_log_group.snyk_watcher_log_group]
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.snyk_watcher.function_name
  principal     = "apigateway.amazonaws.com"

  # The "/*/*" portion grants access from any method on any resource
  # within the API Gateway REST API.
  source_arn = "${aws_api_gateway_rest_api.snyk_watcher_gateway.execution_arn}/*/*"
}