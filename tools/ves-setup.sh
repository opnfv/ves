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
#. What this is: Setup script for the VES monitoring framework.
#. With this script VES support can be installed in one or more hosts, with:
#. - a dedicated or shared Kafka server for collection of events from barometer
#. - VES barometer agents running in host or guest mode
#. - VES monitor (test collector)
#. - Influxdb service (if an existing service is not passed as an option)
#. - Grafana service (if an existing service is not passed as an option)
#. - VES monitor (test collector)
#.  A typical multi-node install could involve these steps:
#.  - Install the VES collector (for testing) on one of the hosts, or use a
#.    pre-installed VES collector e.g. from the ONAP project.
#.  - Install Kafka server on one of the hosts, or use a pre-installed server
#.    accessible from the agent hosts.
#.  - Install barometer on each host.
#.  - Install the VES agent on one of the hosts.
#.
#. Prerequisites:
#. - Ubuntu Xenial (Centos support to be provided)
#. - passwordless sudo setup for user running this script
#. - shell environment variables setup as below (for non-default setting)
#.   ves_mode: install mode (node|guest) for VES barometer plugin (default: node)
#.   ves_host: VES collector IP or hostname (default: 127.0.0.1)
#.   ves_port: VES collector port (default: 3001)
#.   ves_path: REST path optionalRoutingPath element (default: empty)
#.   ves_topic: REST path topicName element (default: empty)
#.   ves_https: use HTTPS instead of HTTP (default: false)
#.   ves_user: username for basic auth with collector (default: empty)
#.   ves_pass: password for basic auth with collector (default: empty)
#.   ves_interval: frequency in sec for barometer data reports (default: 20)
#.   ves_version: VES API version (default: 5.1)
#.   ves_kafka_host: kafka host IP (default: 127.0.0.1)
#.   ves_kafka_hostname: kafka host hostname (default: localhost)
#.   ves_kafka_port: kafka port (default: 9092)
#.   ves_influxdb_host: influxdb host:port (default: none)
#.   ves_influxdb_auth: credentials in form "user/pass" (default: none)
#.   ves_grafana_host: grafana host:port (default: none)
#.   ves_grafana_auth: credentials in form "user/pass" (default: admin/admin)
#.   ves_loglevel: loglevel for VES Agent and Collector (ERROR|DEBUG)
#.
#. Usage:
#.   git clone https://gerrit.opnfv.org/gerrit/ves ~/ves
#.   bash ~/ves/tools/ves-setup.sh <what> [cloudify]
#.     what: one of env|influxdb|grafana|collector|zookeeper|kafka|agent|barometer
#.     env: setup VES environment script ~/ves/tools/ves_env.sh 
#.     influxdb: setup influxdb as a docker container on k8s_master node 
#.     grafana: setup grafana as a docker container on k8s_master node 
#.     collector: setup VES collector (test collector) 
#.     zookeeper: setup zookeeper server for kafka configuration
#.     kafka: setup kafka server for VES events from collect agent(s)
#.     agent: setup VES agent in host or guest mode, as a kafka consumer
#.     barometer: setup barometer with libvirt plugin, as a kafka publisher
#.     cloudify: (optional) use cloudify to deploy the component, as setup by
#.       tools/cloudify/k8s-cloudify.sh in the OPNFV Models repo.
#.
#.   The recommended sequence for setting up the components is:
#.     influxdb: prerequisite for grafana datasource setup
#.     grafana:  prerequisite for setup of datasource and dashboards
#.     collector: creates veseventsdb in influxdb, and grafana 
#.       datasource/dashboards, then starts listening for VES event reports
#.     zookeeper: prerequisite for kafka
#.     kafka: prerequisite for agent and barometer
#.     agent: listens for collectd topic events over kafka, for reporting to collector
#.     barometer: monitors resources and reports via collectd topic in kafka
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

function common_prereqs() {
  log "install common prerequisites"
    if [[ "$dist" == "ubuntu" ]]; then
    sudo apt-get update
    sudo apt-get install -y git wget
  else
    sudo yum update -y
    sudo yum install -y git wget
  fi
}

