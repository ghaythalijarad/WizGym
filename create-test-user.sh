#!/bin/bash
# Create a test user in DynamoDB for login testing

aws dynamodb put-item \
  --table-name wizgym-prod-core \
  --profile wizgym-prod \
  --region us-east-1 \
  --item '{
    "PK": {"S": "USER#test001"},
    "SK": {"S": "PROFILE"},
    "GSI3PK": {"S": "PHONE#+9647831367435"},
    "GSI3SK": {"S": "USER#test001"},
    "id": {"S": "USER#test001"},
    "phoneNumber": {"S": "+9647831367435"},
    "password": {"S": "test123"},
    "displayName": {"S": "Test User"},
    "role": {"S": "USER"},
    "createdAt": {"S": "'$(date -u +"%Y-%m-%dT%H:%M:%SZ")'"},
    "updatedAt": {"S": "'$(date -u +"%Y-%m-%dT%H:%M:%SZ")'"
  }' \
  && echo "✅ Test user created successfully!" \
  || echo "❌ Failed to create test user"
