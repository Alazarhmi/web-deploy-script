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

# Ensure running as root (we need to write /etc/nginx and /var/www)
if [[ "$EUID" -ne 0 ]]; then
  fail "Please run this script with sudo or as root."
fi

read -rp "Enter project subdomain (e.g. myapp.example.com): " SUBDOMAIN
validate_subdomain "$SUBDOMAIN"

# sanitize subdomain for filenames
SAFE_NAME=$(echo "$SUBDOMAIN" | tr '/' '_' )

PROJECT_DIR="/var/www/${SAFE_NAME}"
NGINX_SITES_AVAILABLE="/etc/nginx/sites-available"
NGINX_SITES_ENABLED="/etc/nginx/sites-enabled"
NGINX_CONF_PATH="${NGINX_SITES_AVAILABLE}/${SAFE_NAME}.conf"

# Create project directory
if [[ -d "$PROJECT_DIR" ]]; then
  warn "Project directory already exists at $PROJECT_DIR"
else
  info "Creating project directory at $PROJECT_DIR"
  mkdir -p "$PROJECT_DIR"
  chown -R "${SUDO_USER:-root}":www-data "$PROJECT_DIR" || true
  chmod -R 755 "$PROJECT_DIR"
fi

# Ensure basic tools installed: git, nginx, curl
info "Checking and installing prerequisites (git, nginx, curl)..."
apt-get update -y
for pkg in git nginx curl; do
  if ! command -v "$pkg" >/dev/null 2>&1; then
    info "Installing $pkg..."
    apt-get install -y "$pkg"
  else
    info "$pkg already installed."
  fi
done

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

    info "Cloning private repo into $PROJECT_DIR (using temporary .netrc)..."
    # run git with HOME pointed to a temp dir so .netrc is used
    HOME_TEMP="$(mktemp -d)"
    cp "$NETRC_FILE" "$HOME_TEMP/.netrc"
    chmod 600 "$HOME_TEMP/.netrc"
    # perform clone
    if git -c credential.helper= -c core.askPass= -C /tmp clone "$REPO_URL" "$PROJECT_DIR" --depth=1 2>/dev/null; then
      info "Repository cloned successfully."
    else
      warn "Initial git clone attempt failed; trying with explicit HOME..."
      if ! HOME="$HOME_TEMP" git clone "$REPO_URL" "$PROJECT_DIR" --depth=1; then
        fail "Failed to clone private repository. Check your credentials and repository URL." 1
      fi
    fi

    # cleanup
    rm -f "$NETRC_FILE"
    rm -rf "$HOME_TEMP"
  else
    # public repo
    info "Cloning public repo into $PROJECT_DIR..."
    if ! git clone "$REPO_URL" "$PROJECT_DIR" --depth=1; then
      fail "Failed to clone public repository. Check the repository URL and internet connection." 1
    fi
  fi

  # Set ownership and permissions
  chown -R "${SUDO_USER:-root}":www-data "$PROJECT_DIR" || true
  find "$PROJECT_DIR" -type d -exec chmod 755 {} \;
  find "$PROJECT_DIR" -type f -exec chmod 644 {} \;
else
  info "Skipping git clone. Project directory left empty."
fi

# Create basic index.html if no index exists
if [[ ! -f "${PROJECT_DIR}/index.html" ]]; then
  info "No index.html found; creating a simple index page for testing."
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
  chown "${SUDO_USER:-root}":www-data "${PROJECT_DIR}/index.html"
fi

# Generate Nginx server block
info "Creating Nginx configuration for ${SUBDOMAIN}..."
if [[ -f "$NGINX_CONF_PATH" ]]; then
  warn "Nginx config already exists at $NGINX_CONF_PATH (will be overwritten)."
fi

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

# Enable site
if [[ ! -L "${NGINX_SITES_ENABLED}/${SAFE_NAME}.conf" ]]; then
  ln -sf "$NGINX_CONF_PATH" "${NGINX_SITES_ENABLED}/${SAFE_NAME}.conf"
fi

info "Testing Nginx configuration..."
if ! nginx -t; then
  fail "Nginx configuration test failed. Check the configuration syntax." 3
fi

info "Reloading Nginx..."
if ! systemctl reload nginx; then
  fail "Failed to reload Nginx. Check nginx status: systemctl status nginx" 3
fi

# Ask about enabling HTTPS
read -rp "Do you want to enable HTTPS with Let's Encrypt for ${SUBDOMAIN}? (y/n): " ENABLE_HTTPS
ENABLE_HTTPS=${ENABLE_HTTPS,,}

