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

# Update the landing page index file
sed -i "s/host-ip/$IP/" landing_page/index.html

################################
########### Docker #############
################################
sudo yum install -y docker

# Create non-Root users to manage Docker
# You'll still need to run sudo docker [command] until you log out and back in OR run "newgrp - docker"
# The "newgrp - docker" command starts a subshell that prevents this autobuild script from completing, so we'll just keep using sudo until a reboot.
sudo groupadd docker
sudo usermod -aG docker "$USER"

# Set Docker to start on boot
sudo systemctl enable docker.service

# Start the Docker services
sudo systemctl start docker.service

# Create the CAPES network and data volume
sudo docker network create capes
sudo docker volume create portainer_data

# Update Elasticsearch's folder permissions
sudo mkdir -p /var/lib/docker/volumes/elasticsearch/thehive/_data
sudo mkdir -p /var/lib/docker/volumes/elasticsearch{-1,-2,-3}/capes/_data
sudo chown -R 1000:1000 /var/lib/docker/volumes/elasticsearch{-1,-2,-3}
#sudo mkdir -p /var/lib/docker/volumes/elasticsearch/capes/_data
sudo chown -R 1000:1000 /var/lib/docker/volumes/elasticsearch

# Update permissionso on the Heartbeat and Metricbeat yml file
sudo chown root: heartbeat.yml
sudo chmod 0644 heartbeat.yml
sudo chown root: metricbeat.yml
sudo chmod 0644 metricbeat.yml

# Adjust VM kernel setting for Elasticsearch
sudo sysctl -w vm.max_map_count=262144

## CAPES Databases ##

# Etherpad MYSQL Container
sudo docker run -d --network capes --restart unless-stopped --name capes-etherpad-mysql -v /var/lib/docker/volumes/mysql/etherpad/_data:/var/lib/mysql:z -e "MYSQL_DATABASE=etherpad" -e "MYSQL_USER=etherpad" -e MYSQL_PASSWORD=$etherpad_mysql_passphrase -e "MYSQL_RANDOM_ROOT_PASSWORD=yes" mysql:5.7

# Gitea MYSQL Container
sudo docker run -d --network capes --restart unless-stopped --name capes-gitea-mysql -v /var/lib/docker/volumes/mysql/gitea/_data:/var/lib/mysql:z -e "MYSQL_DATABASE=gitea" -e "MYSQL_USER=gitea" -e MYSQL_PASSWORD=$gitea_mysql_passphrase -e "MYSQL_RANDOM_ROOT_PASSWORD=yes" mysql:5.7

# TheHive & Cortex Elasticsearch Container
sudo docker run -d --network capes --restart unless-stopped --name capes-thehive-elasticsearch -v /var/lib/docker/volumes/elasticsearch/thehive/_data:/usr/share/elasticsearch/data:z -e "http.host=0.0.0.0" -e "transport.host=0.0.0.0" -e "xpack.security.enabled=false" -e "cluster.name=hive" -e "script.inline=true" -e "thread_pool.index.queue_size=100000" -e "thread_pool.search.queue_size=100000" -e "thread_pool.bulk.queue_size=100000" docker.elastic.co/elasticsearch/elasticsearch:5.6.13

# Rocketchat MongoDB Container
sudo docker run -d --network capes --restart unless-stopped --name capes-rocketchat-mongo -v /var/lib/docker/volumes/rocketchat/_data:/data/db:z -v /var/lib/docker/volumes/rocketchat/dump/_data:/dump:z mongo:latest mongod --smallfiles

## CAPES Services ##

# Portainer Service
sudo docker run -d --network capes --restart unless-stopped --name capes-portainer -v /var/lib/docker/volumes/portainer/_data:/data:z -v /var/run/docker.sock:/var/run/docker.sock -p 2000:9000 portainer/portainer:latest

# Nginx Service
sudo docker run -d  --network capes --restart unless-stopped --name capes-landing-page -v $(pwd)/landing_page:/usr/share/nginx/html:z -p 80:80 nginx:latest

# Cyberchef Service
sudo docker run -d --network capes --restart unless-stopped --name capes-cyberchef -p 8000:8080 remnux/cyberchef:latest

# Gitea Service
sudo docker run -d --network capes --restart unless-stopped --name capes-gitea -v /var/lib/docker/volumes/gitea/_data:/data:z -e "VIRTUAL_PORT=3000" -e "VIRTUAL_HOST=capes-gitea" -p 2222:22 -p 4000:3000 gitea/gitea:latest

# Etherpad Service
sudo docker run -d --network capes --restart unless-stopped --name capes-etherpad -e "ETHERPAD_TITLE=CAPES" -e "ETHERPAD_PORT=9001" -e ETHERPAD_ADMIN_PASSWORD=$etherpad_admin_passphrase -e "ETHERPAD_ADMIN_USER=admin" -e "ETHERPAD_DB_TYPE=mysql" -e "ETHERPAD_DB_HOST=capes-etherpad-mysql" -e "ETHERPAD_DB_USER=etherpad" -e ETHERPAD_DB_PASSWORD=$etherpad_mysql_passphrase -e "ETHERPAD_DB_NAME=etherpad" -p 5000:9001 tvelocity/etherpad-lite:latest

