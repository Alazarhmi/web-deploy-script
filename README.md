# 🚀 VPS Deployment Script

**Deploy your web projects to VPS servers in minutes!** This script automatically sets up nginx, clones your repository, configures SSL certificates, and makes your website live.

## 🎯 What This Script Does

- ✅ **One-command deployment** - Deploy any web project in 2-5 minutes
- ✅ **Works on any VPS** - EC2, DigitalOcean, Linode, Vultr, etc.
- ✅ **Handles everything** - nginx, SSL certificates, git cloning, file permissions
- ✅ **Smart error handling** - Clear error messages and troubleshooting tips
- ✅ **Safe backups** - Automatically backs up existing configurations
- ✅ **Supports private repos** - Works with GitHub, GitLab, Bitbucket private repositories

## 🚀 Quick Start

### 1. Download the Script
```bash
# Download to your VPS server
wget https://raw.githubusercontent.com/shahirislam/web-deploy-script/main/deploy.sh
chmod +x deploy.sh
```

### 2. Run the Script
```bash
sudo ./deploy.sh
```

### 3. Follow the Prompts
The script will ask you for:
- **Subdomain**: `myapp.example.com`
- **Repository**: Your GitHub/GitLab repository URL
- **Repository type**: Public or private
- **HTTPS**: Whether to enable SSL certificates

### 4. Your Website is Live! 🎉
In 2-5 minutes, your website will be accessible at `http://your-subdomain.com`

## 📋 Prerequisites

Before running the script, make sure you have:

- ✅ **VPS Server** - Any Linux VPS (Ubuntu/Debian recommended)
- ✅ **Domain/Subdomain** - Pointing to your server's IP address
- ✅ **Root Access** - Ability to run `sudo` commands
- ✅ **Internet Connection** - For downloading packages and cloning repos

### DNS Setup
Make sure your domain/subdomain points to your server:
```bash
# Check if DNS is working
nslookup your-subdomain.com
# Should return your server's IP address
```

## 📖 Step-by-Step Guide

### Example 1: Deploy a Public Repository
```bash
sudo ./deploy.sh

# Script prompts:
# Enter project subdomain: myapp.example.com
# Does the project repository exist remotely? (y/n): y
# Is the repository public or private? (public/private): public
# Enter the Git repository HTTPS URL: https://github.com/username/myapp.git
# Do you want to enable HTTPS? (y/n): y
# Enter email for Let's Encrypt: your@email.com
```

### Example 2: Deploy a Private Repository
```bash
sudo ./deploy.sh

# Script prompts:
# Enter project subdomain: myapp.example.com
# Does the project repository exist remotely? (y/n): y
# Is the repository public or private? (public/private): private
# Enter the Git repository HTTPS URL: https://github.com/username/private-repo.git
# Enter git username: your-github-username
# Enter Personal Access Token: ghp_xxxxxxxxxxxx
# Do you want to enable HTTPS? (y/n): y
```

### Example 3: Deploy Without Repository (Local Files)
```bash
sudo ./deploy.sh

# Script prompts:
# Enter project subdomain: myapp.example.com
# Does the project repository exist remotely? (y/n): n
# Do you want to enable HTTPS? (y/n): y
# (Then manually upload your files to /var/www/myapp.example.com)
```

## 🛠️ Troubleshooting

### Common Issues and Solutions

#### ❌ "HTTP check failed"
**Problem**: Website not accessible after deployment
**Solutions**:
1. Check DNS: `nslookup your-subdomain.com`
2. Check firewall: `sudo ufw status`
3. Check nginx: `sudo systemctl status nginx`
4. Check logs: `sudo tail -f /var/log/nginx/error.log`

#### ❌ "Cannot access private repository"
**Problem**: Git clone fails for private repos
**Solutions**:
1. Verify your Personal Access Token is correct
2. Check token permissions in GitHub/GitLab settings
3. Ensure the repository URL is correct
4. Try creating a new token with full repository access

#### ❌ "SSL certificate failed"
**Problem**: HTTPS setup fails
**Solutions**:
1. Verify DNS points to your server
2. Check if port 443 is open: `sudo ufw allow 443`
3. Try manually: `sudo certbot --nginx -d your-subdomain.com`
4. Check certbot logs: `sudo certbot certificates`

#### ❌ "Pre-flight checks failed"
**Problem**: System requirements not met
**Solutions**:
1. Run as root: `sudo ./deploy.sh`
2. Check internet: `ping google.com`
3. Free up disk space: `df -h`
4. Check available memory: `free -h`

## 🔧 Advanced Usage

### Custom Configuration
After deployment, you can customize your setup:

```bash
# Edit nginx configuration
sudo nano /var/www/your-subdomain.com/nginx.conf

# Add custom nginx rules
sudo nano /etc/nginx/sites-available/your-subdomain.com.conf

# Reload nginx after changes
sudo systemctl reload nginx
```

### Managing SSL Certificates
```bash
# Renew certificates
sudo certbot renew

# Check certificate status
sudo certbot certificates

# Add new domain to existing certificate
sudo certbot --nginx -d new-subdomain.com
```

### Updating Your Website
```bash
# Method 1: Push to git repository (recommended)
git add .
git commit -m "Update website"
git push origin main
sudo ./deploy.sh  # Re-run deployment

# Method 2: Direct file upload
sudo nano /var/www/your-subdomain.com/index.html
```

## 📁 File Locations

After deployment, your files will be located at:
- **Website files**: `/var/www/your-subdomain.com/`
- **Nginx config**: `/etc/nginx/sites-available/your-subdomain.com.conf`
- **Nginx logs**: `/var/log/nginx/your-subdomain.com_*.log`
- **SSL certificates**: `/etc/letsencrypt/live/your-subdomain.com/`
- **Backups**: `/var/backups/`

## 🆘 Getting Help

### Quick Commands
```bash
# Check nginx status
sudo systemctl status nginx

# Test nginx configuration
sudo nginx -t

# View nginx logs
sudo tail -f /var/log/nginx/error.log

# Check SSL certificates
sudo certbot certificates

# Restart nginx
sudo systemctl restart nginx
```

### Support
- Check the troubleshooting section above
- Review nginx logs for specific errors
- Verify DNS and firewall settings
- Test with a simple HTML file first

## 📚 Documentation

- **README.md**: This file - user guide and quick start
- **README-MODULAR.md**: Technical documentation for developers

## 🤝 Contributing

This script uses a modular architecture for easy maintenance and contribution. Each module handles a specific responsibility, making it easy to add new features or modify existing ones.

## 📄 License

[Add your license here]

---

**Made with ❤️ for easy VPS deployment**
