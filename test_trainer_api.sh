#!/bin/bash
curl -s 'https://3u10v51mvk.execute-api.us-east-1.amazonaws.com/api/v1/trainers/me/gyms' \
  -H 'x-user-id: USER#2f2e07be163886e4512d7be47f2dedb3' \
  -H 'x-user-role: trainer' \
  > /Users/ghaythallaheebi/WizGymProd/trainer_gyms_response.json 2>&1
echo "DONE: $?"
