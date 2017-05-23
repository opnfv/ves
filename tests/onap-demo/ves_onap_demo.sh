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
# concept using ONAP VNFs and integrating with the Barometer project collectd
# agent.
# Typical demo procedure is to execute the following actions from the OPNFV
# jumphost or some host wth access to the OpenStack controller
# (see below for details):
#  setup: install Tacker in a Docker container. Note: only needs to be done
#         once per session and can be reused across OPNFV VES and Models tests,
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
#
# Note: if you want to try this on DevStack, your DevStack VM needs at minimum
# 20 GB RAM and 20 GB hard drive.
#
#
# Status: this is a work in progress, under test.
#
# Prerequisites:
#   OPNFV install per JOID or Apex installers.
#   OpenStack client installed and authorized on the jumphost (needed for 
#     client commands executed on the jumphost).
#   For actions on the baremetal compute hosts
#     User must be setup for key auth. Copy your public key to the host and 
#     save in /home/<user>/.ssh/authorized_keys in advance.
#     For Apex, user is heat-admin
#     For JOID, user is ubuntu
#
#   Starting from the OPNFV system deployed and OSC clients installed in a 
#   virtualenv, an example set of prerequisite actions prior to running the
#   test on the jumphost:
#   source ~/venv/bin/activate; # activate virtualenv where OSC are installed
#   source ~/admin-openrc.sh;   # setup OpenStack client env
#   cd ves/tests/onap-demo/;    # go to the test folder
#   eval `ssh-agent`            # prepare to add compute host ssh key
#   ssh-add ~/.ssh/heat-admin   # add compute host ssh key (example for Apex,
#                               # previously copied from the undercloud)
#
#. How to use:
#.   SSH to the jumphost with no SSH forwarding active.
#.   $ git clone https://gerrit.opnfv.org/gerrit/ves
#.   $ cd ves/tests/onap-demo
#.   As a typical sequence, enter the commands (adapted to your environment) per
#.   the detailed options below:
#.   $ bash ves_onap_demo.sh setup ~/admin-openrc.sh stable/newton
#.   $ bash ves_onap_demo.sh start
#.   In a new terminal window, setup SSH port forwarding for the monitor VM as 
#.   described below and SSH to the jumphost.
#.   $ cd ves/tests/onap-demo/;
#.   $ bash ves_onap_demo.sh start agent all 192.168.37.17 heat-admin
#.   When done with testing:
#.   $ bash ves_onap_demo.sh stop
#.   $ bash ves_onap_demo.sh clean
#.
#.   Detailed command options:
#.
#.   $ bash ves_onap_demo.sh setup <openrc> [branch]
#.     setup: setup test environment
#.     <openrc>: location of OpenStack openrc file
#.     branch: OpenStack branch of Tacker to install (default: master)
#.   $ bash ves_onap_demo.sh start [agent] [all|n] [ip] [user]
#.     start: install blueprint
#.     agent: only start the indicated agent(s)
#.       all: all agents
#.       n: agent number (1,2,3,4,5)
#.     ip: for agent 5 actions, ip of the host
#.     user: for compute host actions, ssh user on hosts
#.   $ bash ves_onap_demo.sh monitor
#.     monitor: attach to the collector VM and run the VES Monitor
#.   $ bash ves_onap_demo.sh traffic <n>
#.     traffic: generate some traffic
#.       n: VDU number (1,2,3,4)
#.   $ bash ves_onap_demo.sh pause <1|2>
#.    pause: pause the VNF (web server) for a minute to generate a state change
#.     1|2: pause webserver_1 or webserver_2
#.   $ bash ves_onap_demo.sh stop [agent] [all|n] [ip] [user]
#.     stop: stop test and uninstall blueprint
#.     agent: only stop the indicated agent(s)
#.       all: all agents
#.       n: agent number (1,2,3,4,5)
#.     ip: for agent 5 actions, ip of the host
#.     user: for compute host actions, ssh user on hosts
#.   $ bash ves_onap_demo.sh clean
#.     clean: cleanup after tests
#.   $ bash ves_onap_demo.sh ssh [n]
#.     n: VDU number (1,2,3,4,5)
#
#   If you access the deployment jumphost via SSH, to access the InfluxDB and 
#   Grafana dashboards, when blueprint deploymement is complete you will need to
#   first add forwarding rules to your ~/.ssh/config file before ssh'ing to the 
#   jumphost.
#
#   Host *
#     AddressFamily inet
#
#   Host (name of your jumphost)
#     Hostname (host IP) 
#     User (your username)
#     LocalForward 8086 (monitor VM IP):8086
#     LocalForward 8080 (monitor VM IP):8080
#     LocalForward 8083 (monitor VM IP):8083
#     LocalForward 3000 (monitor VM IP):3000
#
#   Then SSH to the jumphost: ssh (name of your jumphost from the config file)
#   To access Grafana: http://localhost:3000 (admin/admin)
#   To access InfluxDB: http://localhost:8083/#
#

