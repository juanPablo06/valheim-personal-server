resource "aws_iam_role" "lambda_ec2_role" {
  name = "lambda-ec2-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Action = "sts:AssumeRole",
        Effect = "Allow",
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_role_policy" "lambda_ec2_policy" {
  role = aws_iam_role.lambda_ec2_role.id
  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Action = [
          "ec2:StartInstances",
          "ec2:StopInstances",
          "ec2:DescribeInstances"
        ],
        Effect   = "Allow",
        Resource = "*"
      },
      {
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ],
        Effect   = "Allow",
        Resource = "arn:aws:logs:*:*:*"
      },
      {
        Action = [
          "ssm:PutParameter",
          "ssm:GetParameter"
        ],
        Effect   = "Allow",
        Resource = "*"
      }
    ]
  })
}

data "archive_file" "start_stop_lambda" {
  type        = "zip"
  source_file = "./scripts/start_stop_lambda.py"
  output_path = "./scripts/start_stop_lambda.zip"
}

resource "aws_lambda_function" "start_stop_lambda" {
  filename         = data.archive_file.start_stop_lambda.output_path
  function_name    = "valheim-start-stop"
  role             = aws_iam_role.lambda_ec2_role.arn
  handler          = "start_stop_lambda.lambda_handler"
  runtime          = "python3.10"
  source_code_hash = data.archive_file.start_stop_lambda.output_base64sha256
  timeout          = 300

  environment {
    variables = {
      INSTANCE_ID = aws_instance.main.id
      PARAM_NAME  = data.aws_ssm_parameter.valheim_server_password.name
    }
  }
}

resource "aws_cloudwatch_event_rule" "daily_stop_rule" {
  name                = "valheim-daily-stop"
  schedule_expression = "cron(0 4 * * ? *)" # 4 AM UTC daily
}

resource "aws_cloudwatch_event_target" "lambda_target" {
  rule      = aws_cloudwatch_event_rule.daily_stop_rule.name
  target_id = "valheim-daily-stop"
  arn       = aws_lambda_function.start_stop_lambda.arn
  input     = jsonencode({ action = "stop" })
}

resource "aws_lambda_permission" "allow_cloudwatch" {
  statement_id  = "AllowExecutionFromCloudWatch"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.start_stop_lambda.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.daily_stop_rule.arn
}


resource "aws_api_gateway_rest_api" "valheim_api" {
  name        = "ValheimAPI"
  description = "API to start and stop the Valheim server"
}

resource "aws_api_gateway_resource" "valheim_resource" {
  rest_api_id = aws_api_gateway_rest_api.valheim_api.id
  parent_id   = aws_api_gateway_rest_api.valheim_api.root_resource_id
  path_part   = "valheim"
}

resource "aws_cognito_user_pool" "valheim_user_pool" {
  name = "valheim-user-pool"

  password_policy {
    minimum_length    = 8
    require_lowercase = true
    require_numbers   = true
    require_symbols   = true
    require_uppercase = true
  }

  auto_verified_attributes = ["email"]
}

resource "aws_cognito_user_pool_client" "valheim_user_pool_client" {
  name                                 = "valheim-user-pool-client"
  user_pool_id                         = aws_cognito_user_pool.valheim_user_pool.id
  generate_secret                      = false
  allowed_oauth_flows_user_pool_client = true
  allowed_oauth_flows                  = ["implicit"]
  allowed_oauth_scopes                 = ["email", "openid"]
  callback_urls                        = ["https://valheim-control-frontend.s3-website-sa-east-1.amazonaws.com"]
  logout_urls                          = ["https://valheim-control-frontend.s3-website-sa-east-1.amazonaws.com"]
}

resource "aws_api_gateway_authorizer" "cognito_authorizer" {
  name            = "CognitoAuthorizer"
  rest_api_id     = aws_api_gateway_rest_api.valheim_api.id
  identity_source = "method.request.header.Authorization"
  provider_arns   = [aws_cognito_user_pool.valheim_user_pool.arn]
  type            = "COGNITO_USER_POOLS"
}

resource "aws_api_gateway_request_validator" "body_validator" {
  rest_api_id                 = aws_api_gateway_rest_api.valheim_api.id
  validate_request_body       = true
  validate_request_parameters = false
  name                        = "ValidateActionParameter"
}

