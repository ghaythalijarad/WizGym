# ── Cognito User Pool for Admin Web Dashboard ────────────────────────────────
# Manages authentication for the WizGym admin web dashboard only.
# Mobile app uses phone/OTP flow (handled in backend AuthService).

resource "aws_cognito_user_pool" "admin" {
  name = "${local.name_prefix}-admin"

  # Admins sign in with email
  username_attributes      = ["email"]
  auto_verified_attributes = ["email"]

  # Password policy (admins are internal staff — enforce strong passwords)
  password_policy {
    minimum_length                   = 12
    require_lowercase                = true
    require_uppercase                = true
    require_numbers                  = true
    require_symbols                  = true
    temporary_password_validity_days = 7
  }

  # MFA — optional TOTP (can be promoted to required once dashbard is live)
  mfa_configuration = "OPTIONAL"

  software_token_mfa_configuration {
    enabled = true
  }

  # User account recovery via email only
  account_recovery_setting {
    recovery_mechanism {
      name     = "verified_email"
      priority = 1
    }
  }

  # Email verification
  verification_message_template {
    default_email_option = "CONFIRM_WITH_CODE"
    email_subject        = "WizGym Admin — Verify your email"
    email_message        = "Your WizGym admin verification code is {####}"
  }

  # Custom attribute: fine-grained permissions (comma-separated)
  schema {
    name                     = "permissions"
    attribute_data_type      = "String"
    mutable                  = true
    developer_only_attribute = false

    string_attribute_constraints {
      min_length = 0
      max_length = 500
    }
  }

  # Admin-initiated user creation only (no public self-signup)
  admin_create_user_config {
    allow_admin_create_user_only = true

    invite_message_template {
      email_subject = "Welcome to WizGym Admin Dashboard"
      email_message = "Hello {username}, your temporary password is {####}. Please sign in and change it immediately."
      sms_message   = "WizGym admin temp password: {####}"
    }
  }

  tags = local.tags
}

# ── Cognito User Pool Groups ──────────────────────────────────────────────────

resource "aws_cognito_user_group" "superadmins" {
  name         = "superadmins"
  user_pool_id = aws_cognito_user_pool.admin.id
  description  = "Super admins — full access to all admin operations"
  precedence   = 1
}

resource "aws_cognito_user_group" "admins" {
  name         = "admins"
  user_pool_id = aws_cognito_user_pool.admin.id
  description  = "Admins — access controlled by custom:permissions attribute"
  precedence   = 2
}

# ── Cognito App Client ────────────────────────────────────────────────────────

resource "aws_cognito_user_pool_client" "admin_dashboard" {
  name         = "${local.name_prefix}-admin-dashboard"
  user_pool_id = aws_cognito_user_pool.admin.id

  # Use Cognito Managed Login (hosted UI) — no client secret for SPA
  generate_secret = false

  # Auth flows: SRP for the hosted UI; USER_PASSWORD_AUTH for CLI/testing
  explicit_auth_flows = [
    "ALLOW_USER_SRP_AUTH",
    "ALLOW_USER_PASSWORD_AUTH",
    "ALLOW_REFRESH_TOKEN_AUTH",
  ]

  # Token expiry
  access_token_validity  = 1   # hours
  id_token_validity      = 1   # hours
  refresh_token_validity = 30  # days

  token_validity_units {
    access_token  = "hours"
    id_token      = "hours"
    refresh_token = "days"
  }

  # Read custom attributes in the token
  read_attributes = [
    "email",
    "email_verified",
    "custom:permissions",
  ]

  # Allow updating custom:permissions via admin API
  write_attributes = [
    "email",
    "custom:permissions",
  ]

  # Prevent user existence errors leaking
  prevent_user_existence_errors = "ENABLED"

  supported_identity_providers = ["COGNITO"]
}

# ── Outputs ───────────────────────────────────────────────────────────────────

output "cognito_user_pool_id" {
  description = "Cognito User Pool ID — set as COGNITO_USER_POOL_ID in backend .env"
  value       = aws_cognito_user_pool.admin.id
}

output "cognito_client_id" {
  description = "Cognito App Client ID — set as COGNITO_CLIENT_ID in backend .env"
  value       = aws_cognito_user_pool_client.admin_dashboard.id
}

output "cognito_user_pool_endpoint" {
  description = "Cognito JWKS base URL (append /.well-known/jwks.json)"
  value       = "https://cognito-idp.${var.aws_region}.amazonaws.com/${aws_cognito_user_pool.admin.id}"
}