function setup_env() {
  log "updating VES environment variables"
  cat <<EOF >~/ves/tools/ves_env.sh
#!/bin/bash
ves_mode="${ves_mode:=node}"
ves_host="${ves_host:=ves-collector-service.default.svc.cluster.local}"
ves_hostname="${ves_hostname:=ves-collector-service.default.svc.cluster.local}"
ves_port="${ves_port:=3001}"
ves_path="${ves_path:=}"
ves_topic="${ves_topic:=}"
ves_https="${ves_https:=false}"
ves_user="${ves_user:=}"
ves_pass="${ves_pass:=}"
ves_interval="${ves_interval:=20}"
ves_version="${ves_version:=5.1}"
ves_zookeeper_host="${ves_zookeeper_host:=ves-zookeeper-service.default.svc.cluster.local}"
ves_zookeeper_hostname="${ves_zookeeper_hostname:=ves-zookeeper-service.default.svc.cluster.local}"
ves_zookeeper_host="${ves_zookeeper_host:=ves-zookeeper-service.default.svc.cluster.local}"
ves_zookeeper_port="${ves_zookeeper_port:=2181}"
ves_kafka_host="${ves_kafka_host:=ves-kafka-service.default.svc.cluster.local}"
ves_kafka_hostname="${ves_kafka_hostname:=ves-kafka-service.default.svc.cluster.local}"
ves_kafka_port="${ves_kafka_port:=9092}"
ves_influxdb_host="${ves_influxdb_host:=ves-influxdb-service.default.svc.cluster.local}"
ves_influxdb_hostname="${ves_influxdb_hostname:=ves-influxdb-service.default.svc.cluster.local}"
ves_influxdb_port="${ves_influxdb_port:=8086}"
ves_influxdb_auth="${ves_influxdb_auth:=}"
ves_grafana_host="${ves_grafana_host:=ves-grafana-service.default.svc.cluster.local}"
ves_grafana_hostname="${ves_grafana_hostname:=ves-grafana-service.default.svc.cluster.local}"
ves_grafana_port="${ves_grafana_port:=3000}"
ves_grafana_auth="${ves_grafana_auth:=admin:admin}"
ves_loglevel="${ves_loglevel:=DEBUG}"
ves_cloudtype="${ves_cloudtype:=kubernetes}"
export ves_mode
export ves_host
export ves_hostname
export ves_port
export ves_path
export ves_topic
export ves_https
export ves_user
export ves_pass
export ves_interval
export ves_version
export ves_zookeeper_host
export ves_zookeeper_hostname
export ves_zookeeper_port
export ves_kafka_host
export ves_kafka_hostname
export ves_kafka_port
export ves_influxdb_host
export ves_influxdb_hostname
export ves_influxdb_port
export ves_influxdb_auth
export ves_grafana_host
export ves_grafana_hostname
export ves_grafana_port
export ves_grafana_auth
export ves_loglevel
export ves_cloudtype
EOF

  source ~/ves/tools/ves_env.sh
  env | grep ves_
}

function update_env() {
  log "update VES environment with $1=$2"
  eval ${1}=${2}
  export $1
  sed -i -- "s/.*$1=.*/$1=$2/" ~/ves/tools/ves_env.sh
  env | grep ves_
}

