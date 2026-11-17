#!/usr/bin/env bash
set -euo pipefail

# Exercise 6 - AWS infrastructure cleanup

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TERRAFORM_DIR="$SCRIPT_DIR/terraform"

echo "========================================="
echo " Exercise 6 - Terraform Destroy"
echo "========================================="

if ! command -v terraform >/dev/null 2>&1; then
  echo "ERROR: Terraform is not installed."
  exit 1
fi

cd "$TERRAFORM_DIR"

echo "Checking Terraform state..."
terraform state list

echo ""
echo "WARNING: This will destroy all resources"
echo "managed by this Terraform state."
echo ""

read -r -p "Type DESTROY to continue: " CONFIRM

if [[ "$CONFIRM" != "DESTROY" ]]; then
  echo "Cancelled. No resources destroyed."
  exit 0
fi

echo ""
echo "Destroying AWS infrastructure..."

terraform destroy

echo ""
echo "Terraform destroy finished successfully."
echo "Verify that no billable resources remain in AWS."