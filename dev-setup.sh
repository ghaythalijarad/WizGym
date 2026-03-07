#!/bin/bash

# WizGym Development Setup Script
# This script sets up all dependencies for development

set -e  # Exit on error

echo "🏋️ WizGym Development Setup"
echo "=============================="
echo ""

# Colors for output
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Function to print colored output
print_step() {
    echo -e "${BLUE}▶${NC} $1"
}

print_success() {
    echo -e "${GREEN}✓${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}⚠${NC} $1"
}

# Check prerequisites
print_step "Checking prerequisites..."

if ! command -v node &> /dev/null; then
    echo "❌ Node.js is not installed. Please install Node.js first."
    exit 1
fi
print_success "Node.js installed: $(node --version)"

if ! command -v npm &> /dev/null; then
    echo "❌ npm is not installed. Please install npm first."
    exit 1
fi
print_success "npm installed: $(npm --version)"

if ! command -v flutter &> /dev/null; then
    print_warning "Flutter is not installed. Mobile app setup will be skipped."
    FLUTTER_AVAILABLE=false
else
    print_success "Flutter installed: $(flutter --version | head -n 1)"
    FLUTTER_AVAILABLE=true
fi

if ! command -v terraform &> /dev/null; then
    print_warning "Terraform is not installed. Infrastructure setup will be skipped."
    TERRAFORM_AVAILABLE=false
else
    print_success "Terraform installed: $(terraform --version | head -n 1)"
    TERRAFORM_AVAILABLE=true
fi

echo ""

# Install Contracts
print_step "Installing Contracts package..."
cd packages/contracts
npm install
print_success "Contracts dependencies installed"

print_step "Building Contracts package..."
npm run build
print_success "Contracts built successfully"

echo ""

# Install API
print_step "Installing API dependencies..."
cd ../../apps/api
npm install
print_success "API dependencies installed"

print_step "Building API..."
npm run build
print_success "API built successfully"

echo ""

# Setup Mobile App
if [ "$FLUTTER_AVAILABLE" = true ]; then
    print_step "Setting up Mobile app..."
    cd ../mobile
    flutter pub get
    print_success "Mobile app dependencies installed"
    
    print_step "Running Flutter doctor..."
    flutter doctor
else
    print_warning "Skipping mobile app setup (Flutter not available)"
fi

echo ""

# Initialize Terraform
if [ "$TERRAFORM_AVAILABLE" = true ]; then
    print_step "Initializing Terraform..."
    cd ../../infra/aws/terraform
    terraform init
    print_success "Terraform initialized"
else
    print_warning "Skipping Terraform setup (Terraform not available)"
fi

echo ""
echo "================================================"
echo -e "${GREEN}✓ Setup Complete!${NC}"
echo "================================================"
echo ""
echo "Next steps:"
echo "  1. Open the workspace: File > Open Workspace from File"
echo "  2. Select WizGym.code-workspace"
echo "  3. Install recommended VS Code extensions"
echo "  4. Start coding! 🚀"
echo ""
echo "Quick commands:"
echo "  - Run mobile app: cd apps/mobile && flutter run"
echo "  - Build API: cd apps/api && npm run build"
echo "  - Deploy infrastructure: cd infra/aws/terraform && terraform apply"
echo ""
