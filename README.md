# Containerized CAPES

This is the repo for containerized CAPES.

Beta version!

## Requirements
* Clean CentOS system

To deploy
```
sudo yum install -y git
git clone https://github.com/capesstack/capes-docker.git
cd capes-docker
sudo sh deploy_capes.sh
```

After deployment, you can go to http://[host-ip] to view the services.

To do:
* Documentation (yay)
* Add stack monitoring with the Elastic Stack
