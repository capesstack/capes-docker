#!/usr/bin/env bash

################################
########## Globals #############
################################

set -o nounset  # Fail if we try to use an undeclared variable
set -o errexit  # Fail if an error is encountered

################################
########### Options ############
################################

USE_FIREWALLD=true # Controls whether you use firewalld or iptables
PORTAINER=true
THEHIVE=true
ROCKETCHAT=true
MUMBLE=true
ETHERPAD=true
CYBERCHEF=true
GITEA=true

################################
########## Versions ############
################################

MYSQL_VER=5.7
HIVE_ELASTICSEARCH_VER=5.6.13
ELASTICSEARCH_VER=7.0.1
MONGODB_VER=4.0.9
PORTAINER_VER=1.20.2
NGINX_VER=mainline
CYBERCHEF_VER=latest
GITEA_VER=1.8.1
ETHERPAD_VER=latest
THEHIVE_VER=3.3.0
ROCKETCHAT_VER=1.0.3
MUMBLE_VER=v0.3

################################
########### Ports ##############
################################

NGINX_PORT=80
ROCKETCHAT_INTERNAL_PORT=3000
ROCKETCHAT_EXTERNAL_PORT=4000
GITEA_PORT=3000
ETHERPAD_EXTERNAL_PORT=5000
ETHERPAD_INTERNAL_PORT=9001
KIBANA_PORT=5601
MUMBLE_PORT=64738
CYBERCHEF_EXTERNAL_PORT=8000
CYBERCHEF_INTERNAL_PORT=8080
THEHIVE_PORT=9000
PORTAINER_INTERNAL_PORT=9000
PORTAINER_EXTERNAL_PORT=2000
ELASTICSEARCH_PORT=9200
ELASTICSEARCH_MANAGEMENT_PORT=9300

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
IP="$(hostname -I 2> /dev/null | sed -e 's/[[:space:]]*$//')"

# Make sure critical fields are populated before continuing
if [ -z "$IP" ]
then
  read -p "Could not get IP address automatically. What is your IP address? " IP
else
  echo "Detected IP address as $IP"
fi

if [ -z "$HOSTNAME" ]
then
  read -p "There was a problem fetching your hostname. What is your hostname? " HOSTNAME
else
  echo "Detected IP address as $HOSTNAME"
fi

# Update your Host file
echo "$IP $HOSTNAME" | tee -a /etc/hosts

# Update the landing page index file
sed -i "s/host-ip/$IP/" landing_page/index.html

################################
########### Docker #############
################################
# Install Docker if needed
if yum list installed "docker" >/dev/null 2>&1; then echo "Docker already installed. Moving on."; else yum install -y docker; fi

# Create non-Root users to manage Docker
# You'll still need to run docker [command] until you log out and back in OR run "newgrp - docker"
# The "newgrp - docker" command starts a subshell that prevents this autobuild script from completing, so we'll just keep using until a reboot.
set +e
groupadd docker
set -e
usermod -aG docker "$USER"

# Set Docker to start on boot
systemctl enable docker.service

# Start the Docker services
systemctl start docker.service

set +e
# Create the CAPES network and data volume
docker network create capes
docker volume create portainer_data
set -e

# Update Elasticsearch's folder permissions
mkdir -p /var/lib/docker/volumes/elasticsearch/thehive/_data
mkdir -p /var/lib/docker/volumes/elasticsearch{-1,-2,-3}/capes/_data
chown -R 1000:1000 /var/lib/docker/volumes/elasticsearch{-1,-2,-3}
chown -R 1000:1000 /var/lib/docker/volumes/elasticsearch

# Update permissionso on the Heartbeat and Metricbeat yml file
chown root: heartbeat.yml
chmod 0644 heartbeat.yml
chown root: metricbeat.yml
chmod 0644 metricbeat.yml

# Adjust VM kernel setting for Elasticsearch
sysctl -w vm.max_map_count=262144
bash -c 'cat >> /etc/sysctl.conf <<EOF
vm.max_map_count=262144
EOF'