trap 'fail' ERR

pass() {
  echo "$0: $(date) Hooray!"
  end=`date +%s`
  runtime=$((end-test_start))
  echo "$0: $(date) Test Duration = $runtime seconds"
  exit 0
}

fail() {
  echo "$0: $(date) Test Failed!"
  end=`date +%s`
  runtime=$((end-test_start))
  runtime=$((runtime/60))
  echo "$0: $(date) Test Duration = $runtime seconds"
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
  echo "$0: $(date) get_floating_net start"
  network_ids=($(neutron net-list | grep -v "+" | grep -v name | awk '{print $2}'))
  for id in "${network_ids[@]}"; do
      [[ $(neutron net-show ${id} | grep 'router:external' | grep -i "true") != "" ]] && FLOATING_NETWORK_ID=${id}
  done
  if [[ $FLOATING_NETWORK_ID ]]; then
    FLOATING_NETWORK_NAME=$(neutron net-show $FLOATING_NETWORK_ID | awk "/ name / { print \$4 }")
      echo "$0: $(date) floating network name is  $FLOATING_NETWORK_NAME"
  else
    echo "$0: $(date) Floating network not found"
    exit 1
  fi
  echo "$0: $(date) get_floating_net end"
}

try () {
  count=$1
  $3
  while [[ $? == 1 && $count -gt 0 ]]; do
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

  echo "$0: $(date) tacker-setup part 1 fetching tacker-setup script and tacker.conf.sample from Models"
  if [ -a /tmp/tacker-setup.sh ]; then sudo rm /tmp/tacker-setup.sh; fi
  if [ -a /tmp/tacker.conf.sample ]; then sudo rm /tmp/tacker.conf.sample; fi  
  wget https://git.opnfv.org/models/plain/tests/utils/tacker-setup.sh -O /tmp/tacker-setup.sh
  wget https://git.opnfv.org/models/plain/tests/utils/tacker/tacker.conf.sample -O /tmp/tacker.conf.sample
  bash /tmp/tacker-setup.sh init
  if [ $? -eq 1 ]; then fail; fi

  echo "$0: $(date) tacker-setup part 2"
  dist=`grep DISTRIB_ID /etc/*-release | awk -F '=' '{print $2}'`
  if [ "$dist" == "Ubuntu" ]; then
    echo "$0: $(date) Execute tacker-setup.sh in the container"
    sudo docker exec -it tacker /bin/bash /opt/tacker/tacker-setup.sh setup $2
    if [ $? -eq 1 ]; then fail; fi
  else
    echo "$0: $(date) Execute tacker-setup.sh in the container"
    sudo docker exec -i -t tacker /bin/bash /opt/tacker/tacker-setup.sh setup $2
    if [ $? -eq 1 ]; then fail; fi
  fi

  assert "ves-onap-demo-tacker-001 (Tacker installation in a Docker container on the jumphost)" true

  echo "$0: $(date) Create Nova key pair"
  if [[ -f ~/onap-demo ]]; then rm ~/onap-demo; fi
  ssh-keygen -t rsa -N "" -f ~/onap-demo -C ubuntu@onap-demo
  chmod 600 ~/onap-demo
  openstack keypair create --public-key ~/onap-demo.pub ~/onap-demo
  assert "onap-demo-nova-001 (Keypair creation)" true

  sudo cp  ~/onap-demo /opt/tacker/onap-demo
}

