#!/bin/bash
# Copyright 2016 AT&T Intellectual Property, Inc
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
# http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#
# What this is: Startup script for a simple web server as part of the 
# vHello_VES test of the OPNFV VES project.
#
# Status: this is a work in progress, under test.
#
# How to use:
# $ bash start.sh IP ID
#   IP: IP address of the collector
#   ID: username:password to use in REST
#

setup_agent () {
  echo "$0: Install prerequisites"
  sudo apt-get install -y gcc
  # NOTE: force is required as some packages can't be authenticated...
  sudo apt-get install -y --force-yes libcurl4-openssl-dev
  sudo apt-get install -y make

  echo "$0: Clone agent library"
  cd /home/ubuntu
  git clone https://github.com/att/evel-library.git

  echo "$0: Build agent demo"
  sed -i -- '/api_secure,/{n;s/.*/                      "hello",/}' evel-library/code/evel_demo/evel_demo.c
  sed -i -- '/"hello",/{n;s/.*/                      "world",/}' evel-library/code/evel_demo/evel_demo.c

  echo "$0: Build agent demo"
  cd evel-library/bldjobs
  make
  export LD_LIBRARY_PATH=$LD_LIBRARY_PATH:/home/ubuntu/evel-library/libs/x86_64
  
  echo "$0: Start agent demo, repeat every minute"
  crontab -l > /tmp/cron
  echo "* * * * 1-5 /home/ubuntu/evel-library/output/x86_64/evel_demo --fqdn $COL_IP --port 30000 -v" >> /tmp/cron
  crontab /tmp/cron
  rm /tmp/cron
}

echo "$0: Setup website and dockerfile"
mkdir ~/www
mkdir ~/www/html

# ref: https://hub.docker.com/_/nginx/
cat > ~/www/Dockerfile <<EOM
FROM nginx
COPY html /usr/share/nginx/html
EOM

cat > ~/www/html/index.html <<EOM
<!DOCTYPE html>
<html>
<head>
<title>Hello World!</title>
<meta name="viewport" content="width=device-width, minimum-scale=1.0, initial-scale=1"/>
<style>
body { width: 100%; background-color: white; color: black; padding: 0px; margin: 0px; font-family: sans-serif; font-size:100%; }
</style>
</head>
<body>
Hello World!<br>
<a href="http://wiki.opnfv.org"><img src="https://www.opnfv.org/sites/all/themes/opnfv/logo.png"></a>
</body></html>
EOM

echo "$0: Install docker"
# Per https://docs.docker.com/engine/installation/linux/ubuntulinux/
# Per https://www.digitalocean.com/community/tutorials/how-to-install-and-use-docker-on-ubuntu-16-04
sudo apt-get install apt-transport-https ca-certificates
sudo apt-key adv --keyserver hkp://p80.pool.sks-keyservers.net:80 --recv-keys 58118E89F3A912897C070ADBF76221572C52609D
echo "deb https://apt.dockerproject.org/repo ubuntu-xenial main" | sudo tee /etc/apt/sources.list.d/docker.list
sudo apt-get update
sudo apt-get purge lxc-docker
sudo apt-get install -y linux-image-extra-$(uname -r) linux-image-extra-virtual
sudo apt-get install -y docker-engine

echo "$0: Get nginx container and start website in docker"
# Per https://hub.docker.com/_/nginx/
sudo docker pull nginx
cd ~/www
sudo docker build -t vhello .
sudo docker run --name vHello -d -p 80:80 vhello

echo "$0: setup VES event delivery for the nginx server"

# id=$(sudo ls /var/lib/docker/containers)
# sudo tail -f /var/lib/docker/containers/$id/$id-json.log 

export COL_IP=$1
export COL_ID=$2

setup_agent
