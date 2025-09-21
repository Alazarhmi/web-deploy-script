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
    read -rsp "Enter Personal Access Token (PAT) (input is hidden): " GIT_PAT
    echo
    validate_git_credentials "$GIT_USER" "$GIT_PAT"

    local host=$(echo "$repo_url" | sed -E 's#https?://([^/]+)/.*#\1#')
    if [[ -z "$host" ]]; then
        fail "Could not parse host from repository URL." 2
    fi

    echo -n "Testing private repository access... "
    local auth_url
    if [[ -n "$GIT_USER" ]]; then
        auth_url="https://${GIT_USER}:${GIT_PAT}@${host}${repo_url#https://$host}"
    else
        auth_url="https://oauth2:${GIT_PAT}@${host}${repo_url#https://$host}"
    fi
    
    if git ls-remote "$auth_url" > /dev/null 2>&1; then
        echo "✅"
    else
        echo "❌"
        echo
        echo "🔧 Troubleshooting private repository access:"
        echo "   • Verify your Personal Access Token is correct"
        echo "   • Check if the token has repository access permissions"
        echo "   • Ensure the repository URL is correct"
        echo "   • Try creating a new token with full repository access"
        echo "   • For GitHub: Check token permissions in Settings > Developer settings"
        echo
        fail "Cannot access private repository. Please check your credentials and try again." 1
    fi
    
    echo -n "Cloning private repository... "

    if git clone "$auth_url" "$project_dir" --depth=1 2>/dev/null; then
        echo "✅"
        return 0
    fi

    echo -n "Trying alternative method... "
    local netrc_file=$(mktemp)
    local home_temp=$(mktemp -d)

    if [[ -n "$GIT_USER" ]]; then
        echo "machine $host login $GIT_USER password $GIT_PAT" > "$netrc_file"
    else
        echo "machine $host login oauth2 password $GIT_PAT" > "$netrc_file"
    fi
    
    chmod 600 "$netrc_file"
    cp "$netrc_file" "$home_temp/.netrc"
    chmod 600 "$home_temp/.netrc"

    if HOME="$home_temp" git clone "$repo_url" "$project_dir" --depth=1 2>/dev/null; then
        echo "✅"
        rm -f "$netrc_file"
        rm -rf "$home_temp"
        return 0
    fi

    rm -f "$netrc_file"
    rm -rf "$home_temp"
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

setup_repository() {
    local repo_type=$1
    local repo_url=$2
    local project_dir=$3
    
    if [[ "$repo_type" = "private" ]]; then
        clone_private_repository "$repo_url" "$project_dir"
    else
        clone_public_repository "$repo_url" "$project_dir"
    fi

    echo -n "Setting file permissions... "
    chown -R "${SUDO_USER:-root}":www-data "$project_dir" || true
    find "$project_dir" -type d -exec chmod 755 {} \; 2>/dev/null
    find "$project_dir" -type f -exec chmod 644 {} \; 2>/dev/null
    echo "✅"
    success "Repository cloned and configured successfully"
}
