#!/bin/bash
# Copyright 2017 AT&T Intellectual Property, Inc
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
#. What this is: Complete scripted deployment of the VES monitoring framework
#  When complete, the following will be installed:
#.  - On the specified master node, a Kafka server and containers running the 
#     OPNFV Barometer VES agent, OPNFV VES collector, InfluxDB, and Grafana 
#.  - On each specified worker node, collectd configured per OPNFV Barometer
#.
#. Prerequisites:
#. - Ubuntu server for kubernetes cluster nodes (master and worker nodes)
#. - MAAS server as cluster admin for kubernetes master/worker nodes
#. - Password-less ssh key provided for node setup
#. - hostname of kubernetes master setup in DNS or /etc/hosts
#. Usage: on the MAAS server
#. $ git clone https://gerrit.opnfv.org/gerrit/ves ~/ves
#. $ bash ~/ves/tools/demo_deploy.sh master <node> <key> 
#.   master: setup VES on k8s master
#.   <node>: IP of cluster master node
#.   <key>: SSH key enabling password-less SSH to nodes
#. $ bash ~/ves/tools/demo_deploy.sh worker <node> <key> 
#.   worker: setup VES on k8s worker
#.   <node>: IP of worker node
#.   <key>: SSH key enabling password-less SSH to nodes

node=$2
key=$3

eval `ssh-agent`
ssh-add $key
if [[ "$1" == "master" ]]; then
  echo; echo "$0 $(date): Setting up master node"
  scp -r -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no \
    ~/ves ubuntu@$node:/tmp
  ssh -x -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no ubuntu@$node <<EOF
  ves_host="$master"
  export ves_host
  ves_mode="guest"
  export ves_mode
  ves_user="hello"
  export ves_user
  ves_pass="world"
  export ves_pass
  ves_kafka_host="$node"
  export ves_kafka_host
  bash /tmp/ves/tools/ves-setup.sh collector
  bash /tmp/ves/tools/ves-setup.sh kafka
  bash /tmp/ves/tools/ves-setup.sh collectd
  bash /tmp/ves/tools/ves-setup.sh agent
EOF
  mkdir /tmp/ves
  scp -r -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no \
    ubuntu@$node:/tmp/ves/ves_env.sh /tmp/ves/.
  echo "VES Grafana dashboards are available at http://$node:3001 (login as admin/admin)"
else
  echo; echo "$0 $(date): Setting up collectd at $node"
  scp -r -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no \
    ~/ves ubuntu@$node:/tmp
  scp -r -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no \
    /tmp/ves/ves_env.sh ubuntu@$node:/tmp/ves/.
  ssh -x -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no \
    ubuntu@$node bash /tmp/ves/tools/ves-setup.sh collectd
fi
