#!/usr/bin/env bash
# Pre-flight checks

run_preflight_checks() {
    echo "🔍 ==================== PRE-FLIGHT CHECKS ===================="
    echo "Running system checks to ensure deployment will work smoothly..."
    echo
    
    local checks_passed=0
    local total_checks=8
    
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
    
    echo -n "7. Checking for existing nginx... "
    if command -v nginx > /dev/null 2>&1; then
        echo "✅ (nginx already installed)"
        echo "   Info: Nginx is already installed on this system"
        ((checks_passed++))
    else
        echo "ℹ️  (nginx not installed - will be installed)"
        ((checks_passed++))
    fi
    
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
