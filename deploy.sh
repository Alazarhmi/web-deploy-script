#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="$SCRIPT_DIR/lib"

source "$LIB_DIR/error_handling.sh"
source "$LIB_DIR/validation.sh"
source "$LIB_DIR/progress.sh"
source "$LIB_DIR/backup.sh"
source "$LIB_DIR/git.sh"
source "$LIB_DIR/preflight.sh"
source "$LIB_DIR/nginx.sh"
source "$LIB_DIR/ssl.sh"
source "$LIB_DIR/summary.sh"

setup_error_handling

if [[ "$EUID" -ne 0 ]]; then
    fail "Please run this script with sudo or as root."
fi

TOTAL_STEPS=8

show_deployment_banner

if ! run_preflight_checks; then
    fail "Pre-flight checks failed. Please fix the issues above and try again." 1
fi

show_step 1 $TOTAL_STEPS "Gathering project information"
read -rp "Enter project subdomain (e.g. myapp.example.com): " SUBDOMAIN
validate_subdomain "$SUBDOMAIN"

SAFE_NAME=$(echo "$SUBDOMAIN" | tr '/' '_')
PROJECT_DIR="/var/www/${SAFE_NAME}"
NGINX_SITES_AVAILABLE="/etc/nginx/sites-available"
NGINX_SITES_ENABLED="/etc/nginx/sites-enabled"
NGINX_CONF_PATH="${NGINX_SITES_AVAILABLE}/${SAFE_NAME}"

show_step 2 $TOTAL_STEPS "Setting up project directory"
backup_project_directory "$PROJECT_DIR"

if [[ ! -d "$PROJECT_DIR" ]]; then
    info "Creating project directory at $PROJECT_DIR"
    mkdir -p "$PROJECT_DIR"
    chown -R "${SUDO_USER:-root}":www-data "$PROJECT_DIR" || true
    chmod -R 755 "$PROJECT_DIR"
    success "Project directory created successfully"
fi

validate_project_directory "$PROJECT_DIR"

show_step 3 $TOTAL_STEPS "Installing system packages"
install_packages

show_step 4 $TOTAL_STEPS "Setting up repository"
read -rp "Does the project repository exist remotely? (y/n): " REPO_EXISTS
REPO_EXISTS=${REPO_EXISTS,,}
validate_yes_no_input "$REPO_EXISTS" "repository existence"

if [[ "$REPO_EXISTS" = "y" || "$REPO_EXISTS" = "yes" ]]; then
    read -rp "Is the repository public or private? (public/private): " REPO_TYPE
    REPO_TYPE=${REPO_TYPE,,}
    
    if [[ "$REPO_TYPE" != "public" && "$REPO_TYPE" != "private" ]]; then
        fail "❌ Invalid repository type. Please enter 'public' or 'private'" 2
    fi
    
    read -rp "Enter the Git repository HTTPS URL (e.g. https://github.com/owner/repo.git): " REPO_URL
    validate_repo_url "$REPO_URL"
    
    if ! setup_repository "$REPO_TYPE" "$REPO_URL" "$PROJECT_DIR"; then
        fail "❌ Repository setup failed. Please check your repository URL and credentials." 1
    fi
else
    info "Skipping git clone. Project directory left empty."
fi

show_step 5 $TOTAL_STEPS "Configuring web server"
setup_nginx "$SUBDOMAIN" "$PROJECT_DIR" "$NGINX_CONF_PATH" "$NGINX_SITES_ENABLED" "$SAFE_NAME"

show_step 6 $TOTAL_STEPS "Setting up SSL/HTTPS"
read -rp "Do you want to enable HTTPS with Let's Encrypt for ${SUBDOMAIN}? (y/n): " ENABLE_HTTPS
ENABLE_HTTPS=${ENABLE_HTTPS,,}
validate_yes_no_input "$ENABLE_HTTPS" "HTTPS setup"

setup_https "$SUBDOMAIN" "$ENABLE_HTTPS"

show_step 7 $TOTAL_STEPS "Verifying deployment"
VERIFICATION_RESULT=$(verify_deployment "$SUBDOMAIN" "$ENABLE_HTTPS")
HTTP_OK=$(echo "$VERIFICATION_RESULT" | cut -d' ' -f1)
HTTPS_OK=$(echo "$VERIFICATION_RESULT" | cut -d' ' -f2)

show_step 8 $TOTAL_STEPS "Deployment complete"

show_backup_info

cleanup_old_backups

show_deployment_status "$SUBDOMAIN" "$PROJECT_DIR" "$NGINX_CONF_PATH" "$REPO_URL" "$REPO_TYPE" "$ENABLE_HTTPS" "$HTTP_OK" "$HTTPS_OK"

show_next_steps "$SUBDOMAIN" "$HTTP_OK" "$HTTPS_OK" "$ENABLE_HTTPS" "$PROJECT_DIR"

show_troubleshooting "$SUBDOMAIN" "$HTTP_OK" "$HTTPS_OK" "$ENABLE_HTTPS"

echo
echo "🏁 ==================== FINAL STATUS ===================="
if [[ "$HTTP_OK" = true && ( "$ENABLE_HTTPS" != "y" && "$ENABLE_HTTPS" != "yes" || "$HTTPS_OK" = true ) ]]; then
    show_success_celebration "$SUBDOMAIN" "$ENABLE_HTTPS" "$HTTPS_OK" "$PROJECT_DIR"
    exit 0
else
    echo "⚠️  DEPLOYMENT COMPLETED WITH ISSUES"
    echo "   Please check the troubleshooting section above"
    echo "   and verify your DNS and firewall settings."
    exit 1
fi
