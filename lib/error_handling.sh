#!/usr/bin/env bash
# Error handling and logging functions

warn() { echo -e "\e[33m[WARN]\e[0m $*"; }
info() { echo -e "\e[32m[INFO]\e[0m $*"; }
fail() { echo -e "\e[31m[ERROR]\e[0m $*"; exit 1; }
success() { echo -e "\e[32m[SUCCESS]\e[0m $*"; }

handle_error() {
    local exit_code=$1
    local line_number=$2
    echo
    echo "❌ ==================== ERROR OCCURRED ===================="
    echo "Error at line $line_number (exit code: $exit_code)"
    echo
    
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

setup_error_handling() {
    trap 'handle_error $? $LINENO' ERR
}
