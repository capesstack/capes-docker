# Containerized CAPES

This is the repo for containerized CAPES. This will replace the non-containerized version.

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

Passwords are written to `~/capes_credentials.txt` in the event that they're needed.

To do:
* Documentation (yay)
* Add stack monitoring with the Elastic Stack