# TheHive Service
sudo docker run -d --network capes --restart unless-stopped --name capes-thehive -e CORTEX_URL=capes-cortex -p 9000:9000 thehiveproject/thehive:latest --es-hostname capes-thehive-elasticsearch --cortex-hostname capes-cortex

# Cortex Service
# sudo docker run -d --network capes --restart unless-stopped --name capes-cortex -p 9001:9000 thehiveproject/cortex:latest --es-hostname capes-thehive-elasticsearch

# Rocketchat Service
sudo docker run -d --network capes --restart unless-stopped --name capes-rocketchat --link capes-rocketchat-mongo -e "MONGO_URL=mongodb://capes-rocketchat-mongo:27017/rocketchat" -e "ROOT_URL=http://localhost:3000" -p 3000:3000 rocketchat/rocket.chat:latest

# Mumble Service
sudo docker run -d --network capes --restart unless-stopped --name capes-mumble -p 64738:64738 -p 64738:64738/udp -v /var/lib/docker/volumes/mumble-data/_data:/data:z -e SUPW=$mumble_passphrase extra/mumble:latest

## CAPES Monitoring ##

# CAPES Elasticsearch
#sudo docker run -d --network capes --restart unless-stopped --name capes-elasticsearch -v /var/lib/docker/volumes/elasticsearch/capes/_data:/usr/share/elasticsearch/data:z -p 9200:9200 -p 9300:9300 -e "discovery.type=single-node" -e "cluster.name=capes" docker.elastic.co/elasticsearch/elasticsearch:7.0.0

sudo docker run -d --network capes --restart unless-stopped --name capes-elasticsearch-1 -v /var/lib/docker/volumes/elasticsearch-1/capes/_data:/usr/share/elasticsearch/data:z --ulimit memlock=-1:-1 -p 9200:9200 -p 9300:9300 -e "cluster.name=capes" -e "node.name=capes-elasticsearch-1" -e "cluster.initial_master_nodes=capes-elasticsearch-1" -e "bootstrap.memory_lock=true" -e "ES_JAVA_OPTS=-Xms512m -Xmx512m" docker.elastic.co/elasticsearch/elasticsearch:7.0.0

sudo docker run -d --network capes --restart unless-stopped --name capes-elasticsearch-2 -v /var/lib/docker/volumes/elasticsearch-2/capes/_data:/usr/share/elasticsearch/data:z --ulimit memlock=-1:-1 -e "cluster.name=capes" -e "node.name=capes-elasticsearch-2" -e "cluster.initial_master_nodes=capes-elasticsearch-1" -e "bootstrap.memory_lock=true" -e "ES_JAVA_OPTS=-Xms512m -Xmx512m" -e "discovery.seed_hosts=capes-elasticsearch-1,capes-elasticsearch-3" docker.elastic.co/elasticsearch/elasticsearch:7.0.0

sudo docker run -d --network capes --restart unless-stopped --name capes-elasticsearch-3 -v /var/lib/docker/volumes/elasticsearch-3/capes/_data:/usr/share/elasticsearch/data:z --ulimit memlock=-1:-1 -e "cluster.name=capes" -e "node.name=capes-elasticsearch-3" -e "cluster.initial_master_nodes=capes-elasticsearch-1" -e "bootstrap.memory_lock=true" -e "ES_JAVA_OPTS=-Xms512m -Xmx512m" -e "discovery.seed_hosts=capes-elasticsearch-1,capes-elasticsearch-2" docker.elastic.co/elasticsearch/elasticsearch:7.0.0

# CAPES Kibana
sudo docker run -d --network capes --restart unless-stopped --name capes-kibana --network capes -p 5601:5601 --link capes-elasticsearch-1:elasticsearch docker.elastic.co/kibana/kibana:7.0.0

# CAPES Heartbeat
sudo docker run -d --network capes --restart unless-stopped --name capes-heartbeat --network capes --user=heartbeat -v $(pwd)/heartbeat.yml:/usr/share/heartbeat/heartbeat.yml:z docker.elastic.co/beats/heartbeat:7.0.0 -e -E output.elasticsearch.hosts=["capes-elasticsearch-1:9200"]

# CAPES Metricbeat
sudo docker run -d --network capes --restart unless-stopped --name capes-metricbeat --network capes --user=root -v $(pwd)/metricbeat.yml:/usr/share/metricbeat/metricbeat.yml:z -v /var/run/docker.sock:/var/run/docker.sock:z -v /sys/fs/cgroup:/hostfs/sys/fs/cgroup:z -v /proc:/hostfs/proc:z -v /:/hostfs:z docker.elastic.co/beats/metricbeat:7.0.0 -e -E output.elasticsearch.hosts=["capes-elasticsearch-1:9200"]

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
