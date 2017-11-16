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
#. $ bash ~/ves/tools/demo_deploy.sh <key> <master> "<workers>"
#. <key>: SSH key enabling password-less SSH to nodes
#. <master>: IP of cluster master node
#. <workers>: space separated list of worker node IPs

key=$1
master=$2
workers="$3"

eval `ssh-agent`
ssh-add $key
echo; echo "$0 $(date): Setting up master node"
scp -r -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no \
  ~/ves/tools/ves-setup.sh ubuntu@$master:/home/ubuntu/.
ssh -x -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no ubuntu@$master <<EOF
ves_host="$master"
export ves_host
ves_mode="guest"
export ves_mode
ves_user="hello"
export ves_user
ves_pass="world"
export ves_pass
ves_kafka_host="$master"
export ves_kafka_host
bash ves-setup.sh collector
bash ves-setup.sh kafka
bash ves-setup.sh collectd
bash ves-setup.sh agent
EOF

for worker in $workers; do
  echo; echo "$0 $(date): Setting up collectd at $worker"
  scp -r -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no \
    ubuntu@$master:/tmp/ves/ves_env.sh ~/.
  ssh -x -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no \
    ubuntu@$worker mkdir /tmp/ves
  scp -r -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no \
    ~/ves_env.sh ubuntu@$worker:/tmp/ves/.
  scp -r -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no \
    ~/ves/tools/ves-setup.sh ubuntu@$worker:/home/ubuntu/.
  ssh -x -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no \
    ubuntu@$worker bash ves-setup.sh collectd
  ssh -x -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no \
    ubuntu@$worker bash ves-setup.sh agent
done

echo "VES Grafana dashboards are available at http://$master:3001 (login as admin/admin)"
