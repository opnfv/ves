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
# What this is: Deployment script for the VNF Event Stream (VES) Reference VNF
# and Test Collector. Runs the VES Collector in a docker container on the 
# OPNFV jumphost, and the VES Reference VNF as an OpenStack VM.
#
# Status: this is a work in progress, under test.
#
# How to use:
#   $ git clone https://gerrit.opnfv.org/gerrit/ves
#   $ cd ves/tests
#   $ bash VES_Reference.sh [setup|start|run|stop|clean]
#   setup: setup test environment
#   start: install blueprint and run test
#   run: setup test environment and run test
#   stop: stop test and uninstall blueprint
#   clean: cleanup after test

trap 'fail' ERR

pass() {
  echo "$0: Hooray!"
  set +x #echo off
  exit 0
}

fail() {
  echo "$0: Test Failed!"
  set +x
  exit 1
}

function setenv () {
  echo "$0: Setup OpenStack environment variables"
  source utils/setenv.sh /tmp/VES
}

get_floating_net () {
  network_ids=($(neutron net-list|grep -v "+"|grep -v name|awk '{print $2}'))
  for id in ${network_ids[@]}; do
    [[ $(neutron net-show ${id}|grep 'router:external'|grep -i "true") != "" ]] && FLOATING_NETWORK_ID=${id}
  done
  if [[ $FLOATING_NETWORK_ID ]]; then
    FLOATING_NETWORK_NAME=$(openstack network show $FLOATING_NETWORK_ID | awk "/ name / { print \$4 }")
  else
    echo "$0: Floating network not found"
    exit 1
  fi
}

try () {
  count=$1
  $3
  while [[ $? -eq 1 && $count -gt 0 ]] 
  do 
    sleep $2
    let count=$count-1
    $3
  done
  if [[ $count -eq 0 ]]; then echo "$0: Command \"$3\" was not successful after $1 tries"; fi
}

