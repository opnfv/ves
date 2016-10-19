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
# Intended to be invoked from vHello_VES.sh
# $ bash start.sh type params
#   type: type of VNF component [webserver|lb|monitor|collectd]
#     webserver params: ID CollectorIP username password
#     lb params:        ID CollectorIP username password app1_ip app2_ip
#     collector params: ID CollectorIP username password
#     collector params: ID CollectorIP username password
#   ID: VM ID
#   CollectorIP: IP address of the collector
#   username: Username for Collector RESTful API authentication
#   password: Password for Collector RESTful API authentication
#   app1_ip app2_ip: address of the web servers

setup_collectd () {
  echo "$0: Install prerequisites"
  sudo apt-get update
  echo "$0: Install collectd plugin"
  cd ~
  git clone https://github.com/maryamtahhan/OpenStackBarcelonaDemo.git

  sudo apt-get install -y collectd
  sudo sed -i -- "s/FQDNLookup true/FQDNLookup false/" /etc/collectd/collectd.conf
  sudo sed -i -- "s/#LoadPlugin cpu/LoadPlugin cpu/" /etc/collectd/collectd.conf
  sudo sed -i -- "s/#LoadPlugin disk/LoadPlugin disk/" /etc/collectd/collectd.conf
  sudo sed -i -- "s/#LoadPlugin interface/LoadPlugin interface/" /etc/collectd/collectd.conf
  sudo sed -i -- "s/#LoadPlugin memory/LoadPlugin memory/" /etc/collectd/collectd.conf
  cat <<EOF | sudo tee -a  /etc/collectd/collectd.conf
<LoadPlugin python>
  Globals true
</LoadPlugin>
<Plugin python>
  ModulePath "/home/ubuntu/OpenStackBarcelonaDemo/ves_plugin/"
  LogTraces true
  Interactive false
  Import "ves_plugin"
<Module ves_plugin>
  Domain "$collector_ip"
  Port 30000
  Path ""
  Topic ""
  UseHttps false
  Username "hello"
  Password "world"
  FunctionalRole "Collectd VES Agent"
</Module>
</Plugin>
LoadPlugin virt
<Plugin virt>
        Connection "qemu:///system"
        RefreshInterval 60
        HostnameFormat uuid
</Plugin>
<Plugin cpu>
        ReportByCpu false
        ValuesPercentage true
</Plugin>
EOF
  sudo service collectd restart
}

setup_agent () {
  echo "$0: Install prerequisites"
  sudo apt-get install -y gcc
  # NOTE: force is required as some packages can't be authenticated...
  sudo apt-get install -y --force-yes libcurl4-openssl-dev
  sudo apt-get install -y make

  echo "$0: Clone agent library"
  cd /home/ubuntu
  git clone https://github.com/att/evel-library.git

  echo "$0: Clone VES repo"
  git clone https://gerrit.opnfv.org/gerrit/ves

  echo "$0: Use vHello_VES blueprint version of agent_demo.c"
  cp ves/tests/blueprints/tosca-vnfd-hello-ves/evel_demo.c evel-library/code/evel_demo/evel_demo.c
  
  echo "$0: Update parameters and build agent demo"
  sed -i -- "/api_secure,/{n;s/.*/                      \"$username\",/}" evel-library/code/evel_demo/evel_demo.c
  sed -i -- "/\"hello\",/{n;s/.*/                      \"$password\",/}" evel-library/code/evel_demo/evel_demo.c

  echo "$0: Build evel_demo agent"
  cd evel-library/bldjobs
  make
  export LD_LIBRARY_PATH=$LD_LIBRARY_PATH:/home/ubuntu/evel-library/libs/x86_64
  
  echo "$0: Start evel_demo agent"
  nohup ../output/x86_64/evel_demo --id $vm_id --fqdn $collector_ip --port 30000 --username $username --password $password > /dev/null 2>&1 &
}

setup_webserver () {
  echo "$0: Setup website and dockerfile"
  mkdir ~/www
  mkdir ~/www/html

  # ref: https://hub.docker.com/_/nginx/
  cat > ~/www/Dockerfile <<EOM
FROM nginx
COPY html /usr/share/nginx/html
EOM

  host=$(hostname)
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
Welcome to OPNFV @ $host!</large><br/>
<a href="http://wiki.opnfv.org"><img src="https://www.opnfv.org/sites/all/themes/opnfv/logo.png"></a>
</body></html>
EOM

  wget https://git.opnfv.org/cgit/ves/plain/tests/blueprints/tosca-vnfd-hello-ves/favicon.ico -O  ~/www/html/favicon.ico

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

  echo "$0: setup VES agents"
  setup_agent

  # Debug hints
  # id=$(sudo ls /var/lib/docker/containers)
  # sudo tail -f /var/lib/docker/containers/$id/$id-json.log \
  }

setup_lb () {
  echo "$0: setup VES load balancer"
  echo "$0: install dependencies"
  sudo apt-get update

  echo "$0: Setup iptables rules"
  echo "1" | sudo tee /proc/sys/net/ipv4/ip_forward
  sudo sysctl net.ipv4.ip_forward=1
  sudo iptables -t nat -A PREROUTING -p tcp --dport 80 -m state --state NEW -m statistic --mode nth --every 2 --packet 0 -j DNAT --to-destination $app1_ip:80
  sudo iptables -t nat -A PREROUTING -p tcp --dport 80 -m state --state NEW -m statistic --mode nth --every 2 --packet 0 -j DNAT --to-destination $app2_ip:80
  sudo iptables -t nat -A POSTROUTING -j MASQUERADE
  # debug hints: list rules (sudo iptables -S -t nat), flush (sudo iptables -F -t nat)

  echo "$0: setup VES agents"
  setup_agent
}

setup_monitor () {
  echo "$0: setup VES Monitor"
  echo "$0: install dependencies"
  # Note below: python (2.7) is required due to dependency on module 'ConfigParser'
  sudo apt-get update
  sudo apt-get upgrade -y
  sudo apt-get install -y python python-jsonschema

  echo "$0: setup VES Monitor config"
  sudo mkdir /var/log/att
  sudo chown ubuntu /var/log/att
  touch /var/log/att/collector.log
  sudo chown ubuntu /home/ubuntu/
  cd /home/ubuntu/
  git clone https://github.com/att/evel-test-collector.git
  sed -i -- "s/vel_username = /vel_username = $username/" evel-test-collector/config/collector.conf
  sed -i -- "s/vel_password = /vel_password = $password/" evel-test-collector/config/collector.conf

  python monitor.py --config evel-test-collector/config/collector.conf --section default 
}

type=$1
vm_id=$2
collector_ip=$3
username=$4
password=$5
app1_ip=$6
app2_ip=$7

setup_$type
exit 0
