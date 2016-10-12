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

while true 
do
  sleep 30
  curl --user $COL_ID -H "Content-Type: application/json" -X POST -d '{ "event": { "commonEventHeader": { "domain": "fault", "eventType": "Fault_MobileCallRecording_PilotNumberPoolExhaustion", "eventId": "ab305d54-85b4-a31b-7db2-fb6b9e546015", "sequence": "0", "priority": "High", "sourceId": "de305d54-75b4-431b-adb2-eb6b9e546014", "sourceName": "EricssonECE", "functionalRole": "SCF", "startEpochMicrosec": "1413378172000000", "lastEpochMicrosec": "1413378172000000", "reportingEntityId": "de305d54-75b4-431b-adb2-eb6b9e546014", "reportingEntityName": "EricssonECE" }, "faultFields": { "alarmCondition": "PilotNumberPoolExhaustion", "eventSourceType": "other(0)", "specificProblem": "Calls cannot complete because pilot numbers are unavailable", "eventSeverity": "CRITICAL", "vfStatus": "Active" } } }' http://$COL_IP:30000/eventListener/v1
done

