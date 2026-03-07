#!/bin/bash
# Script to add OTPIQ API Key to AWS Parameter Store

echo "🔑 OTPIQ API Key Setup"
echo "====================="
echo ""

# Check if API key is provided
if [ -z "$1" ]; then
    echo "❌ Error: No API key provided"
    echo ""
    echo "Usage: ./setup-otpiq-key.sh YOUR_OTPIQ_API_KEY"
    echo ""
    echo "Example:"
    echo "  ./setup-otpiq-key.sh sk_live_abc123xyz456"
    echo ""
    exit 1
fi

API_KEY="$1"

echo "📝 Adding OTPIQ API Key to AWS Parameter Store..."
echo ""

# Add to Parameter Store
aws ssm put-parameter \
  --name "/wizgym/prod/OTPIQ_API_KEY" \
  --value "$API_KEY" \
  --type "SecureString" \
  --profile wizgym-prod \
  --region us-east-1 \
  --overwrite 2>/dev/null

if [ $? -eq 0 ]; then
    echo "✅ API Key added successfully!"
    echo ""
    
    # Verify
    echo "🔍 Verifying..."
    VALUE=$(aws ssm get-parameter \
      --name "/wizgym/prod/OTPIQ_API_KEY" \
      --with-decryption \
      --profile wizgym-prod \
      --region us-east-1 \
      --query "Parameter.Value" \
      --output text 2>/dev/null)
    
    if [ ! -z "$VALUE" ]; then
        # Show first and last 4 characters only for security
        MASKED="${VALUE:0:4}...${VALUE: -4}"
        echo "✅ Verified! Key stored: $MASKED"
        echo ""
        echo "📦 Next Steps:"
        echo "   1. cd infra/sam"
        echo "   2. sam build"
        echo "   3. sam deploy --config-env prod"
        echo ""
        echo "✨ After deployment, OTP will be sent via WhatsApp/SMS!"
    else
        echo "⚠️  Could not verify the key"
    fi
else
    echo "❌ Failed to add API Key"
    echo ""
    echo "Please check:"
    echo "  - AWS credentials are configured correctly"
    echo "  - Profile 'wizgym-prod' exists"
    echo "  - You have permissions to write to Parameter Store"
    exit 1
fi
