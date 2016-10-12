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
# What this is: Deployment test for the VES agent and collector based 
# upon the Tacker Hello World blueprint 
#
# Status: this is a work in progress, under test.
#
# How to use:
#   $ git clone https://gerrit.opnfv.org/gerrit/ves
#   $ cd ves/tests
#   $ bash vHello_VES.sh [setup|start|run|stop|clean|collector]
#   setup: setup test environment
#   start: install blueprint and run test
#   run: setup test environment and run test
#   stop: stop test and uninstall blueprint
#   clean: cleanup after test
#   collector: attach to the collector VM and run the collector

set -x

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

setup () {
  echo "$0: Setup temp test folder /tmp/tacker and copy this script there"
  mkdir -p /tmp/tacker
  chmod 777 /tmp/tacker/
  cp $0 /tmp/tacker/.
  chmod 755 /tmp/tacker/*.sh

  echo "$0: tacker-setup part 1"
  wget https://git.opnfv.org/cgit/models/plain/tests/utils/tacker-setup.sh -O /tmp/tacker/tacker-setup.sh
  bash /tmp/tacker/tacker-setup.sh tacker-cli init

  echo "$0: tacker-setup part 2"
  CONTAINER=$(sudo docker ps -l | awk "/tacker/ { print \$1 }")
  dist=`grep DISTRIB_ID /etc/*-release | awk -F '=' '{print $2}'`
  if [ "$dist" == "Ubuntu" ]; then
    echo "$0: JOID workaround for Colorado - enable ML2 port security"
    juju set neutron-api enable-ml2-port-security=true

    echo "$0: Execute tacker-setup.sh in the container"
    sudo docker exec -it $CONTAINER /bin/bash /tmp/tacker/tacker-setup.sh tacker-cli setup
  else
    echo "$0: Execute tacker-setup.sh in the container"
    sudo docker exec -i -t $CONTAINER /bin/bash /tmp/tacker/tacker-setup.sh tacker-cli setup
  fi

  echo "$0: reset blueprints folder"
  if [[ -d /tmp/tacker/blueprints/tosca-vnfd-hello-ves ]]; then rm -rf /tmp/tacker/blueprints/tosca-vnfd-hello-ves; fi
  mkdir -p /tmp/tacker/blueprints/tosca-vnfd-hello-ves

  echo "$0: copy tosca-vnfd-hello-ves to blueprints folder"
  cp -r blueprints/tosca-vnfd-hello-ves /tmp/tacker/blueprints

  # Following two steps are in testing still. The guestfish step needs work.

  #  echo "$0: Create Nova key pair"
  #  mkdir -p ~/.ssh
  #  nova keypair-delete vHello
  #  nova keypair-add vHello > /tmp/tacker/vHello.pem
  #  chmod 600 /tmp/tacker/vHello.pem
  #  pubkey=$(nova keypair-show vHello | grep "Public key:" | sed -- 's/Public key: //g')
  #  nova keypair-show vHello | grep "Public key:" | sed -- 's/Public key: //g' >/tmp/tacker/vHello.pub

  echo "$0: Inject key into xenial server image"
  #  wget http://cloud-images.ubuntu.com/xenial/current/xenial-server-cloudimg-amd64-disk1.img
  #  sudo yum install -y libguestfs-tools
  #  guestfish <<EOF
#add xenial-server-cloudimg-amd64-disk1.img
#run
#mount /dev/sda1 /
#mkdir /home/ubuntu
#mkdir /home/ubuntu/.ssh
#cat <<EOM >/home/ubuntu/.ssh/authorized_keys
#$pubkey
#EOM
#exit
#chown -R ubuntu /home/ubuntu
#EOF

  # Using pre-key-injected image for now, vHello.pem as provided in the blueprint
  if [ ! -f /tmp/xenial-server-cloudimg-amd64-disk1.img ]; then 
    wget -O /tmp/xenial-server-cloudimg-amd64-disk1.img  http://artifacts.opnfv.org/models/images/xenial-server-cloudimg-amd64-disk1.img
  fi
  cp blueprints/tosca-vnfd-hello-ves/vHello.pem /tmp/tacker
  chmod 600 /tmp/tacker/vHello.pem

  echo "$0: setup OpenStack CLI environment"
  source /tmp/tacker/admin-openrc.sh

  echo "$0: Setup image_id"
  image_id=$(openstack image list | awk "/ models-xenial-server / { print \$2 }")
  if [[ -z "$image_id" ]]; then glance --os-image-api-version 1 image-create --name models-xenial-server --disk-format qcow2 --file /tmp/xenial-server-cloudimg-amd64-disk1.img --container-format bare; fi 
}

start() {
  echo "$0: setup OpenStack CLI environment"
  source /tmp/tacker/admin-openrc.sh

  echo "$0: create VNFD"
  cd /tmp/tacker/blueprints/tosca-vnfd-hello-ves
  tacker vnfd-create --vnfd-file blueprint.yaml --name hello-ves
  if [ $? -eq 1 ]; then fail; fi

  echo "$0: create VNF"
  tacker vnf-create --vnfd-name hello-ves --name hello-ves
  if [ $? -eq 1 ]; then fail; fi

  echo "$0: wait for hello-ves to go ACTIVE"
  active=""
  while [[ -z $active ]]
  do
    active=$(tacker vnf-show hello-ves | grep ACTIVE)
    if [ "$(tacker vnf-show hello-ves | grep -c ERROR)" == "1" ]; then 
      echo "$0: hello-ves VNF creation failed with state ERROR"
      fail
    fi
    sleep 10
  done

  echo "$0: directly set port security on ports (bug/unsupported in Mitaka Tacker?)"
  HEAT_ID=$(tacker vnf-show hello-ves | awk "/instance_id/ { print \$4 }")
  VDU1_ID=$(openstack stack resource list $HEAT_ID | awk "/VDU1 / { print \$4 }")
  id=($(neutron port-list|grep -v "+"|grep -v name|awk '{print $2}'))
  for id in ${id[@]}; do
    if [[ $(neutron port-show $id|grep $VDU1_ID) ]]; then neutron port-update ${id} --port-security-enabled=True; fi
  done

  VDU2_ID=$(openstack stack resource list $HEAT_ID | awk "/VDU2 / { print \$4 }")
  id=($(neutron port-list|grep -v "+"|grep -v name|awk '{print $2}'))
  for id in ${id[@]}; do
    if [[ $(neutron port-show $id|grep $VDU2_ID) ]]; then neutron port-update ${id} --port-security-enabled=True; fi
  done

  echo "$0: directly assign security group (unsupported in Mitaka Tacker)"
  if [[ $(openstack security group list | awk "/ vHello / { print \$2 }") ]]; then openstack security group delete vHello; fi
  openstack security group create vHello
  openstack security group rule create --ingress --protocol TCP --dst-port 22:22 vHello
  openstack security group rule create --ingress --protocol TCP --dst-port 80:80 vHello
  openstack server add security group $VDU1_ID vHello
  openstack server add security group $VDU1_ID default
  openstack server add security group $VDU2_ID vHello
  openstack server add security group $VDU2_ID default

  echo "$0: associate floating IPs"
  get_floating_net
  FIP=$(openstack floating ip create $FLOATING_NETWORK_NAME | awk "/floating_ip_address/ { print \$4 }")
  nova floating-ip-associate $VDU1_ID $FIP
  FIP=$(openstack floating ip create $FLOATING_NETWORK_NAME | awk "/floating_ip_address/ { print \$4 }")
  nova floating-ip-associate $VDU2_ID $FIP

  echo "$0: get web server addresses"
  VDU1_IP=$(openstack server show $VDU1_ID | awk "/ addresses / { print \$6 }")
  VDU1_URL="http://$VUD1_IP"
  VDU2_IP=$(openstack server show $VDU2_ID | awk "/ addresses / { print \$6 }")
  VDU2_URL="http://$VUD2_IP:30000"

  echo "$0: wait 30 seconds for server SSH to be available"
  sleep 30

  echo "$0: Setup the VES Collector in VDU2"
  chown root /tmp/tacker/vHello.pem
  # Note below: python (2.7) is required due to dependency on module 'ConfigParser'
  ssh -i /tmp/tacker/vHello.pem -x -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no ubuntu@$VDU2_IP << EOF
sudo apt-get update
sudo apt-get upgrade -y
sudo apt-get install -y python python-jsonschema
sudo mkdir /var/log/att
sudo chown ubuntu /var/log/att
touch /var/log/att/collector.log
sudo chown ubuntu /home/ubuntu/
cd /home/ubuntu/
git clone https://github.com/att/evel-test-collector.git
sed -i -- 's/vel_username = /vel_username = hello/' evel-test-collector/config/collector.conf
sed -i -- 's/vel_password = /vel_password = world/' evel-test-collector/config/collector.conf
EOF

  echo "$0: start vHello web server in VDU1"
  ssh -i /tmp/tacker/vHello.pem -x -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no ubuntu@$VDU1_IP "sudo chown ubuntu /home/ubuntu"
  scp -i /tmp/tacker/vHello.pem -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no /tmp/tacker/blueprints/tosca-vnfd-hello-ves/start.sh ubuntu@$VDU1_IP:/home/ubuntu/start.sh
  ssh -i /tmp/tacker/vHello.pem -x -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no ubuntu@$VDU1_IP "bash /home/ubuntu/start.sh $VDU2_IP hello:world"

  echo "$0: verify vHello server is running"
  apt-get install -y curl
  count=10
  while [[ $count -gt 0 ]] 
  do 
    sleep 60
    let count=$count-1
    if [[ $(curl http://$VDU1_IP | grep -c "Hello World") == 1 ]]; then pass; fi
  done
  fail
}

collector () {
  echo "$0: setup OpenStack CLI environment"
  source /tmp/tacker/admin-openrc.sh

  echo "$0: find Collector VM IP"
  HEAT_ID=$(tacker vnf-show hello-ves | awk "/instance_id/ { print \$4 }")
  VDU2_ID=$(openstack stack resource list $HEAT_ID | awk "/VDU2 / { print \$4 }")
  VDU2_IP=$(openstack server show $VDU2_ID | awk "/ addresses / { print \$6 }")
  VDU2_URL="http://$VUD2_IP:30000"

  echo "$0: Start the VES Collector in VDU2"
  ssh -i /tmp/tacker/vHello.pem -x -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no ubuntu@$VDU2_IP << EOF
cd /home/ubuntu/
python evel-test-collector/code/collector/collector.py \
       --config evel-test-collector/config/collector.conf \
       --section default \
       --verbose
EOF
}

stop() {
  echo "$0: setup OpenStack CLI environment"
  source /tmp/tacker/admin-openrc.sh

  echo "$0: uninstall vHello blueprint via CLI"
  vid=($(tacker vnf-list|grep hello-ves|awk '{print $2}')); for id in ${vid[@]}; do tacker vnf-delete ${id};  done
  vid=($(tacker vnfd-list|grep hello-ves|awk '{print $2}')); for id in ${vid[@]}; do tacker vnfd-delete ${id};  done
# Need to remove the floatingip deletion or make it specific to the vHello VM
#  fip=($(neutron floatingip-list|grep -v "+"|grep -v id|awk '{print $2}')); for id in ${fip[@]}; do neutron floatingip-delete ${id};  done
  sg=($(openstack security group list|grep vHello|awk '{print $2}'))
  for id in ${sg[@]}; do try 5 5 "openstack security group delete ${id}";  done
}

forward_to_container () {
  echo "$0: pass $1 command to this script in the tacker container"
  CONTAINER=$(sudo docker ps -a | awk "/tacker/ { print \$1 }")
  sudo docker exec $CONTAINER /bin/bash /tmp/tacker/vHello_VES.sh $1 $1
  if [ $? -eq 1 ]; then fail; fi
}

dist=`grep DISTRIB_ID /etc/*-release | awk -F '=' '{print $2}'`
case "$1" in
  setup)
    setup
    pass
    ;;
  run)
    setup
    forward_to_container start
    pass
    ;;
  start|stop|collector)
    if [[ $# -eq 1 ]]; then forward_to_container $1
    else
      # running inside the tacker container, ready to go
      $1
    fi
    pass
    ;;
  clean)
    echo "$0: Uninstall Tacker and test environment"
    bash /tmp/tacker/tacker-setup.sh $1 clean
    pass
    ;;
  *)
    echo "usage: bash vHello_VES.sh [setup|start|run|clean]"
    echo "setup: setup test environment"
    echo "start: install blueprint and run test"
    echo "run: setup test environment and run test"
    echo "stop: stop test and uninstall blueprint"
    echo "clean: cleanup after test"
    fail
esac
