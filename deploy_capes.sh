#!/bin/bash

################################
##### Credential Creation ######
################################

# Create passphrases and set them as variables
etherpad_user_passphrase=$(head -c 100 /dev/urandom | sha256sum | base64 | head -c 32)
etherpad_mysql_passphrase=$(head -c 100 /dev/urandom | sha256sum | base64 | head -c 32)
etherpad_admin_passphrase=$(head -c 100 /dev/urandom | sha256sum | base64 | head -c 32)
gitea_mysql_passphrase=$(head -c 100 /dev/urandom | sha256sum | base64 | head -c 32)
mumble_passphrase=$(head -c 100 /dev/urandom | sha256sum | base64 | head -c 32)

# Write the passphrases to a file for reference. You should store this securely in accordance with your local security policy.
# As much as it pains me to admit it, @dcode helped me with the USER_HOME variable to get the creds written to the unprivileged user's home directory
USER_HOME=$(getent passwd 1000 | cut -d':' -f6)
for i in {etherpad_user_passphrase,etherpad_mysql_passphrase,etherpad_admin_passphrase,gitea_mysql_passphrase,mumble_passphrase}; do echo "$i = ${!i}"; done > $USER_HOME/capes_credentials.txt

# Set your IP address as a variable. This is for instructions below.
IP="$(hostname -I | sed -e 's/[[:space:]]*$//')"

# Update your Host file
echo "${IP} ${HOSTNAME}" | tee -a /etc/hosts

# Update the landing page index file
sed -i "s/host-ip/${IP}/" nginx/landing_page/index.html

# Create SSL certificates
mkdir -p $(pwd)/nginx/ssl
openssl req -newkey rsa:2048 -nodes -keyout $(pwd)/nginx/ssl/capes.key -x509 -sha256 -days 365 -out $(pwd)/nginx/ssl/capes.crt -subj "/C=US/ST=CAPES/L=CAPES/O=CAPES/OU=CAPES/CN=CAPES"

################################
########### Docker #############
################################
# Install Docker if needed
if yum list installed "docker" >/dev/null 2>&1; then echo "Docker already installed. Moving on."; else yum install -y docker; fi

# Create non-Root users to manage Docker
# You'll still need to run sudo docker [command] until you log out and back in OR run "newgrp - docker"
# The "newgrp - docker" command starts a subshell that prevents this autobuild script from completing, so we'll just keep using until a reboot.
groupadd docker
usermod -aG docker "${USER}"

# Set Docker to start on boot
systemctl enable docker.service

# Start the Docker services
systemctl start docker.service

# Create the CAPES network and data volume
docker network create capes
docker volume create portainer_data

# Create & update Elasticsearch's folder permissions
mkdir -p /var/lib/docker/volumes/elasticsearch/thehive/_data
mkdir -p /var/lib/docker/volumes/elasticsearch{-1,-2,-3}/capes/_data
chown -R 1000:1000 /var/lib/docker/volumes/elasticsearch{-1,-2,-3}
chown -R 1000:1000 /var/lib/docker/volumes/elasticsearch

# Update permissionso on the Heartbeat and Metricbeat yml file
chown root: heartbeat.yml
chmod 0644 heartbeat.yml
chown root: metricbeat.yml
chmod 0644 metricbeat.yml

# Disable auditd so Auditbeat can grab that process
auditctl -e0
systemctl disable auditd

# Adjust VM kernel setting for Elasticsearch
sysctl -w vm.max_map_count=262144
bash -c 'cat >> /etc/sysctl.conf <<EOF
vm.max_map_count=262144
EOF'

## CAPES Databases ##

# Etherpad MYSQL Container
docker run -d --network capes --restart unless-stopped --name capes-etherpad-mysql -v /var/lib/docker/volumes/mysql/etherpad/_data:/var/lib/mysql:z -e "MYSQL_DATABASE=etherpad" -e "MYSQL_USER=etherpad" -e MYSQL_PASSWORD=${etherpad_mysql_passphrase} -e "MYSQL_RANDOM_ROOT_PASSWORD=yes" mysql:5.7