# Validate yes/no input for HTTPS
if [[ "$ENABLE_HTTPS" != "y" && "$ENABLE_HTTPS" != "yes" && "$ENABLE_HTTPS" != "n" && "$ENABLE_HTTPS" != "no" ]]; then
  fail "❌ Invalid input. Please enter 'y' for yes or 'n' for no" 2
fi

CERTBOT_INSTALLED=false
if [[ "$ENABLE_HTTPS" = "y" || "$ENABLE_HTTPS" = "yes" ]]; then
  info "Preparing to install certbot (if needed) and request a certificate."

  # prefer python3-certbot-nginx if available; fallback to snap
  if command -v certbot >/dev/null 2>&1; then
    info "certbot already installed."
    CERTBOT_INSTALLED=true
  else
    info "Attempting to install certbot via apt (python3-certbot-nginx)..."
    apt-get install -y software-properties-common
    apt-get update -y || true
    if apt-get install -y certbot python3-certbot-nginx; then
      CERTBOT_INSTALLED=true
    else
      warn "apt install of certbot failed — trying snap method."
      if command -v snap >/dev/null 2>&1; then
        snap install core; snap refresh core
        snap install --classic certbot
        ln -sf /snap/bin/certbot /usr/bin/certbot
        CERTBOT_INSTALLED=true
      else
        warn "snap not installed; attempting to install snapd..."
        apt-get install -y snapd
        systemctl enable --now snapd.socket || true
        snap install core; snap refresh core
        snap install --classic certbot
        ln -sf /snap/bin/certbot /usr/bin/certbot
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

    info "Running certbot to obtain & install certificate for ${SUBDOMAIN}..."
    # Use non-interactive to auto agree tos; interactive may be needed in some cases
    if certbot --nginx -d "$SUBDOMAIN" $CERTBOT_EMAIL_ARG --agree-tos --non-interactive --redirect; then
      info "Certificate obtained and installed successfully."
    else
      warn "certbot failed. You may need to run: certbot --nginx -d ${SUBDOMAIN} and investigate errors."
      # Don't fail here, just warn - HTTPS is optional
    fi
  fi
fi

# Final verification
info "Performing final verification..."

HTTP_OK=false
HTTPS_OK=false

# check HTTP
if curl -sS --max-time 10 "http://${SUBDOMAIN}" -o /dev/null; then
  info "HTTP check succeeded: http://${SUBDOMAIN} returned a response."
  HTTP_OK=true
else
  warn "HTTP check failed for http://${SUBDOMAIN} (DNS may not be set or server not reachable)."
fi

# check HTTPS if enabled
if [[ "$ENABLE_HTTPS" = "y" || "$ENABLE_HTTPS" = "yes" ]]; then
  if curl -sS --max-time 10 -k "https://${SUBDOMAIN}" -o /dev/null; then
    info "HTTPS check succeeded: https://${SUBDOMAIN} returned a response."
    HTTPS_OK=true
  else
    warn "HTTPS check failed for https://${SUBDOMAIN}."
  fi
fi

# Summary
echo
echo "==================== Deployment Summary ===================="
echo "Subdomain: $SUBDOMAIN"
echo "Project directory: $PROJECT_DIR"
echo "Nginx config: $NGINX_CONF_PATH"
if [[ "$REPO_EXISTS" = "y" || "$REPO_EXISTS" = "yes" ]]; then
  echo "Repository: $REPO_URL"
  echo "Repo type: $REPO_TYPE"
else
  echo "Repository: (none)"
fi
if [[ "$ENABLE_HTTPS" = "y" || "$ENABLE_HTTPS" = "yes" ]]; then
  echo "HTTPS requested: yes"
else
  echo "HTTPS requested: no"
fi
echo "HTTP reachable: $HTTP_OK"
if [[ "$ENABLE_HTTPS" = "y" || "$ENABLE_HTTPS" = "yes" ]]; then
  echo "HTTPS reachable: $HTTPS_OK"
fi
echo "============================================================"
echo

if [[ "$HTTP_OK" = true && ( "$ENABLE_HTTPS" != "y" && "$ENABLE_HTTPS" != "yes" || "$HTTPS_OK" = true ) ]]; then
  info "Deployment successful! Visit: http://${SUBDOMAIN} $( [[ "$ENABLE_HTTPS" = "y" || "$ENABLE_HTTPS" = "yes" ]] && echo "and https://${SUBDOMAIN}" )"
  exit 0
else
  fail "Deployment may have issues. Check DNS, firewall (port 80/443), and Nginx logs: /var/log/nginx/${SAFE_NAME}_error.log"
fi
