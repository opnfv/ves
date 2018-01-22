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
#. - Ubuntu Xenial or Centos 7 server for master and worker nodes
#. - Password-less ssh key provided for node setup
#. - hostname of selected master node in DNS or /etc/hosts
#. - env variables set prior to running this script, as per ves-setup.sh
#.     ves_kafka_hostname: hostname of the node where the kafka server runs
#. - optional env varibles set prior to running this script, as per ves-setup.sh
#.     ves_host: ip of the VES collector service
#.     ves_zookeeper_host: ip of the zookeeper service
#.     ves_zookeeper_port: port of the zookeeper service
#.     ves_kafka_host: ip of the kafka service
#.     ves_kafka_port: port of the kafka service
#.     ves_port: port of the VES collector service
#.     ves_influxdb_host: ip of the influxdb service
#.     ves_influxdb_port: port of the influxdb service
#.     ves_influxdb_auth: authentication for the influxdb service
#.     ves_grafana_host: ip of the grafana service
#.     ves_grafana_port: port of the grafana service
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
#. $ cd ~/ves/tools
#. $ bash demo_deploy.sh <user> <master> [cloudify]
#.   <user>: username on node with password-less SSH authorized
#.   <master>: hostname of k8s master node
#.   cloudify: flag indicating to deploy VES core services via Cloudify

trap 'fail' ERR

function fail() {
  log $1
  exit 1
}

function log() {
  f=$(caller 0 | awk '{print $2}')
  l=$(caller 0 | awk '{print $1}')
  echo; echo "$f:$l ($(date)) $1"
}

function run() {
  log "$1"
  start=$((`date +%s`/60))
  $1
  step_end "$1"
}

function step_end() {
  end=$((`date +%s`/60))
  runtime=$((end-start))
  log "step \"$1\" duration = $runtime minutes"
}

function run_master() {
  log "$1"
  start=$((`date +%s`/60))
  ssh -x -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no \
    $k8s_user@$k8s_master "$1"
  step_end "$1"
}

function deploy() {
  if [[ -f ~/ves/tools/ves_env.sh ]]; then rm ~/ves/tools/ves_env.sh; fi
  ves_host=$ves_host
  ves_port=$ves_port
  ves_mode=node
  ves_user=hello
  ves_pass=world
  ves_kafka_host=$ves_kafka_host
  ves_kafka_hostname=$ves_kafka_hostname
  ves_zookeeper_host=$ves_zookeeper_host
  ves_zookeeper_port=$ves_zookeeper_port
  ves_influxdb_host=$ves_influxdb_host
  ves_influxdb_port=$ves_influxdb_port
  ves_influxdb_auth=$ves_influxdb_auth
  ves_grafana_host=$ves_grafana_host
  ves_grafana_port=$ves_grafana_port
  ves_grafana_auth=$ves_grafana_auth
  ves_loglevel=$ves_loglevel
  source ~/ves/tools/ves-setup.sh env
  env | grep ves_ >~/ves/tools/ves_env.sh
  for var in $vars; do echo "export $var" | tee -a ~/ves/tools/ves_env.sh; done

  log "Setting up master node"
  run_master "mkdir /home/$user/ves"
  scp -r -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no \
    ~/ves/tools $user@$master:/home/$user/ves
  run "bash ves/tools/ves-setup.sh collector $cloudify"
  run "bash ves/tools/ves-setup.sh kafka $cloudify"
  run "bash ves/tools/ves-setup.sh agent $cloudify"

  if [[ "$k8s_master" == "$k8s_workers" ]]; then
    nodes=$k8s_master
  else
    nodes="$k8s_master $k8s_workers"
  fi

  for node in $nodes; do
    log "Setting up collectd at $node"
    if [[ "$node" != "$k8s_master" ]]; then
      ssh -x -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no \
        $user@$node mkdir /home/$user/ves
      scp -r -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no \
       ~/ves/tools $user@$node:/home/$user/ves
    fi
    run "bash ves/tools/ves-setup.sh collectd"
EOF
  done

  source ~/ves/tools/ves_env.sh
  log "VES Grafana dashboards are available at http://$ves_grafana_host:$ves_grafana_port (login as admin/admin)"
}

deploy_start=$((`date +%s`/60))
user=$1
master=$2
cloudify=$3
source ~/k8s_env_$master.sh
log "k8s environment as input"
env | grep k8s
eval `ssh-agent`
ssh-add $k8s_key
deploy