# Gitea MYSQL Container
docker run -d --network capes --restart unless-stopped --name capes-gitea-mysql -v /var/lib/docker/volumes/mysql/gitea/_data:/var/lib/mysql:z -e "MYSQL_DATABASE=gitea" -e "MYSQL_USER=gitea" -e MYSQL_PASSWORD=${gitea_mysql_passphrase} -e "MYSQL_RANDOM_ROOT_PASSWORD=yes" mysql:5.7

# TheHive & Cortex Elasticsearch Container
docker run -d --network capes --restart unless-stopped --name capes-thehive-elasticsearch -v /var/lib/docker/volumes/elasticsearch/thehive/_data:/usr/share/elasticsearch/data:z -e "http.host=0.0.0.0" -e "transport.host=0.0.0.0" -e "xpack.security.enabled=false" -e "cluster.name=hive" -e "script.allowed_types=inline" -e "thread_pool.index.queue_size=100000" -e "thread_pool.search.queue_size=100000" -e "thread_pool.bulk.queue_size=100000" --ulimit nofile=65536:65536 docker.elastic.co/elasticsearch/elasticsearch:6.8.0

# Rocketchat MongoDB Container & Configuration
docker run -d --network capes --restart unless-stopped --name capes-rocketchat-mongo -v /var/lib/docker/volumes/rocketchat/_data:/data/db:z -v /var/lib/docker/volumes/rocketchat/dump/_data:/dump:z mongo:4.0 mongod --smallfiles --oplogSize 128 --replSet rs1 --storageEngine=mmapv1
sleep 5
docker exec -d capes-rocketchat-mongo bash -c 'echo -e "replication:\n  replSetName: \"rs01\"" | tee -a /etc/mongod.conf && mongo --eval "printjson(rs.initiate())"'

## CAPES Services ##

# Portainer Service
docker run --privileged -d --network capes --restart unless-stopped --name capes-portainer -v /var/lib/docker/volumes/portainer/_data:/data:z -v /var/run/docker.sock:/var/run/docker.sock portainer/portainer:latest

# Nginx Service
docker run -d  --network capes --restart unless-stopped --name capes-landing-page -v $(pwd)/nginx/ssl/capes.crt:/etc/nginx/capes.crt:z -v $(pwd)/nginx/ssl/capes.key:/etc/nginx/capes.key:z -v $(pwd)/nginx/nginx.conf:/etc/nginx/nginx.conf:z -v $(pwd)/nginx/landing_page:/usr/share/nginx/html:z -p 443:443 nginx:latest

# Cyberchef Service
docker run -d --network capes --restart unless-stopped --name capes-cyberchef remnux/cyberchef:latest

# Gitea Service
docker run -d --network capes --restart unless-stopped --name capes-gitea -v /var/lib/docker/volumes/gitea/_data:/data:z -e "VIRTUAL_PORT=3000" -e "VIRTUAL_HOST=capes-gitea" -p 2222:22 -p 3000:3000 gitea/gitea:latest

# Etherpad Service
docker run -d --network capes --restart unless-stopped --name capes-etherpad -e "ETHERPAD_TITLE=CAPES" -e "ETHERPAD_PORT=9001" -e ETHERPAD_ADMIN_PASSWORD=${etherpad_admin_passphrase} -e "ETHERPAD_ADMIN_USER=admin" -e "ETHERPAD_DB_TYPE=mysql" -e "ETHERPAD_DB_HOST=capes-etherpad-mysql" -e "ETHERPAD_DB_USER=etherpad" -e ETHERPAD_DB_PASSWORD=${etherpad_mysql_passphrase} -e "ETHERPAD_DB_NAME=etherpad" tvelocity/etherpad-lite:latest

