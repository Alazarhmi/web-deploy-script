#!/usr/bin/env bash
# Git clone and repository functions

test_git_connectivity() {
    local repo_url=$1
    
    echo -n "Testing git connectivity... "
    if git ls-remote "$repo_url" > /dev/null 2>&1; then
        echo "✅"
        return 0
    else
        echo "❌"
        return 1
    fi
}

clone_public_repository() {
    local repo_url=$1
    local project_dir=$2
    
    if ! test_git_connectivity "$repo_url"; then
        echo
        echo "🔧 Troubleshooting public repository access:"
        echo "   • Check if the repository URL is correct"
        echo "   • Verify the repository is public and accessible"
        echo "   • Test the URL in your browser"
        echo "   • Check your internet connection"
        echo "   • Ensure git is properly installed"
        echo
        fail "Cannot access public repository. Please check the URL and try again." 1
    fi
    
    echo -n "Cloning public repository... "
    if git clone "$repo_url" "$project_dir" --depth=1 2>/dev/null; then
        echo "✅"
        return 0
    else
        echo "❌"
        echo
        echo "🔧 Troubleshooting public repository clone:"
        echo "   • Check if the repository URL is correct"
        echo "   • Verify the repository is public and accessible"
        echo "   • Test the URL in your browser"
        echo "   • Check your internet connection"
        echo
        fail "Failed to clone public repository. Please check the URL and try again." 1
    fi
}


clone_private_repository() {
    local repo_url=$1
    local project_dir=$2
    
    read -rp "Enter git username for PAT (e.g. GitHub username) [press Enter to skip]: " GIT_USER
    read -rp "Enter Personal Access Token (PAT): " GIT_PAT
    validate_git_credentials "$GIT_USER" "$GIT_PAT"

    local host=$(echo "$repo_url" | sed -E 's#https?://([^/]+)/.*#\1#')
    if [[ -z "$host" ]]; then
        fail "Could not parse host from repository URL." 2
    fi

    # Create authenticated URL
    local auth_url
    if [[ -n "$GIT_USER" ]]; then
        auth_url="https://${GIT_USER}:${GIT_PAT}@${host}${repo_url#https://$host}"
    else
        auth_url="https://oauth2:${GIT_PAT}@${host}${repo_url#https://$host}"
    fi
    
    echo -n "Testing private repository access... "
    if git ls-remote "$auth_url" > /dev/null 2>&1; then
        echo "✅"
    else
        echo "❌"
        echo
        echo "🔧 Debug information:"
        echo "   • Repository URL: $repo_url"
        echo "   • Host: $host"
        echo "   • Username: ${GIT_USER:-'oauth2'}"
        echo "   • Token length: ${#GIT_PAT} characters"
        echo
        echo "🔧 Troubleshooting private repository access:"
        echo "   • Verify your Personal Access Token is correct"
        echo "   • Check if the token has repository access permissions"
        echo "   • Ensure the repository URL is correct"
        echo "   • Try creating a new token with full repository access"
        echo "   • For GitHub: Check token permissions in Settings > Developer settings"
        echo
        echo "💡 Try testing manually:"
        echo "   git ls-remote $auth_url"
        echo
        fail "Cannot access private repository. Please check your credentials and try again." 1
    fi
    
    echo -n "Cloning private repository... "
    
    if git clone "$auth_url" "$project_dir" --depth=1 2>/dev/null; then
        echo "✅"
        return 0
    fi

    echo "❌"
    
    echo
    echo "🔧 Troubleshooting private repository clone:"
    echo "   • Verify your Personal Access Token is correct"
    echo "   • Check if the token has repository access permissions"
    echo "   • Ensure the repository URL is correct"
    echo "   • Try creating a new token with full repository access"
    echo "   • For GitHub: Check token permissions in Settings > Developer settings"
    echo
    fail "Failed to clone private repository. Please check your credentials and try again." 1
}

cleanup_failed_clone() {
    local project_dir=$1
    
    if [[ -d "$project_dir" ]]; then
        echo -n "Cleaning up failed clone attempt... "
        rm -rf "$project_dir" 2>/dev/null
        echo "✅"
    fi
}

setup_repository() {
    local repo_type=$1
    local repo_url=$2
    local project_dir=$3
    
    # Remove existing directory if it exists (from failed deployments)
    if [[ -d "$project_dir" ]]; then
        echo -n "Removing existing project directory... "
        rm -rf "$project_dir" 2>/dev/null
        echo "✅"
    fi
    
    # Create fresh project directory
    echo -n "Creating project directory... "
    mkdir -p "$project_dir"
    echo "✅"
    
    if [[ "$repo_type" = "private" ]]; then
        if ! clone_private_repository "$repo_url" "$project_dir"; then
            cleanup_failed_clone "$project_dir"
            return 1
        fi
    else
        if ! clone_public_repository "$repo_url" "$project_dir"; then
            cleanup_failed_clone "$project_dir"
            return 1
        fi
    fi

    echo -n "Setting file permissions... "
    chown -R "${SUDO_USER:-root}":www-data "$project_dir" || true
    find "$project_dir" -type d -exec chmod 755 {} \; 2>/dev/null
    find "$project_dir" -type f -exec chmod 644 {} \; 2>/dev/null
    echo "✅"
    success "Repository cloned and configured successfully"
}
