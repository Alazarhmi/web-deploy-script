#!/usr/bin/env bash
# SSL/HTTPS functions

install_certbot() {
    if command -v certbot > /dev/null 2>&1; then
        echo "✅ certbot already installed"
        return 0
    else
        echo -n "Installing certbot via apt... "
        apt-get install -y software-properties-common > /dev/null 2>&1
        apt-get update -y > /dev/null 2>&1 || true
        if apt-get install -y certbot python3-certbot-nginx > /dev/null 2>&1; then
            echo "✅"
            return 0
        else
            echo "❌"
            echo -n "Trying snap method... "
            if command -v snap > /dev/null 2>&1; then
                snap install core > /dev/null 2>&1; snap refresh core > /dev/null 2>&1
                snap install --classic certbot > /dev/null 2>&1
                ln -sf /snap/bin/certbot /usr/bin/certbot
                echo "✅"
                return 0
            else
                echo -n "Installing snapd first... "
                apt-get install -y snapd > /dev/null 2>&1
                systemctl enable --now snapd.socket > /dev/null 2>&1 || true
                snap install core > /dev/null 2>&1; snap refresh core > /dev/null 2>&1
                snap install --classic certbot > /dev/null 2>&1
                ln -sf /snap/bin/certbot /usr/bin/certbot
                echo "✅"
                return 0
            fi
        fi
    fi
}

setup_ssl_certificate() {
    local subdomain=$1
    local le_email=$2
    
    backup_ssl_certificate "$subdomain"
    
    echo "Preparing to install certbot (if needed) and request a certificate..."
    
    if ! install_certbot; then
        warn "Could not install certbot automatically. Please install certbot and re-run certbot --nginx -d ${subdomain}"
        return 1
    fi
    
    local certbot_email_arg
    if [[ -z "$le_email" ]]; then
        warn "Empty email — certbot will be run without --email (not recommended)."
        certbot_email_arg="--register-unsafely-without-email"
    else
        certbot_email_arg="--email $le_email"
    fi
    
    echo -n "Obtaining SSL certificate... "
    if certbot --nginx -d "$subdomain" $certbot_email_arg --agree-tos --non-interactive --redirect > /dev/null 2>&1; then
        echo "✅"
        success "SSL certificate obtained and installed successfully"
        return 0
    else
        echo "❌"
        warn "certbot failed. You may need to run: certbot --nginx -d ${subdomain} and investigate errors."
        return 1
    fi
}

setup_https() {
    local subdomain=$1
    local enable_https=$2
    
    if [[ "$enable_https" = "y" || "$enable_https" = "yes" ]]; then
        read -rp "Enter email for Let's Encrypt registration (for renewal notices): " LE_EMAIL
        validate_email "$LE_EMAIL"
        
        setup_ssl_certificate "$subdomain" "$LE_EMAIL"
    fi
}