## CAPES Databases ##

if ${ETHERPAD} ; then

  # Etherpad MYSQL Container
  
  
  docker run -d \
  --network capes \
  --restart unless-stopped \
  --name capes-etherpad-mysql \
  -v /var/lib/docker/volumes/mysql/etherpad/_data:/var/lib/mysql:z \
  -e "MYSQL_DATABASE=etherpad" \
  -e "MYSQL_USER=etherpad" \
  -e MYSQL_PASSWORD=$etherpad_mysql_passphrase \
  -e "MYSQL_RANDOM_ROOT_PASSWORD=yes" mysql:${MYSQL_VER}

fi

if ${GITEA} ; then

  # Gitea MYSQL Container

  
  docker run -d \
  --network capes \
  --restart unless-stopped \
  --name capes-gitea-mysql \
  -v /var/lib/docker/volumes/mysql/gitea/_data:/var/lib/mysql:z \
  -e "MYSQL_DATABASE=gitea" \
  -e "MYSQL_USER=gitea" \
  -e MYSQL_PASSWORD=$gitea_mysql_passphrase \
  -e "MYSQL_RANDOM_ROOT_PASSWORD=yes" mysql:${MYSQL_VER}

fi

if ${THEHIVE} ; then

  # TheHive & Cortex Elasticsearch Container

  
  docker run -d \
  --network capes \
  --restart unless-stopped \
  --name capes-thehive-elasticsearch \
  -v /var/lib/docker/volumes/elasticsearch/thehive/_data:/usr/share/elasticsearch/data:z \
  -e "http.host=0.0.0.0" \
  -e "transport.host=0.0.0.0" \
  -e "xpack.security.enabled=false" \
  -e "cluster.name=hive" \
  -e "script.inline=true" \
  -e "thread_pool.index.queue_size=100000" \
  -e "thread_pool.search.queue_size=100000" \
  -e "thread_pool.bulk.queue_size=100000" \
  docker.elastic.co/elasticsearch/elasticsearch:${HIVE_ELASTICSEARCH_VER}

fi

if ${ROCKETCHAT} ; then

  # Rocketchat MongoDB Container & Configuration

  
  docker run -d \
  --network capes \
  --restart unless-stopped \
  --name capes-rocketchat-mongo \
  -v /var/lib/docker/volumes/rocketchat/_data:/data/db:z \
  -v /var/lib/docker/volumes/rocketchat/dump/_data:/dump:z \
  mongo:${MONGODB_VER} mongod \
  --smallfiles \
  --oplogSize 128 \
  --replSet rs1 \
  --storageEngine=mmapv1

  sleep 5

  docker exec -d capes-rocketchat-mongo bash -c \
  'echo -e "replication:\n  replSetName: \"rs01\"" | tee -a /etc/mongod.conf && mongo --eval "printjson(rs.initiate())"'

fi

## CAPES Services ##

if ${PORTAINER} ; then

  # Portainer Service

  
  docker run --privileged -d \
  --network capes \
  --restart unless-stopped \
  --name capes-portainer \
  -v /var/lib/docker/volumes/portainer/_data:/data:z \
  -v /var/run/docker.sock:/var/run/docker.sock \
  -p ${PORTAINER_EXTERNAL_PORT}:${PORTAINER_INTERNAL_PORT} \
  portainer/portainer:${PORTAINER_VER}

fi

# Nginx Service


docker run -d nginx \
--network capes \
--restart unless-stopped \
--name capes-landing-page \
-v $(pwd)/landing_page:/usr/share/nginx/html:ro \
-p ${NGINX_PORT}:${NGINX_PORT} nginx:${NGINX_VER}

chown -R 1000:1000 ./landing_page
find ./landing_page -type d -exec chmod 0755 {}
find ./landing_page -type f -exec chmod 0644 {}

if ${CYBERCHEF} ; then

  # Cyberchef Service

