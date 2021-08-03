# Containerized CAPES

This is the repo for containerized CAPES. This will replace the non-containerized version.

## Requirements
* Clean CentOS system

To deploy
```
sudo yum install -y git
git clone https://github.com/capesstack/capes-docker.git
cd capes-docker
sudo sh deploy_capes.sh
```

After deployment, you can go to https://[CAPES-ip] to view the services.

Passwords are written to `~/capes_credentials.txt` in the event that they're needed.

**Note the `capes_credentials.txt` file is written to the home directory of user 1000. If that isn't you, you'll need to adjust the `deploy_capes.sh` script.**

Please see the documentation, especially the [Post Installation Documentation](https://github.com/capesstack/capes-docs#post-installation).

To do:
* Moar Beats (Metric, audit)
* Documentation (yay)
