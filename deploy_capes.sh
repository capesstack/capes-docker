#!/bin/bash

# Install dependencies
sudo yum install -y docker
sudo curl -L "https://github.com/docker/compose/releases/download/1.23.2/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose

# Apply executable permissions to the Docker Compose binary
sudo chmod +x /usr/local/bin/docker-compose

## Set passphrases as variables
etherpad_user_passphrase=`date +%s | sha256sum | base64 | head -c 32`
sleep 1
etherpad_mysql_passphrase=`date +%s | sha256sum | base64 | head -c 32`
sleep 1
etherpad_admin_passphrase=`date +%s | sha256sum | base64 | head -c 32`
sleep 1
gitea_mysql_passphrase=`date +%s | sha256sum | base64 | head -c 32`

## Update configuration files
sed -i "s/etherpad_mysql_passphrase/$etherpad_mysql_passphrase/" test-docker-compose.yml
sed -i "s/etherpad_admin_passphrase/$etherpad_admin_passphrase/" test-docker-compose.yml
sed -i "s/etherpad_user_passphrase/$etherpad_user_passphrase/" test-docker-compose.yml
sed -i "s/gitea_mysql_passphrase/$gitea_mysql_passphrase/" test-docker-compose.yml

# Run Docker Compose to create all of the other containers
docker-compose -f test-docker-compose.yml up
