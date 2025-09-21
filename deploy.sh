#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

# -------------------------
# deploy-ec2.sh
# Automate project deployment on EC2:
# - create /var/www/<subdomain>
# - clone public/private git repo (handles PAT securely)
# - create nginx server block and enable it (HTTP)
# - optionally install certbot and enable HTTPS
# - verify via curl
# -------------------------

# Enhanced error handling with specific guidance
trap 'handle_error $? $LINENO' ERR

# Color-coded output functions
warn() { echo -e "\e[33m[WARN]\e[0m $*"; }
info() { echo -e "\e[32m[INFO]\e[0m $*"; }
fail() { echo -e "\e[31m[ERROR]\e[0m $*"; exit 1; }
success() { echo -e "\e[32m[SUCCESS]\e[0m $*"; }

# Comprehensive error handling function
handle_error() {
    local exit_code=$1
    local line_number=$2
    echo
    echo "❌ ==================== ERROR OCCURRED ===================="
    echo "Error at line $line_number (exit code: $exit_code)"
    echo
    
    # Provide specific guidance based on common error scenarios
    case $exit_code in
        1) 
            echo "💡 Common fixes:"
            echo "   - Check if you have internet connection"
            echo "   - Verify the repository URL is correct"
            echo "   - Make sure you have proper permissions"
            ;;
        2) 
            echo "💡 Common fixes:"
            echo "   - Verify the subdomain format is correct"
            echo "   - Check if the subdomain is already in use"
            echo "   - Ensure DNS is pointing to this server"
            ;;
        3) 
            echo "💡 Common fixes:"
            echo "   - Check if nginx is already running on port 80/443"
            echo "   - Verify nginx configuration is valid"
            echo "   - Restart nginx: sudo systemctl restart nginx"
            ;;
        4) 
            echo "💡 Common fixes:"
            echo "   - Check if certbot is properly installed"
            echo "   - Verify domain DNS is pointing to this server"
            echo "   - Try running: sudo certbot --nginx -d $SUBDOMAIN"
            ;;
        5) 
            echo "💡 Common fixes:"
            echo "   - Check if the project directory exists and is writable"
            echo "   - Verify file permissions: sudo chown -R www-data:www-data $PROJECT_DIR"
            ;;
        *) 
            echo "💡 Common fixes:"
            echo "   - Check the error message above"
            echo "   - Verify all inputs are correct"
            echo "   - Check system logs: journalctl -xe"
            ;;
    esac
    
    echo
    echo "📋 Next steps:"
    echo "   1. Fix the issue mentioned above"
    echo "   2. Run the script again"
    echo "   3. If problem persists, check nginx logs: /var/log/nginx/error.log"
    echo "==============================================================="
    echo
    exit $exit_code
}

