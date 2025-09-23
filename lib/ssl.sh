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

check_ssl_prerequisites() {
    local subdomain=$1
    
    echo "🔍 Checking SSL prerequisites..."
    
    echo -n "   • Checking DNS resolution... "
    local domain_ip=$(dig +short "$subdomain" | tail -n1)
    local server_ip=$(curl -s ifconfig.me 2>/dev/null || curl -s ipinfo.io/ip 2>/dev/null || echo "unknown")
    
    if [[ -n "$domain_ip" && "$domain_ip" != "127.0.0.1" ]]; then
        echo "✅ ($domain_ip)"
    else
        echo "❌ (DNS not pointing to server)"
        warn "   DNS issue: $subdomain is not pointing to this server"
        warn "   Current server IP: $server_ip"
        warn "   Please update your DNS settings and wait 5-10 minutes"
        return 1
    fi
    
    echo -n "   • Checking port 443... "
    if netstat -tlnp 2>/dev/null | grep -q ":443 "; then
        echo "✅ (port 443 in use - existing SSL sites detected)"
        echo "   📋 Existing SSL sites:"
        sudo certbot certificates 2>/dev/null | grep -E "Certificate Name|Domains:" | sed 's/^/      /'
    else
        echo "⚠️  (port 443 not in use - this is normal for new setups)"
    fi
    
    echo -n "   • Checking nginx status... "
    if systemctl is-active --quiet nginx; then
        echo "✅ (nginx running)"
    else
        echo "❌ (nginx not running)"
        warn "   Nginx is not running. Please start it first: sudo systemctl start nginx"
        return 1
    fi
    
    local safe_name=$(echo "$subdomain" | tr '/' '_')
    local nginx_conf="/etc/nginx/sites-available/${safe_name}.conf"
    local nginx_enabled="/etc/nginx/sites-enabled/${safe_name}.conf"
    
    echo -n "   • Checking nginx configuration... "
    if [[ -f "$nginx_conf" ]]; then
        if [[ -L "$nginx_enabled" ]]; then
            echo "✅ (config exists and enabled)"
        else
            echo "❌ (config exists but not enabled)"
            warn "   Nginx config exists but is not enabled. Run: sudo ln -sf $nginx_conf $nginx_enabled"
            return 1
        fi
    else
        echo "❌ (config not found)"
        warn "   Nginx configuration not found at: $nginx_conf"
        return 1
    fi
    
    echo -n "   • Testing nginx configuration... "
    if nginx -t > /dev/null 2>&1; then
        echo "✅ (nginx config is valid)"
    else
        echo "❌ (nginx config has errors)"
        warn "   Nginx configuration has errors. Run: sudo nginx -t"
        return 1
    fi
    
    return 0
}

setup_ssl_certificate() {
    local subdomain=$1
    local le_email=$2
    
    backup_ssl_certificate "$subdomain"
    
    echo "Preparing to install certbot (if needed) and request a certificate..."
    
    if ! check_ssl_prerequisites "$subdomain"; then
        warn "SSL prerequisites not met. Please fix the issues above and try again."
        return 1
    fi
    
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
    
    local certbot_log=$(mktemp)
    
    if certbot --nginx -d "$subdomain" $certbot_email_arg --agree-tos --non-interactive --redirect > "$certbot_log" 2>&1; then
        echo "✅"
        success "SSL certificate obtained and installed successfully"
        rm -f "$certbot_log"
        return 0
    else
        echo "❌"
        echo
        warn "certbot failed. Here's what went wrong:"
        echo "   📋 Certbot error output:"
        cat "$certbot_log" | sed 's/^/      /'
        echo
        warn "Common issues and solutions:"
        echo "   • DNS not pointing to this server (wait 5-10 minutes)"
        echo "   • Port 443 not open (run: sudo ufw allow 443)"
        echo "   • Domain already has a certificate (check: sudo certbot certificates)"
        echo "   • Nginx configuration issue (check: sudo nginx -t)"
        echo
        echo "🔧 Try running manually:"
        echo "   **sudo certbot --nginx -d ${subdomain}**"
        echo
        echo "📋 Debug information:"
        echo "   • Check nginx status: sudo systemctl status nginx"
        echo "   • Check nginx config: sudo nginx -t"
        echo "   • Check certbot logs: sudo certbot certificates"
        echo "   • Check nginx sites: ls -la /etc/nginx/sites-enabled/"
        rm -f "$certbot_log"
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