resource "aws_api_gateway_method" "valheim_method" {
  rest_api_id          = aws_api_gateway_rest_api.valheim_api.id
  resource_id          = aws_api_gateway_resource.valheim_resource.id
  http_method          = "POST"
  authorization        = "COGNITO_USER_POOLS"
  authorizer_id        = aws_api_gateway_authorizer.cognito_authorizer.id
  request_validator_id = aws_api_gateway_request_validator.body_validator.id
}

resource "aws_api_gateway_integration" "valheim_integration" {
  rest_api_id             = aws_api_gateway_rest_api.valheim_api.id
  resource_id             = aws_api_gateway_resource.valheim_resource.id
  http_method             = aws_api_gateway_method.valheim_method.http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.start_stop_lambda.invoke_arn
}

resource "aws_lambda_permission" "api_gateway_invoke" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.start_stop_lambda.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.valheim_api.execution_arn}/*/*"
}

resource "aws_api_gateway_deployment" "valheim_deployment" {
  depends_on  = [aws_api_gateway_integration.valheim_integration]
  rest_api_id = aws_api_gateway_rest_api.valheim_api.id
}

resource "aws_api_gateway_stage" "valheim_stage" {
  deployment_id = aws_api_gateway_deployment.valheim_deployment.id
  rest_api_id   = aws_api_gateway_rest_api.valheim_api.id
  stage_name    = "prod"

  lifecycle {
    ignore_changes = [deployment_id]
  }
}

resource "aws_api_gateway_method" "options_method" {
  rest_api_id   = aws_api_gateway_rest_api.valheim_api.id
  resource_id   = aws_api_gateway_resource.valheim_resource.id
  http_method   = "OPTIONS"
  authorization = "NONE"
}

resource "aws_api_gateway_integration" "options_integration" {
  rest_api_id = aws_api_gateway_rest_api.valheim_api.id
  resource_id = aws_api_gateway_resource.valheim_resource.id
  http_method = aws_api_gateway_method.options_method.http_method
  type        = "MOCK"
  request_templates = {
    "application/json" = "{\"statusCode\": 200}"
  }
}

resource "aws_api_gateway_method_response" "options_method_response" {
  rest_api_id = aws_api_gateway_rest_api.valheim_api.id
  resource_id = aws_api_gateway_resource.valheim_resource.id
  http_method = aws_api_gateway_method.options_method.http_method
  status_code = "200"

  response_parameters = {
    "method.response.header.Access-Control-Allow-Headers" = true,
    "method.response.header.Access-Control-Allow-Methods" = true,
    "method.response.header.Access-Control-Allow-Origin"  = true
  }

  response_models = {
    "application/json" = "Empty"
  }
}

resource "aws_api_gateway_integration_response" "options_integration_response" {
  rest_api_id = aws_api_gateway_rest_api.valheim_api.id
  resource_id = aws_api_gateway_resource.valheim_resource.id
  http_method = aws_api_gateway_method.options_method.http_method
  status_code = aws_api_gateway_method_response.options_method_response.status_code

  response_parameters = {
    "method.response.header.Access-Control-Allow-Headers" = "'Content-Type,X-Amz-Date,Authorization,X-Api-Key,X-Amz-Security-Token'",
    "method.response.header.Access-Control-Allow-Methods" = "'OPTIONS,POST'",
    "method.response.header.Access-Control-Allow-Origin"  = "'*'"
  }

  response_templates = {
    "application/json" = ""
  }
}

resource "aws_api_gateway_method_response" "post_method_response" {
  rest_api_id = aws_api_gateway_rest_api.valheim_api.id
  resource_id = aws_api_gateway_resource.valheim_resource.id
  http_method = aws_api_gateway_method.valheim_method.http_method
  status_code = "200"

  response_parameters = {
    "method.response.header.Access-Control-Allow-Headers" = true,
    "method.response.header.Access-Control-Allow-Methods" = true,
    "method.response.header.Access-Control-Allow-Origin"  = true
  }
}

resource "aws_api_gateway_integration_response" "post_integration_response" {
  rest_api_id = aws_api_gateway_rest_api.valheim_api.id
  resource_id = aws_api_gateway_resource.valheim_resource.id
  http_method = aws_api_gateway_method.valheim_method.http_method
  status_code = aws_api_gateway_method_response.post_method_response.status_code

  response_parameters = {
    "method.response.header.Access-Control-Allow-Headers" = "'Content-Type,X-Amz-Date,Authorization,X-Api-Key,X-Amz-Security-Token'",
    "method.response.header.Access-Control-Allow-Methods" = "'OPTIONS,POST'",
    "method.response.header.Access-Control-Allow-Origin"  = "'*'"
  }
}