function setup_kafka() {
  log "setup kafka server"
  log "deploy zookeeper and kafka"
  if [[ "$1" == "cloudify" ]]; then
    cp -r ~/ves/tools/cloudify/ves-zookeeper ~/models/tools/cloudify/blueprints/.
    source ~/models/tools/cloudify/k8s-cloudify.sh start ves-zookeeper ves-zookeeper
    source ~/models/tools/cloudify/k8s-cloudify.sh clusterIp ves-zookeeper
    update_env ves_zookeeper_host $clusterIp

    cp -r ~/ves/tools/cloudify/ves-kafka ~/models/tools/cloudify/blueprints/.
    inputs="{ \
      \"zookeeper_hostname\": \"$ves_zookeeper_hostname\",
      \"zookeeper_host\": \"$ves_zookeeper_host\",
      \"zookeeper_port\": \"$ves_zookeeper_port\",
      \"kafka_port\": \"$ves_kafka_port\",
      \"kafka_hostname\": \"$ves_kafka_hostname\"}"

    source ~/models/tools/cloudify/k8s-cloudify.sh start ves-kafka ves-kafka "$inputs"
    source ~/models/tools/cloudify/k8s-cloudify.sh clusterIp ves-kafka
    update_env ves_kafka_host $clusterIp
  else
    ssh -x -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no \
       $k8s_user@$k8s_master <<EOF
sudo docker run -it -d -p $ves_zookeeper_port:2181 --name ves-zookeeper zookeeper
sudo docker run -it -d -p $ves_kafka_port:9092 --name ves-kafka \
  -e zookeeper_hostname=$ves_zookeeper_hostname \
  -e kafka_hostname=$ves_kafka_hostname \
  -e zookeeper_host=$ves_zookeeper_host \
  -e zookeeper_port=$ves_zookeeper_port \
  -e kafka_port=$ves_kafka_port \
  -e kafka_hostname=$ves_kafka_hostname \
  blsaws/ves-kafka:latest
EOF
  fi
}

function setup_barometer() {
  log "setup barometer"
#  if [[ $(grep -c $ves_kafka_hostname /etc/hosts) -eq 0 ]]; then
#    log "add to /etc/hosts: $ves_kafka_host $ves_kafka_hostname"
#    echo "$ves_kafka_host $ves_kafka_hostname" | sudo tee -a /etc/hosts
#  fi

  log "start Barometer container as daemonset under kubernetes"
  ssh -x -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no \
    $k8s_user@$k8s_master <<EOF
sed -i -- "s/<ves_mode>/$ves_mode/" \
  /home/$k8s_user/ves/tools/kubernetes/ves-barometer/daemonset.yaml
sed -i -- "s/<ves_kafka_hostname>/$ves_kafka_hostname/" \
  /home/$k8s_user/ves/tools/kubernetes/ves-barometer/daemonset.yaml
sed -i -- "s/<ves_kafka_port>/$ves_kafka_port/" \
  /home/$k8s_user/ves/tools/kubernetes/ves-barometer/daemonset.yaml
kubectl create \
  -f /home/$k8s_user/ves/tools/kubernetes/ves-barometer/daemonset.yaml
EOF
  
#  sudo docker run -tid --net=host --name ves-barometer \
#    -v ~/collectd:/opt/collectd/etc/collectd.conf.d \
#    -v /var/run:/var/run -v /tmp:/tmp --privileged \
#    opnfv/barometer:latest /run_collectd.sh
}

function setup_agent() {
  log "setup VES agent"

  log "deploy the VES agent container"
  if [[ "$1" == "cloudify" ]]; then
    cp -r ~/ves/tools/cloudify/ves-agent ~/models/tools/cloudify/blueprints/.
    inputs="{ \
      \"ves_mode\": \"$ves_mode\",
      \"ves_host\": \"$ves_host\",
      \"ves_port\": \"$ves_port\",
      \"ves_path\": \"$ves_path\",
      \"ves_topic\": \"$ves_topic\",
      \"ves_https\": \"$ves_https\",
      \"ves_user\": \"$ves_user\",
      \"ves_pass\": \"$ves_pass\",
      \"ves_interval\": \"$ves_interval\",
      \"ves_version\": \"$ves_version\", 
      \"ves_kafka_hostname\": \"$ves_kafka_hostname\",
      \"ves_kafka_host\": \"$ves_kafka_host\",
      \"ves_kafka_port\": \"$ves_kafka_port\",
      \"ves_loglevel\": \"$ves_loglevel\"}"

    bash ~/models/tools/cloudify/k8s-cloudify.sh start ves-agent ves-agent "$inputs"
  else
    ssh -x -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no \
       $k8s_user@$k8s_master <<EOF
sudo docker run -it -d \
  -e ves_mode=$ves_mode \
  -e ves_host=$ves_host  \
  -e ves_port=$ves_port \
  -e ves_path=$ves_path \
  -e ves_topic=$ves_topic \
  -e ves_https=$ves_https \
  -e ves_user=$ves_user \
  -e ves_pass=$ves_pass \
  -e ves_interval=$ves_interval \
  -e ves_version=$ves_version \
  -e ves_kafka_port=$ves_kafka_port \
  -e ves_kafka_host=$ves_kafka_host \
  -e ves_kafka_hostname=$ves_kafka_hostname \
  -e ves_loglevel=$ves_loglevel \
  --name ves-agent blsaws/ves-agent:latest
EOF
  fi

  # debug hints
  # sudo docker logs ves-agent
  # sudo docker exec -it ves-agent apt-get install -y wget
  # sudo docker exec -it ves-agent wget http://www-eu.apache.org/dist/kafka/0.11.0.2/kafka_2.11-0.11.0.2.tgz -O /opt/ves/kafka_2.11-0.11.0.2.tgz
  # sudo docker exec -it ves-agent tar -xvzf /opt/ves/kafka_2.11-0.11.0.2.tgz
  # sudo docker exec -it ves-agent kafka_2.11-0.11.0.2/bin/kafka-console-consumer.sh --zookeeper <kafka server ip>:2181 --topic collectd
  # ~/kafka_2.11-0.11.0.2/bin/kafka-console-consumer.sh --zookeeper localhost:2181 --topic collectd
}

