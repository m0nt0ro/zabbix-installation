#!/bin/bash
# A script to install Zabbix 5.0 server on Ubuntu 18.04 running HTTPS
# Name: Henry Hoang Tran
# Date: 08 Sept 2020
# Updated: 09 Sept 2020
# SSL cert is self-signed
# Notes: need to change the MySQL_PASS: root and Zabbix_PASS: zabbix user

if [ "$EUID" -ne 0 ]
    then 
        echo "Please run as root. Syntax: sudo ./script.sh"
        exit
fi

# Update & Upgrade
sudo apt update -y
sudo apt upgrade

# Install nmap
sudo apt-get install nmap

########### Install Apache2 #############

# Install Apache2
sudo apt install apache2

# Add two lines to apache2.conf
sudo echo "ServerName zabbix.dhtran6.local" >> /etc/apache2/apache2.conf
sudo echo "ServerAdmin admin@dhtran6.local" >> /etc/apache2/apache2.conf

# Install SSL on Apache2
sudo openssl req -x509 -nodes -days 365 -newkey rsa:2048 -keyout /etc/ssl/private/apache-selfsigned.key -out /etc/ssl/certs/apache-selfsigned.crt

# Creating an Apache Configuration Snippet with Strong Encryption Settings
# Using here doc
sudo cat > /etc/apache2/conf-available/ssl-params.conf <<- "EOF"
SSLCipherSuite EECDH+AESGCM:EDH+AESGCM:AES256+EECDH:AES256+EDH
SSLProtocol All -SSLv2 -SSLv3 -TLSv1 -TLSv1.1
SSLHonorCipherOrder On
# Disable preloading HSTS for now.  You can use the commented out header line that includes
# the "preload" directive if you understand the implications.
# Header always set Strict-Transport-Security "max-age=63072000; includeSubDomains; preload"
Header always set X-Frame-Options DENY
Header always set X-Content-Type-Options nosniff
# Requires Apache >= 2.4
SSLCompression off
SSLUseStapling on
SSLStaplingCache "shmcb:logs/stapling-cache(150000)"
# Requires Apache >= 2.4.11
SSLSessionTickets Off
EOF

# Backup SSL config file
sudo cp /etc/apache2/sites-available/default-ssl.conf /etc/apache2/sites-available/default-ssl.conf.bak
sudo sed -i 's/ssl-cert-snakeoil.pem/apache-selfsigned.crt/g' /etc/apache2/sites-available/default-ssl.conf
sudo sed -i 's/ssl-cert-snakeoil.key/apache-selfsigned.key/g' /etc/apache2/sites-available/default-ssl.conf
sudo sed -i 's/webmaster@localhost/admin@dhtran6.local/g' /etc/apache2/sites-available/default-ssl.conf
sudo echo 'ServerName 192.168.150.151' >> /etc/apache2/sites-available/default-ssl.conf

# Enable the change in Apache2
sudo a2enmod ssl
sudo a2enmod headers

# Enable SSL virtual host
sudo a2ensite default-ssl
sudo a2enconf ssl-params

# Check config test
syntax=$(sudo apache2ctl configtest 2>&1)

# Reload apache2 if the Syntax OK
if [[ $syntax == *"Syntax OK"* ]]; 
then
	echo "Restarting Apache2 ..."
	sudo systemctl restart apache2
else
	echo "Checking the syntax again!!!"
	exit
fi

# Add SSL redirect permanently
# Add permanent redirect to SSL
sudo sed -i '13s/^/Redirect permanent "\/" "https:\/\/192.168.150.151\/"/g' /etc/apache2/sites-available/000-default.conf
sudo systemctl restart apache2

################ Install PHP for Apache ########################
sudo apt-get -y install php php-pear php-cgi php-common libapache2-mod-php php-mbstring php-net-socket php-gd php-xml-util php-mysql php-gettext php-bcmath
sudo a2enconf php7.2-cgi
sudo systemctl reload apache2

############### Install MariaDB ####################
# Link: https://downloads.mariadb.org/mariadb/repositories/#distro=Ubuntu&distro_release=bionic--ubuntu_bionic&mirror=globotech&version=10.5
sudo apt-get install software-properties-common
sudo apt-key adv --fetch-keys 'https://mariadb.org/mariadb_release_signing_key.asc'
sudo add-apt-repository 'deb [arch=amd64,arm64,ppc64el] http://mariadb.mirror.globo.tech/repo/10.5/ubuntu bionic main'
sudo apt update
sudo apt -y install mariadb-server mariadb-client
sudo mysql_secure_installation
# Enter current password for root (enter for none): Enter
# Switch to unix_socket authentication [Y/n]: n
# Change the root password? [Y/n]: y
# New password: Type new root password
# Remove anonymous users? [Y/n]: y
# Disallow root login remotely? [Y/n]: y
# Remove test database and access to it? [Y/n]: y
# Reload privilege tables now? [Y/n]: y
sudo systemctl restart mysql

############## Install Zabbix Server ################
sudo wget https://repo.zabbix.com/zabbix/5.0/ubuntu/pool/main/z/zabbix-release/zabbix-release_5.0-1+bionic_all.deb
sudo dpkg -i zabbix-release_5.0-1+bionic_all.deb
sudo apt update
sudo apt -y install zabbix-server-mysql zabbix-frontend-php zabbix-apache-conf zabbix-agent

############# Configure Zabbix to connect to MariaDB ################
echo "Configure Zabbix to connect to MariaDB"
MySQL_PASS="Passw0rd123"
Zabbix_PASS="Passw0rd123"
sudo mysql -u root -p$MySQL_PASS -e "create database zabbix character set utf8 collate utf8_bin;create user zabbix@localhost identified by '$Zabbix_PASS';grant all privileges on zabbix.* to zabbix@localhost;"
sudo zcat /usr/share/doc/zabbix-server-mysql*/create.sql.gz | mysql -uzabbix -p$MySQL_PASS zabbix
sudo sed -i "125s/^/DBPassword=$Zabbix_PASS/g" /etc/zabbix/zabbix_server.conf
sudo sed -i '380s/30/300/g' /etc/php/7.2/apache2/php.ini
sudo sed -i '390s/60/300/g' /etc/php/7.2/apache2/php.ini
sudo sed -i '669s/8M/16M/g' /etc/php/7.2/apache2/php.ini

# Set timezone America/Toronto###
sudo sed -i '937s/^/date.timezone = "America\/Toronto"/g' /etc/php/7.2/apache2/php.ini
sudo timedatectl set-timezone America/Toronto
sudo sed -i 's/Europe\/Riga/America\/Toronto/g' /etc/zabbix/apache.conf
sudo sed -i '20,30s/#/ /g' /etc/zabbix/apache.conf

# Add firewall rule
sudo ufw enable
sudo ufw allow 'Apache Full'
sudo ufw allow openssh
sudo ufw allow proto tcp from any to any port 10050,10051

###### Start Zabbix Server and Agent process ############
sudo systemctl restart zabbix-server zabbix-agent apache2
sudo systemctl enable zabbix-server zabbix-agent apache2