docker run -d --network capes --restart unless-stopped --name capes-draw.io -p 8001:8443 fjudith/draw.io
# Draw.io Service
  docker run -d \
  --network capes \
  --restart unless-stopped \
  --name capes-cyberchef \
  -p ${CYBERCHEF_EXTERNAL_PORT}:${CYBERCHEF_INTERNAL_PORT} \
  remnux/cyberchef:${CYBERCHEF_VER}

fi

if ${GITEA} ; then

  # Gitea Service

  
  docker run -d \
  --network capes \
  --restart unless-stopped \
  --name capes-gitea \
  -v /var/lib/docker/volumes/gitea/_data:/data:z \
  -e "VIRTUAL_PORT=${GITEA_PORT}" \
  -e "VIRTUAL_HOST=capes-gitea" \
  -p 2222:22 \
  -p ${GITEA_PORT}:${GITEA_PORT} \
  gitea/gitea:${GITEA_VER}

fi

if ${ETHERPAD} ; then

  # Etherpad Service

  
  docker run -d \
  --network capes \
  --restart unless-stopped \
  --name capes-etherpad \
  -e "ETHERPAD_TITLE=CAPES" \
  -e "ETHERPAD_PORT=9001" \
  -e ETHERPAD_ADMIN_PASSWORD=$etherpad_admin_passphrase \
  -e "ETHERPAD_ADMIN_USER=admin" \
  -e "ETHERPAD_DB_TYPE=mysql" \
  -e "ETHERPAD_DB_HOST=capes-etherpad-mysql" \
  -e "ETHERPAD_DB_USER=etherpad" \
  -e ETHERPAD_DB_PASSWORD=$etherpad_mysql_passphrase \
  -e "ETHERPAD_DB_NAME=etherpad" \
  -p ${ETHERPAD_EXTERNAL_PORT}:${ETHERPAD_INTERNAL_PORT} \
  tvelocity/etherpad-lite:${ETHERPAD_VER}

fi

if ${THEHIVE} ; then

  # TheHive Service

  
  docker run -d \
  --network capes \
  --restart unless-stopped \
  --name capes-thehive \
  -p ${THEHIVE_PORT}:${THEHIVE_PORT} \
  thehiveproject/thehive:${THEHIVE_VER} \
  --es-hostname capes-thehive-elasticsearch

fi

if ${ROCKETCHAT} ; then

  # Rocketchat Service

  
  docker run -d \
  --network capes \
  --restart unless-stopped \
  --name capes-rocketchat \
  --link capes-rocketchat-mongo \
  -e "MONGO_URL=mongodb://capes-rocketchat-mongo:27017/rocketchat" \
  -e MONGO_OPLOG_URL=mongodb://capes-rocketchat-mongo:27017/local?replSet=rs01 \
  -e ROOT_URL=http://$IP:${ROCKETCHAT_EXTERNAL_PORT} \
  -p ${ROCKETCHAT_EXTERNAL_PORT}:${ROCKETCHAT_INTERNAL_PORT} \
  rocketchat/rocket.chat:${ROCKETCHAT_VER}

fi

if ${MUMBLE} ; then

  # Mumble Service

  
  docker run -d --network capes \
  --restart unless-stopped \
  --name capes-mumble \
  -p ${MUMBLE_PORT}:${MUMBLE_PORT} \
  -p ${MUMBLE_PORT}:${MUMBLE_PORT}/udp \
  -v /var/lib/docker/volumes/mumble-data/_data:/data:z \
  -e SUPW=$mumble_passphrase \
  extra/mumble:${MUMBLE_VER}

fi

## CAPES Monitoring ##

# CAPES Elasticsearch Nodes


docker run -d --network capes \
--restart unless-stopped \
--name capes-elasticsearch-1 \
-v /var/lib/docker/volumes/elasticsearch-1/capes/_data:/usr/share/elasticsearch/data:z \
--ulimit memlock=-1:-1 \
-p ${ELASTICSEARCH_PORT}:${ELASTICSEARCH_PORT} \
-p ${ELASTICSEARCH_MANAGEMENT_PORT}:${ELASTICSEARCH_MANAGEMENT_PORT} \
-e "cluster.name=capes" \
-e "node.name=capes-elasticsearch-1" \
-e "cluster.initial_master_nodes=capes-elasticsearch-1" \
-e "bootstrap.memory_lock=true" \
-e "ES_JAVA_OPTS=-Xms512m -Xmx512m" \
docker.elastic.co/elasticsearch/elasticsearch:${ELASTICSEARCH_VER}

