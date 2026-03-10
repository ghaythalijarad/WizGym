#!/bin/bash
set -e
export AWS_PROFILE=wizgym-prod
export AWS_REGION=us-east-1

echo "=== Step 1: Delete ghost TRAINER#USER records ==="
# Query ghost records
ITEMS=$(aws dynamodb query \
  --table-name wizgym-prod-core \
  --key-condition-expression "PK = :pk" \
  --expression-attribute-values '{":pk":{"S":"TRAINER#USER"}}' \
  --region us-east-1 \
  --output json 2>&1)

echo "$ITEMS" > /Users/ghaythallaheebi/WizGymProd/ghost_items.json
COUNT=$(echo "$ITEMS" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('Count',0))" 2>/dev/null || echo "0")
echo "Found $COUNT ghost records"

# Delete each one
echo "$ITEMS" | python3 -c "
import json, sys, subprocess
data = json.load(sys.stdin)
for item in data.get('Items', []):
    sk = item.get('SK',{}).get('S','')
    print(f'Deleting TRAINER#USER / {sk}')
    result = subprocess.run([
        'aws', 'dynamodb', 'delete-item',
        '--table-name', 'wizgym-prod-core',
        '--key', json.dumps({'PK':{'S':'TRAINER#USER'}, 'SK':{'S':sk}}),
        '--region', 'us-east-1',
        '--profile', 'wizgym-prod'
    ], capture_output=True, text=True)
    print(f'  -> exit={result.returncode}')
" 2>&1

echo "=== Step 2: Check current gym trainersCount ==="
aws dynamodb get-item \
  --table-name wizgym-prod-core \
  --key '{"PK":{"S":"GYM#165f99666fdeb3f5"},"SK":{"S":"PROFILE"}}' \
  --projection-expression "trainersCount,membersCount" \
  --region us-east-1 \
  --output json > /Users/ghaythallaheebi/WizGymProd/gym_counts_final.json 2>&1

cat /Users/ghaythallaheebi/WizGymProd/gym_counts_final.json

echo "=== DONE ==="
