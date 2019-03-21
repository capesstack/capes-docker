#!/bin/bash

################################
##### Credential Creation ######
################################

# Create passphrases and set them as variables
etherpad_user_passphrase=$(date +%s | sha256sum | base64 | head -c 32)
sleep 1
etherpad_mysql_passphrase=$(date +%s | sha256sum | base64 | head -c 32)
sleep 1
etherpad_admin_passphrase=$(date +%s | sha256sum | base64 | head -c 32)
sleep 1
gitea_mysql_passphrase=$(date +%s | sha256sum | base64 | head -c 32)
sleep 1
mumble_passphrase=$(date +%s | sha256sum | base64 | head -c 32)

# Write the passphrases to a file for reference. You should store this securely in accordance with your local security policy.
# As much as it pains me to admit it, @dcode helped me with the USER_HOME variable to get the creds written to the unprivileged user's home directory
USER_HOME=$(getent passwd 1000 | cut -d':' -f6)
for i in {etherpad_user_passphrase,etherpad_mysql_passphrase,etherpad_admin_passphrase,gitea_mysql_passphrase,mumble_passphrase}; do echo "$i = ${!i}"; done > $USER_HOME/capes_credentials.txt

# Set your IP address as a variable. This is for instructions below.
IP="$(hostname -I | sed -e 's/[[:space:]]*$//')"

# Update your Host file
echo "$IP $HOSTNAME" | sudo tee -a /etc/hosts

################################
########## Containers ##########
################################
sudo yum install -y docker
sudo curl -L "https://github.com/docker/compose/releases/download/1.23.2/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose

# Apply executable permissions to the Docker Compose binary
sudo chmod +x /usr/local/bin/docker-compose

# Create non-Root users to manage Docker
# You'll still need to run sudo docker [command] until you log out and back in OR run "newgrp - docker"
# The "newgrp - docker" command starts a subshell that prevents this autobuild script from completing
sudo groupadd docker
sudo usermod -aG docker "$USER"

# Set Docker to start on boot
sudo systemctl enable docker.service

# Start the Docker services
sudo systemctl start docker.service

# Adjust VM kernel setting for Elasticsearch
sudo sysctl -w vm.max_map_count=262144

# Update configuration files
sed -i "s/etherpad_mysql_passphrase/$etherpad_mysql_passphrase/" docker-compose.yml
sed -i "s/etherpad_admin_passphrase/$etherpad_admin_passphrase/" docker-compose.yml
sed -i "s/etherpad_user_passphrase/$etherpad_user_passphrase/" docker-compose.yml
sed -i "s/gitea_mysql_passphrase/$gitea_mysql_passphrase/" docker-compose.yml
sed -i "s/host-ip/$IP/" landing_page/index.html

# Update Elasticsearch's folder permissions
#mkdir -p volumes/elasticsearch
#chown -R 1000:1000 volumes/elasticsearch
sudo mkdir -p /var/lib/docker/volumes/elasticsearch/_data
sudo chown -R 1000:1000 /var/lib/docker/volumes/elasticsearch

# Build the docker volume for Mumble
sudo docker volume create --name mumble-data

# Run Docker Compose to create all of the other containers
sudo /usr/local/bin/docker-compose -f docker-compose.yml up -d

# Set the passphrase for the SuperUser account in Mumble
# sudo docker exec -it capes-mumble supw
# $mumble_passphrase

################################
### Firewall Considerations ####
################################
# Make firewall considerations
# Port 80 - Nginx (landing page)
# Port 3000 - Rocketchat
# Port 4000 - Gitea
# Port 5000 - Etherpad
# Port 5601 - Kibana
# Port 64738 - Mumble
# Port 8000 - Cyberchef
# Port 9000 - TheHive
# Port 9001 - Cortex (TheHive Analyzer Plugin)
sudo firewall-cmd --add-port=80/tcp --add-port=3000/tcp --add-port=4000/tcp --add-port=5000/tcp --add-port=5601/tcp --add-port=64738/tcp --add-port=64738/udp --add-port=8000/tcp --add-port=9000/tcp --add-port=9001/tcp --permanent
sudo firewall-cmd --reload

################################
######### Success Page #########
################################
clear
echo "Please see the "Build, Operate, Maintain" documentation for the post-installation steps."
echo "The CAPES landing page has been successfully deployed. Browse to http://$HOSTNAME (or http://$IP if you don't have DNS set up) to begin using the services."
