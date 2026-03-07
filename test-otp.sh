#!/bin/bash
# Quick OTP Test Script

echo "📱 WizGym OTP Test"
echo "=================="
echo ""

# Check if phone number is provided
PHONE="${1:-+9647831367435}"

echo "📞 Testing OTP for: $PHONE"
echo ""

# Test send OTP
echo "1️⃣ Sending OTP..."
RESPONSE=$(curl -s -X POST https://3u10v51mvk.execute-api.us-east-1.amazonaws.com/api/v1/auth/phone/send-otp \
  -H "Content-Type: application/json" \
  -d "{\"phoneNumber\":\"$PHONE\"}")

echo "$RESPONSE" | jq .

# Check if mockCode appears
if echo "$RESPONSE" | jq -e '.mockCode' > /dev/null 2>&1; then
    MOCK_CODE=$(echo "$RESPONSE" | jq -r '.mockCode')
    echo ""
    echo "⚠️  WARNING: Mock Mode is ACTIVE!"
    echo "   Mock Code: $MOCK_CODE"
    echo ""
    echo "   To enable real OTP:"
    echo "   1. Run: ./setup-otpiq-key.sh YOUR_OTPIQ_KEY"
    echo "   2. Redeploy: cd infra/sam && sam build && sam deploy --config-env prod"
else
    echo ""
    echo "✅ Real OTP Mode is ACTIVE!"
    echo "   Check your phone for the OTP message"
    echo ""
    
    # Show session ID
    SESSION_ID=$(echo "$RESPONSE" | jq -r '.sessionId')
    echo "   Session ID: $SESSION_ID"
    echo ""
    echo "   Next: Enter the OTP you received to verify"
fi

echo ""
echo "📊 View recent logs:"
echo "   aws logs tail /aws/lambda/sam-app-WizGymApiFunction-yE1SQSAsdJGg --since 2m --profile wizgym-prod --region us-east-1"