function setup_influxdb() {
  log "setup influxdb"
  log "install prerequistes"
  if [[ "$dist" == "ubuntu" ]]; then
    sudo apt-get install -y jq
  else
    sudo yum install -y jq
  fi

  log "checking for influxdb at http://$ves_influxdb_host:$ves_influxdb_port/ping"
  if ! curl http://$ves_influxdb_host:$ves_influxdb_port/ping ; then
    log "install influxdb container on k8s master"
    update_env ves_influxdb_host $k8s_master
    update_env ves_influxdb_hostname $k8s_master_hostname
    ssh -x -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no \
      $k8s_user@$k8s_master \
      sudo docker run -d --name=ves-influxdb -p 8086:8086 influxdb
    ssh -x -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no \
      $k8s_user@$k8s_master <<'EOF'
status=$(sudo docker inspect ves-influxdb | jq -r '.[0].State.Status')
while [[ "x$status" != "xrunning" ]]; do
  echo; echo "InfluxDB container state is ($status)"
  sleep 10
  status=$(sudo docker inspect ves-influxdb | jq -r '.[0].State.Status')
done
echo; echo "InfluxDB container state is $status"
EOF
  fi
}

function setup_grafana() {
  log "setup grafana"
  log "checking for grafana at http://$ves_grafana_host:$ves_grafana_port"
  if ! curl http://$ves_grafana_host:$ves_grafana_port ; then
    log "install Grafana container on k8s master"
    update_env ves_grafana_host $k8s_master
    update_env ves_grafana_hostname $k8s_master_hostname
    ssh -x -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no \
      $k8s_user@$k8s_master \
      sudo docker run -d --name ves-grafana -p 3000:3000 grafana/grafana
    ssh -x -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no \
      $k8s_user@$k8s_master <<'EOF'
status=$(sudo docker inspect ves-grafana | jq -r '.[0].State.Status')
while [[ "x$status" != "xrunning" ]]; do
  echo; echo "Grafana container state is ($status)"
  sleep 10
status=$(sudo docker inspect ves-grafana | jq -r '.[0].State.Status')
done
echo; echo "Grafana container state is $status"
EOF
  fi
}