# Input validation functions
validate_subdomain() {
    local subdomain=$1
    
    # Check if empty
    if [[ -z "$subdomain" ]]; then
        fail "❌ Subdomain cannot be empty. Please enter a valid subdomain like 'myapp.example.com'" 2
    fi
    
    # Check basic format (letters, numbers, dots, hyphens only)
    if [[ ! "$subdomain" =~ ^[a-zA-Z0-9]([a-zA-Z0-9.-]*[a-zA-Z0-9])?$ ]]; then
        fail "❌ Invalid subdomain format. Use only letters, numbers, dots, and hyphens. Example: 'myapp.example.com'" 2
    fi
    
    # Check length (not too long)
    if [[ ${#subdomain} -gt 253 ]]; then
        fail "❌ Subdomain is too long. Maximum 253 characters allowed." 2
    fi
    
    # Check if it starts or ends with dot or hyphen
    if [[ "$subdomain" =~ ^[.-] ]] || [[ "$subdomain" =~ [.-]$ ]]; then
        fail "❌ Subdomain cannot start or end with dot or hyphen. Example: 'myapp.example.com'" 2
    fi
    
    # Check for consecutive dots
    if [[ "$subdomain" =~ \.\. ]]; then
        fail "❌ Subdomain cannot have consecutive dots. Example: 'myapp.example.com'" 2
    fi
    
    # Check if subdomain is already configured
    local safe_name=$(echo "$subdomain" | tr '/' '_')
    if [[ -f "/etc/nginx/sites-available/${safe_name}.conf" ]]; then
        warn "⚠️  Subdomain '$subdomain' is already configured"
        read -p "Do you want to update the existing configuration? (y/n): " UPDATE
        if [[ ! "$UPDATE" =~ ^[Yy] ]]; then
            fail "❌ Deployment cancelled. Choose a different subdomain" 2
        fi
    fi
    
    info "✅ Subdomain format is valid"
}

validate_repo_url() {
    local repo_url=$1
    
    # Check if empty
    if [[ -z "$repo_url" ]]; then
        fail "❌ Repository URL cannot be empty" 2
    fi
    
    # Check if it's a valid URL format
    if [[ ! "$repo_url" =~ ^https?:// ]]; then
        fail "❌ Invalid repository URL. Must start with http:// or https://" 2
    fi
    
    # Check if it ends with .git or looks like a git repository
    if [[ ! "$repo_url" =~ \.git$ ]] && [[ ! "$repo_url" =~ github\.com ]] && [[ ! "$repo_url" =~ gitlab\.com ]] && [[ ! "$repo_url" =~ bitbucket\.org ]]; then
        warn "⚠️  URL doesn't look like a git repository. Make sure it's correct."
        read -p "Continue anyway? (y/n): " CONTINUE
        if [[ ! "$CONTINUE" =~ ^[Yy] ]]; then
            fail "❌ Please enter a valid git repository URL" 2
        fi
    fi
    
    info "✅ Repository URL format is valid"
}

validate_email() {
    local email=$1
    
    # Check if empty (email is optional for Let's Encrypt)
    if [[ -z "$email" ]]; then
        return 0
    fi
    
    # Basic email format validation
    if [[ ! "$email" =~ ^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$ ]]; then
        fail "❌ Invalid email format. Example: 'user@example.com'" 2
    fi
    
    info "✅ Email format is valid"
}

validate_git_credentials() {
    local git_user=$1
    local git_pat=$2
    
    # Check if PAT is empty
    if [[ -z "$git_pat" ]]; then
        fail "❌ Personal Access Token cannot be empty for private repositories" 2
    fi
    
    # Check PAT length (most PATs are at least 20 characters)
    if [[ ${#git_pat} -lt 10 ]]; then
        warn "⚠️  Personal Access Token seems too short. Most PATs are 20+ characters."
        read -p "Continue anyway? (y/n): " CONTINUE
        if [[ ! "$CONTINUE" =~ ^[Yy] ]]; then
            fail "❌ Please enter a valid Personal Access Token" 2
        fi
    fi
    
    info "✅ Git credentials format is valid"
}

# Progress feedback functions
show_progress() {
    local pid=$1
    local message=$2
    local delay=0.1
    local spinstr='|/-\'
    local temp
    
    echo -n "$message "
    while [ "$(ps a | awk '{print $1}' | grep $pid)" ]; do
        temp=${spinstr#?}
        printf " [%c]  " "$spinstr"
        spinstr=$temp${spinstr%"$temp"}
        sleep $delay
        printf "\b\b\b\b\b\b"
    done
    printf "    \b\b\b\b"
    echo "✅"
}

run_with_progress() {
    local command="$1"
    local message="$2"
    
    echo -n "$message "
    if eval "$command" > /dev/null 2>&1; then
        echo "✅"
        return 0
    else
        echo "❌"
        return 1
    fi
}

show_step() {
    local step_number=$1
    local total_steps=$2
    local message=$3
    
    echo
    echo "🔄 Step $step_number/$total_steps: $message"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
}

# Backup safety functions
create_backup() {
    local file_path=$1
    local backup_type=$2
    
    if [[ -f "$file_path" ]]; then
        local backup_dir="/var/backups/deploy-$(date +%Y%m%d-%H%M%S)"
        local filename=$(basename "$file_path")
        local backup_file="$backup_dir/$filename"
        
        # Create backup directory
        mkdir -p "$backup_dir"
        
        # Copy file to backup
        cp "$file_path" "$backup_file"
        
        # Set proper permissions
        chmod 644 "$backup_file"
        
        echo "✅ Backed up $backup_type to: $backup_file"
        return 0
    else
        echo "ℹ️  No existing $backup_type found to backup"
        return 1
    fi
}

ask_backup() {
    local file_path=$1
    local file_type=$2
    
    if [[ -f "$file_path" ]]; then
        echo
        warn "⚠️  Existing $file_type found at: $file_path"
        read -p "Do you want to create a backup before overwriting? (y/n): " CREATE_BACKUP
        
        # Validate input
        while [[ "$CREATE_BACKUP" != "y" && "$CREATE_BACKUP" != "yes" && "$CREATE_BACKUP" != "n" && "$CREATE_BACKUP" != "no" ]]; do
            echo "❌ Invalid input. Please enter 'y' for yes or 'n' for no"
            read -p "Do you want to create a backup before overwriting? (y/n): " CREATE_BACKUP
        done
        
        if [[ "$CREATE_BACKUP" = "y" || "$CREATE_BACKUP" = "yes" ]]; then
            create_backup "$file_path" "$file_type"
            return 0
        else
            echo "ℹ️  Skipping backup for $file_type"
            return 1
        fi
    else
        return 1
    fi
}

show_backup_info() {
    local backup_dir="/var/backups/deploy-$(date +%Y%m%d-%H%M%S)"
    echo
    echo "💾 ==================== BACKUP INFORMATION ===================="
    echo "Backup directory: $backup_dir"
    echo "To restore a backup:"
    echo "  sudo cp $backup_dir/filename.conf /etc/nginx/sites-available/"
    echo "  sudo systemctl reload nginx"
    echo "==============================================================="
    echo
}

cleanup_old_backups() {
    local backup_dir="/var/backups"
    local max_backups=10
    
    if [[ -d "$backup_dir" ]]; then
        # Count current backups
        local backup_count=$(find "$backup_dir" -maxdepth 1 -type d -name "*deploy-*" -o -name "*project-*" -o -name "*ssl-*" 2>/dev/null | wc -l)
        
        if [[ $backup_count -gt $max_backups ]]; then
            echo "🧹 Cleaning up old backups (keeping last $max_backups)..."
            find "$backup_dir" -maxdepth 1 -type d -name "*deploy-*" -o -name "*project-*" -o -name "*ssl-*" 2>/dev/null | \
            sort | head -n -$max_backups | xargs rm -rf 2>/dev/null
            echo "✅ Old backups cleaned up"
        fi
    fi
}

# Enhanced summary functions
show_deployment_status() {
    local subdomain=$1
    local project_dir=$2
    local nginx_conf=$3
    local repo_url=$4
    local repo_type=$5
    local https_enabled=$6
    local http_ok=$7
    local https_ok=$8
    
    echo
    echo "🎉 ==================== DEPLOYMENT SUMMARY ===================="
    echo
    echo "📋 PROJECT INFORMATION"
    echo "   Subdomain: $subdomain"
    echo "   Project Directory: $project_dir"
    echo "   Nginx Config: $nginx_conf"
    
    if [[ -n "$repo_url" ]]; then
        echo "   Repository: $repo_url"
        echo "   Repository Type: $repo_type"
    else
        echo "   Repository: (none - local deployment)"
    fi
    
    echo
    echo "🌐 WEB SERVER STATUS"
    if [[ "$http_ok" = true ]]; then
        echo "   ✅ HTTP: http://$subdomain - Working!"
    else
        echo "   ❌ HTTP: http://$subdomain - Not accessible"
    fi
    
    if [[ "$https_enabled" = "y" || "$https_enabled" = "yes" ]]; then
        if [[ "$https_ok" = true ]]; then
            echo "   ✅ HTTPS: https://$subdomain - Working!"
        else
            echo "   ❌ HTTPS: https://$subdomain - Not accessible"
        fi
    else
        echo "   ⚪ HTTPS: Not enabled"
    fi
    
    echo
    echo "📁 FILE LOCATIONS"
    echo "   Project Files: $project_dir"
    echo "   Nginx Config: $nginx_conf"
    echo "   Nginx Logs: /var/log/nginx/${subdomain//[^a-zA-Z0-9]/_}_*.log"
    
    if [[ "$https_enabled" = "y" || "$https_enabled" = "yes" ]]; then
        echo "   SSL Certificates: /etc/letsencrypt/live/$subdomain/"
    fi
}

show_next_steps() {
    local subdomain=$1
    local http_ok=$2
    local https_ok=$3
    local https_enabled=$4
    
    echo
    echo "🚀 NEXT STEPS"
    
    if [[ "$http_ok" = true ]]; then
        echo "   ✅ Your website is live at: http://$subdomain"
        if [[ "$https_enabled" = "y" || "$https_enabled" = "yes" && "$https_ok" = true ]]; then
            echo "   ✅ Secure version: https://$subdomain"
        fi
        echo
        echo "   📝 To update your website:"
        echo "     1. Edit files in: $PROJECT_DIR"
        echo "     2. Or push changes to your git repository"
        echo "     3. Run this script again to redeploy"
    else
        echo "   ⚠️  Website may not be accessible yet"
        echo
        echo "   🔧 Troubleshooting steps:"
        echo "     1. Check DNS: Make sure $subdomain points to this server"
        echo "     2. Check firewall: Ensure ports 80 and 443 are open"
        echo "     3. Check nginx: sudo systemctl status nginx"
        echo "     4. Check logs: sudo tail -f /var/log/nginx/error.log"
    fi
    
    echo
    echo "   🛠️  Useful commands:"
    echo "     • Restart nginx: sudo systemctl restart nginx"
    echo "     • Check nginx status: sudo systemctl status nginx"
    echo "     • View nginx logs: sudo tail -f /var/log/nginx/error.log"
    echo "     • Test nginx config: sudo nginx -t"
    
    if [[ "$https_enabled" = "y" || "$https_enabled" = "yes" ]]; then
        echo "     • Renew SSL certificate: sudo certbot renew"
        echo "     • Check SSL status: sudo certbot certificates"
    fi
}

show_troubleshooting() {
    local subdomain=$1
    local http_ok=$2
    local https_ok=$3
    local https_enabled=$4
    
    if [[ "$http_ok" = false || ("$https_enabled" = "y" && "$https_ok" = false) ]]; then
        echo
        echo "🔧 ==================== TROUBLESHOOTING ===================="
        
        if [[ "$http_ok" = false ]]; then
            echo
            echo "❌ HTTP NOT WORKING"
            echo "   Common causes:"
            echo "   • DNS not pointing to this server"
            echo "   • Firewall blocking port 80"
            echo "   • Nginx not running"
            echo "   • Domain not configured properly"
            echo
            echo "   Solutions:"
            echo "   1. Check DNS: nslookup $subdomain"
            echo "   2. Check firewall: sudo ufw status"
            echo "   3. Check nginx: sudo systemctl status nginx"
            echo "   4. Check nginx config: sudo nginx -t"
        fi
        
        if [[ "$https_enabled" = "y" && "$https_ok" = false ]]; then
            echo
            echo "❌ HTTPS NOT WORKING"
            echo "   Common causes:"
            echo "   • SSL certificate not obtained"
            echo "   • DNS not pointing to this server"
            echo "   • Firewall blocking port 443"
            echo "   • Certificate expired or invalid"
            echo
            echo "   Solutions:"
            echo "   1. Check SSL: sudo certbot certificates"
            echo "   2. Renew certificate: sudo certbot renew"
            echo "   3. Check firewall: sudo ufw status"
            echo "   4. Check nginx config: sudo nginx -t"
        fi
        
        echo
        echo "📞 GETTING HELP"
        echo "   • Check nginx logs: sudo tail -f /var/log/nginx/error.log"
        echo "   • Check system logs: sudo journalctl -xe"
        echo "   • Test nginx config: sudo nginx -t"
        echo "   • Restart nginx: sudo systemctl restart nginx"
        echo "==============================================================="
    fi
}

show_success_celebration() {
    local subdomain=$1
    local https_enabled=$2
    local https_ok=$3
    
    echo
    echo "🎉 ==================== SUCCESS! ===================="
    echo
    echo "   🚀 Your website is now live and ready!"
    echo
    echo "   🌐 Visit your site:"
    echo "      http://$subdomain"
    if [[ "$https_enabled" = "y" || "$https_enabled" = "yes" ]] && [[ "$https_ok" = true ]]; then
        echo "      https://$subdomain (secure)"
    fi
    echo
    echo "   🎯 What's next?"
    echo "      • Share your website with others"
    echo "      • Update content by editing files in $PROJECT_DIR"
    echo "      • Push changes to your git repository to redeploy"
    echo "      • Set up monitoring and backups"
    echo
    echo "   💡 Pro tip: Bookmark this page for easy access!"
    echo "=================================================="
    echo
    success "🎉 DEPLOYMENT SUCCESSFUL!"
    echo "   Your website is ready to use!"
}

# Ensure running as root (we need to write /etc/nginx and /var/www)
if [[ "$EUID" -ne 0 ]]; then
  fail "Please run this script with sudo or as root."
fi

# Initialize step counter
CURRENT_STEP=0
TOTAL_STEPS=8

# Show deployment banner
# Pre-flight checks
run_preflight_checks() {
    echo "🔍 ==================== PRE-FLIGHT CHECKS ===================="
    echo "Running system checks to ensure deployment will work smoothly..."
    echo
    
    local checks_passed=0
    local total_checks=8
    
    # Check 1: Root privileges
    echo -n "1. Checking root privileges... "
    if [[ "$EUID" -eq 0 ]]; then
        echo "✅"
        ((checks_passed++))
    else
        echo "❌"
        echo "   Error: This script must be run as root or with sudo"
        echo "   Fix: Run with 'sudo ./deploy.sh'"
        return 1
    fi
    
    # Check 2: Internet connectivity
    echo -n "2. Checking internet connectivity... "
    if ping -c 1 google.com > /dev/null 2>&1; then
        echo "✅"
        ((checks_passed++))
    else
        echo "❌"
        echo "   Error: No internet connection detected"
        echo "   Fix: Check your network connection and try again"
        return 1
    fi
    
    # Check 3: Package manager availability
    echo -n "3. Checking package manager... "
    if command -v apt-get > /dev/null 2>&1; then
        echo "✅ (apt-get)"
        ((checks_passed++))
    elif command -v yum > /dev/null 2>&1; then
        echo "✅ (yum)"
        ((checks_passed++))
    elif command -v pacman > /dev/null 2>&1; then
        echo "✅ (pacman)"
        ((checks_passed++))
    else
        echo "❌"
        echo "   Error: No supported package manager found"
        echo "   Fix: This script requires apt-get, yum, or pacman"
        return 1
    fi
    
    # Check 4: Disk space
    echo -n "4. Checking disk space... "
    local available_space=$(df / | awk 'NR==2 {print $4}')
    if [[ $available_space -gt 1048576 ]]; then  # 1GB in KB
        echo "✅ ($(($available_space / 1024))MB available)"
        ((checks_passed++))
    else
        echo "❌"
        echo "   Error: Insufficient disk space (need at least 1GB)"
        echo "   Fix: Free up disk space and try again"
        return 1
    fi
    
    # Check 5: Port availability
    echo -n "5. Checking port availability... "
    if ! netstat -tlnp 2>/dev/null | grep -q ":80 "; then
        echo "✅ (port 80 available)"
        ((checks_passed++))
    else
        echo "⚠️  (port 80 in use)"
        echo "   Warning: Port 80 is already in use"
        echo "   This might cause issues with nginx"
        read -p "   Continue anyway? (y/n): " CONTINUE_PORT
        if [[ "$CONTINUE_PORT" =~ ^[Yy] ]]; then
            echo "   Proceeding with deployment..."
            ((checks_passed++))
        else
            echo "   Deployment cancelled"
            return 1
        fi
    fi
    
    # Check 6: System resources
    echo -n "6. Checking system resources... "
    local memory_mb=$(free -m | awk 'NR==2{print $2}')
    if [[ $memory_mb -gt 512 ]]; then
        echo "✅ (${memory_mb}MB RAM)"
        ((checks_passed++))
    else
        echo "⚠️  (${memory_mb}MB RAM - low memory)"
        echo "   Warning: Low memory detected"
        echo "   Deployment may be slow but should work"
        ((checks_passed++))
    fi
    
    # Check 7: Existing nginx installation
    echo -n "7. Checking for existing nginx... "
    if command -v nginx > /dev/null 2>&1; then
        echo "✅ (nginx already installed)"
        echo "   Info: Nginx is already installed on this system"
        ((checks_passed++))
    else
        echo "ℹ️  (nginx not installed - will be installed)"
        ((checks_passed++))
    fi
    
    # Check 8: Conflicting web servers
    echo -n "8. Checking for conflicting web servers... "
    local conflicts=()
    if command -v apache2 > /dev/null 2>&1; then
        conflicts+=("Apache2")
    fi
    if command -v httpd > /dev/null 2>&1; then
        conflicts+=("Apache HTTPD")
    fi
    if command -v lighttpd > /dev/null 2>&1; then
        conflicts+=("Lighttpd")
    fi
    
    if [[ ${#conflicts[@]} -eq 0 ]]; then
        echo "✅ (no conflicts)"
        ((checks_passed++))
    else
        echo "⚠️  (found: ${conflicts[*]})"
        echo "   Warning: Other web servers detected: ${conflicts[*]}"
        echo "   These might conflict with nginx on port 80"
        read -p "   Continue anyway? (y/n): " CONTINUE_CONFLICT
        if [[ "$CONTINUE_CONFLICT" =~ ^[Yy] ]]; then
            echo "   Proceeding with deployment..."
            ((checks_passed++))
        else
            echo "   Deployment cancelled"
            return 1
        fi
    fi
    
    echo
    echo "📊 Pre-flight check results: $checks_passed/$total_checks passed"
    
    if [[ $checks_passed -eq $total_checks ]]; then
        echo "✅ All checks passed! Ready for deployment."
        echo
        echo "📋 System Information:"
        echo "   OS: $(lsb_release -d 2>/dev/null | cut -f2 || uname -s)"
        echo "   Kernel: $(uname -r)"
        echo "   Architecture: $(uname -m)"
        echo "   Memory: $(free -h | awk 'NR==2{print $2}')"
        echo "   Disk: $(df -h / | awk 'NR==2{print $4}') available"
        echo "=================================================================="
        return 0
    else
        echo "❌ Some checks failed. Please fix the issues above and try again."
        echo "=================================================================="
        return 1
    fi
}

show_deployment_banner() {
    echo
    echo "🚀 ==================== VPS DEPLOYMENT SCRIPT ===================="
    echo "   Automated web project deployment for VPS servers"
    echo "   Supports: EC2, DigitalOcean, Linode, and other VPS providers"
    echo "=================================================================="
    echo
    echo "📋 This script will:"
    echo "   • Set up your project directory"
    echo "   • Install required packages (git, nginx, curl)"
    echo "   • Clone your repository (if provided)"
    echo "   • Configure nginx web server"
    echo "   • Set up SSL certificates (optional)"
    echo "   • Verify your deployment"
    echo
    echo "⏱️  Estimated time: 2-5 minutes"
    echo "=================================================================="
    echo
}

show_deployment_banner

# Run pre-flight checks
if ! run_preflight_checks; then
    fail "Pre-flight checks failed. Please fix the issues above and try again." 1
fi

show_step 1 $TOTAL_STEPS "Gathering project information"
read -rp "Enter project subdomain (e.g. myapp.example.com): " SUBDOMAIN
validate_subdomain "$SUBDOMAIN"

# sanitize subdomain for filenames
SAFE_NAME=$(echo "$SUBDOMAIN" | tr '/' '_' )

PROJECT_DIR="/var/www/${SAFE_NAME}"
NGINX_SITES_AVAILABLE="/etc/nginx/sites-available"
NGINX_SITES_ENABLED="/etc/nginx/sites-enabled"
NGINX_CONF_PATH="${NGINX_SITES_AVAILABLE}/${SAFE_NAME}.conf"

show_step 2 $TOTAL_STEPS "Setting up project directory"
# Create project directory
if [[ -d "$PROJECT_DIR" ]]; then
  warn "Project directory already exists at $PROJECT_DIR"
  echo
  read -p "Do you want to backup the existing project directory before proceeding? (y/n): " BACKUP_PROJECT
  
  # Validate input
  while [[ "$BACKUP_PROJECT" != "y" && "$BACKUP_PROJECT" != "yes" && "$BACKUP_PROJECT" != "n" && "$BACKUP_PROJECT" != "no" ]]; do
    echo "❌ Invalid input. Please enter 'y' for yes or 'n' for no"
    read -p "Do you want to backup the existing project directory before proceeding? (y/n): " BACKUP_PROJECT
  done
  
  if [[ "$BACKUP_PROJECT" = "y" || "$BACKUP_PROJECT" = "yes" ]]; then
    local backup_dir="/var/backups/project-$(date +%Y%m%d-%H%M%S)"
    local project_name=$(basename "$PROJECT_DIR")
    local backup_path="$backup_dir/$project_name"
    
    echo -n "Creating project backup... "
    mkdir -p "$backup_dir"
    cp -r "$PROJECT_DIR" "$backup_path" 2>/dev/null
    chmod -R 755 "$backup_path" 2>/dev/null
    echo "✅"
    echo "✅ Project backed up to: $backup_path"
  else
    echo "ℹ️  Skipping project backup"
  fi
else
  info "Creating project directory at $PROJECT_DIR"
  mkdir -p "$PROJECT_DIR"
  chown -R "${SUDO_USER:-root}":www-data "$PROJECT_DIR" || true
  chmod -R 755 "$PROJECT_DIR"
  success "Project directory created successfully"
fi

show_step 3 $TOTAL_STEPS "Installing system packages"
# Ensure basic tools installed: git, nginx, curl
info "Checking and installing prerequisites (git, nginx, curl)..."
echo -n "Updating package list... "
if apt-get update -y > /dev/null 2>&1; then
  echo "✅"
else
  echo "❌"
  fail "Failed to update package list" 1
fi

for pkg in git nginx curl; do
  if ! command -v "$pkg" >/dev/null 2>&1; then
    echo -n "Installing $pkg... "
    if apt-get install -y "$pkg" > /dev/null 2>&1; then
      echo "✅"
    else
      echo "❌"
      fail "Failed to install $pkg" 1
    fi
  else
    echo "✅ $pkg already installed"
  fi
done
success "All required packages are ready"

show_step 4 $TOTAL_STEPS "Setting up repository"
# Ask about Git repo
read -rp "Does the project repository exist remotely? (y/n): " REPO_EXISTS
REPO_EXISTS=${REPO_EXISTS,,} # to lower

# Validate yes/no input
if [[ "$REPO_EXISTS" != "y" && "$REPO_EXISTS" != "yes" && "$REPO_EXISTS" != "n" && "$REPO_EXISTS" != "no" ]]; then
  fail "❌ Invalid input. Please enter 'y' for yes or 'n' for no" 2
fi
if [[ "$REPO_EXISTS" = "y" || "$REPO_EXISTS" = "yes" ]]; then
  read -rp "Is the repository public or private? (public/private): " REPO_TYPE
  REPO_TYPE=${REPO_TYPE,,}
  
  # Validate repository type
  if [[ "$REPO_TYPE" != "public" && "$REPO_TYPE" != "private" ]]; then
    fail "❌ Invalid repository type. Please enter 'public' or 'private'" 2
  fi
  read -rp "Enter the Git repository HTTPS URL (e.g. https://github.com/owner/repo.git): " REPO_URL
  validate_repo_url "$REPO_URL"

  if [[ "$REPO_TYPE" = "private" ]]; then
    # Ask for PAT and optionally username
    read -rp "Enter git username for PAT (e.g. GitHub username) [press Enter to skip]: " GIT_USER
    read -rsp "Enter Personal Access Token (PAT) (input is hidden): " GIT_PAT
    echo
    validate_git_credentials "$GIT_USER" "$GIT_PAT"

    # Extract host from URL for .netrc (handles https://host/... or https://user@host/...)
    host=$(echo "$REPO_URL" | sed -E 's#https?://([^/]+)/.*#\1#' )
    if [[ -z "$host" ]]; then
      fail "Could not parse host from repo URL."
    fi

    # Create temporary .netrc with restricted permissions
    NETRC_FILE="$(mktemp)"
    chmod 600 "$NETRC_FILE"
    # netrc fields: machine <host> login <user> password <token>
    # If user omitted, use "git" as login or "oauth2" depending on host; leaving login as provided or "git"
    if [[ -z "$GIT_USER" ]]; then
      echo "machine $host login oauth2 password $GIT_PAT" > "$NETRC_FILE" || true
    else
      echo "machine $host login $GIT_USER password $GIT_PAT" > "$NETRC_FILE" || true
    fi

    echo -n "Cloning private repository... "
    # run git with HOME pointed to a temp dir so .netrc is used
    HOME_TEMP="$(mktemp -d)"
    cp "$NETRC_FILE" "$HOME_TEMP/.netrc"
    chmod 600 "$HOME_TEMP/.netrc"
    # perform clone
    if git -c credential.helper= -c core.askPass= -C /tmp clone "$REPO_URL" "$PROJECT_DIR" --depth=1 2>/dev/null; then
      echo "✅"
    else
      echo -n "Retrying with different method... "
      if ! HOME="$HOME_TEMP" git clone "$REPO_URL" "$PROJECT_DIR" --depth=1 2>/dev/null; then
        echo "❌"
        fail "Failed to clone private repository. Check your credentials and repository URL." 1
      else
        echo "✅"
      fi
    fi

    # cleanup
    rm -f "$NETRC_FILE"
    rm -rf "$HOME_TEMP"
  else
    # public repo
    echo -n "Cloning public repository... "
    if ! git clone "$REPO_URL" "$PROJECT_DIR" --depth=1 2>/dev/null; then
      echo "❌"
      fail "Failed to clone public repository. Check the repository URL and internet connection." 1
    else
      echo "✅"
    fi
  fi

  # Set ownership and permissions
  echo -n "Setting file permissions... "
  chown -R "${SUDO_USER:-root}":www-data "$PROJECT_DIR" || true
  find "$PROJECT_DIR" -type d -exec chmod 755 {} \; 2>/dev/null
  find "$PROJECT_DIR" -type f -exec chmod 644 {} \; 2>/dev/null
  echo "✅"
  success "Repository cloned and configured successfully"
else
  info "Skipping git clone. Project directory left empty."
fi

show_step 5 $TOTAL_STEPS "Configuring web server"
# Create basic index.html if no index exists
if [[ ! -f "${PROJECT_DIR}/index.html" ]]; then
  echo -n "Creating default index page... "
  cat > "${PROJECT_DIR}/index.html" <<EOF
<!doctype html>
<html>
<head><meta charset="utf-8"><title>Welcome to ${SUBDOMAIN}</title></head>
<body>
  <h1>Deployment successful for ${SUBDOMAIN}</h1>
  <p>Document root: ${PROJECT_DIR}</p>
</body>
</html>
EOF
  chown "${SUDO_USER:-root}":www-data "${PROJECT_DIR}/index.html" 2>/dev/null
  echo "✅"
else
  echo "✅ Default index page already exists"
fi

# Generate Nginx server block
echo -n "Creating Nginx configuration... "
# Ask for backup if nginx config already exists
ask_backup "$NGINX_CONF_PATH" "Nginx configuration"

cat > "$NGINX_CONF_PATH" <<NGCONF
server {
    listen 80;
    listen [::]:80;
    server_name ${SUBDOMAIN};

    root ${PROJECT_DIR};
    index index.html index.htm index.php;

    access_log /var/log/nginx/${SAFE_NAME}_access.log;
    error_log  /var/log/nginx/${SAFE_NAME}_error.log;

    location / {
        try_files \$uri \$uri/ =404;
    }

    # Pass PHP (if using PHP-FPM) - uncomment and adjust if needed
    #location ~ \.php\$ {
    #    include snippets/fastcgi-php.conf;
    #    fastcgi_pass unix:/var/run/php/php7.4-fpm.sock;
    #}
}
NGCONF
echo "✅"

# Enable site
echo -n "Enabling Nginx site... "
if [[ ! -L "${NGINX_SITES_ENABLED}/${SAFE_NAME}.conf" ]]; then
  ln -sf "$NGINX_CONF_PATH" "${NGINX_SITES_ENABLED}/${SAFE_NAME}.conf"
fi
echo "✅"

echo -n "Testing Nginx configuration... "
if ! nginx -t > /dev/null 2>&1; then
  echo "❌"
  fail "Nginx configuration test failed. Check the configuration syntax." 3
else
  echo "✅"
fi

echo -n "Reloading Nginx... "
if ! systemctl reload nginx > /dev/null 2>&1; then
  echo "❌"
  fail "Failed to reload Nginx. Check nginx status: systemctl status nginx" 3
else
  echo "✅"
fi
success "Web server configured successfully"

show_step 6 $TOTAL_STEPS "Setting up SSL/HTTPS"
# Ask about enabling HTTPS
read -rp "Do you want to enable HTTPS with Let's Encrypt for ${SUBDOMAIN}? (y/n): " ENABLE_HTTPS
ENABLE_HTTPS=${ENABLE_HTTPS,,}

# Validate yes/no input for HTTPS
if [[ "$ENABLE_HTTPS" != "y" && "$ENABLE_HTTPS" != "yes" && "$ENABLE_HTTPS" != "n" && "$ENABLE_HTTPS" != "no" ]]; then
  fail "❌ Invalid input. Please enter 'y' for yes or 'n' for no" 2
fi

CERTBOT_INSTALLED=false
if [[ "$ENABLE_HTTPS" = "y" || "$ENABLE_HTTPS" = "yes" ]]; then
  echo "Preparing to install certbot (if needed) and request a certificate..."
  
  # Check for existing SSL certificates and offer backup
  local ssl_cert_path="/etc/letsencrypt/live/$SUBDOMAIN/fullchain.pem"
  if [[ -f "$ssl_cert_path" ]]; then
    warn "⚠️  Existing SSL certificate found for $SUBDOMAIN"
    read -p "Do you want to backup the existing SSL certificate before proceeding? (y/n): " BACKUP_SSL
    
    # Validate input
    while [[ "$BACKUP_SSL" != "y" && "$BACKUP_SSL" != "yes" && "$BACKUP_SSL" != "n" && "$BACKUP_SSL" != "no" ]]; do
      echo "❌ Invalid input. Please enter 'y' for yes or 'n' for no"
      read -p "Do you want to backup the existing SSL certificate before proceeding? (y/n): " BACKUP_SSL
    done
    
    if [[ "$BACKUP_SSL" = "y" || "$BACKUP_SSL" = "yes" ]]; then
      local backup_dir="/var/backups/ssl-$(date +%Y%m%d-%H%M%S)"
      echo -n "Creating SSL certificate backup... "
      mkdir -p "$backup_dir"
      cp -r "/etc/letsencrypt/live/$SUBDOMAIN" "$backup_dir/" 2>/dev/null
      cp -r "/etc/letsencrypt/archive/$SUBDOMAIN" "$backup_dir/" 2>/dev/null
      echo "✅"
      echo "✅ SSL certificate backed up to: $backup_dir"
    else
      echo "ℹ️  Skipping SSL certificate backup"
    fi
  fi

  # prefer python3-certbot-nginx if available; fallback to snap
  if command -v certbot >/dev/null 2>&1; then
    echo "✅ certbot already installed"
    CERTBOT_INSTALLED=true
  else
    echo -n "Installing certbot via apt... "
    apt-get install -y software-properties-common > /dev/null 2>&1
    apt-get update -y > /dev/null 2>&1 || true
    if apt-get install -y certbot python3-certbot-nginx > /dev/null 2>&1; then
      echo "✅"
      CERTBOT_INSTALLED=true
    else
      echo "❌"
      echo -n "Trying snap method... "
      if command -v snap >/dev/null 2>&1; then
        snap install core > /dev/null 2>&1; snap refresh core > /dev/null 2>&1
        snap install --classic certbot > /dev/null 2>&1
        ln -sf /snap/bin/certbot /usr/bin/certbot
        echo "✅"
        CERTBOT_INSTALLED=true
      else
        echo -n "Installing snapd first... "
        apt-get install -y snapd > /dev/null 2>&1
        systemctl enable --now snapd.socket > /dev/null 2>&1 || true
        snap install core > /dev/null 2>&1; snap refresh core > /dev/null 2>&1
        snap install --classic certbot > /dev/null 2>&1
        ln -sf /snap/bin/certbot /usr/bin/certbot
        echo "✅"
        CERTBOT_INSTALLED=true
      fi
    fi
  fi

  if [[ "$CERTBOT_INSTALLED" != true ]]; then
    warn "Could not install certbot automatically. Please install certbot and re-run certbot --nginx -d ${SUBDOMAIN}"
  else
    # ask for email
    read -rp "Enter email for Let's Encrypt registration (for renewal notices): " LE_EMAIL
    validate_email "$LE_EMAIL"
    if [[ -z "$LE_EMAIL" ]]; then
      warn "Empty email — certbot will be run without --email (not recommended)."
      CERTBOT_EMAIL_ARG="--register-unsafely-without-email"
    else
      CERTBOT_EMAIL_ARG="--email $LE_EMAIL"
    fi

    echo -n "Obtaining SSL certificate... "
    # Use non-interactive to auto agree tos; interactive may be needed in some cases
    if certbot --nginx -d "$SUBDOMAIN" $CERTBOT_EMAIL_ARG --agree-tos --non-interactive --redirect > /dev/null 2>&1; then
      echo "✅"
      success "SSL certificate obtained and installed successfully"
    else
      echo "❌"
      warn "certbot failed. You may need to run: certbot --nginx -d ${SUBDOMAIN} and investigate errors."
      # Don't fail here, just warn - HTTPS is optional
    fi
  fi
fi

show_step 7 $TOTAL_STEPS "Verifying deployment"
echo "Performing final verification..."

HTTP_OK=false
HTTPS_OK=false

# check HTTP
echo -n "Testing HTTP connection... "
if curl -sS --max-time 10 "http://${SUBDOMAIN}" -o /dev/null 2>&1; then
  echo "✅"
  HTTP_OK=true
else
  echo "❌"
  warn "HTTP check failed for http://${SUBDOMAIN} (DNS may not be set or server not reachable)."
fi

# check HTTPS if enabled
if [[ "$ENABLE_HTTPS" = "y" || "$ENABLE_HTTPS" = "yes" ]]; then
  echo -n "Testing HTTPS connection... "
  if curl -sS --max-time 10 -k "https://${SUBDOMAIN}" -o /dev/null 2>&1; then
    echo "✅"
    HTTPS_OK=true
  else
    echo "❌"
    warn "HTTPS check failed for https://${SUBDOMAIN}."
  fi
fi

show_step 8 $TOTAL_STEPS "Deployment complete"

# Show backup information if any backups were created
if [[ -d "/var/backups" ]] && [[ -n "$(find /var/backups -name "*deploy-*" -o -name "*project-*" -o -name "*ssl-*" 2>/dev/null | head -1)" ]]; then
  echo
  echo "💾 ==================== BACKUP INFORMATION ===================="
  echo "The following backups were created during deployment:"
  find /var/backups -name "*deploy-*" -o -name "*project-*" -o -name "*ssl-*" 2>/dev/null | while read backup_path; do
    if [[ -d "$backup_path" ]]; then
      echo "📁 $backup_path"
    fi
  done
  echo
  echo "To restore a backup:"
  echo "  • Nginx config: sudo cp /var/backups/deploy-*/filename.conf /etc/nginx/sites-available/"
  echo "  • Project files: sudo cp -r /var/backups/project-*/projectname /var/www/"
  echo "  • SSL certificates: sudo cp -r /var/backups/ssl-*/* /etc/letsencrypt/"
  echo "  • Then restart nginx: sudo systemctl reload nginx"
  echo "==============================================================="
fi

# Clean up old backups to prevent disk space issues
cleanup_old_backups

# Show enhanced deployment summary
show_deployment_status "$SUBDOMAIN" "$PROJECT_DIR" "$NGINX_CONF_PATH" "$REPO_URL" "$REPO_TYPE" "$ENABLE_HTTPS" "$HTTP_OK" "$HTTPS_OK"

# Show next steps
show_next_steps "$SUBDOMAIN" "$HTTP_OK" "$HTTPS_OK" "$ENABLE_HTTPS"

# Show troubleshooting if needed
show_troubleshooting "$SUBDOMAIN" "$HTTP_OK" "$HTTPS_OK" "$ENABLE_HTTPS"

# Final status
echo
echo "🏁 ==================== FINAL STATUS ===================="
if [[ "$HTTP_OK" = true && ( "$ENABLE_HTTPS" != "y" && "$ENABLE_HTTPS" != "yes" || "$HTTPS_OK" = true ) ]]; then
  show_success_celebration "$SUBDOMAIN" "$ENABLE_HTTPS" "$HTTPS_OK"
  exit 0
else
  echo "⚠️  DEPLOYMENT COMPLETED WITH ISSUES"
  echo "   Please check the troubleshooting section above"
  echo "   and verify your DNS and firewall settings."
  exit 1
fi