function create_container () {
  echo "$0: Creating docker container"
  echo "$0: Copy this script to /tmp/VES"
  mkdir /tmp/VES
  cp $0 /tmp/VES/.
  chmod 755 /tmp/VES/*.sh

  echo "$0: reset blueprints folder"
  if [[ -d /tmp/VES/blueprints/ ]]; then rm -rf /tmp/VES/blueprints/; fi
  mkdir -p /tmp/VES/blueprints/

  echo "$0: Setup admin-openrc.sh"
  setenv

  echo "$0: Setup container"
  if [ "$dist" == "Ubuntu" ]; then
    # xenial is needed for python 3.5
    sudo docker pull ubuntu:xenial
    sudo service docker start
    # Port 30000 is the default for the VES Collector
    sudo docker run -it -d -p 30000:30000 -v /tmp/VES/:/tmp/VES \
         --name VES ubuntu:xenial /bin/bash
  else 
    # Centos
    echo "Centos-based install"
    sudo tee /etc/yum.repos.d/docker.repo <<-'EOF'
[dockerrepo]
name=Docker Repository--parents 
baseurl=https://yum.dockerproject.org/repo/main/centos/7/
enabled=1
gpgcheck=1
gpgkey=https://yum.dockerproject.org/gpg 
EOF
    sudo yum install -y docker-engine
    # xenial is needed for python 3.5
    sudo service docker start
    sudo docker pull ubuntu:xenial
    # Port 30000 is the default for the VES Collector
    sudo docker run -i -t -d -p 30000:30000 -v /tmp/VES/:/tmp/VES \
         --name VES ubuntu:xenial /bin/bash
  fi
}

setup_Openstack () {
  echo "$0: install OpenStack clients"
  pip install --upgrade python-openstackclient 
  pip install --upgrade python-glanceclient
  pip install --upgrade python-neutronclient
  pip install --upgrade python-heatclient
#  pip install --upgrade keystonemiddleware

  echo "$0: setup OpenStack environment"
  source /tmp/VES/admin-openrc.sh

  echo "$0: determine external (public) network as the floating ip network"  echo "$0: setup OpenStack environment"
  get_floating_net

  echo "$0: Setup centos7-server glance image if needed"
  if [[ -z $(openstack image list | awk "/ centos7-server / { print \$2 }") ]]; \
    then glance --os-image-api-version 1 image-create \
         --name centos7-server \
         --disk-format qcow2 \
         --location http://cloud.centos.org/centos/7/images/CentOS-7-x86_64-GenericCloud-1607.qcow2 \
         --container-format bare; fi 

  if [[ -z $(neutron net-list | awk "/ internal / { print \$2 }") ]]; then 
    echo "$0: Create internal network"
    neutron net-create internal

    echo "$0: Create internal subnet"
    neutron subnet-create internal 10.0.0.0/24 --name internal \
            --gateway 10.0.0.1 --enable-dhcp \
            --allocation-pool start=10.0.0.2,end=10.0.0.254 \
            --dns-nameserver 8.8.8.8
  fi

  if [[ -z $(neutron router-list | awk "/ public_router / { print \$2 }") ]]; then 
    echo "$0: Create router"
    neutron router-create public_router

    echo "$0: Create router gateway"
    neutron router-gateway-set public_router $FLOATING_NETWORK_NAME

    echo "$0: Add router interface for internal network"
    neutron router-interface-add public_router subnet=internal
  fi
}

setup_Collector () {
  echo "$0: Install dependencies - OS specific"
  if [ "$dist" == "Ubuntu" ]; then
    apt-get update
    apt-get install -y python
    apt-get install -y python-pip
    apt-get install -y git
  else
    yum install -y python
    yum install -y python-pip
    yum install -y git
  fi
  pip install --upgrade pip

  echo "$0: clone VES Collector repo"
  cd /tmp/VES/blueprints/
  git clone https://github.com/att/evel-test-collector.git
  echo "$0: update collector.conf"
  cd /tmp/VES/blueprints/evel-test-collector
  sed -i -- 's~/var/log/att/~/tmp/VES/~g' config/collector.conf
}

start_Collector () {
  echo "$0: start the VES Collector"
  cd /tmp/VES/blueprints/evel-test-collector
  python code/collector/collector.py \
       --config config/collector.conf \
       --section default \
       --verbose  
}

setup_Reference_VNF_VM () {
  echo "$0: Create Nova key pair"
  nova keypair-add VES > /tmp/VES/VES-key
  chmod 600 /tmp/VES/VES-key

  echo "$0: Add ssh key"
  eval $(ssh-agent -s)
  ssh-add /tmp/VES/VES-key

  echo "$0: clone VES Reference VNF repo"
  cd /tmp/VES/blueprints/
  git clone https://github.com/att/evel-reporting-reference-vnf.git

  echo "$0: customize VES Reference VNF Heat template"
  cd evel-reporting-reference-vnf/hot
  ID=$(openstack image list | awk "/ centos7-server / { print \$2 }")
  sed -i -- "s/40299aa3-2921-43b0-86b9-56c28a2b5232/$ID/g" event_reporting_vnf.env.yaml
  ID=$(neutron net-list | awk "/ internal / { print \$2 }")
  sed -i -- "s/84985f60-fbba-4a78-ba83-2815ff620dbc/$ID/g" event_reporting_vnf.env.yaml
  sed -i -- "s/127.0.0.1/$JUMPHOST/g" event_reporting_vnf.env.yaml
  sed -i -- "s/my-keyname/VES/g" event_reporting_vnf.env.yaml

  echo "$0: Create VES Reference VNF via Heat"
  heat stack-create -e event_reporting_vnf.env.yaml \
    -f event_reporting_vnf.template.yaml VES

  echo "$0: Wait for VES Reference VNF to go Active"
  COUNTER=0
  until [[ $(heat stack-list | awk "/ VES / { print \$6 }") == "CREATE_COMPLETE" ]]; do
    sleep 5
    let COUNTER+=1
    if [[ $COUNTER > "20" ]]; then fail; fi
  done

  echo "$0: Get Server ID"
  SID=$(heat resource-list VES | awk "/ OS::Nova::Server / { print \$4 }")

  echo "$0: associate SSH security group"
  # TODO: Update Heat template to include security group
  if [[ $(openstack security group list | awk "/ vHello / { print \$2 }") ]]; then neutron security-group-delete vHello; fi
  openstack security group create VES_Reference
  openstack security group rule create --ingress --protocol TCP --dst-port 22:22 VES_Reference
  openstack security group rule create --ingress --protocol TCP --dst-port 80:80 VES_Reference
  openstack server add security group $SID VES_Reference

  echo "$0: associate floating IP"
  # TODO: Update Heat template to include floating IP (if supported)
  FIP=$(openstack floating ip create $FLOATING_NETWORK_NAME | awk "/floating_ip_address/ { print \$4 }")
  nova floating-ip-associate $SID $FIP

#  scp -i /tmp/VES/VES-key -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no /tmp/VES/VES_Reference.sh centos@$FIP:/home/centos
  scp -i /tmp/VES/VES-key -o UserKnownHostsFile=/dev/null \
                          -o StrictHostKeyChecking=no \
                          $0 centos@$FIP:/home/centos
# run thru setup_Reference_VNF manually to verify
# ssh -i /tmp/VES/VES-key -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no centos@$FIP
#  ssh -i /tmp/VES/VES-key -x -o UserKnownHostsFile=/dev/null 
#                          -o StrictHostKeyChecking=no 
#                          centos@$FIP \
#                          "nohup source $0 setup_VNF &" 
}

setup_Reference_VNF () {
  echo "$0: Install dependencies"
  sudo yum update -y
  sudo yum install -y wget
  sudo yum install -y gcc
  sudo yum install -y openssl-devel
  sudo yum install -y epel-release
  sudo yum install -y python-pip
  sudo pip install --upgrade pip
  sudo yum install -y git

  echo "$0: Install Django"
  sudo pip install django

  echo "$0: Install Apache"
  sudo yum install -y httpd httpd-devel

  echo "$0: Install mod_python"
  sudo yum install -y python-devel
  mkdir ~/mod_python-3.4.1
  cd ~/mod_python-3.4.1
  wget http://dist.modpython.org/dist/mod_python-3.4.1.tgz
  tar xvf mod_python-3.4.1.tgz
  cd mod_python-3.4.1

  # Edit .../dist/version.sh to remove the dependency on Git as described at
  # http://stackoverflow.com/questions/20022952/fatal-not-a-git-repository-when-installing-mod-python
  sed \
   -e 's/(git describe --always)/(git describe --always 2>\/dev\/null)/g' \
   -e 's/`git describe --always`/`git describe --always 2>\/dev\/null`/g' \
   -i $( find . -type f -name Makefile\* -o -name version.sh )

  ./configure
  make
  sudo make install
  make test

  echo "$0: Install mod_wsgi"
  sudo yum install -y mod_wsgi

  echo "$0: clone VES Reference VNF repo"
  cd ~
  git clone https://github.com/att/evel-reporting-reference-vnf.git

  echo "$0: Setup collector"
  
  sudo mkdir -p /opt/att/collector
  sudo install -m=644 -t /opt/att/collector ~/evel-reporting-reference-vnf/code/collector/* 

  echo "$0: Setup Reference VNF website"
  sudo mkdir -p /opt/att/website/
  sudo cp -r ~/evel-reporting-reference-vnf/code/webserver/django/* /opt/att/website/
  sudo chown -R root:root /opt/att/website/
  sudo mkdir -p /var/log/att/
  echo "eh?" | sudo tee /var/log/att/django.log

  echo "$0: Create database"

  cd /opt/att/website
  sudo python manage.py migrate
  sudo python manage.py createsuperuser 
  sudo rm -f /var/log/att/django.log

  sudo systemctl daemon-reload
  sudo systemctl enable httpd
  sudo systemctl restart httpd

  echo "$0: Setup website backend"
  sudo mkdir -p /opt/att/backend/
  sudo install -m=644 -t /opt/att/backend ~/evel-reporting-reference-vnf/code/backend/* 
  sudo install -m=644 ~/evel-reporting-reference-vnf/config/backend.service /etc/systemd/system
  sudo systemctl daemon-reload
  sudo systemctl enable backend
  sudo systemctl restart backend

  
  echo "$0: Change security context for database"
  chcon -t httpd_sys_content_t db.sqlite3
  chcon -t httpd_sys_content_t .
  setsebool -P httpd_unified 1
  setsebool -P httpd_can_network_connect=1

  echo "$0: Gather static files"
  sudo python manage.py collectstatic

  echo "$0: Install jsonschema"
  sudo pip install jsonschema

  echo "$0: Put backend.service into /etc/systemd/system"
  sudo systemctl daemon-reload
  sudo systemctl start backend
  sudo systemctl status backend
  sudo systemctl enable backend

  # from initialize-event-database.sh
  cd /opt/att/website
  sudo python manage.py migrate
  sudo python manage.py createsuperuser

  # from go-webserver.sh
  sudo python /opt/att/website/manage.py runserver &

  # from go-backend.sh
  sudo python /opt/att/backend/backend.py --config ~/evel-reporting-reference-vnf/config/backend.conf --section default --verbose &
}

clean () {
  echo "$0: delete container"
  CONTAINER=$(sudo docker ps -a | awk "/VES/ { print \$1 }")
  sudo docker stop $CONTAINER
  sudo docker rm -v $CONTAINER
}

forward_to_container () {
  echo "$0: pass $1 command to VES_Reference.sh in container"
  CONTAINER=$(sudo docker ps -a | awk "/VES/ { print \$1 }")
  sudo docker exec $CONTAINER /bin/bash /tmp/VES/VES_Reference.sh $1 $1
  if [ $? -eq 1 ]; then fail; fi
}

dist=`grep DISTRIB_ID /etc/*-release | awk -F '=' '{print $2}'`
case "$1" in
  setup)
    if [[ $# -eq 1 ]]; then
      create_container
      echo "$0: Execute VES_Reference.sh in the container"
      CONTAINER=$(sudo docker ps -l | awk "/VES/ { print \$1 }")
      if [ "$dist" == "Ubuntu" ]; then
        sudo docker exec -it $CONTAINER /bin/bash /tmp/VES/VES_Reference.sh setup setup
      else
        sudo docker exec -i -t $CONTAINER /bin/bash /tmp/VES/VES_Reference.sh setup setup
      fi
    else
      # Running in the container, continue VES setup
      setup_Collector
      setup_Openstack
      setup_Reference_VNF_VM
      start_Collector
    fi
    pass
    ;;
  setup_VNF)
    setup_Reference_VNF
    ;;
  clean)
    echo "$0: Uninstall"
    clean
    pass
    ;;
  *)
    echo "usage: bash VES_Reference.sh [setup|clean]"
    echo "setup: setup test environment"
    echo "clean: cleanup after test"
    fail
esac
