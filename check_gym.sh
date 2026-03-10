#!/bin/bash
export AWS_PROFILE=wizgym-prod
export AWS_REGION=us-east-1

# Check gym counts
aws dynamodb get-item \
  --table-name wizgym-prod-core \
  --key '{"PK":{"S":"GYM#165f99666fdeb3f5"},"SK":{"S":"PROFILE"}}' \
  --projection-expression "trainersCount,membersCount" \
  --output json 2>&1

echo "EXIT_CODE=$?"
