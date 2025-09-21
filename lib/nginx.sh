#!/usr/bin/env bash
# Nginx configuration functions

install_packages() {
    echo -n "Updating package list... "
    if apt-get update -y > /dev/null 2>&1; then
        echo "✅"
    else
        echo "❌"
        fail "Failed to update package list" 1
    fi

    for pkg in git nginx curl; do
        if ! command -v "$pkg" > /dev/null 2>&1; then
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
}

create_nginx_config() {
    local subdomain=$1
    local project_dir=$2
    local nginx_conf_path=$3
    local safe_name=$4
    
    echo -n "Creating Nginx configuration... "
    ask_backup "$nginx_conf_path" "Nginx configuration"

    cat > "$nginx_conf_path" <<NGCONF
server {
    listen 80;
    listen [::]:80;
    server_name ${subdomain};

    root ${project_dir};
    index index.html index.htm index.php;

    access_log /var/log/nginx/${safe_name}_access.log;
    error_log  /var/log/nginx/${safe_name}_error.log;

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
}

enable_nginx_site() {
    local nginx_conf_path=$1
    local nginx_sites_enabled=$2
    local safe_name=$3
    
    echo -n "Enabling Nginx site... "
    if [[ ! -L "${nginx_sites_enabled}/${safe_name}.conf" ]]; then
        ln -sf "$nginx_conf_path" "${nginx_sites_enabled}/${safe_name}.conf"
    fi
    echo "✅"
}

test_nginx_config() {
    echo -n "Testing Nginx configuration... "
    if ! nginx -t > /dev/null 2>&1; then
        echo "❌"
        fail "Nginx configuration test failed. Check the configuration syntax." 3
    else
        echo "✅"
    fi
}

reload_nginx() {
    echo -n "Reloading Nginx... "
    if ! systemctl reload nginx > /dev/null 2>&1; then
        echo "❌"
        fail "Failed to reload Nginx. Check nginx status: systemctl status nginx" 3
    else
        echo "✅"
    fi
}

create_default_index() {
    local project_dir=$1
    local subdomain=$2
    
    if [[ ! -f "${project_dir}/index.html" ]]; then
        echo -n "Creating default index page... "
        cat > "${project_dir}/index.html" <<EOF
<!doctype html>
<html>
<head><meta charset="utf-8"><title>Welcome to ${subdomain}</title></head>
<body>
  <h1>Deployment successful for ${subdomain}</h1>
  <p>Document root: ${project_dir}</p>
</body>
</html>
EOF
        chown "${SUDO_USER:-root}":www-data "${project_dir}/index.html" 2>/dev/null
        echo "✅"
    else
        echo "✅ Default index page already exists"
    fi
}

setup_nginx() {
    local subdomain=$1
    local project_dir=$2
    local nginx_conf_path=$3
    local nginx_sites_enabled=$4
    local safe_name=$5
    
    create_default_index "$project_dir" "$subdomain"
    
    create_nginx_config "$subdomain" "$project_dir" "$nginx_conf_path" "$safe_name"
    
    enable_nginx_site "$nginx_conf_path" "$nginx_sites_enabled" "$safe_name"
    
    test_nginx_config
    reload_nginx
    
    success "Web server configured successfully"
}
