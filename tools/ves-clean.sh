#!/bin/bash
# Copyright 2017-2018 AT&T Intellectual Property, Inc
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
#. What this is: Cleanup script for the VES monitoring framework.
#. With this script a VES deployment can be cleaned from one or more hosts.
#.
#. Prerequisites:
#. - VES framework deployed as in ves-setup.sh in this repo
#.
#. Usage:
#.   bash ~/ves/ves-setup.sh clean <what> [cloudify]
#.     what: one of all|influxdb|grafana|collector|kafka|collectd|agent|nodes
#.     barometer: clean barometer
#.     agent: clean VES agent
#.     kafka: clean kafka
#.     zookeeper: clean zookeeper
#.     grafana: clean grafana 
#.     influxdb: clean influxdb 
#.     collector: clean VES collector
#.     nodes: clean VES code etc at nodes
#.     cloudify: (optional) clean up cloudify-based deployments
#.
#.   See demo_deploy.sh in this repo for a recommended sequence of the above.
#.
#. Status: this is a work in progress, under test.

# http://docs.opnfv.org/en/latest/submodules/barometer/docs/release/userguide/collectd.ves.userguide.html

function fail() {
  log "$1"
  exit 1
}

function log() {
  f=$(caller 0 | awk '{print $2}')
  l=$(caller 0 | awk '{print $1}')
  echo ""
  echo "$f:$l ($(date)) $1"
}

function clean_all() {
  log "clean installation"
  clean_barometer
  clean_agent
  clean_kafka
  clean_zookeeper
  clean_grafana
  clean_influxdb
  clean_collector
  clean_nodes  
}

function clean_via_docker() {
  log "clean docker container $1 at k8s master $k8s_master"
  ssh -x -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no \
    $k8s_user@$k8s_master <<EOF
sudo docker stop $1
sudo docker rm -v $1
EOF
}

function clean_via_cloudify() {
  log "clean $1 via cloudify"
  bash ~/models/tools/cloudify/k8s-cloudify.sh stop $1 $1
}


function clean_grafana() {
  log "clean grafana"

  log "VES datasources and dashboards at grafana server, if needed"
  curl -X DELETE \
    http://$ves_grafana_auth@$ves_grafana_host:$ves_grafana_port/api/datasources/name/VESEvents
  curl -X DELETE \
    http://$ves_grafana_auth@$ves_grafana_host:$ves_grafana_port/api/dashboards/db/ves-demo

  clean_via_docker ves-grafana
}

function clean_influxdb() {
  log "clean influxdb"
  clean_via_docker ves-influxdb
}

function clean_agent() {
  log "clean ves-agent"
  if [[ "$cloudify" == "cloudify" ]]; then
    clean_via_cloudify ves-agent
    force_k8s_clean ves-agent
  else
    clean_via_docker ves-agent
  fi
}

function clean_kafka() {
  log "clean ves-kafka"
  if [[ "$cloudify" == "cloudify" ]]; then
    clean_via_cloudify ves-kafka
    force_k8s_clean ves-kafka
  else
    clean_via_docker ves-kafka
  fi
}

function clean_zookeeper() {
  log "clean ves-zookeeper"
  if [[ "$cloudify" == "cloudify" ]]; then
    clean_via_cloudify ves-zookeeper
    force_k8s_clean ves-zookeeper
  else
    clean_via_docker ves-zookeeper
  fi
}

function clean_collector() {
  log "clean ves-zookeeper"
  if [[ "$cloudify" == "cloudify" ]]; then
    clean_via_cloudify ves-collector
    force_k8s_clean ves-collector
  else
    clean_via_docker ves-collector
  fi
}

function clean_barometer() {
  log "clean ves-barometer"
  ssh -x -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no \
kubectl delete daemonset --namespace default ves-barometer
EOF
  force_k8s_clean ves-barometer
}

function clean_nodes() {
  log "clean ves code etc from nodes"
  if [[ "$k8s_master" == "$k8s_workers" ]]; then
    nodes=$k8s_master
  else
    nodes="$k8s_master $k8s_workers"
  fi
  for node in $nodes; do 
    log "remove ves-barometer container and config for VES at node $node"
    ssh -x -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no \
      $k8s_user@$node <<EOF
sudo rm -rf /home/$k8s_user/ves
sudo rm -rf /home/$k8s_user/collectd
EOF
  done
}

function force_k8s_clean() {
  log "force cleanup of k8s pod for $1 if still present"
  ssh -x -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no \
    $k8s_user@$k8s_master "kubectl delete pods --namespace default $1-pod"
  pods=$(ssh -x -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no $k8s_user@$k8s_master kubectl get pods --namespace default | grep -c $1)
  echo "wait for all kubectl pods to be terminated"
  tries=10
  while [[ $pods -gt 0 && $tries -gt 0 ]]; do
    echo "$pods VES pods remaining in kubectl"
    sleep 30
    ((tries--))
    pods=$(ssh -x -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no $k8s_user@$k8s_master kubectl get pods --namespace default | grep -c $1)
  done
  if [[ $pods -gt 0 ]]; then
    log "manually terminate $1 pods via docker"
    cs=$(ssh -x -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no $k8s_user@$k8s_master sudo docker ps -a | awk "/$1/ {print $1}") 
    for c in $cs ; do
      ssh -x -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no $k8s_user@$k8s_master "sudo docker stop $c"
      ssh -x -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no $k8s_user@$k8s_master "sudo docker rm -v $c"
    done
  fi
}

dist=$(grep --m 1 ID /etc/os-release | awk -F '=' '{print $2}' | sed 's/"//g')
if [[ $(grep -c $HOSTNAME /etc/hosts) -eq 0 ]]; then 
  echo "$(ip route get 8.8.8.8 | awk '{print $NF; exit}') $HOSTNAME" |\
    sudo tee -a /etc/hosts
fi

source ~/k8s_env.sh
if [[ -f ~/ves/tools/ves_env.sh ]]; then
  source ~/ves/tools/ves_env.sh
fi
log "VES environment as input"
env | grep ves_

trap 'fail' ERR

cloudify=$2

case "$1" in
  "all")
    clean_all
    ;;
  "modes")
    clean_nodes
    ;;
  "collectd")
    clean_collectd
    ;;
  "agent")
    clean_agent
    ;;
  "influxdb")
    clean_influxdb
    ;;
  "grafana")
    clean_grafana
    ;;
  "collector")
    clean_collector
    ;;
  "kafka")
    clean_kafka
    ;;
  *)
    grep '#. ' $0
esac
trap '' ERR
