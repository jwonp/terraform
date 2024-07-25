# terraform {
#   required_providers {
#     aws = {
#         source = "hashicorp/aws"
#         version = "~> 4.21.0"
#     }
#     random = {
#         source = "hashicorp/random"
#         version = "~> 3.3.0"
#     }
#     archive = {
#         source = "hashicorp/archive"
#         version = "~> 2.2.0"
#     }
#   }
  
#   required_version = "~> 1.0"
# }
provider "aws" {
    region = "ap-northeast-2"   
}

data "aws_iam_policy_document" "assume_role" {
  statement {
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }

    actions = ["sts:AssumeRole"]
  }
}

resource "aws_iam_role" "lambda_role" {
  name = "terraform_aws_lambda_role"
  assume_role_policy = data.aws_iam_policy_document.assume_role.json

}

resource "aws_iam_policy" "terraform_iam_policy_for_lambda" {
    name = "aws_iam_policy_for_terraform_aws_lambda_role"
    path = "/"
    description = "AWS IAM Policy for managing aws lambda role"
    policy = jsonencode({
        Version = "2012-10-17"
        Statement = [
            {
                Effect = "Allow"
                Action = [
                    "logs:CreateLogGroup",
                    "logs:CreateLogStream",
                    "logs:PutLogEvents"
                ]
                Resource = "arn:aws:logs:*:*:*"
            }
        ]
    })
}


resource "aws_iam_role_policy_attachment" "attach_iam_policy_to_iam_role" {
    role = aws_iam_role.lambda_role.name
    policy_arn = aws_iam_policy.terraform_iam_policy_for_lambda.arn
}

data "archive_file" "zip_the_nodejs_code" {
    type = "zip"
    source_dir = "${path.module}/lambda/"
    output_path = "${path.module}/lambda/nodejs.zip"
}

resource "aws_lambda_function" "terraform_lambda_func" {
  filename = "${path.module}/lambda/nodejs.zip"
  function_name = "terraform_lambda_function"
  role = aws_iam_role.lambda_role.arn
  handler = "index.handler"
  runtime = "nodejs20.x"
  depends_on = [ aws_iam_role_policy_attachment.attach_iam_policy_to_iam_role ] 
}

# module "ts_lambda_function" {
#   source = "terraform-aws-modules/lambda/aws"
#   function_name = "ts-my-terraform_lambda_function"
#   description   = "My lambda function written in TS"
#   handler       = "index.handler"
#   runtime       = "nodejs20.x"
#   source_path = [{
#     path = "../lambda"
#     commands = [
#       "npm ci", # install dependencies
#       "npm run build", # npx tsc to transpile
#       "npm prune --omit=dev",
#       ":zip" # zip all
#     ]
#   }]
#   depends_on = [ aws_iam_role_policy_attachment.attach_iam_policy_to_iam_role ] 
#   publish = true
#   environment_variables = {
#     ENV = "dev"
#   }
#   attach_policy_statements = true
#   policy_statements = {
#     cloud_watch = {
#       effect    = "Allow",
#       actions   = ["cloudwatch:PutMetricData"],
#       resources = ["*"]
#     }
#   }
#   tags = {
#     Name = "ts-lambda"
#   }
# }

output "terraform_aws_role_output" {
  value = aws_iam_role.lambda_role.name
}

output "terraform_aws_role_arn_output" {
  value = aws_iam_role.lambda_role.arn
}

output "terraform_logging_arn_output" {
value = aws_iam_policy.terraform_iam_policy_for_lambda.arn
}

# cloudwatch
resource "aws_cloudwatch_log_group" "terraform_cloudwatch" {
  name = "/aws/lambda/${aws_lambda_function.terraform_lambda_func.function_name}"
  retention_in_days = 14
}

# api gateway
resource "aws_apigatewayv2_api" "terraform_api" {
  name = "terraform_api"
  protocol_type = "HTTP"
}

resource "aws_apigatewayv2_stage" "dev" {
    api_id = aws_apigatewayv2_api.terraform_api.id
    name = "dev"
    auto_deploy = true
    access_log_settings {
      destination_arn = aws_cloudwatch_log_group.terraform_cloudwatch.arn

      format = "{ \"requestId\": \"$context.requestId\", \"sourceIp\": \"$context.identity.sourceIp\", \"requestTime\": \"$context.requestTime\", \"protocol\": \"$context.protocol\", \"httpMethod\": \"$context.httpMethod\", \"resourcePath\": \"$context.resourcePath\", \"routeKey\": \"$context.routeKey\", \"status\": \"$context.status\", \"responseLength\": \"$context.responseLength\" }"
    }
}

resource "aws_apigatewayv2_integration" "lambda_integration" {
  api_id = aws_apigatewayv2_api.terraform_api.id

  integration_uri = aws_lambda_function.terraform_lambda_func.invoke_arn
  integration_type = "AWS_PROXY"
  integration_method = "POST"
  payload_format_version = "2.0"
}

resource "aws_apigatewayv2_route" "get_hello" {
  api_id = aws_apigatewayv2_api.terraform_api.id

  route_key = "GET /hello"
  target = "integrations/${aws_apigatewayv2_integration.lambda_integration.id}"
}
resource "aws_apigatewayv2_route" "post_hello" {
  api_id = aws_apigatewayv2_api.terraform_api.id

  route_key = "POST /hello"
  target = "integrations/${aws_apigatewayv2_integration.lambda_integration.id}"
}

resource "aws_lambda_permission" "lambda_permission" {
statement_id = "AllowExecutionFromAPIGateway"
action = "lambda:InvokeFunction"
function_name = aws_lambda_function.terraform_lambda_func.function_name
principal = "apigateway.amazonaws.com"

source_arn = "${aws_apigatewayv2_api.terraform_api.execution_arn}/*/*"
}