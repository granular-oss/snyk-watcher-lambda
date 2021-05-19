//
// Reminder from https://learn.hashicorp.com/terraform/aws/lambda-api-gateway:
//
// Due to API Gateway's staged deployment model, if you do need to make changes
// to the API Gateway configuration you must explicitly request that it be
// re-deployed by "tainting" the deployment resource:
//
//   $ terraform taint aws_api_gateway_deployment.example
//
variable "HOSTED_ZONE" {}


output "base_url" {
  value = aws_api_gateway_deployment.snyk_watcher_gateway_deployment.invoke_url
}

resource "aws_api_gateway_rest_api" "snyk_watcher_gateway" {
  name        = "SnykWatcherGateway"
  description = "API Gateway for Snyk-watcher"

  endpoint_configuration {
    types = [
    "REGIONAL"]
  }
  tags = {
    Name                  = "snyk-watcher APIG"
    App                   = "snyk-watcher"
  }
}

resource "aws_api_gateway_resource" "snyk_watcher_proxy" {
  rest_api_id = aws_api_gateway_rest_api.snyk_watcher_gateway.id
  parent_id   = aws_api_gateway_rest_api.snyk_watcher_gateway.root_resource_id
  path_part   = "{proxy+}"
}

resource "aws_api_gateway_method" "snyk_watcher_proxy" {
  rest_api_id   = aws_api_gateway_rest_api.snyk_watcher_gateway.id
  resource_id   = aws_api_gateway_resource.snyk_watcher_proxy.id
  http_method   = "ANY"
  authorization = "NONE"
}
resource "aws_api_gateway_integration" "snyk_watcher_lambda" {
  rest_api_id = aws_api_gateway_rest_api.snyk_watcher_gateway.id
  resource_id = aws_api_gateway_method.snyk_watcher_proxy.resource_id
  http_method = aws_api_gateway_method.snyk_watcher_proxy.http_method

  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.snyk_watcher.invoke_arn

  # This block ensures headers are passed through to the lambda so the X-Gitlab-Token is usable
  request_templates = {
    "application/json" = <<EOF
{
    "method": "$context.httpMethod",
    "body" : $input.json('$'),
    "headers": {
        #foreach($param in $input.params().header.keySet())
        "$param": "$util.escapeJavaScript($input.params().header.get($param))"
        #if($foreach.hasNext),#end
        #end
    }
}
EOF
  }
}

resource "aws_api_gateway_method" "snyk_watcher_proxy_root" {
  rest_api_id   = aws_api_gateway_rest_api.snyk_watcher_gateway.id
  resource_id   = aws_api_gateway_rest_api.snyk_watcher_gateway.root_resource_id
  http_method   = "ANY"
  authorization = "NONE"
}

resource "aws_api_gateway_integration" "snyk_watcher_lambda_root" {
  rest_api_id = aws_api_gateway_rest_api.snyk_watcher_gateway.id
  resource_id = aws_api_gateway_method.snyk_watcher_proxy_root.resource_id
  http_method = aws_api_gateway_method.snyk_watcher_proxy_root.http_method

  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.snyk_watcher.invoke_arn
}

resource "aws_api_gateway_deployment" "snyk_watcher_gateway_deployment" {
  depends_on = [
    aws_api_gateway_integration.snyk_watcher_lambda,
    aws_api_gateway_integration.snyk_watcher_lambda_root,
  ]

  rest_api_id = aws_api_gateway_rest_api.snyk_watcher_gateway.id
}

resource "aws_api_gateway_stage" "snyk_watcher_gateway_stage" {
  stage_name    = "default"
  rest_api_id   = aws_api_gateway_rest_api.snyk_watcher_gateway.id
  deployment_id = aws_api_gateway_deployment.snyk_watcher_gateway_deployment.id

  tags = {
    Name                  = "snyk-watcher APIG stage"
    App                   = "snyk-watcher"
  }
}


/////////////////////////////////////////////////
// Route53 alias to make the URL prettier.
// Everything in here is the pieces to make that happen.
resource "aws_acm_certificate" "snyk_watcher_cert" {
  domain_name       = "snyk-watcher.${var.HOSTED_ZONE}"
  validation_method = "DNS"

  tags = {
    Name            = "Snyk-watcher Certificate"
    App             = "snyk-watcher"
  }

  lifecycle {
    create_before_destroy = "true"
  }
}
data "aws_route53_zone" "snyk_watcher_zone" {
  name         = "${var.HOSTED_ZONE}."
  private_zone = "false"
}
resource "aws_route53_record" "snyk_watcher_cert_validation_record" {
  name    = tolist(aws_acm_certificate.snyk_watcher_cert.domain_validation_options)[0].resource_record_name
  type    = tolist(aws_acm_certificate.snyk_watcher_cert.domain_validation_options)[0].resource_record_type
  zone_id = data.aws_route53_zone.snyk_watcher_zone.id
  records = [tolist(aws_acm_certificate.snyk_watcher_cert.domain_validation_options)[0].resource_record_value]
  ttl     = 60
}
resource "aws_acm_certificate_validation" "snyk_watcher_cert" {
  certificate_arn         = aws_acm_certificate.snyk_watcher_cert.arn
  validation_record_fqdns = [aws_route53_record.snyk_watcher_cert_validation_record.fqdn]
}
resource "aws_api_gateway_domain_name" "snyk_watcher" {
  domain_name     = "snyk-watcher.${var.HOSTED_ZONE}"
  certificate_arn = aws_acm_certificate_validation.snyk_watcher_cert.certificate_arn

  tags = {
    Name                  = "snyk-watcher"
    App                   = "snyk-watcher"
  }
}
// NOTE: A path mapping is required, otherwise requests come back as forbidden
resource "aws_api_gateway_base_path_mapping" "path_mapping" {
  api_id      = aws_api_gateway_rest_api.snyk_watcher_gateway.id
  stage_name  = "default"
  domain_name = aws_api_gateway_domain_name.snyk_watcher.domain_name
}
resource "aws_route53_record" "snyk_watcher_record" {
  name    = aws_api_gateway_domain_name.snyk_watcher.domain_name
  type    = "A"
  zone_id = data.aws_route53_zone.snyk_watcher_zone.id

  alias {
    evaluate_target_health = "false"
    name                   = aws_api_gateway_domain_name.snyk_watcher.cloudfront_domain_name
    zone_id                = aws_api_gateway_domain_name.snyk_watcher.cloudfront_zone_id
  }
}
//
/////////////////////////////////////////////////