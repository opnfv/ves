#!/bin/bash
# Copyright 2016-2017 AT&T Intellectual Property, Inc
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
# upon the Tacker Hello World blueprint, designed as a manual demo of the VES
# concept and integration with the Barometer project collectd agent. Typical 
# demo procedure is to execute the following actions from the OPNFV jumphost
# or some host wth access to the OpenStack controller (see below for details):
#  setup: install Tacker in a docker container. Note: only needs to be done
#         once per session, and can be reused across OPNFV VES and Models tests,
#         i.e. you can start another test at the "start" step below.
#  start: install blueprint and start the VNF, including the app (load-balanced
#         web server) and VES agents running on the VMs. Installs the VES 
#         monitor code but does not start the monitor (see below).
#  start_collectd: start the collectd daemon on bare metal hypervisor hosts
#  monitor: start the VES monitor, typically run in a second shell session.
#  pause: pause the app at one of the web server VDUs (VDU1 or VDU2)
#  stop: stop the VNF and uninstall the blueprint
#  start_collectd: start the collectd daemon on bare metal hypervisor hosts
#  clean: remove the tacker container and service (if desired, when done)
#
# Status: this is a work in progress, under test.
#
# How to use:
#   $ git clone https://gerrit.opnfv.org/gerrit/ves
#   $ cd ves/tests
#   $ bash vHello_VES.sh setup <openrc> [branch]
#     setup: setup test environment
#     <openrc>: location of OpenStack openrc file
#     branch: OpenStack branch to install (default: master)
#   $ bash vHello_VES.sh start
#     start: install blueprint and run test
#   $ bash vHello_VES.sh start_collectd|stop_collectd <hpv_ip> <user> <mon_ip> 
#     start_collectd: install and start collectd daemon on hypervisor
#     stop_collectd: stop and uninstall collectd daemon on hypervisor
#     <hpv_ip>: hypervisor ip 
#     <user>: username on hypervisor hosts, for ssh (user must be setup for 
#       key-based auth on the hosts)
#     <mon_ip>: IP address of VES monitor
#   $ bash vHello_VES.sh monitor <mon_ip>
#     monitor: attach to the collector VM and run the VES Monitor
#     <mon_ip>: IP address of VDU4 (monitor VM)
#   $ bash vHello_VES.sh traffic
#     traffic: generate some traffic
#   $ bash vHello_VES.sh pause VDU1|VDU2
#     pause: pause the VNF (web server) for a minute to generate a state change
#     VDU1: Pause VDU1
#     VDU2: Pause VDU2
#   $ bash vHello_VES.sh stop
#     stop: stop test and uninstall blueprint
#   $ bash vHello_VES.sh clean  <hpvuser> <hpvpw>
#     clean: cleanup after test
#     <hpvuser>: username on hypervisor
#     <hpvpw>: password on hypervisor

trap 'fail' ERR

pass() {
  echo "$0: $(date) Hooray!"
  exit 0
}

fail() {
  echo "$0: $(date) Test Failed!"
  exit 1
}

assert() {
  if [[ $2 == true ]]; then echo "$0 test assertion passed: $1"
  else 
    echo "$0 test assertion failed: $1"
    fail
  fi
}

get_floating_net () {
  network_ids=($(neutron net-list|grep -v "+"|grep -v name|awk '{print $2}'))
  for id in ${network_ids[@]}; do
      [[ $(neutron net-show ${id}|grep 'router:external'|grep -i "true") != "" ]] && FLOATING_NETWORK_ID=${id}
  done
  if [[ $FLOATING_NETWORK_ID ]]; then
    FLOATING_NETWORK_NAME=$(neutron net-show $FLOATING_NETWORK_ID | awk "/ name / { print \$4 }")
  else
    echo "$0: $(date) Floating network not found"
    exit 1
  fi
}

try () {
  count=$1
  $3
  while [[ $? == 1 && $count > 0 ]]; do 
    sleep $2
    let count=$count-1
    $3
  done
  if [[ $count -eq 0 ]]; then echo "$0: $(date) Command \"$3\" was not successful after $1 tries"; fi
}