docker run -d --network capes --restart unless-stopped --name capes-elasticsearch-2 \
-v /var/lib/docker/volumes/elasticsearch-2/capes/_data:/usr/share/elasticsearch/data:z \
--ulimit memlock=-1:-1 \
-e "cluster.name=capes" \
-e "node.name=capes-elasticsearch-2" \
-e "cluster.initial_master_nodes=capes-elasticsearch-1" \
-e "bootstrap.memory_lock=true" -e "ES_JAVA_OPTS=-Xms512m -Xmx512m" \
-e "discovery.seed_hosts=capes-elasticsearch-1,capes-elasticsearch-3" \
docker.elastic.co/elasticsearch/elasticsearch:${ELASTICSEARCH_VER}

docker run -d \
--network capes \
--restart unless-stopped \
--name capes-elasticsearch-3 \
-v /var/lib/docker/volumes/elasticsearch-3/capes/_data:/usr/share/elasticsearch/data:z \
--ulimit memlock=-1:-1 \
-e "cluster.name=capes" \
-e "node.name=capes-elasticsearch-3" \
-e "cluster.initial_master_nodes=capes-elasticsearch-1" \
-e "bootstrap.memory_lock=true" -e "ES_JAVA_OPTS=-Xms512m -Xmx512m" \
-e "discovery.seed_hosts=capes-elasticsearch-1,capes-elasticsearch-2" \
docker.elastic.co/elasticsearch/elasticsearch:${ELASTICSEARCH_VER}

# CAPES Kibana


docker run -d \
--network capes \
--restart unless-stopped \
--name capes-kibana \
--network capes \
-p ${KIBANA_PORT}:${KIBANA_PORT} \
--link capes-elasticsearch-1:elasticsearch docker.elastic.co/kibana/kibana:${ELASTICSEARCH_VER}

# CAPES Heartbeat


docker run -d \
--network capes \
--restart unless-stopped \
--name capes-heartbeat \
--network capes \
--user=heartbeat \
-v $(pwd)/heartbeat.yml:/usr/share/heartbeat/heartbeat.yml:z docker.elastic.co/beats/heartbeat:${ELASTICSEARCH_VER} \
-e -E output.elasticsearch.hosts=["capes-elasticsearch-1:${ELASTICSEARCH_PORT}"]

# CAPES Metricbeat


docker run --privileged -d \
--network capes \
--restart unless-stopped \
--name capes-metricbeat \
--network capes \
--user=root \
-v $(pwd)/metricbeat.yml:/usr/share/metricbeat/metricbeat.yml:z \
-v /var/run/docker.sock:/var/run/docker.sock:z \
-v /sys/fs/cgroup:/hostfs/sys/fs/cgroup:z \
-v /proc:/hostfs/proc:z \
-v /:/hostfs:z docker.elastic.co/beats/metricbeat:${ELASTICSEARCH_VER} \
-e -E output.elasticsearch.hosts=["capes-elasticsearch-1:${ELASTICSEARCH_PORT}"]