# TheHive Service
# Integrating Cortex with TheHive, read below
# https://github.com/TheHive-Project/CortexDocs/blob/master/admin/quick-start.md#step-7-optional-create-an-account-for-thehive-integration
# https://github.com/TheHive-Project/TheHiveDocs/blob/master/admin/configuration.md#6-cortex
docker run -d --network capes --restart unless-stopped --name capes-thehive -v $(pwd)/application.conf:/etc/thehive/application.conf:z thehiveproject/thehive:3.4.0 --es-hostname capes-thehive-elasticsearch

# Cortex Service
# Integrating Cortex with TheHive, read below
# https://github.com/TheHive-Project/CortexDocs/blob/master/admin/quick-start.md#step-7-optional-create-an-account-for-thehive-integration
# https://github.com/TheHive-Project/TheHiveDocs/blob/master/admin/configuration.md#6-cortex
docker run -d --network capes --restart unless-stopped --name capes-cortex thehiveproject/cortex:3.0.1 --es-hostname capes-thehive-elasticsearch

# TheHive Template Import Preparation
docker build -t capes/thehivetemplateimport .

# Draw.io Service
docker run -d --network capes --restart unless-stopped --name capes-draw.io fjudith/draw.io

# Rocketchat Service
docker run -d --network capes --restart unless-stopped --name capes-rocketchat --link capes-rocketchat-mongo -e "MONGO_URL=mongodb://capes-rocketchat-mongo:27017/rocketchat" -e MONGO_OPLOG_URL=mongodb://capes-rocketchat-mongo:27017/local?replSet=rs01 -e ROOT_URL=http://${IP}:4000 -p 4000:3000 rocketchat/rocket.chat:latest

# Mumble Service
docker run -d --network capes --restart unless-stopped --name capes-mumble -p 64738:64738 -p 64738:64738/udp -v /var/lib/docker/volumes/mumble-data/_data:/data:z -e SUPW=${mumble_passphrase} extra/mumble:latest

## CAPES Monitoring ##

# CAPES Elasticsearch Nodes
docker run -d --network capes --restart unless-stopped --name capes-elasticsearch-1 -v /var/lib/docker/volumes/elasticsearch-1/capes/_data:/usr/share/elasticsearch/data:z --ulimit memlock=-1:-1 -p 127.0.0.1:9200:9200 -e "cluster.name=capes" -e "node.name=capes-elasticsearch-1" -e "cluster.initial_master_nodes=capes-elasticsearch-1" -e "bootstrap.memory_lock=true" -e "ES_JAVA_OPTS=-Xms512m -Xmx512m" docker.elastic.co/elasticsearch/elasticsearch:7.8.0

docker run -d --network capes --restart unless-stopped --name capes-elasticsearch-2 -v /var/lib/docker/volumes/elasticsearch-2/capes/_data:/usr/share/elasticsearch/data:z --ulimit memlock=-1:-1 -e "cluster.name=capes" -e "node.name=capes-elasticsearch-2" -e "cluster.initial_master_nodes=capes-elasticsearch-1" -e "bootstrap.memory_lock=true" -e "ES_JAVA_OPTS=-Xms512m -Xmx512m" -e "discovery.seed_hosts=capes-elasticsearch-1,capes-elasticsearch-3" docker.elastic.co/elasticsearch/elasticsearch:7.8.0
docker run -d --network capes --restart unless-stopped --name capes-elasticsearch-3 -v /var/lib/docker/volumes/elasticsearch-3/capes/_data:/usr/share/elasticsearch/data:z --ulimit memlock=-1:-1 -e "cluster.name=capes" -e "node.name=capes-elasticsearch-3" -e "cluster.initial_master_nodes=capes-elasticsearch-1" -e "bootstrap.memory_lock=true" -e "ES_JAVA_OPTS=-Xms512m -Xmx512m" -e "discovery.seed_hosts=capes-elasticsearch-1,capes-elasticsearch-2" docker.elastic.co/elasticsearch/elasticsearch:7.8.0

