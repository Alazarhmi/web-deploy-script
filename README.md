# 🚀 Easy VPS Deployment Script

**Deploy your websites to any VPS server in just 3 simple steps!** 

This script makes it super easy to get your website online. It automatically sets up everything you need - no technical knowledge required!

---

## ✨ What This Does For You

- 🌐 **Makes your website live** - Your site will be accessible on the internet
- 🔒 **Adds security (HTTPS)** - Makes your site secure with free SSL certificates
- 📁 **Downloads your code** - Automatically gets your code from GitHub/GitLab
- 🛡️ **Keeps backups** - Saves your old files before making changes
- ⚡ **Works everywhere** - Compatible with DigitalOcean, AWS, Linode, and more

---

## 🎯 Perfect For

- **Beginners** who want to deploy their first website
- **Students** learning web development
- **Developers** who want to save time on deployment
- **Anyone** who finds server setup confusing

---

## 🚀 How to Use (Super Simple!)

### Step 1: Get Your VPS Ready
1. Buy a VPS from any provider (DigitalOcean, AWS, Linode, etc.)
2. Make sure your domain points to your VPS IP address
3. Connect to your VPS using SSH

### Step 2: Download and Run the Script
```bash
# Download the script
wget https://raw.githubusercontent.com/shahirislam/web-deploy-script/main/deploy.sh

# Make it executable
chmod +x deploy.sh

# Run it (this will ask you some questions)
sudo ./deploy.sh
```

### Step 3: Answer the Questions
The script will ask you:
- **What's your website address?** (like: mywebsite.com)
- **Do you have code on GitHub?** (yes/no)
- **Is your code public or private?** (public/private)
- **Do you want HTTPS security?** (yes/no)

### Step 4: Done! 🎉
Your website is now live! Visit your domain to see it working.

---

## 📋 What You Need Before Starting

### ✅ Required:
- **A VPS server** (any Linux server works)
- **A domain name** (like mywebsite.com)
- **Your domain pointing to your VPS** (ask your domain provider for help)

### ✅ Nice to Have:
- **Code on GitHub/GitLab** (or you can upload files manually)
- **Basic terminal knowledge** (just copy-paste commands)

---

## 🎬 Real Examples

### Example 1: Deploy a Website from GitHub
```bash
sudo ./deploy.sh

# The script asks:
# Enter project subdomain: myawesomeapp.com
# Does the project repository exist remotely? (y/n): y
# Is the repository public or private? (public/private): public
# Enter the Git repository HTTPS URL: https://github.com/yourusername/yourapp.git
# Do you want to enable HTTPS? (y/n): y
# Enter email for Let's Encrypt: your@email.com

# Result: Your website is live at https://myawesomeapp.com
```

### Example 2: Deploy a Private Repository
```bash
sudo ./deploy.sh

# The script asks:
# Enter project subdomain: mysecretapp.com
# Does the project repository exist remotely? (y/n): y
# Is the repository public or private? (public/private): private
# Enter the Git repository HTTPS URL: https://github.com/yourusername/privateapp.git
# Enter git username: your-github-username
# Enter Personal Access Token: ghp_xxxxxxxxxxxx
# Do you want to enable HTTPS? (y/n): y

# Result: Your private website is live at https://mysecretapp.com
```

### Example 3: Deploy Without GitHub (Manual Upload)
```bash
sudo ./deploy.sh

# The script asks:
# Enter project subdomain: mylocalapp.com
# Does the project repository exist remotely? (y/n): n
# Do you want to enable HTTPS? (y/n): y

# Result: Upload your files to /var/www/mylocalapp.com/ manually
```

---

## 🛠️ Common Problems and Easy Fixes

### ❌ "Website not working"
**What's wrong:** Your domain might not be pointing to your server
**How to fix:**
1. Check if your domain points to your server: `nslookup yourdomain.com`
2. Wait a few minutes for DNS to update
3. Make sure your VPS is running

### ❌ "Can't access private repository"
**What's wrong:** Your GitHub token might be wrong
**How to fix:**
1. Go to GitHub → Settings → Developer settings → Personal access tokens
2. Create a new token with full repository access
3. Use the new token when the script asks

### ❌ "HTTPS not working"
**What's wrong:** SSL certificate setup failed
**How to fix:**
1. Make sure your domain points to your server
2. Wait 5-10 minutes and try again
3. Check if port 443 is open on your server

### ❌ "Script won't run"
**What's wrong:** Missing permissions or internet
**How to fix:**
1. Make sure you're using `sudo ./deploy.sh`
2. Check your internet connection
3. Make sure you have enough disk space

---

## 🔧 After Your Website is Live

### Update Your Website
**Method 1: Using GitHub (Recommended)**
```bash
# Make changes to your code
git add .
git commit -m "Updated my website"
git push origin main

# Re-run the deployment script
sudo ./deploy.sh
```

**Method 2: Direct Upload**
```bash
# Edit files directly on your server
sudo nano /var/www/yourdomain.com/index.html
```

### Check Your Website Status
```bash
# See if your website is running
sudo systemctl status nginx

# Check your website logs
sudo tail -f /var/log/nginx/yourdomain.com_error.log

# Test your website
curl http://yourdomain.com
```

### Renew SSL Certificates (Automatic)
Your SSL certificates renew automatically, but you can check them:
```bash
sudo certbot certificates
```

---

## 📁 Where Your Files Are Stored

After deployment, you'll find your files here:
- **Your website files:** `/var/www/yourdomain.com/`
- **Website settings:** `/etc/nginx/sites-available/yourdomain.com.conf`
- **Website logs:** `/var/log/nginx/yourdomain.com_*.log`
- **SSL certificates:** `/etc/letsencrypt/live/yourdomain.com/`
- **Backups:** `/var/backups/`

---

## 🆘 Need Help?

### Quick Commands to Check Everything
```bash
# Check if your website is running
sudo systemctl status nginx

# Test your website configuration
sudo nginx -t

# See what's wrong (if anything)
sudo tail -f /var/log/nginx/error.log

# Restart your website
sudo systemctl restart nginx
```

### Still Having Issues?
1. **Check the troubleshooting section above**
2. **Look at the error messages** - they usually tell you what's wrong
3. **Make sure your domain points to your server**
4. **Try with a simple HTML file first**

---

## 🎓 Learning More

This script handles the technical stuff so you can focus on building your website. But if you want to learn more:

- **Nginx:** The web server that serves your website
- **SSL/HTTPS:** Makes your website secure
- **Git:** Version control for your code
- **VPS:** Virtual Private Server - your website's home

---

## 🤝 Contributing

Found a bug or want to add a feature? We'd love your help!

1. Fork this repository
2. Make your changes
3. Test them
4. Submit a pull request

---

## 📄 License

This project is open source and free to use.

---

## 👨‍💻 About the Developer

**Created by [Shahir Islam](https://shahirislam.me)**

This script was built to make web deployment simple and accessible for everyone. Whether you're just starting out or you're an experienced developer, this tool will save you time and frustration.

Visit [shahirislam.me](https://shahirislam.me) to see more projects and tutorials.

---

**Made with ❤️ for the developer community**

*Happy coding! 🚀*