setup () {
  trap 'fail' ERR

  echo "$0: $(date) Setup shared test folder /opt/tacker"
  if [ -d /opt/tacker ]; then sudo rm -rf /opt/tacker; fi 
  sudo mkdir -p /opt/tacker
  sudo chown $USER /opt/tacker
  chmod 777 /opt/tacker/

  echo "$0: $(date) copy test script and openrc to /opt/tacker"
  cp $0 /opt/tacker/.
  cp $1 /opt/tacker/admin-openrc.sh

  source /opt/tacker/admin-openrc.sh
  chmod 755 /opt/tacker/*.sh

  echo "$0: $(date) tacker-setup part 1"
  wget https://git.opnfv.org/models/plain/tests/utils/tacker-setup.sh -O /tmp/tacker-setup.sh
  bash /tmp/tacker-setup.sh init
  if [ $? -eq 1 ]; then fail; fi

  echo "$0: $(date) tacker-setup part 2"
  dist=`grep DISTRIB_ID /etc/*-release | awk -F '=' '{print $2}'`
  if [ "$dist" == "Ubuntu" ]; then
    echo "$0: $(date) Execute tacker-setup.sh in the container"
    sudo docker exec -it tacker /bin/bash /opt/tacker/tacker-setup.sh setup $2
  else
    echo "$0: $(date) Execute tacker-setup.sh in the container"
    sudo docker exec -i -t tacker /bin/bash /opt/tacker/tacker-setup.sh setup $2
  fi

  assert "models-tacker-001 (Tacker installation in a docker container on the jumphost)" true 
}

say_hello() {
  echo "$0: $(date) Testing $1"
  pass=false
  count=10
  while [[ $count > 0 && $pass != true ]] 
  do 
    sleep 30
    let count=$count-1
    if [[ $(curl $1 | grep -c "Hello World") > 0 ]]; then
      echo "$0: $(date) Hello World found at $1"
      pass=true
    fi
  done
  if [[ $pass != true ]]; then fail; fi
}

copy_blueprint() {
  echo "$0: $(date) copy test script to /opt/tacker"
  cp $0 /opt/tacker/.

  echo "$0: $(date) reset blueprints folder"
  if [[ -d /opt/tacker/blueprints/tosca-vnfd-hello-ves ]]; then 
    rm -rf /opt/tacker/blueprints/tosca-vnfd-hello-ves
  fi

  echo "$0: $(date) copy tosca-vnfd-hello-ves to blueprints folder"
  if [[ ! -d /opt/tacker/blueprints ]]; then mkdir /opt/tacker/blueprints; fi
  cp -r blueprints/tosca-vnfd-hello-ves /opt/tacker/blueprints/tosca-vnfd-hello-ves
}

start() {
#  Disable trap for now, need to test to ensure premature fail does not occur
#  trap 'fail' ERR

  echo "$0: $(date) setup OpenStack CLI environment"
  source /opt/tacker/admin-openrc.sh

  echo "$0: $(date) Create Nova key pair"
  if [[ -f /opt/tacker/vHello ]]; then rm /opt/tacker/vHello; fi
  ssh-keygen -t rsa -N "" -f /opt/tacker/vHello -C ubuntu@vHello
  chmod 600 /opt/tacker/vHello
  openstack keypair create --public-key /opt/tacker/vHello.pub vHello
  assert "models-nova-001 (Keypair creation)" true 

  echo "$0: $(date) Inject public key into blueprint"
  pubkey=$(cat /opt/tacker/vHello.pub)
  sed -i -- "s~<pubkey>~$pubkey~" /opt/tacker/blueprints/tosca-vnfd-hello-ves/blueprint.yaml

  vdus="VDU1 VDU2 VDU3 VDU4"
  vdui="1 2 3 4"
  vnf_vdui="1 2 3"
  declare -a vdu_id=()
  declare -a vdu_ip=()
  declare -a vdu_url=()

  # Setup for workarounds
  echo "$0: $(date) allocate floating IPs"
  get_floating_net
  for i in $vdui; do
    vdu_ip[$i]=$(nova floating-ip-create $FLOATING_NETWORK_NAME | awk "/$FLOATING_NETWORK_NAME/ { print \$4 }")
    echo "$0: $(date) Pre-allocated ${vdu_ip[$i]} to VDU$i"
  done

  echo "$0: $(date) Inject web server floating IPs into LB code in blueprint"
  sed -i -- "s/<vdu1_ip>/${vdu_ip[1]}/" /opt/tacker/blueprints/tosca-vnfd-hello-ves/blueprint.yaml
  sed -i -- "s/<vdu2_ip>/${vdu_ip[2]}/" /opt/tacker/blueprints/tosca-vnfd-hello-ves/blueprint.yaml
  # End setup for workarounds

  echo "$0: $(date) create VNFD"
  cd /opt/tacker/blueprints/tosca-vnfd-hello-ves
  # newton: NAME (was "--name") is now a positional parameter
  tacker vnfd-create --vnfd-file blueprint.yaml hello-ves
  if [[ $? -eq 0 ]]; then 
    assert "models-tacker-002 (VNFD creation)" true
  else
    assert "models-tacker-002 (VNFD creation)" false
  fi

  echo "$0: $(date) create VNF"
  # newton: NAME (was "--name") is now a positional parameter
  tacker vnf-create --vnfd-name hello-ves hello-ves
  if [ $? -eq 1 ]; then fail; fi

  echo "$0: $(date) wait for hello-ves to go ACTIVE"
  active=""
  count=24
  while [[ -z $active && $count -gt 0 ]]
  do
    active=$(tacker vnf-show hello-ves | grep ACTIVE)
    if [[ $(tacker vnf-show hello-ves | grep -c ERROR) > 0 ]]; then 
      echo "$0: $(date) hello-ves VNF creation failed with state ERROR"
      assert "models-tacker-002 (VNF creation)" false
    fi
    let count=$count-1
    sleep 30
    echo "$0: $(date) wait for hello-ves to go ACTIVE"
  done
  if [[ $count == 0 ]]; then 
    echo "$0: $(date) hello-ves VNF creation failed - timed out"
    assert "models-tacker-002 (VNF creation)" false
  fi

  # Setup for workarounds
  echo "$0: $(date) directly set port security on ports (unsupported in Mitaka Tacker)"
  # Alternate method
  #  HEAT_ID=$(tacker vnf-show hello-ves | awk "/instance_id/ { print \$4 }")
  #  SERVER_ID=$(openstack stack resource list $HEAT_ID | awk "/VDU1 / { print \$4 }")
  for vdu in $vdus; do
    echo "$0: $(date) Setting port security on $vdu"  
    SERVER_ID=$(openstack server list | awk "/$vdu/ { print \$2 }")
    id=($(neutron port-list|grep -v "+"|grep -v name|awk '{print $2}'))
    for id in ${id[@]}; do
      if [[ $(neutron port-show $id|grep $SERVER_ID) ]]; then neutron port-update ${id} --port-security-enabled=True; fi
    done
  done

  echo "$0: $(date) directly assign security group (unsupported in Mitaka Tacker)"
  if [[ $(neutron security-group-list | awk "/ vHello / { print \$2 }") ]]; then neutron security-group-delete vHello; fi
  neutron security-group-create vHello
  neutron security-group-rule-create --direction ingress --protocol TCP --port-range-min 22 --port-range-max 22 vHello
  neutron security-group-rule-create --direction ingress --protocol TCP --port-range-min 80 --port-range-max 80 vHello
  neutron security-group-rule-create --direction ingress --protocol TCP --port-range-min 30000 --port-range-max 30000 vHello
  for i in $vdui; do
    vdu_id[$i]=$(openstack server list | awk "/VDU$i/ { print \$2 }")
    echo "$0: $(date) Assigning security groups to VDU$i (${vdu_id[$i]})"    
    openstack server add security group ${vdu_id[$i]} vHello
    openstack server add security group ${vdu_id[$i]} default
  done

  echo "$0: $(date) associate floating IPs"
  for i in $vdui; do
    nova floating-ip-associate ${vdu_id[$i]} ${vdu_ip[$i]}
  done

  echo "$0: $(date) get web server addresses"
  vdu_url[1]="http://${vdu_ip[1]}"
  vdu_url[2]="http://${vdu_ip[2]}"
  vdu_url[3]="http://${vdu_ip[3]}"
  vdu_url[4]="http://${vdu_ip[4]}:30000/eventListener/v3"

  apt-get install -y curl

  echo "$0: $(date) wait for VNF web service to be ready"
  count=0
  resp=$(curl http://${vdu_ip[1]})
  echo $resp
  while [[ $count < 10 && "$resp" == "" ]]; do
    echo "$0: $(date) waiting for HTTP response from LB"
    sleep 60
    let count=$count+1
    resp=$(curl http://${vdu_ip[3]})
    echo $resp
  done
     
  echo "$0: $(date) verify vHello server is running at each web server and via the LB"
  say_hello http://${vdu_ip[1]}
  say_hello http://${vdu_ip[2]}
  say_hello http://${vdu_ip[3]}

  assert "models-vhello-001 (vHello VNF creation)" true
  assert "models-tacker-003 (VNF creation)" true
  assert "models-tacker-vnfd-002 (artifacts creation)" true
  assert "models-tacker-vnfd-003 (user_data creation)" true

  echo "$0: $(date) setup Monitor in VDU4 at ${vdu_ip[4]}"
  scp -i /opt/tacker/vHello -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no /opt/tacker/blueprints/tosca-vnfd-hello-ves/start.sh ubuntu@${vdu_ip[4]}:/home/ubuntu/start.sh
  scp -i /opt/tacker/vHello -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no /opt/tacker/blueprints/tosca-vnfd-hello-ves/monitor.py ubuntu@${vdu_ip[4]}:/home/ubuntu/monitor.py
  ssh -i /opt/tacker/vHello -t -t -x -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no ubuntu@${vdu_ip[4]} "nohup bash /home/ubuntu/start.sh monitor ${vdu_id[1]} ${vdu_id[2]} ${vdu_id[3]} hello world > ~/monitor.log &"

  echo "$0: $(date) Execute agent startup script in the VNF VMs"
  for i in $vnf_vdui; do
    ssh -i /opt/tacker/vHello -x -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no ubuntu@${vdu_ip[$i]} "sudo chown ubuntu /home/ubuntu"
    scp -i /opt/tacker/vHello -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no /opt/tacker/blueprints/tosca-vnfd-hello-ves/start.sh ubuntu@${vdu_ip[$i]}:/home/ubuntu/start.sh
    ssh -i /opt/tacker/vHello -x -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no \
    ubuntu@${vdu_ip[$i]} "nohup bash /home/ubuntu/start.sh agent ${vdu_id[$i]} ${vdu_ip[4]} hello world > /dev/null 2>&1 &"
  done

  echo "$0: $(date) Startup complete. VDU addresses:"
  echo "web server  1: ${vdu_ip[1]}"
  echo "web server  2: ${vdu_ip[2]}"
  echo "load balancer: ${vdu_ip[3]}"
  echo "monitor      : ${vdu_ip[4]}"
}

stop() {
  trap 'fail' ERR

  echo "$0: $(date) setup OpenStack CLI environment"
  source /opt/tacker/admin-openrc.sh

  if [[ "$(tacker vnf-list|grep hello-ves|awk '{print $2}')" != '' ]]; then
    echo "$0: $(date) uninstall vHello blueprint via CLI"
    try 12 10 "tacker vnf-delete hello-ves"
    # It can take some time to delete a VNF - thus wait 2 minutes
    count=12
    while [[ $count > 0 && "$(tacker vnf-list|grep hello-ves|awk '{print $2}')" != '' ]]; do 
      echo "$0: $(date) waiting for hello-ves VNF delete to complete"
      sleep 10
      let count=$count-1
    done 
    if [[ "$(tacker vnf-list|grep hello-ves|awk '{print $2}')" == '' ]]; then
      assert "models-tacker-004 (VNF deletion)" true
    else
      assert "models-tacker-004 (VNF deletion)" false
    fi
  fi

  # It can take some time to delete a VNFD - thus wait 2 minutes
  if [[ "$(tacker vnfd-list|grep hello-ves|awk '{print $2}')" != '' ]]; then
    echo "$0: $(date) trying to delete the hello-ves VNFD"
    try 12 10 "tacker vnfd-delete hello-ves"
    if [[ "$(tacker vnfd-list|grep hello-ves|awk '{print $2}')" == '' ]]; then
      assert "models-tacker-005 (VNFD deletion)" true
    else
      assert "models-tacker-005 (VNFD deletion)" false
    fi
  fi

# This part will apply for tests that dynamically create the VDU base image
#  iid=($(openstack image list|grep VNFImage|awk '{print $2}')); for id in ${iid[@]}; do openstack image delete ${id};  done
#  if [[ "$(openstack image list|grep VNFImage|awk '{print $2}')" == '' ]]; then
#    assert "models-tacker-vnfd-004 (artifacts deletion)" true
#  else
#    assert "models-tacker-vnfd-004 (artifacts deletion)" false
#  fi

  # Cleanup for workarounds
  fip=($(neutron floatingip-list|grep -v "+"|grep -v id|awk '{print $2}')); for id in ${fip[@]}; do neutron floatingip-delete ${id};  done
  sg=($(openstack security group list|grep vHello|awk '{print $2}'))
  for id in ${sg[@]}; do try 5 5 "openstack security group delete ${id}";  done
  kid=($(openstack keypair list|grep vHello|awk '{print $2}')); for id in ${kid[@]}; do openstack keypair delete ${id};  done
}

start_collectd() {
  # NOTE: ensure hypervisor hostname is resolvable e.g. thru /etc/hosts
  echo "$0: $(date) update start.sh script in case it changed"
  cp -r blueprints/tosca-vnfd-hello-ves/start.sh /opt/tacker/blueprints/tosca-vnfd-hello-ves
  echo "$0: $(date) start collectd agent on bare metal hypervisor host"
  scp -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no /opt/tacker/blueprints/tosca-vnfd-hello-ves/start.sh $2@$1:/home/$2/start.sh
  ssh -x -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no $2@$1 \
    "nohup bash /home/$2/start.sh collectd $1 $3 hello world > /dev/null 2>&1 &"
}

stop_collectd() {
  echo "$0: $(date) remove collectd agent on bare metal hypervisor hosts"
  ssh -x -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no $2@$1 <<'EOF'
dist=`grep DISTRIB_ID /etc/*-release | awk -F '=' '{print $2}'`
if [ "$dist" == "Ubuntu" ]; then 
  sudo service collectd stop
  sudo apt-get remove -y collectd
else
  sudo service collectd stop
  sudo yum remove -y collectd collectd-virt
fi
rm -rf $HOME/barometer
EOF
}

#
# Test tools and scenarios
#

get_vdu_ip () {
  source /opt/tacker/admin-openrc.sh

  echo "$0: $(date) find VM IP for $1"
  ip=$(openstack server list | awk "/$1/ { print \$10 }")
}

monitor () {
  echo "$0: $(date) Start the VES Monitor in VDU4 - Stop first if running"
  sudo ssh -t -t -i /opt/tacker/vHello -x -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no ubuntu@$1 << 'EOF'
sudo kill $(ps -ef | grep evel-test-collector | awk '{print $2}')
python evel-test-collector/code/collector/monitor.py --config evel-test-collector/config/collector.conf --section default 
EOF
}

traffic () {
  echo "$0: $(date) Generate some traffic, somewhat randomly"
  get_vdu_ip VDU3
  ns="0 00 000"
  while true
  do
    for n in $ns; do
      sleep .$n$[ ( $RANDOM % 10 ) + 1 ]s
      curl -s http://$ip > /dev/null
    done
  done
}

pause () {
  echo "$0: $(date) Pause the VNF (web server) in $1 for 30 seconds to generate a state change fault report (Stopped)"
  get_vdu_ip $1
  ssh -i /tmp/vHello -x -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no ubuntu@$ip "sudo docker pause vHello"
  sleep 20
  echo "$0: $(date) Unpausing the VNF to generate a state change fault report (Started)"
  ssh -i /tmp/vHello -x -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no ubuntu@$ip "sudo docker unpause vHello"
}

forward_to_container () {
  echo "$0: $(date) pass $1 command to vHello.sh in tacker container"
  sudo docker exec tacker /bin/bash /opt/tacker/vHello_VES.sh $1
  if [ $? -eq 1 ]; then fail; fi
}

dist=`grep DISTRIB_ID /etc/*-release | awk -F '=' '{print $2}'`
case "$1" in
  setup)
    setup $2 $3
    if [ $? -eq 1 ]; then fail; fi
    pass
    ;;
  run)
    setup $2 $3
    copy_blueprint
    forward_to_container start
    if [ $? -eq 1 ]; then fail; fi
    pass
    ;;
  start)
    if [[ -f /.dockerenv ]]; then
      start
    else
      copy_blueprint
      forward_to_container start
    fi
    pass
    ;;
  start_collectd)
    start_collectd $2 $3 $4
    if [ $? -eq 1 ]; then fail; fi
    pass
    ;;
  stop_collectd)
    stop_collectd $2 $3
    if [ $? -eq 1 ]; then fail; fi
    pass
    ;;
  monitor)
    monitor $2
    if [ $? -eq 1 ]; then fail; fi
    pass
    ;;
  traffic)
    traffic
    pass
    ;;
  pause)
    pause $2
    ;;
  stop)
    if [[ -f /.dockerenv ]]; then
      stop
    else
      forward_to_container stop
    fi
    if [ $? -eq 1 ]; then fail; fi
    pass
    ;;
  clean)
    echo "$0: $(date) Uninstall Tacker and test environment"
    sudo docker exec -it tacker /bin/bash /opt/tacker/tacker-setup.sh clean
    sudo docker stop tacker
    sudo docker rm -v tacker
    sudo rm -rf /opt/tacker
    pass
    ;;
  *)
    cat <<EOF
 What this is: Deployment test for the VES agent and collector based 
 upon the Tacker Hello World blueprint, designed as a manual demo of the VES
 concept and integration with the Barometer project collectd agent. Typical 
 demo procedure is to execute the following actions from the OPNFV jumphost
 or some host wth access to the OpenStack controller (see below for details):
  setup: install Tacker in a docker container. Note: only needs to be done
         once per session, and can be reused across OPNFV VES and Models tests,
         i.e. you can start another test at the "start" step below.
  start: install blueprint and start the VNF, including the app (load-balanced
         web server) and VES agents running on the VMs. Installs the VES 
         monitor code but does not start the monitor (see below).
  start_collectd: start the collectd daemon on bare metal hypervisor hosts
  monitor: start the VES monitor, typically run in a second shell session.
  pause: pause the app at one of the web server VDUs (VDU1 or VDU2)
  stop: stop the VNF and uninstall the blueprint
  start_collectd: start the collectd daemon on bare metal hypervisor hosts
  clean: remove the tacker container and service (if desired, when done)

 How to use:
   $ git clone https://gerrit.opnfv.org/gerrit/ves
   $ cd ves/tests
   $ bash vHello_VES.sh <setup> <openrc> [branch]
     setup: setup test environment
     <openrc>: location of OpenStack openrc file
     branch: OpenStack branch to install (default: master)
   $ bash vHello_VES.sh start
     start: install blueprint and run test
     <user>: username on hypervisor hosts, for ssh (user must be setup for 
       key-based auth on the hosts)
   $ bash vHello_VES.sh start_collectd|stop_collectd <hpv_ip> <user> <mon_ip> 
     start_collectd: install and start collectd daemon on hypervisor
     stop_collectd: stop and uninstall collectd daemon on hypervisor
     <hpv_ip>: hypervisor ip 
     <user>: username on hypervisor hosts, for ssh (user must be setup for 
       key-based auth on the hosts)
     <mon_ip>: IP address of VES monitor
   $ bash vHello_VES.sh monitor <mon_ip>
     monitor: attach to the collector VM and run the VES Monitor
     <mon_ip>: IP address of VDU4 (monitor VM)
   $ bash vHello_VES.sh traffic
     traffic: generate some traffic
   $ bash vHello_VES.sh pause VDU1|VDU2
     pause: pause the VNF (web server) for a minute to generate a state change
     VDU1: Pause VDU1
     VDU2: Pause VDU2
   $ bash vHello_VES.sh stop
     stop: stop test and uninstall blueprint
   $ bash vHello_VES.sh clean <user>
     clean: cleanup after test
     <user>: username on hypervisor hosts, for ssh (user must be setup for 
       key-based auth on the hosts)
EOF
esac