# CAPES Kibana
docker run -d --network capes --restart unless-stopped --name capes-kibana -e SERVER_BASEPATH=/kibana --link capes-elasticsearch-1:elasticsearch docker.elastic.co/kibana/kibana:7.8.0

# CAPES Heartbeat
docker run -d --network capes --restart unless-stopped --name capes-heartbeat --user=heartbeat -v $(pwd)/heartbeat.yml:/usr/share/heartbeat/heartbeat.yml:z docker.elastic.co/beats/heartbeat:7.8.0 -e -E output.elasticsearch.hosts=["capes-elasticsearch-1:9200"]

# CAPES Metricbeat
docker run -d --network capes --restart unless-stopped --name capes-metricbeat --user=root -v $(pwd)/metricbeat.yml:/usr/share/metricbeat/metricbeat.yml:z -v /var/run/docker.sock:/var/run/docker.sock:z -v /sys/fs/cgroup:/hostfs/sys/fs/cgroup:z -v /proc:/hostfs/proc:z -v /:/hostfs:z --privileged docker.elastic.co/beats/metricbeat:7.8.0 -e -E output.elasticsearch.hosts=["capes-elasticsearch-1:9200"]

# CAPES Packetbeat
docker run -d --network host --restart unless-stopped --name capes-packetbeat -v $(pwd)/packetbeat.yml:/usr/share/packetbeat/packetbeat.yml:z --cap-add="NET_RAW" --cap-add="NET_ADMIN" docker.elastic.co/beats/packetbeat:7.8.0 --strict.perms=false -e -E output.elasticsearch.hosts=["127.0.0.1:9200"]

# CAPES Auditbeat
docker run -d --network host --restart unless-stopped --name capes-auditbeat --user=root -v $(pwd)/auditbeat.yml:/usr/share/auditbeat/auditbeat.yml:z --pid=host --privileged=true docker.elastic.co/beats/auditbeat:7.8.0 --strict.perms=false -e -E output.elasticsearch.hosts=["127.0.0.1:9200"]

# Wait for Elasticsearch to become available
echo "Elasticsearch takes a bit to negotiate it's cluster settings and come up. Give it a minute."
while true
do
  STATUS=$(curl -sL -o /dev/null -w '%{http_code}' http://127.0.0.1:9200)
  if [ ${STATUS} -eq 200 ]; then
    echo "Elasticsearch is up. Proceeding"
    break
  else
    echo "Elasticsearch still loading. Trying again in 10 seconds"
  fi
  sleep 10
done

# Adjust the Elasticsearch bucket size
curl -X PUT "localhost:9200/_cluster/settings" -H 'Content-Type: application/json' -d'
{
    "persistent" : {
        "search.max_buckets" : "100000000"
    }
}
'

################################
### Firewall Considerations ####
################################
# Docker manages this for you with iptables, but in the event you need to add them.
# Make firewall considerations
# Port 443 - Nginx (landing page)
# Port 2000 - Portainer
# Port 3000 - Rocketchat
# Port 4000 - Gitea
# Port 5000 - Etherpad
# Port 5601 - Kibana
# Port 64738 - Mumble
# Port 8000 - Cyberchef
# Port 8001 - Draw.io
# Port 9000 - TheHive
# Port 9001 - Cortex (TheHive Analyzer Plugin)
# firewall-cmd --add-port=443/tcp --add-port=2000/tcp --add-port=3000/tcp --add-port=4000/tcp --add-port=5000/tcp --add-port=5601/tcp --add-port=64738/tcp --add-port=64738/udp --add-port=8000/tcp --add-port=9000/tcp --add-port=9001/tcp --permanent
# firewall-cmd --reload

################################
######### Success Page #########
################################
clear
echo "Please see the "Build, Operate, Maintain" documentation for the post-installation steps."
echo "The CAPES landing page has been successfully deployed. Browse to https://${HOSTNAME} (or https://${IP} if you don't have DNS set up) to begin using the services."