function setup_collector() {
  log "setup collector"
  if [[ "$1" == "cloudify" ]]; then
    cp -r ~/ves/tools/cloudify/ves-collector ~/models/tools/cloudify/blueprints/.
    inputs="{ \
      \"ves_host\": \"$ves_host\",
      \"ves_port\": \"$ves_port\",
      \"ves_path\": \"$ves_path\",
      \"ves_topic\": \"$ves_topic\",
      \"ves_https\": \"$ves_https\",
      \"ves_user\": \"$ves_user\",
      \"ves_pass\": \"$ves_pass\",
      \"ves_interval\": \"$ves_interval\",
      \"ves_version\": \"$ves_version\", 
      \"ves_influxdb_host\": \"$ves_influxdb_host\",
      \"ves_influxdb_port\": \"$ves_influxdb_port\",
      \"ves_grafana_host\": \"$ves_grafana_host\",
      \"ves_grafana_port\": \"$ves_grafana_port\",
      \"ves_grafana_auth\": \"$ves_grafana_auth\",
      \"ves_loglevel\": \"$ves_loglevel\"}"

    source ~/models/tools/cloudify/k8s-cloudify.sh start \
      ves-collector ves-collector "$inputs"
    source ~/models/tools/cloudify/k8s-cloudify.sh clusterIp ves-collector
    update_env ves_host $clusterIp
    log "updated VES env"; env | grep ves
  else
    ssh -x -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no \
       $k8s_user@$k8s_master <<EOF
sudo docker run -it -d -p 3001:3001 \
  -e ves_host=$ves_host  \
  -e ves_port=$ves_port \
  -e ves_path=$ves_path \
  -e ves_topic=$ves_topic \
  -e ves_https=$ves_https \
  -e ves_user=$ves_user \
  -e ves_pass=$ves_pass \
  -e ves_interval=$ves_interval \
  -e ves_version=$ves_version \
  -e ves_influxdb_host=$ves_influxdb_host \
  -e ves_grafana_port=$ves_grafana_port \
  -e ves_grafana_host=$ves_grafana_host \
  -e ves_grafana_auth=$ves_grafana_auth \
  -e ves_loglevel=$ves_loglevel \
  --name ves-collector blsaws/ves-collector:latest
EOF
  fi

  # debug hints
  # curl 'http://172.16.0.5:30886/query?pretty=true&db=veseventsdb&q=SELECT%20moving_average%28%22load-shortterm%22%2C%205%29%20FROM%20%22load%22%20WHERE%20time%20%3E%3D%20now%28%29%20-%205m%20GROUP%20BY%20%22system%22'
  # sudo docker logs ves-collector
  # sudo docker exec -it ves-collector apt-get install -y tcpdump
  # sudo docker exec -it ves-collector tcpdump -A -v -s 0 -i any port 3001
  # curl http://$ves_host:3001
  # sudo docker exec -it ves-collector /bin/bash
}

function verify_veseventsdb() {
  log "VES environment as set by ves_env.sh"
  env | grep ves

  for host in $1; do
    uuid=$(ssh -x -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no $k8s_user@$host sudo cat /sys/class/dmi/id/product_uuid)
    echo "$host=$uuid"
    result=$(curl -G "http://$ves_influxdb_host:$ves_influxdb_port/query?pretty=true" --data-urlencode "db=veseventsdb" --data-urlencode "q=SELECT moving_average(\"$3\", 5) FROM \"$2\" WHERE (\"system\" =~ /^($uuid)$/) AND time >= now() - 5m" | jq -r '.results[0].series')
    if [[ "$result" != "null" ]]; then
      echo "$host load data found in influxdb"
    else
      echo "$host load data NOT found in influxdb"
    fi
  done
}

dist=$(grep --m 1 ID /etc/os-release | awk -F '=' '{print $2}' | sed 's/"//g')
if [[ $(grep -c $HOSTNAME /etc/hosts) -eq 0 ]]; then 
  echo "$(ip route get 8.8.8.8 | awk '{print $NF; exit}') $HOSTNAME" |\
    sudo tee -a /etc/hosts
fi

source ~/k8s_env_$k8s_master_hostname.sh
if [[ -f ~/ves/tools/ves_env.sh ]]; then
  source ~/ves/tools/ves_env.sh
fi
log "VES environment as input"
env | grep ves_

trap 'fail' ERR

case "$1" in
  "env")
    setup_env
    ;;
  "barometer")
    setup_barometer
    ;;
  "agent")
    setup_agent $2
    ;;
  "influxdb")
    setup_influxdb
    ;;
  "grafana")
    setup_grafana
    ;;
  "collector")
    setup_collector $2
    ;;
  "kafka")
    setup_kafka $2
    ;;
  "verify")
    verify_veseventsdb "$1" load load-shortterm
    ;;
  *)
    grep '#. ' $0
esac
trap '' ERR
