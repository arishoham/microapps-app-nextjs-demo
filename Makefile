
AWS_PROFILE ?= pwrdrvr
AWS_ACCOUNT ?= 239161478713
REGION ?= us-east-2
ECR_HOST ?= ${AWS_ACCOUNT}.dkr.ecr.${REGION}.amazonaws.com
ECR_REPO ?= app-nextjs-demo
IMAGE_TAG ?= ${ECR_REPO}:0.0.3
LAMBDA_ALIAS ?= v0_0_3

help:
	@echo "Commands:"
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort \
		| awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-30s\033[0m %s\n", $$1, $$2}'
	@echo


copy-router: ../serverless-nextjs-router/dist/index.js ## Copy compiled Next.js Router to output
	-rm .serverless_nextjs/index.js
	cp ../serverless-nextjs-router/dist/index.js .serverless_nextjs/

start: ## Start App Docker Container
	docker-compose up --build

sam-debug: ## Start App w/SAM Local for VS Code Debugging
	-rm .serverless_nextjs/config.json
	cp config.json .serverless_nextjs/
	sam local start-api --debug-port 5859 --warm-containers EAGER

#
# Lambda ECR Publishing
#

aws-ecr-login: ## establish ECR docker login session
	@aws ecr get-login-password --region ${REGION} | docker login \
		--username AWS --password-stdin ${ECR_HOST}

aws-ecr-publish-svc: ## publish updated ECR docker image
	@docker build -f Dockerfile -t ${IMAGE_TAG}  .
	@docker tag ${IMAGE_TAG} ${ECR_HOST}/${IMAGE_TAG}
	@docker tag ${IMAGE_TAG} ${ECR_HOST}/${ECR_REPO}:latest
	@docker push ${ECR_HOST}/${IMAGE_TAG}
	@docker push ${ECR_HOST}/${ECR_REPO}:latest

# We don't use this anymore now that we have multiple versions
# aws-lambda-update-svc: ## Update the lambda function to use latest image
# 	@aws lambda update-function-code --function-name ${ECR_REPO} \
# 		--image-uri ${ECR_HOST}/${IMAGE_TAG} --region=${REGION} \
# 		--publish


#$(eval VERSION=$$(shell aws lambda publish-version --function-name ${ECR_REPO} | jq -r ".Version"))
aws-create-alias-svc: ## Update the lambda function to use latest image
	# Capture the Revision ID of the newly published code
	@echo "Creating new alias, ${LAMBDA_ALIAS}, pointing to ${ECR_HOST}/${IMAGE_TAG}"
	$(eval VERSION:=$$(shell aws lambda update-function-code --function-name ${ECR_REPO} \
		--image-uri ${ECR_HOST}/${IMAGE_TAG} --region=${REGION} \
		--output json --publish \
		| jq -r ".Version"))
	@echo "New Lambda Version: ${ECR_REPO}/${VERSION}"
	@sleep 10
	@aws lambda create-alias --function-name ${ECR_REPO} \
		--name ${LAMBDA_ALIAS} --function-version '${VERSION}' --region=${REGION}
	@sleep 5

aws-update-alias-svc: ## Update the lambda function to use latest image
	# Capture the Revision ID of the newly published code
	@echo "Updating existing alias, ${LAMBDA_ALIAS}, pointing to ${ECR_HOST}/${IMAGE_TAG}"
	$(eval VERSION:=$$(shell aws lambda update-function-code --function-name ${ECR_REPO} \
		--image-uri ${ECR_HOST}/${IMAGE_TAG} --region=${REGION} \
		--output json --publish \
		| jq -r ".Version"))
	@echo "New Lambda Version: ${ECR_REPO}/${VERSION}"
	@sleep 10
	@aws lambda update-alias --function-name ${ECR_REPO} \
		--name ${LAMBDA_ALIAS} --function-version '${VERSION}' --region=${REGION}
	@sleep 5

#
# MicroApps - Publishing New App Version / Updated HTML
#

microapps-publish: ## publishes a new version of the microapp OR updates HTML
	@dotnet run --project ~/pwrdrvr/microapps-cdk/src/PwrDrvr.MicroApps.DeployTool/


#
# Fix API Gateay Permissions
#

fix-api-gateway-v0_0_1: ## Fix busted permissions on API Gateway Integrations
	@aws lambda add-permission \
		--statement-id microapps-version \
		--action lambda:InvokeFunction \
		--function-name "arn:aws:lambda:us-east-2:239161478713:function:app-nextjs-demo:v0_0_1" \
		--principal apigateway.amazonaws.com \
		--source-arn "arn:aws:execute-api:us-east-2:239161478713:4jssqkktsg/*/*/nextjs-demo/0.0.1"
	@aws lambda add-permission \
		--statement-id microapps-version-root \
		--action lambda:InvokeFunction \
		--function-name "arn:aws:lambda:us-east-2:239161478713:function:app-nextjs-demo:v0_0_1" \
		--principal apigateway.amazonaws.com \
		--source-arn "arn:aws:execute-api:us-east-2:239161478713:4jssqkktsg/*/*/nextjs-demo/0.0.1/{proxy+}"

fix-api-gateway-v0_0_3: ## Fix busted permissions on API Gateway Integrations
	@aws lambda add-permission \
		--statement-id microapps-version \
		--action lambda:InvokeFunction \
		--function-name "arn:aws:lambda:us-east-2:239161478713:function:app-nextjs-demo:v0_0_3" \
		--principal apigateway.amazonaws.com \
		--source-arn "arn:aws:execute-api:us-east-2:239161478713:4jssqkktsg/*/*/nextjs-demo/0.0.2"
	@aws lambda add-permission \
		--statement-id microapps-version-root \
		--action lambda:InvokeFunction \
		--function-name "arn:aws:lambda:us-east-2:239161478713:function:app-nextjs-demo:v0_0_3" \
		--principal apigateway.amazonaws.com \
		--source-arn "arn:aws:execute-api:us-east-2:239161478713:4jssqkktsg/*/*/nextjs-demo/0.0.2/{proxy+}"

#
# API Gateway Payloads for Testing
#

curl-api-hello-fails: ## Send test request to local app
	@curl -v -XPOST -H "Content-Type: application/json" \
		http://localhost:9000/2015-03-31/functions/function/invocations \
		--data-binary "@test-payloads/api-hello-fails.json"

curl-home: ## Send test request to local app
	@curl -v -XPOST -H "Content-Type: application/json" \
		http://localhost:9000/2015-03-31/functions/function/invocations \
		--data-binary "@test-payloads/home.json"

curl-image: ## Send test request to local app
	@curl -v -XPOST -H "Content-Type: application/json" \
		http://localhost:9000/2015-03-31/functions/function/invocations \
		--data-binary "@test-payloads/image.json"