# Wait for Elasticsearch to become available
echo "Elasticsearch takes a bit to negotiate it's cluster settings and come up. Give it a minute."
while true
do
  set +e
  STATUS=$(curl -sL -o /dev/null -w '%{http_code}' http://127.0.0.1:${ELASTICSEARCH_PORT})
  set -e

  if [ ${STATUS} -eq 200 ]; then
    echo "Elasticsearch is up. Proceeding"
    break
  else
    echo "Elasticsearch still loading. Trying again in 10 seconds"
  fi
  sleep 10
done

# Adjust the Elasticsearch bucket size
curl -X PUT "localhost:${ELASTICSEARCH_PORT}/_cluster/settings" -H 'Content-Type: application/json' -d'
{
    "persistent" : {
        "search.max_buckets" : "100000000"
    }
}
'

################################
### Firewall Considerations ####
################################
# Make firewall considerations
# Port 80 - Nginx (landing page)
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
firewall-cmd --add-port=80/tcp --add-port=3000/tcp --add-port=4000/tcp --add-port=5000/tcp --add-port=5601/tcp --add-port=64738/tcp --add-port=64738/udp --add-port=8000/tcp --add-port=9000/tcp --add-port=9001/tcp --permanent
firewall-cmd --reload

# TODO: Need to make it so firewall rules selectively enable.

if ${USE_FIREWALLD} ; then

  firewall-cmd \
  --add-port=${NGINX_PORT}/tcp \
  --add-port=${GITEA_PORT}/tcp \
  --add-port=${ROCKETCHAT_EXTERNAL_PORT}/tcp \
  --add-port=${ETHERPAD_EXTERNAL_PORT}/tcp \
  --add-port=${KIBANA_PORT}/tcp \
  --add-port=${CYBERCHEF_EXTERNAL_PORT}/tcp \
  --add-port=${MUMBLE_PORT}/tcp \
  --add-port=${THEHIVE_PORT}/tcp \
  --permanent
  firewall-cmd --reload

else

  echo iptables -I INPUT -p tcp -m tcp --dport ${NGINX_PORT} -j ACCEPT >> /etc/systemd/scripts/iptables
  echo iptables -I INPUT -p tcp -m tcp --dport ${GITEA_PORT} -j ACCEPT >> /etc/systemd/scripts/iptables
  echo iptables -I INPUT -p tcp -m tcp --dport ${ROCKETCHAT_EXTERNAL_PORT} -j ACCEPT >> /etc/systemd/scripts/iptables
  echo iptables -I INPUT -p tcp -m tcp --dport ${ETHERPAD_EXTERNAL_PORT} -j ACCEPT >> /etc/systemd/scripts/iptables
  echo iptables -I INPUT -p tcp -m tcp --dport ${KIBANA_PORT} -j ACCEPT >> /etc/systemd/scripts/iptables
  echo iptables -I INPUT -p tcp -m tcp --dport ${CYBERCHEF_EXTERNAL_PORT} -j ACCEPT >> /etc/systemd/scripts/iptables
  echo iptables -I INPUT -p tcp -m tcp --dport ${MUMBLE_PORT} -j ACCEPT >> /etc/systemd/scripts/iptables
  echo iptables -I INPUT -p tcp -m tcp --dport ${THEHIVE_PORT} -j ACCEPT >> /etc/systemd/scripts/iptables
  iptables -I INPUT -p tcp -m tcp --dport ${NGINX_PORT} -j ACCEPT
  iptables -I INPUT -p tcp -m tcp --dport ${GITEA_PORT} -j ACCEPT
  iptables -I INPUT -p tcp -m tcp --dport ${ROCKETCHAT_EXTERNAL_PORT} -j ACCEPT
  iptables -I INPUT -p tcp -m tcp --dport ${ETHERPAD_EXTERNAL_PORT} -j ACCEPT
  iptables -I INPUT -p tcp -m tcp --dport ${KIBANA_PORT} -j ACCEPT
  iptables -I INPUT -p tcp -m tcp --dport ${CYBERCHEF_EXTERNAL_PORT} -j ACCEPT
  iptables -I INPUT -p tcp -m tcp --dport ${MUMBLE_PORT} -j ACCEPT
  iptables -I INPUT -p tcp -m tcp --dport ${THEHIVE_PORT} -j ACCEPT

fi

################################
######### Success Page #########
################################
clear
echo "Please see the "Build, Operate, Maintain" documentation for the post-installation steps."
echo "The CAPES landing page has been successfully deployed. Browse to http://${HOSTNAME} (or http://${IP} if you don't have DNS set up) to begin using the services."
