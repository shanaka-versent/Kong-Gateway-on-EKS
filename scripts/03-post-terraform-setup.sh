#!/bin/bash
# EKS Kong Gateway POC - Post-Terraform Configuration Setup
# @author Shanaka Jayasundera - shanakaj@gmail.com
#
# Run this script AFTER 'terraform apply' to inject Terraform outputs into
# the K8s and ArgoCD manifest files. This eliminates manual copy-paste of
# zone IDs, IAM role ARNs, and domain names.
#
# What it does:
#   1. Reads terraform outputs (route53_zone_id, cert_manager_role_arn, domain_name)
#   2. Updates k8s/cert-manager/cluster-issuer.yaml with the Route53 zone ID and domain
#   3. Updates k8s/cert-manager/certificate.yaml with the domain name
#   4. Updates argocd/apps/00b-cert-manager.yaml with the cert-manager IRSA role ARN
#
# Usage:
#   ./scripts/03-post-terraform-setup.sh
#   ./scripts/03-post-terraform-setup.sh --dry-run    # Preview changes without writing

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="${SCRIPT_DIR}/.."
TERRAFORM_DIR="${REPO_DIR}/terraform"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

DRY_RUN=false
[[ "${1:-}" == "--dry-run" ]] && DRY_RUN=true

log()  { echo -e "${GREEN}[INFO]${NC} $*"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $*"; }
error(){ echo -e "${RED}[ERROR]${NC} $*"; }
dry()  { echo -e "${CYAN}[DRY-RUN]${NC} $*"; }

# ---------------------------------------------------------------------------
# Read Terraform outputs
# ---------------------------------------------------------------------------
read_terraform_outputs() {
    log "Reading Terraform outputs..."

    cd "$TERRAFORM_DIR"

    ROUTE53_ZONE_ID=$(terraform output -raw route53_zone_id 2>/dev/null || true)
    CERT_MANAGER_ROLE_ARN=$(terraform output -raw cert_manager_role_arn 2>/dev/null || true)
    DOMAIN_NAME=$(terraform output -raw domain_name 2>/dev/null || true)
    ROUTE53_NAME_SERVERS=$(terraform output -json route53_name_servers 2>/dev/null || true)

    # Fallback: read domain_name from terraform variable if not in outputs
    if [[ -z "$DOMAIN_NAME" ]]; then
        DOMAIN_NAME=$(terraform show -json 2>/dev/null | jq -r '.values.root_module.variables.domain_name.value // empty' || true)
    fi

    cd "$REPO_DIR"

    # Validate required outputs
    local missing=false
    if [[ -z "$ROUTE53_ZONE_ID" ]]; then
        error "Missing terraform output: route53_zone_id"
        error "Make sure you ran: terraform apply -var=\"enable_cloudfront=true\""
        missing=true
    fi
    if [[ -z "$CERT_MANAGER_ROLE_ARN" ]]; then
        error "Missing terraform output: cert_manager_role_arn"
        missing=true
    fi
    if [[ -z "$DOMAIN_NAME" ]]; then
        error "Missing domain_name from terraform variables"
        missing=true
    fi

    if [[ "$missing" == true ]]; then
        error "Cannot proceed without required Terraform outputs."
        exit 1
    fi

    echo ""
    log "Terraform outputs:"
    echo "  Route53 Zone ID:       $ROUTE53_ZONE_ID"
    echo "  cert-manager Role ARN: $CERT_MANAGER_ROLE_ARN"
    echo "  Domain Name:           $DOMAIN_NAME"
    if [[ -n "$ROUTE53_NAME_SERVERS" && "$ROUTE53_NAME_SERVERS" != "null" ]]; then
        echo "  Route53 Name Servers:  $(echo "$ROUTE53_NAME_SERVERS" | jq -r 'join(", ")')"
    fi
    echo ""
}

# ---------------------------------------------------------------------------
# Update cluster-issuer.yaml — Route53 zone ID + domain
# ---------------------------------------------------------------------------
update_cluster_issuer() {
    local file="k8s/cert-manager/cluster-issuer.yaml"
    log "Updating $file ..."

    if [[ ! -f "$file" ]]; then
        error "File not found: $file"
        return 1
    fi

    if $DRY_RUN; then
        dry "Would replace hostedZoneID with: $ROUTE53_ZONE_ID"
        dry "Would replace dnsZones entries with: $DOMAIN_NAME"
        return
    fi

    # Replace hostedZoneID (matches any quoted value after hostedZoneID:)
    sed -i.bak -E "s/(hostedZoneID: \")[^\"]+\"/\1${ROUTE53_ZONE_ID}\"/" "$file"

    # Replace dnsZones entries (matches any quoted value in the dnsZones list)
    sed -i.bak -E "s/(- \")[^\"]+(\")$/\1${DOMAIN_NAME}\2/" "$file"

    rm -f "${file}.bak"
    log "  ✅ Updated hostedZoneID → $ROUTE53_ZONE_ID"
    log "  ✅ Updated dnsZones → $DOMAIN_NAME"
}

# ---------------------------------------------------------------------------
# Update certificate.yaml — domain name in dnsNames
# ---------------------------------------------------------------------------
update_certificate() {
    local file="k8s/cert-manager/certificate.yaml"
    log "Updating $file ..."

    if [[ ! -f "$file" ]]; then
        error "File not found: $file"
        return 1
    fi

    if $DRY_RUN; then
        dry "Would replace dnsNames entry with: $DOMAIN_NAME"
        return
    fi

    # Replace the dnsNames entry (matches the line under dnsNames:)
    sed -i.bak -E "s/(dnsNames:)/\1/" "$file"
    sed -i.bak -E "/dnsNames:/{ n; s/- .+$/- ${DOMAIN_NAME}/ }" "$file"

    rm -f "${file}.bak"
    log "  ✅ Updated dnsNames → $DOMAIN_NAME"
}

# ---------------------------------------------------------------------------
# Update 00b-cert-manager.yaml — IRSA role ARN
# ---------------------------------------------------------------------------
update_cert_manager_app() {
    local file="argocd/apps/00b-cert-manager.yaml"
    log "Updating $file ..."

    if [[ ! -f "$file" ]]; then
        error "File not found: $file"
        return 1
    fi

    if $DRY_RUN; then
        dry "Would replace eks.amazonaws.com/role-arn with: $CERT_MANAGER_ROLE_ARN"
        return
    fi

    # Replace the IRSA role ARN (matches the quoted value after role-arn:)
    sed -i.bak -E "s|(eks.amazonaws.com/role-arn: \")[^\"]+\"|\1${CERT_MANAGER_ROLE_ARN}\"|" "$file"

    rm -f "${file}.bak"
    log "  ✅ Updated IRSA role ARN → $CERT_MANAGER_ROLE_ARN"
}

# ---------------------------------------------------------------------------
# Show DNS delegation instructions
# ---------------------------------------------------------------------------
show_dns_instructions() {
    echo ""
    echo "=========================================="
    echo "  DNS Delegation Required"
    echo "=========================================="
    echo ""
    echo "If your parent domain is in a different AWS account or registrar,"
    echo "create an NS record to delegate the subdomain:"
    echo ""
    echo "  Name:  ${DOMAIN_NAME}"
    echo "  Type:  NS"

    if [[ -n "$ROUTE53_NAME_SERVERS" && "$ROUTE53_NAME_SERVERS" != "null" ]]; then
        echo "  Value:"
        echo "$ROUTE53_NAME_SERVERS" | jq -r '.[]' | while read -r ns; do
            echo "    - $ns"
        done
    else
        echo "  Value: <run 'terraform output route53_name_servers' to get values>"
    fi

    echo ""
    echo "Verify delegation:"
    echo "  dig NS ${DOMAIN_NAME}"
    echo ""
}

# ---------------------------------------------------------------------------
# Show summary and next steps
# ---------------------------------------------------------------------------
show_summary() {
    echo ""
    echo "=========================================="
    echo "  Post-Terraform Setup Complete"
    echo "=========================================="
    echo ""
    echo "Files updated:"
    echo "  ✅ k8s/cert-manager/cluster-issuer.yaml  (Route53 zone ID + domain)"
    echo "  ✅ k8s/cert-manager/certificate.yaml      (domain name)"
    echo "  ✅ argocd/apps/00b-cert-manager.yaml       (IRSA role ARN)"
    echo ""
    echo "Next steps:"
    echo "  1. Complete DNS delegation (see above)"
    echo "  2. Configure Konnect integration (Step 4 in README)"
    echo "  3. Deploy via ArgoCD: kubectl apply -f argocd/apps/root-app.yaml"
    echo "  4. Verify: kubectl get applications -n argocd -w"
    echo ""
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
main() {
    echo ""
    echo "=========================================="
    echo "  Post-Terraform Configuration Setup"
    echo "=========================================="
    echo ""

    if $DRY_RUN; then
        dry "Running in dry-run mode — no files will be modified"
        echo ""
    fi

    read_terraform_outputs
    update_cluster_issuer
    update_certificate
    update_cert_manager_app
    show_dns_instructions

    if ! $DRY_RUN; then
        show_summary
    fi
}

main "$@"
