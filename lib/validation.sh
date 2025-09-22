#!/usr/bin/env bash
# Input validation functions

validate_subdomain() {
    local subdomain=$1
    
    if [[ -z "$subdomain" ]]; then
        fail "❌ Subdomain cannot be empty. Please enter a valid subdomain like 'myapp.example.com'" 2
    fi
    
    if [[ ! "$subdomain" =~ ^[a-zA-Z0-9]([a-zA-Z0-9.-]*[a-zA-Z0-9])?$ ]]; then
        fail "❌ Invalid subdomain format. Use only letters, numbers, dots, and hyphens. Example: 'myapp.example.com'" 2
    fi
    
    if [[ ${#subdomain} -gt 253 ]]; then
        fail "❌ Subdomain is too long. Maximum 253 characters allowed." 2
    fi
    
    if [[ "$subdomain" =~ ^[.-] ]] || [[ "$subdomain" =~ [.-]$ ]]; then
        fail "❌ Subdomain cannot start or end with dot or hyphen. Example: 'myapp.example.com'" 2
    fi
    
    if [[ "$subdomain" =~ \.\. ]]; then
        fail "❌ Subdomain cannot have consecutive dots. Example: 'myapp.example.com'" 2
    fi

    local safe_name=$(echo "$subdomain" | tr '/' '_')
    if [[ -f "/etc/nginx/sites-available/${safe_name}.conf" ]]; then
        warn "⚠️  Subdomain '$subdomain' is already configured"
        read -p "Do you want to update the existing configuration? (y/n): " UPDATE
        if [[ ! "$UPDATE" =~ ^[Yy] ]]; then
            fail "❌ Deployment cancelled. Choose a different subdomain" 2
        fi
    fi
    
    info "✅ Subdomain format is valid"
}

validate_repo_url() {
    local repo_url=$1

    if [[ -z "$repo_url" ]]; then
        fail "❌ Repository URL cannot be empty" 2
    fi

    if [[ ! "$repo_url" =~ ^https?:// ]]; then
        fail "❌ Invalid repository URL. Must start with http:// or https://" 2
    fi

    if [[ ! "$repo_url" =~ \.git$ ]] && [[ ! "$repo_url" =~ github\.com ]] && [[ ! "$repo_url" =~ gitlab\.com ]] && [[ ! "$repo_url" =~ bitbucket\.org ]]; then
        warn "⚠️  URL doesn't look like a git repository. Make sure it's correct."
        read -p "Continue anyway? (y/n): " CONTINUE
        if [[ ! "$CONTINUE" =~ ^[Yy] ]]; then
            fail "❌ Please enter a valid git repository URL" 2
        fi
    fi
    
    info "✅ Repository URL format is valid"
}

validate_email() {
    local email=$1

    if [[ -z "$email" ]]; then
        return 0
    fi

    if [[ ! "$email" =~ ^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$ ]]; then
        fail "❌ Invalid email format. Example: 'user@example.com'" 2
    fi
    
    info "✅ Email format is valid"
}

validate_git_credentials() {
    local git_user=$1
    local git_pat=$2

    if [[ -z "$git_pat" ]]; then
        fail "❌ Personal Access Token cannot be empty for private repositories" 2
    fi

    if [[ ${#git_pat} -lt 10 ]]; then
        warn "⚠️  Personal Access Token seems too short. Most PATs are 20+ characters."
        read -p "Continue anyway? (y/n): " CONTINUE
        if [[ ! "$CONTINUE" =~ ^[Yy] ]]; then
            fail "❌ Please enter a valid Personal Access Token" 2
        fi
    fi
    
    info "✅ Git credentials format is valid"
}

validate_yes_no_input() {
    local input=$1
    local field_name=$2
    
    if [[ "$input" != "y" && "$input" != "yes" && "$input" != "n" && "$input" != "no" ]]; then
        fail "❌ Invalid input for $field_name. Please enter 'y' for yes or 'n' for no" 2
    fi
}

validate_project_directory() {
    local project_dir=$1
    
    if [[ ! -d "$project_dir" ]]; then
        fail "❌ Project directory creation failed: $project_dir" 5
    fi
    
    if [[ ! -w "$project_dir" ]]; then
        fail "❌ Project directory is not writable: $project_dir" 5
    fi
    
    info "✅ Project directory is valid and writable"
}