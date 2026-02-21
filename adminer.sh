# ================ Install Adminer ===================
SITE="db.pishtaweb.ir"
WEBROOT="/home/cloudpanel/htdocs/$SITE"

cd $WEBROOT || exit

wget https://www.adminer.org/latest.php -O index.php
chown -R cloudpanel:cloudpanel $WEBROOT
chmod 640 index.php

read -p "Username: " USERNAME
read -s -p "Password: " PASSWORD
echo
HASH=$(openssl passwd -apr1 $PASSWORD)

echo "$USERNAME:$HASH" > $WEBROOT/.htpasswd

cat > $WEBROOT/.htaccess <<EOF
AuthType Basic
AuthName "Database Login"
AuthUserFile $WEBROOT/.htpasswd
Require valid-user
EOF

echo "Adminer ready: https://$SITE"
