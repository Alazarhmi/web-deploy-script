#!/usr/bin/env bash
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