say_hello() {
  echo "$0: $(date) Testing $1"
  pass=false
  count=10
  while [[ $count -gt 0 && $pass != true ]]
  do
    sleep 60
    let count=$count-1
    if [[ $(curl $1 | grep -c "Hello World") -gt 0 ]]; then
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
  if [[ -d /opt/tacker/blueprints/tosca-vnfd-onap-demo ]]; then
    rm -rf /opt/tacker/blueprints/tosca-vnfd-onap-demo
  fi

  echo "$0: $(date) copy tosca-vnfd-onap-demo to blueprints folder"
  if [[ ! -d /opt/tacker/blueprints ]]; then mkdir /opt/tacker/blueprints; fi
  cp -r blueprints/tosca-vnfd-onap-demo  /opt/tacker/blueprints
}

ssh_to_vdu() {
  get_vdu_ip $1
  ssh -t -i ~/onap-demo -x -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no ubuntu@$ip
	}

start_agent() {
  get_vdu_ip 5
  mon_ip=$ip
  if [[ $1 == 5 ]]; then
    # NOTE: ensure hypervisor hostname is resolvable e.g. thru /etc/hosts
    echo "$0: $(date) start collectd agent on bare metal hypervisor host"
    scp -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no \
      blueprints/tosca-vnfd-onap-demo/start.sh $3@$2:/home/$3/start.sh
    ssh -x -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no $3@$2 \
      "nohup bash start.sh collectd $mon_ip hello world > /dev/null 2>&1 &"
  else
    get_vdu_ip $1
    scp -r -i ~/onap-demo -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no blueprints/tosca-vnfd-onap-demo ubuntu@$ip:/home/ubuntu
    ssh -i ~/onap-demo -x -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no \
      ubuntu@$ip "bash ~/tosca-vnfd-onap-demo/start.sh ${vnfc_type[$1]} $mon_ip hello world"
  fi
}

start_agents() {
  echo "$0: $(date) Execute agent startup script in the VNF VMs"
  if [[ "$1" == "all" ]]; then
    echo "$0: $(date) Start agents in the VNF VMs"
    for i in $vnf_vdui; do
      start_agent $i
    done
    start_agent 5 $2 $3
  else
    start_agent $1 $2 $3
  fi
}

stop_agent() {
  if [[ $1 == 5 ]]; then
    echo "$0: $(date) remove collectd agent on bare metal hypervisor host, user $3 at $2"
    ssh -x -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no $3@$2 <<'EOF'
dist=`grep DISTRIB_ID /etc/*-release | awk -F '=' '{print $2}'`
if [ "$dist" == "Ubuntu" ]; then
  sudo systemctl stop collectd
  sudo apt-get remove -y collectd
else
  sudo systemctl stop collectd
  sudo yum remove -y collectd collectd-virt
fi
rm -rf $HOME/barometer
EOF
  else
    get_vdu_ip $1
    if [[ ${vnfc_type[$1]} == "webserver" ]]; then
      echo "$0: $(date) stopping webserver $1 agent at $ip"
      ssh -i ~/onap-demo -x -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no ubuntu@$ip << 'EOF'
sudo kill $(ps -ef | grep evel_demo | awk '{print $2}')
rm -rf evel-library
rm -rf tosca-vnfd-onap-demo
EOF
    else
      echo "$0: $(date) stopping VDU$1 agent at $ip"
      ssh -i ~/onap-demo -x -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no ubuntu@$ip << 'EOF'
sudo kill $(ps -ef | grep vpp_measurement_reporter | awk '{print $2}')
rm -rf evel-library
rm -rf tosca-vnfd-onap-demo
EOF
    fi
  fi
}

