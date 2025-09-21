#!/usr/bin/env bash
# Summary and reporting functions

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
    local project_dir=$5
    
    echo
    echo "🚀 NEXT STEPS"
    
    if [[ "$http_ok" = true ]]; then
        echo "   ✅ Your website is live at: http://$subdomain"
        if [[ "$https_enabled" = "y" || "$https_enabled" = "yes" && "$https_ok" = true ]]; then
            echo "   ✅ Secure version: https://$subdomain"
        fi
        echo
        echo "   📝 To update your website:"
        echo "     1. Edit files in: $project_dir"
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
    local project_dir=$4
    
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
    echo "      • Update content by editing files in $project_dir"
    echo "      • Push changes to your git repository to redeploy"
    echo "      • Set up monitoring and backups"
    echo
    echo "   💡 Pro tip: Bookmark this page for easy access!"
    echo "=================================================="
    echo
    success "🎉 DEPLOYMENT SUCCESSFUL!"
    echo "   Your website is ready to use!"
}

verify_deployment() {
    local subdomain=$1
    local https_enabled=$2
    
    echo "Performing final verification..."
    
    local http_ok=false
    local https_ok=false
    
    echo -n "Testing HTTP connection... "
    if curl -sS --max-time 10 "http://${subdomain}" -o /dev/null 2>&1; then
        echo "✅"
        http_ok=true
    else
        echo "❌"
        warn "HTTP check failed for http://${subdomain} (DNS may not be set or server not reachable)."
    fi
    
    if [[ "$https_enabled" = "y" || "$https_enabled" = "yes" ]]; then
        echo -n "Testing HTTPS connection... "
        if curl -sS --max-time 10 -k "https://${subdomain}" -o /dev/null 2>&1; then
            echo "✅"
            https_ok=true
        else
            echo "❌"
            warn "HTTPS check failed for https://${subdomain}."
        fi
    fi
    
    echo "$http_ok $https_ok"
}
