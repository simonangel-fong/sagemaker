# api.tf

# ##############################
# HTTP API
# ##############################
resource "aws_apigatewayv2_api" "this" {
  count = local.endpoint_enabled ? 1 : 0

  name          = "${local.prefix_name}-api"
  protocol_type = "HTTP"

  # CORS headers
  cors_configuration {
    allow_origins = ["*"]
    allow_methods = ["POST", "OPTIONS"]
    allow_headers = ["content-type"]
  }
}

resource "aws_apigatewayv2_integration" "predict" {
  count = local.endpoint_enabled ? 1 : 0

  api_id                 = aws_apigatewayv2_api.this[0].id
  integration_type       = "AWS_PROXY"
  integration_uri        = aws_lambda_function.api[0].invoke_arn
  payload_format_version = "2.0"
}

resource "aws_apigatewayv2_route" "predict" {
  count = local.endpoint_enabled ? 1 : 0

  api_id    = aws_apigatewayv2_api.this[0].id
  route_key = "POST /predict"
  target    = "integrations/${aws_apigatewayv2_integration.predict[0].id}"
}

resource "aws_apigatewayv2_stage" "default" {
  count = local.endpoint_enabled ? 1 : 0

  api_id      = aws_apigatewayv2_api.this[0].id
  name        = "$default"
  auto_deploy = true

  # Throttling is the only brake on an unauthenticated route.
  default_route_settings {
    throttling_rate_limit  = 10
    throttling_burst_limit = 20
  }
}

resource "aws_lambda_permission" "api" {
  count = local.endpoint_enabled ? 1 : 0

  statement_id  = "AllowExecutionFromAPIGateway"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.api[0].function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.this[0].execution_arn}/*/*"
}