stop_agents() {
  if [[ $1 == "all" ]]; then
    echo "$0: $(date) Stop agents in the VNF VMs"
    for i in $vnf_vdui; do
      stop_agent $i
    done
    stop_agent 5 $2 $3
  else
    stop_agent $1 $2 $3
  fi
}

start_monitor() {
  for i in $vdui; do
    vdu_id[$i]=$(openstack server list | awk "/VDU$i/ { print \$2 }")
  done
  get_vdu_ip 5
  mon_ip=$ip
  echo "$0: $(date) start Monitor in VDU5 at $mon_ip"
  scp -i ~/onap-demo -r -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no blueprints/tosca-vnfd-onap-demo ubuntu@$mon_ip:/home/ubuntu/
  ssh -i ~/onap-demo -x -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no ubuntu@$mon_ip "bash /home/ubuntu/tosca-vnfd-onap-demo/start.sh monitor ${vdu_id[1]} ${vdu_id[2]} ${vdu_id[3]} ${vdu_id[4]} hello world"
}

start() {
#  Disable trap for now, need to test to ensure premature fail does not occur
#  trap 'fail' ERR

  if [[ "$1" == "agent" ]]; then
    start_agent $2 $3 $4
    pass
  fi

  echo "$0: $(date) setup OpenStack CLI environment"
  source /opt/tacker/admin-openrc.sh

  echo "$0: $(date) create flavor to use in blueprint"
  openstack flavor create onap.demo --id auto --ram 1024 --disk 4 --vcpus 1

  # Setup for workarounds
  echo "$0: $(date) allocate floating IPs"
  get_floating_net
  for i in $vdui; do
    vdu_ip[$i]=$(nova floating-ip-create $FLOATING_NETWORK_NAME | awk "/$FLOATING_NETWORK_NAME/ { print \$4 }")
    echo "$0: $(date) Pre-allocated ${vdu_ip[$i]} to VDU$i"
  done

  echo "$0: $(date) Inject public key into blueprint"
  pubkey=$(cat /opt/tacker/onap-demo.pub)
  sed -i -- "s~<pubkey>~$pubkey~" /opt/tacker/blueprints/tosca-vnfd-onap-demo/blueprint.yaml

  echo "$0: $(date) Inject web server floating IPs into LB code in blueprint"
  sed -i -- "s/<vdu1_ip>/${vdu_ip[1]}/" /opt/tacker/blueprints/tosca-vnfd-onap-demo/blueprint.yaml
  sed -i -- "s/<vdu2_ip>/${vdu_ip[2]}/" /opt/tacker/blueprints/tosca-vnfd-onap-demo/blueprint.yaml
  sed -i -- "s/<vdu3_ip>/${vdu_ip[3]}/" /opt/tacker/blueprints/tosca-vnfd-onap-demo/blueprint.yaml
  # End setup for workarounds

  echo "$0: $(date) create VNFD named onap-demo-vnfd"
  cd /opt/tacker/blueprints/tosca-vnfd-onap-demo
  # newton: NAME (was "--name") is now a positional parameter
  tacker vnfd-create --vnfd-file blueprint.yaml onap-demo-vnfd
  if [[ $? -eq 0 ]]; then
    assert "onap-demo-tacker-002 (VNFD creation onap-demo-vnfd)" true
  else
    assert "onap-demo-tacker-002 (VNFD creation onap-demo-vnfd)" false
  fi

  echo "$0: $(date) create VNF named onap-demo-vnf"
  # newton: NAME (was "--name") is now a positional parameter
  tacker vnf-create --vnfd-name onap-demo-vnfd onap-demo-vnf
  if [ $? -eq 1 ]; then fail; fi

  echo "$0: $(date) wait for onap-demo-vnf to go ACTIVE"
  active=""
  count=24
  while [[ -z $active && $count -gt 0 ]]
  do
    active=$(tacker vnf-show onap-demo-vnf | grep ACTIVE)
    if [[ $(tacker vnf-show onap-demo-vnf | grep -c ERROR) -gt 0 ]]; then
      echo "$0: $(date) onap-demo-vnf VNF creation failed with state ERROR"
      assert "onap-demo-tacker-002 (onap-demo-vnf creation)" false
    fi
    let count=$count-1
    #sleep for 60 seconds
    sleep 60
    echo "$0: $(date) wait for onap-demo-vnf to go ACTIVE"
  done
  if [[ $count == 0 ]]; then
    echo "$0: $(date) onap-demo-vnf VNF creation failed - timed out"
    assert "onap-demo-tacker-002 (VNF creation)" false
  fi

  # Setup for workarounds
  echo "$0: $(date) directly set port security on ports (unsupported in Newton Tacker)"
  # Alternate method
  #  HEAT_ID=$(tacker vnf-show onap-demo-vnfd | awk "/instance_id/ { print \$4 }")
  #  SERVER_ID=$(openstack stack resource list $HEAT_ID | awk "/VDU1 / { print \$4 }")
  for vdu in $vdus; do
    echo "$0: $(date) Setting port security on $vdu"
    SERVER_ID=$(openstack server list | awk "/$vdu/ { print \$2 }")
    id=($(neutron port-list -F id -f value))
    for id in "${id[@]}"; do
      if [[ $(neutron port-show $id | grep $SERVER_ID) ]]; then neutron port-update ${id} --port-security-enabled=True; fi
    done
  done

  echo "$0: $(date) directly assign security group to VDUs (unsupported in Newton Tacker)"
  if [[ $(neutron security-group-list | awk "/ onap-demo / { print \$2 }") ]]; then neutron security-group-delete onap-demo; fi
  neutron security-group-create onap-demo
  echo "$0: $(date) Add SSH traffic ingress rule to onap-demo"
  neutron security-group-rule-create --direction ingress --protocol TCP --port-range-min 22 --port-range-max 22 onap-demo
  echo "$0: $(date) Add HTTP traffic ingress rule to onap-demo"
  neutron security-group-rule-create --direction ingress --protocol TCP --port-range-min 80 --port-range-max 80 onap-demo
  # TODO: Split out the rest of the rules below into a security group specific to the role of the monitor
  echo "$0: $(date) Add VES monitor traffic ingress rule to onap-demo"
  neutron security-group-rule-create --direction ingress --protocol TCP --port-range-min 30000 --port-range-max 30000 onap-demo
  echo "$0: $(date) Add Grafana dahboard ingress rule to onap-demo"
  neutron security-group-rule-create --direction ingress --protocol TCP --port-range-min 3000 --port-range-max 3000 onap-demo
  echo "$0: $(date) Add InfluxDB API traffic ingress rule to onap-demo"
  neutron security-group-rule-create --direction ingress --protocol TCP --port-range-min 8086 --port-range-max 8086 onap-demo
  echo "$0: $(date) Add InfluxDB dashboard ingress rule to onap-demo"
  neutron security-group-rule-create --direction ingress --protocol TCP --port-range-min 8083 --port-range-max 8083 onap-demo

  for i in $vdui; do
    vdu_id[$i]=$(openstack server list | awk "/VDU$i/ { print \$2 }")
    echo "$0: $(date) Assigning security groups to VDU$i (${vdu_id[$i]})"
    openstack server add security group ${vdu_id[$i]} onap-demo
    openstack server add security group ${vdu_id[$i]} default
  done

  echo "$0: $(date) associate floating IPs with VDUs"
  # openstack server add floating ip INSTANCE_NAME_OR_ID FLOATING_IP_ADDRESS
  for i in $vdui; do
    openstack server add floating ip ${vdu_id[$i]} ${vdu_ip[$i]}
  done

  echo "$0: $(date) get web server addresses"
  vdu_url[1]="http://${vdu_ip[1]}"
  vdu_url[2]="http://${vdu_ip[2]}"
  vdu_url[3]="http://${vdu_ip[3]}"
  vdu_url[4]="http://${vdu_ip[4]}"
  vdu_url[5]="http://${vdu_ip[5]}:30000/eventListener/v5"

  apt-get install -y curl

  echo "$0: $(date) wait for VNF web service to be ready"
  count=0
  resp=$(curl http://${vdu_ip[1]})
  echo $resp
  while [[ $count -gt 10 && "$resp" == "" ]]; do
    echo "$0: $(date) waiting for HTTP response from FW"
    sleep 90
    let count=$count+1
    resp=$(curl http://${vdu_ip[4]})
    echo $resp
  done

  echo "$0: $(date) verify onap-demo server is running at each web server and via the LB and via the FW"
  echo "$0: $(date) say_hello VDU1"
  say_hello http://${vdu_ip[1]}
  echo "$0: $(date) say_hello VDU2"
  say_hello http://${vdu_ip[2]}
  echo "$0: $(date) say_hello VDU3"
  say_hello http://${vdu_ip[3]}
  echo "$0: $(date) say_hello VDU4"
  say_hello http://${vdu_ip[4]}

  assert "onap-demo-onap-demo-vnf-001 (onap-demo VNF creation)" true
  assert "onap-demo-tacker-003 (VNF creation)" true
  assert "onap-demo-tacker-vnfd-002 (artifacts creation)" true
  assert "onap-demo-tacker-vnfd-003 (user_data creation)" true
}

stop() {
  trap 'fail' ERR

  echo "$0: $(date) setup OpenStack CLI environment"
  source /opt/tacker/admin-openrc.sh

  if [[ "$(tacker vnf-list | grep onap-demo-vnf | awk '{print $2}')" != '' ]]; then
    echo "$0: $(date) uninstall onap-demo-vnf blueprint via CLI"
    try 12 10 "tacker vnf-delete onap-demo-vnf"
    # It can take some time to delete a VNF - thus wait 2 minutes
    count=12
    while [[ $count -gt 0 && "$(tacker vnf-list | grep onap-demo-vnfd | awk '{print $2}')" != '' ]]; do
      echo "$0: $(date) waiting for onap-demo-vnf VNF delete to complete"
      sleep 10
      let count=$count-1
    done
    if [[ "$(tacker vnf-list | grep onap-demo-vnf | awk '{print $2}')" == '' ]]; then
      assert "onap-demo-tacker-004 (VNF onap-demo-vnf deletion)" true
    else
      assert "onap-demo-tacker-004 (VNF onap-demo-vnf deletion)" false
    fi
  fi

  # It can take some time to delete a VNFD - thus wait 2 minutes
  if [[ "$(tacker vnfd-list | grep onap-demo-vnfd | awk '{print $2}')" != '' ]]; then
    echo "$0: $(date) trying to delete the onap-demo-vnfd VNFD"
    try 12 10 "tacker vnfd-delete onap-demo-vnfd"
    if [[ "$(tacker vnfd-list | grep onap-demo-vnfd | awk '{print $2}')" == '' ]]; then
      assert "onap-demo-tacker-005 (VNFD deletion onap-demo-vnfd)" true
    else
      assert "onap-demo-tacker-005 (VNFD deletion onap-demo-vnfd)" false
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
  fip=($(neutron floatingip-list | grep -v "+" | grep -v id | awk '{print $2}')); for id in "${fip[@]}"; do neutron floatingip-delete ${id};  done
  sg=($(openstack security group list | grep onap-demo |awk '{print $2}'))
  for id in "${sg[@]}"; do try 5 5 "openstack security group delete ${id}";  done
  kid=($(openstack keypair list | grep onap-demo | awk '{print $2}')); for id in "${kid[@]}"; do openstack keypair delete ${id};  done

  openstack flavor delete onap.demo
}


#
# Test tools and scenarios
#	

get_vdu_ip () {
  source /opt/tacker/admin-openrc.sh
  ip=$(openstack server list | awk "/VDU$1/ { print \$10 }")
}

monitor () {
  echo "$0: $(date) Start the VES Monitor in VDU5 - Stop first if running"
  get_vdu_ip 5
  scp -i ~/onap-demo -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no blueprints/tosca-vnfd-onap-demo/monitor.py ubuntu@$ip:/home/ubuntu/evel-test-collector/code/collector/monitor.py
  ssh -t -t -i ~/onap-demo -x -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no ubuntu@$ip << 'EOF'
sudo kill $(ps -ef | grep evel-test-collector | awk '{print $2}')
python evel-test-collector/code/collector/monitor.py --config evel-test-collector/config/collector.conf --section default
EOF
}

traffic () {
  echo "$0: $(date) Generate some traffic, somewhat randomly"
  get_vdu_ip $1
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
  get_vdu_ip $1
  echo "$0: $(date) Pause the VNF (web server) in $1 for 60 seconds to generate a state change fault report (Stopped)"
  ssh -t -i ~/onap-demo -x -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no ubuntu@$ip "sudo docker pause onap-demo"
  sleep 60
  echo "$0: $(date) Unpausing the VNF to generate a state change fault report (Started)"
  ssh -t -i ~/onap-demo -x -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no ubuntu@$ip "sudo docker unpause onap-demo"
}

forward_to_container () {
  echo "$0: $(date) pass $1 command to ves_onap_demo in tacker container"
  sudo docker exec tacker /bin/bash /opt/tacker/ves_onap_demo.sh $1
  if [ $? -eq 1 ]; then fail; fi
}

print_vdu_ip () {
  echo "$0: $(date) Startup complete. VDU addresses:"
  get_vdu_ip 1
  echo "web server  1: $ip"
  get_vdu_ip 2
  echo "web server  2: $ip"
  get_vdu_ip 3
  echo "load balancer: $ip"
  get_vdu_ip 4
  echo "firewall     : $ip"
  get_vdu_ip 5
  echo "monitor      : $ip"
}


vdus="VDU1 VDU2 VDU3 VDU4 VDU5"
vdui="1 2 3 4 5"
vnf_vdui="1 2 3 4"
vnfc_type[1]="webserver"
vnfc_type[2]="webserver"
vnfc_type[3]="vLB"
vnfc_type[4]="vFW"
declare -a vdu_id=()
declare -a vdu_ip=()
declare -a vdu_url=()

dist=`grep DISTRIB_ID /etc/*-release | awk -F '=' '{print $2}'`
case "$1" in
  setup)
    setup $2 $3
    if [ $? -eq 1 ]; then fail; fi
    pass
    ;;
  start)
    if [[ "$2" == "agent" ]]; then
      start_agents $3 $4 $5
      pass
    fi
    if [[ -f /.dockerenv ]]; then
      start
    else
      copy_blueprint
      forward_to_container start
      start_monitor
      print_vdu_ip
    fi
    pass
    ;;
  ssh)
    ssh_to_vdu $2
    ;;
  monitor)
    monitor $2
    if [ $? -eq 1 ]; then fail; fi
    pass
    ;;
  traffic)
    traffic $2
    pass
    ;;
  pause)
    pause $2
    ;;
  stop)
    if [[ $2 == "agent" ]]; then
      stop_agents $3 $4 $5
      pass
    fi
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
    grep '#  ' $0
esac
