#!/usr/bin/env bash

echo "CloudPanel Adminer Installer"

read -p "Enter Domain (example: db.example.com): " SITE

# Auto detect CloudPanel webroot
WEBROOT=$(find /home -type d -path "*/htdocs/$SITE" 2>/dev/null | head -n 1)

if [ -z "$WEBROOT" ]; then
    echo "Domain not found inside CloudPanel structure."
    exit 1
fi

# If public folder exists use it
if [ -d "$WEBROOT/public" ]; then
    WEBROOT="$WEBROOT/public"
fi

echo "Detected Webroot: $WEBROOT"

cd "$WEBROOT" || exit 1

# Download Adminer
wget -q https://www.adminer.org/latest.php -O index.php

# Secure permissions
chown -R $(stat -c '%U:%G' "$WEBROOT") "$WEBROOT"
chmod 640 index.php

# Create login
read -p "Username: " USERNAME
read -s -p "Password: " PASSWORD
echo
HASH=$(openssl passwd -apr1 "$PASSWORD")
echo "$USERNAME:$HASH" > "$WEBROOT/.htpasswd"

# Enable Basic Auth
cat > "$WEBROOT/.htaccess" <<EOF
AuthType Basic
AuthName "Database Login"
AuthUserFile $WEBROOT/.htpasswd
Require valid-user
EOF

echo "--------------------------------------"
echo "Adminer Installed Successfully"
echo "Access: https://$SITE"
echo "--------------------------------------"
