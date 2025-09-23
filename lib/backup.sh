#!/usr/bin/env bash
# Backup and safety functions

create_backup() {
    local file_path=$1
    local backup_type=$2
    
    if [[ -f "$file_path" ]]; then
        local timestamp=$(date +%Y%m%d-%H%M%S-%N | cut -c1-23)
        local backup_dir="/var/backups/deploy-${timestamp}"
        local filename=$(basename "$file_path")
        local backup_file="$backup_dir/$filename"
        
        mkdir -p "$backup_dir"
        
        cp "$file_path" "$backup_file"
        
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
        echo -n "Do you want to create a backup before overwriting? (y/n): "
        read CREATE_BACKUP
        
        # Validate input with timeout
        local attempts=0
        while [[ "$CREATE_BACKUP" != "y" && "$CREATE_BACKUP" != "yes" && "$CREATE_BACKUP" != "n" && "$CREATE_BACKUP" != "no" ]]; do
            ((attempts++))
            if [[ $attempts -gt 3 ]]; then
                echo "❌ Too many invalid attempts. Skipping backup."
                return 1
            fi
            echo "❌ Invalid input. Please enter 'y' for yes or 'n' for no"
            echo -n "Do you want to create a backup before overwriting? (y/n): "
            read CREATE_BACKUP
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

backup_project_directory() {
    local project_dir=$1
    
    if [[ -d "$project_dir" ]]; then
        warn "Project directory already exists at $project_dir"
        echo
        read -p "Do you want to backup the existing project directory before proceeding? (y/n): " BACKUP_PROJECT
        
        while [[ "$BACKUP_PROJECT" != "y" && "$BACKUP_PROJECT" != "yes" && "$BACKUP_PROJECT" != "n" && "$BACKUP_PROJECT" != "no" ]]; do
            echo "❌ Invalid input. Please enter 'y' for yes or 'n' for no"
            read -p "Do you want to backup the existing project directory before proceeding? (y/n): " BACKUP_PROJECT
        done
        
        if [[ "$BACKUP_PROJECT" = "y" || "$BACKUP_PROJECT" = "yes" ]]; then
            local timestamp=$(date +%Y%m%d-%H%M%S-%N | cut -c1-23)
            local backup_dir="/var/backups/project-${timestamp}"
            local project_name=$(basename "$project_dir")
            local backup_path="$backup_dir/$project_name"
            
            echo -n "Creating project backup... "
            mkdir -p "$backup_dir"
            cp -r "$project_dir" "$backup_path" 2>/dev/null
            chmod -R 755 "$backup_path" 2>/dev/null
            echo "✅"
            echo "✅ Project backed up to: $backup_path"
        else
            echo "ℹ️  Skipping project backup"
        fi
    fi
}

backup_ssl_certificate() {
    local subdomain=$1
    
    local ssl_cert_path="/etc/letsencrypt/live/$subdomain/fullchain.pem"
    if [[ -f "$ssl_cert_path" ]]; then
        warn "⚠️  Existing SSL certificate found for $subdomain"
        read -p "Do you want to backup the existing SSL certificate before proceeding? (y/n): " BACKUP_SSL
        
        while [[ "$BACKUP_SSL" != "y" && "$BACKUP_SSL" != "yes" && "$BACKUP_SSL" != "n" && "$BACKUP_SSL" != "no" ]]; do
            echo "❌ Invalid input. Please enter 'y' for yes or 'n' for no"
            read -p "Do you want to backup the existing SSL certificate before proceeding? (y/n): " BACKUP_SSL
        done
        
        if [[ "$BACKUP_SSL" = "y" || "$BACKUP_SSL" = "yes" ]]; then
            local timestamp=$(date +%Y%m%d-%H%M%S-%N | cut -c1-23)
            local backup_dir="/var/backups/ssl-${timestamp}"
            echo -n "Creating SSL certificate backup... "
            mkdir -p "$backup_dir"
            cp -r "/etc/letsencrypt/live/$subdomain" "$backup_dir/" 2>/dev/null
            cp -r "/etc/letsencrypt/archive/$subdomain" "$backup_dir/" 2>/dev/null
            echo "✅"
            echo "✅ SSL certificate backed up to: $backup_dir"
        else
            echo "ℹ️  Skipping SSL certificate backup"
        fi
    fi
}

cleanup_old_backups() {
    local backup_dir="/var/backups"
    local max_backups=10
    
    if [[ -d "$backup_dir" ]]; then
        local backup_count=$(find "$backup_dir" -maxdepth 1 -type d -name "*deploy-*" -o -name "*project-*" -o -name "*ssl-*" 2>/dev/null | wc -l)
        
        if [[ $backup_count -gt $max_backups ]]; then
            echo "🧹 Cleaning up old backups (keeping last $max_backups)..."
            find "$backup_dir" -maxdepth 1 -type d -name "*deploy-*" -o -name "*project-*" -o -name "*ssl-*" 2>/dev/null | \
            sort | head -n -$max_backups | xargs rm -rf 2>/dev/null
            echo "✅ Old backups cleaned up"
        fi
    fi
}

show_backup_info() {
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
}
