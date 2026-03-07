# WizGym Admin Dashboard

## Development

### Run locally

Backend (live AWS Lambda — no local server needed):

- API: `https://3u10v51mvk.execute-api.us-east-1.amazonaws.com/api/v1`

Dashboard:

- `cd apps/admin-dashboard && python3 -m http.server 8080`

Open:

- `http://localhost:8080`

## Production

The old production workflow using **AWS Copilot / ECS** is deprecated.

Current production API deployment source of truth:

- `docs/aws-sam-lambda/DEPLOYMENT.md`

> Admin dashboard hosting (S3/CloudFront) will be documented separately once domains are finalized.
