#!/bin/bash

################################
##### Credential Creation ######
################################

# Create passphrases and set them as variables
etherpad_user_passphrase=`date +%s | sha256sum | base64 | head -c 32`
sleep 1
etherpad_mysql_passphrase=`date +%s | sha256sum | base64 | head -c 32`
sleep 1
etherpad_admin_passphrase=`date +%s | sha256sum | base64 | head -c 32`
sleep 1
gitea_mysql_passphrase=`date +%s | sha256sum | base64 | head -c 32`
sleep 1
mumble_passphrase=`date +%s | sha256sum | base64 | head -c 32`

# Write the passphrases to a file for reference. You should store this securely in accordance with your local security policy.
for i in {etherpad_user_passphrase,etherpad_mysql_passphrase,etherpad_admin_passphrase,gitea_mysql_passphrase,mumble_passphrase}; do echo "$i = ${!i}"; done > ~/capes_credentials.txt

# Set your IP address as a variable. This is for instructions below.
IP="$(hostname -I | sed -e 's/[[:space:]]*$//')"

# Update your Host file
echo "$IP $HOSTNAME" | sudo tee -a /etc/hosts

################################
########### Mumble #############
################################

# Prepare the environment
sudo yum -y install bzip2
sudo groupadd -r murmur
sudo useradd -r -g murmur -m -d /var/lib/murmur -s /sbin/nologin murmur
sudo mkdir -p /var/log/murmur
sudo chown murmur:murmur /var/log/murmur
sudo chmod 0770 /var/log/murmur

# Download binaries
curl -OL https://github.com/mumble-voip/mumble/releases/download/1.2.19/murmur-static_x86-1.2.19.tar.bz2
tar vxjf murmur-static_x86-1.2.19.tar.bz2
sudo mkdir -p /opt/murmur
sudo cp -r murmur-static_x86-1.2.19/* /opt/murmur
sudo cp murmur-static_x86-1.2.19/murmur.ini /etc/murmur.ini
rm -rf murmur-static_x86-1.2.19.tar.bz2 murmur-static_x86-1.2.19

# Configure /etc/murmur.ini
sudo sed -i 's/database=/database=\/var\/lib\/murmur\/murmur\.sqlite/' /etc/murmur.ini
sudo sed -i 's/\#logfile=murmur\.log/logfile=\/var\/log\/murmur\/murmur\.log/' /etc/murmur.ini
sudo sed -i 's/\#pidfile=/pidfile=\/var\/run\/murmur\/murmur\.pid/' /etc/murmur.ini
sudo sed -i 's/\#registerName=Mumble\ Server/registerName=CAPES\ -\ Mumble\ Server/' /etc/murmur.ini
sudo sed -i 's/port=64738/port=7000/' /etc/murmur.ini

# Configure the firewall
sudo firewall-cmd --add-port=7000/tcp --add-port=7000/udp --permanent
sudo firewall-cmd --reload

# Rotate logs
sudo bash -c 'cat > /etc/logrotate.d/murmur <<EOF
/var/log/murmur/*log {
    su murmur murmur
    dateext
    rotate 4
    missingok
    notifempty
    sharedscripts
    delaycompress
    postrotate
        /bin/systemctl reload murmur.service > /dev/null 2>/dev/null || true
    endscript
}
EOF'

# Creating the systemd service
sudo bash -c 'cat > /etc/systemd/system/murmur.service <<EOF
[Unit]
Description=Mumble Server (Murmur)
Requires=network-online.target
After=network-online.target mariadb.service time-sync.target

[Service]
User=murmur
Type=forking
ExecStart=/opt/murmur/murmur.x86 -ini /etc/murmur.ini
PIDFile=/var/run/murmur/murmur.pid
ExecReload=/bin/kill -s HUP $MAINPID

[Install]
WantedBy=multi-user.target
EOF'

# Generate the pid directory for Murmur:
sudo bash -c 'cat > /etc/tmpfiles.d/murmur.conf <<EOF
d /var/run/murmur 775 murmur murmur
EOF'

# Prepare the service environment
sudo systemd-tmpfiles --create /etc/tmpfiles.d/murmur.conf
sudo systemctl daemon-reload

# Set Murmur to start on boot
sudo systemctl enable murmur.service

# Start the Murmur service
sudo systemctl start murmur.service

# Configure the SuperUser account
sudo /opt/murmur/murmur.x86 -ini /etc/murmur.ini -supw $mumblepassphrase

################################
########## Containers ##########
################################
sudo yum install -y docker
sudo curl -L "https://github.com/docker/compose/releases/download/1.23.2/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose

# Apply executable permissions to the Docker Compose binary
sudo chmod +x /usr/local/bin/docker-compose

# Create non-Root users to manage Docker
sudo groupadd docker
sudo usermod -aG docker $USER
newgrp $USER docker
cd capes-docker

# Set Docker to start on boot
sudo systemctl enable docker.service

# Start the Docker services
sudo systemctl start docker.service

# Adjust VM kernel setting for Elasticsearch
sudo sysctl -w vm.max_map_count=262144

# Update configuration files
sed -i "s/etherpad_mysql_passphrase/$etherpad_mysql_passphrase/" test-docker-compose.yml
sed -i "s/etherpad_admin_passphrase/$etherpad_admin_passphrase/" test-docker-compose.yml
sed -i "s/etherpad_user_passphrase/$etherpad_user_passphrase/" test-docker-compose.yml
sed -i "s/gitea_mysql_passphrase/$gitea_mysql_passphrase/" test-docker-compose.yml
sed -i "s/host-ip/$IP/" landing_page/index.html

# Update Elasticsearch's folder permissions
#mkdir -p volumes/elasticsearch
#chown -R 1000:1000 volumes/elasticsearch
mkdir -p /var/lib/docker/volumes/elasticsearch/_data
chown -R 1000:1000 /var/lib/docker/volumes/elasticsearch

# Run Docker Compose to create all of the other containers
docker-compose -f test-docker-compose.yml up -d

################################
### Firewall Considerations ####
################################
# Make firewall considerations
# Port 80 - Nginx (landing page)
# Port 3000 - Rocketchat
# Port 4000 - Gitea
# Port 5000 - Etherpad
# Port 5601 - Kibana
# Port 7000 - Mumble
# Port 9000 - TheHive
# Port 9001 - Cortex (TheHive Analyzer Plugin)
sudo firewall-cmd --add-port=80/tcp --add-port=3000/tcp --add-port=4000/tcp --add-port=5000/tcp --add-port=5601/tcp --add-port=7000/tcp --add-port=7000/udp --add-port=9000/tcp --add-port=9001/tcp --permanent
sudo firewall-cmd --reload

################################
######### Success Page #########
################################
clear
echo "Please see the "Build, Operate, Maintain" documentation for the post-installation steps."
echo "The CAPES landing page has been successfully deployed. Browse to http://$HOSTNAME (or http://$IP if you don't have DNS set up) to begin using the services."
