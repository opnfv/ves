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
#. What this is: Complete scripted deployment of the VES monitoring framework.
#. Intended to be invoked from a server used to manage the nodes where the VES
#. framework is to be installed, referred to here as the "admin server". When
#. complete, the following will be installed:
#.  - On the specified master node, a Kafka server and containers running the
#.    VES "core components" (OPNFV Barometer VES agent, OPNFV VES collector,
#.    and optionally InfluxDB and Grafana if pre-existing instances of those
#.    components are not accessible at the default or provided hosts as
#.    described below).
#.    "master" as used here refers to the node where these common VES framework
#.    elements are deployed. It may typically be a master/control plane node
#.    for a set of nodes, but can also be any other node.
#.  - On each specified worker node, collectd configured per OPNFV Barometer
#.
#. Prerequisites:
#. - Ubuntu Xenial host for the admin server
#. - Ubuntu Xenial server for master and worker nodes
#. - Password-less ssh key provided for node setup
#. - hostname of selected master node in DNS or /etc/hosts
#. - env variables set prior to running this script, as per ves-setup.sh
#.     ves_kafka_hostname: hostname of the node where the kafka server runs
#. - optional env varibles set prior to running this script, as per ves-setup.sh
#.     ves_influxdb_host: ip:port of the influxdb service
#.     ves_influxdb_auth: authentication for the influxdb service
#.     ves_grafana_host: ip:port of the grafana service
#.     ves_grafana_auth: authentication for the grafana service
#.     ves_loglevel: loglevel for VES Agent and Collector (ERROR|DEBUG)
#.
#. For deployment in a kubernetes cluster as setup by OPNFV Models scripts:
#. - k8s cluster setup as in OPNFV Models repo tools/kubernetes/demo_deploy.sh
#.   which also allows use of Cloudify to deploy VES core services as
#.   k8s services.
#.
#. Usage: on the admin server
#. $ git clone https://gerrit.opnfv.org/gerrit/ves ~/ves
#. $ bash ~/ves/tools/demo_deploy.sh <key> <master> <workers> [cloudify]
#.   <key>: SSH key enabling password-less SSH to nodes
#.   <master>: master node where core components will be installed
#.   <workers>: list of worker nodes where collectd will be installed
#.   cloudify: flag indicating to deploy VES core services via Cloudify

key=$1
master=$2
workers="$3"
cloudify=$4

eval `ssh-agent`
ssh-add $key

echo; echo "$0 $(date): Setting up master node"
ssh -x -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no \
  ubuntu@$master sudo rm -rf /tmp/ves
scp -r -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no \
  ~/ves ubuntu@$master:/tmp
ssh -x -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no \
  ubuntu@$master <<EOF
  ves_host=$master
  export ves_host
  ves_mode=node
  export ves_mode
  ves_user=hello
  export ves_user
  ves_pass=world
  export ves_pass
  ves_kafka_host=$master
  export ves_kafka_host
  ves_kafka_hostname=$ves_kafka_hostname
  export ves_kafka_hostname
  ves_influxdb_host=$ves_influxdb_host
  export ves_influxdb_host
  ves_influxdb_auth=$ves_influxdb_auth
  export ves_influxdb_auth
  ves_grafana_host=$ves_grafana_host
  export ves_grafana_host
  ves_grafana_auth=$ves_grafana_auth
  export ves_grafana_auth
  ves_loglevel=$ves_loglevel
  export ves_loglevel
  env | grep ves
  bash /tmp/ves/tools/ves-setup.sh collector
  bash /tmp/ves/tools/ves-setup.sh kafka
  bash /tmp/ves/tools/ves-setup.sh agent $cloudify
EOF

scp -r -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no \
  ubuntu@$master:/tmp/ves/ves_env.sh ~/ves/.

echo; echo "$0 $(date): VES Grafana dashboards are available at http://$master:3001 (login as admin/admin)"

nodes="$master $workers"
for node in $nodes; do
  echo; echo "$0 $(date): Setting up collectd at $node"
  if [[ "$node" != "$master" ]]; then
    scp -r -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no \
      ~/ves ubuntu@$node:/tmp
  fi
  ssh -x -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no \
    ubuntu@$node <<EOF > /dev/null 2>&1 &
  ves_kafka_host=$master
  export ves_kafka_host
  ves_kafka_hostname=$ves_kafka_hostname
  export ves_kafka_hostname
  ves_collectd=build
  export ves_collectd
  bash /tmp/ves/tools/ves-setup.sh collectd
EOF
done
