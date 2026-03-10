#!/bin/bash
export AWS_PROFILE=wizgym-prod
export AWS_REGION=us-east-1

echo "=== Cleaning ghost records with PK=TRAINER#USER ==="

# Query all items with PK = TRAINER#USER (the truncated ghost records)
aws dynamodb query \
  --table-name wizgym-prod-core \
  --key-condition-expression "PK = :pk" \
  --expression-attribute-values '{":pk":{"S":"TRAINER#USER"}}' \
  --region us-east-1 \
  --output json > /tmp/ghost_trainer_records.json 2>&1

echo "Ghost records found:"
cat /tmp/ghost_trainer_records.json

echo ""
echo "=== Checking for any ghost subscription request records ==="
aws dynamodb query \
  --table-name wizgym-prod-core \
  --key-condition-expression "PK = :pk" \
  --expression-attribute-values '{":pk":{"S":"TRAINER#USER"}}' \
  --region us-east-1 \
  --output json | python3 -c "
import json, sys
data = json.load(sys.stdin)
items = data.get('Items', [])
print(f'Total ghost items: {len(items)}')
for item in items:
    pk = item.get('PK',{}).get('S','')
    sk = item.get('SK',{}).get('S','')
    print(f'  PK={pk} SK={sk}')
" 2>&1

echo "DONE"
