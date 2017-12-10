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
#. What this is: Setup script for the VES monitoring framework.
#. With this script VES support can be installed in one or more hosts, with:
#. - a dedicated or shared Kafka server for collection of events from collectd
#. - VES collectd agents running in host or guest mode
#. - VES monitor (test collector)
#. - Influxdb service (if an existing service is not passed as an option)
#. - Grafana service (if an existing service is not passed as an option)
#. - VES monitor (test collector)
#.  A typical multi-node install could involve these steps:
#.  - Install the VES collector (for testing) on one of the hosts, or use a
#.    pre-installed VES collector e.g. from the ONAP project.
#.  - Install Kafka server on one of the hosts, or use a pre-installed server
#.    accessible from the agent hosts.
#.  - Install collectd on each host.
#.  - Install the VES agent on one of the hosts.
#.
#. Prerequisites:
#. - Ubuntu Xenial (Centos support to be provided)
#. - passwordless sudo setup for user running this script
#. - shell environment variables setup as below (for non-default setting)
#.   ves_mode: install mode (node|guest) for VES collectd plugin (default: node)
#.   ves_host: VES collector IP or hostname (default: 127.0.0.1)
#.   ves_port: VES collector port (default: 30000)
#.   ves_path: REST path optionalRoutingPath element (default: empty)
#.   ves_topic: REST path topicName element (default: empty)
#.   ves_https: use HTTPS instead of HTTP (default: false)
#.   ves_user: username for basic auth with collector (default: empty)
#.   ves_pass: password for basic auth with collector (default: empty)
#.   ves_interval: frequency in sec for collectd data reports (default: 20)
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
#.   bash ~/ves/ves-setup.sh <collector|kafka|collectd|agent> [cloudify]
#.     collector: setup VES collector (test collector) 
#.     kafka: setup kafka server for VES events from collect agent(s)
#.     collectd: setup collectd with libvirt plugin, as a kafka publisher
#.     agent: setup VES agent in host or guest mode, as a kafka consumer
#.     cloudify: (optional) use cloudify to deploy the component, as setup by
#.       tools/cloudify/k8s-cloudify.sh in the OPNFV Models repo.
#.   bash ~/ves/ves-setup.sh <master> <workers>
#.     master: VES master node IP
#.     workers: quoted, space-separated list of worker node IPs
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
  cat <<'EOF' >~/ves/tools/ves_env.sh
#!/bin/bash
ves_mode="${ves_mode:=node}"
ves_host="${ves_host:=127.0.0.1}"
ves_port="${ves_port:=30000}"
ves_path="${ves_path:=}"
ves_topic="${ves_topic:=}"
ves_https="${ves_https:=false}"
ves_user="${ves_user:=}"
ves_pass="${ves_pass:=}"
ves_interval="${ves_interval:=20}"
ves_version="${ves_version:=5.1}"
ves_kafka_host="${ves_kafka_host:=127.0.0.1}"
ves_kafka_hostname="${ves_kafka_hostname:=localhost}"
ves_kafka_port="${ves_kafka_port:=9092}"
ves_influxdb_host="${ves_influxdb_host:=localhost:8086}"
ves_influxdb_auth="${ves_influxdb_auth:=}"
ves_grafana_host="${ves_grafana_host:=localhost:3000}"
ves_grafana_auth="${ves_grafana_auth:=admin:admin}"
ves_loglevel="${ves_loglevel:=}"
ves_cloudtype="${ves_cloudtype:=kubernetes}"
export ves_mode
export ves_host
export ves_port
export ves_path
export ves_topic
export ves_https
export ves_user
export ves_pass
export ves_interval
export ves_kafka_host
export ves_kafka_hostname
export ves_kafka_port
export ves_influxdb_host
export ves_influxdb_auth
export ves_grafana_host
export ves_grafana_auth
export ves_loglevel
export ves_cloudtype
EOF

  source ~/ves/tools/ves_env.sh
  echo ~/ves/tools/ves_env.sh
}

function setup_kafka() {
  log "setup kafka server"
  common_prereqs

  log "install kafka prerequisites"
    if [[ "$dist" == "ubuntu" ]]; then
    sudo apt-get install -y default-jre
    sudo apt-get install -y zookeeperd
    sudo apt-get install -y python-pip
  else
    # per http://aurora.apache.org/documentation/0.12.0/installing/#centos-7
    sudo yum install -y https://archive.cloudera.com/cdh5/one-click-install/redhat/7/x86_64/cloudera-cdh-5-0.x86_64.rpm
    # TODO: Barometer guide: Java 1.7 is needed for Kafka
    sudo yum install -y java-1.7.0-openjdk
    # TODO: Barometer guide: both packages and init needed
    sudo yum install -y zookeeper zookeeper-server
    sudo service zookeeper-server init
    sudo zookeeper-server start
    sudo yum install -y python-pip
  fi
  sudo pip install kafka-python

  setup_env

  cd ~
  ver="0.11.0.2"
  log "get and unpack kafka_2.11-$ver.tgz"
  wget "http://www-eu.apache.org/dist/kafka/$ver/kafka_2.11-$ver.tgz"
  tar -xvzf kafka_2.11-$ver.tgz

  log "set delete.topic.enable=true"
  sed -i -- 's/#delete.topic.enable=true/delete.topic.enable=true/' \
    kafka_2.11-$ver/config/server.properties
  grep delete.topic.enable kafka_2.11-$ver/config/server.properties
  # TODO: Barometer VES guide to clarify hostname must be in /etc/hosts
  sudo nohup kafka_2.11-$ver/bin/kafka-server-start.sh \
    kafka_2.11-$ver/config/server.properties >kafka.log 2>&1 &
}

function setup_collectd() {
  log "setup collectd"

  common_prereqs
  source ~/ves/tools/ves_env.sh

  log "setup VES collectd config for VES $ves_mode mode"
  mkdir ~/collectd
  if [[ "$ves_mode" == "node" ]]; then
#    # TODO: fix for journalctl -xe report "... is marked executable"
#    sudo chmod 744 /etc/systemd/system/collectd.service

    cat <<EOF >~/collectd/collectd.conf
# for VES plugin
LoadPlugin logfile
<Plugin logfile>
  LogLevel debug
  File STDOUT
  Timestamp true
  PrintSeverity false
</Plugin>

LoadPlugin csv
<Plugin csv>
 DataDir "/work-dir/collectd/install/var/lib/csv"
 StoreRates false
</Plugin>

LoadPlugin target_set
LoadPlugin match_regex
<Chain "PreCache">
  <Rule "mark_memory_as_host">
    <Match "regex">
      Plugin "^memory$"
    </Match>
    <Target "set">
      PluginInstance "host"
    </Target>
  </Rule>
</Chain>

LoadPlugin cpu
<Plugin cpu>
  ReportByCpu true
  ReportByState true
  ValuesPercentage true
</Plugin>

LoadPlugin interface
LoadPlugin memory
LoadPlugin load
LoadPlugin disk
# TODO: how to set this option only to apply to VMs (not nodes)
LoadPlugin uuid

LoadPlugin write_kafka
<Plugin write_kafka>
  Property "metadata.broker.list" "$ves_kafka_host:$ves_kafka_port"
  <Topic "collectd">
    Format JSON
  </Topic>
</Plugin>
EOF

    if [[ -d /etc/nova ]]; then
      cat <<EOF >>~/collectd/collectd.conf
LoadPlugin virt
<Plugin virt>
  Connection "qemu:///system"
  RefreshInterval 60
  HostnameFormat uuid
  PluginInstanceFormat name
  ExtraStats "cpu_util"
</Plugin>
EOF
    fi
  else
    cat <<EOF >~/collectd/collectd.conf
# for VES plugin
LoadPlugin logfile
<Plugin logfile>
  LogLevel debug
  File STDOUT
  Timestamp true
  PrintSeverity false
</Plugin>

LoadPlugin cpu
<Plugin cpu>
  ReportByCpu true
  ReportByState true
  ValuesPercentage true
</Plugin>

LoadPlugin csv
<Plugin csv>
        DataDir "/tmp"
</Plugin>

LoadPlugin interface
LoadPlugin memory
LoadPlugin load
LoadPlugin disk
LoadPlugin uuid

LoadPlugin write_kafka
<Plugin write_kafka>
  Property "metadata.broker.list" "$ves_kafka_host:$ves_kafka_port"
  <Topic "collectd">
    Format JSON
  </Topic>
</Plugin>

LoadPlugin target_set
LoadPlugin match_regex
<Chain "PreCache">
  <Rule "mark_memory_as_guest">
    <Match "regex">
      Plugin "^memory$"
    </Match>
    <Target "set">
      PluginInstance "guest"
    </Target>
  </Rule>
</Chain>
EOF
  fi
  log "collectd config updated"

  if [[ $(grep -c $ves_kafka_hostname /etc/hosts) -eq 0 ]]; then
    log "add to /etc/hosts: $ves_kafka_host $ves_kafka_hostname"
    echo "$ves_kafka_host $ves_kafka_hostname" | sudo tee -a /etc/hosts
  fi

  log "start Barometer container"
  sudo docker run -tid --net=host --name ves-barometer \
    -v ~/collectd:/opt/collectd/etc/collectd.conf.d \
    -v /var/run:/var/run -v /tmp:/tmp --privileged \
    opnfv/barometer:latest /run_collectd.sh
}

function setup_agent() {
  log "setup VES agent"
  source ~/k8s_env.sh
  source ~/ves/tools/ves_env.sh

  log "deploy the VES agent container"
  if [[ "$1" == "cloudify" ]]; then
    cd ~/ves/tools/cloudify
    # Cloudify is deployed on the k8s master node
    manager_ip=$k8s_master
    log "copy kube config from k8s master for insertion into blueprint"
    scp -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no \
      $k8s_user@$manager_ip:/home/$k8s_user/.kube/config ves-agent/kube.config

    log "package the blueprint"
    # CLI: cfy blueprints package -o /tmp/$bp $bp
    tar ckf /tmp/blueprint.tar ves-agent

    log "upload the blueprint"
    # CLI: cfy blueprints upload -t default_tenant -b $bp /tmp/$bp.tar.gz
    curl -s -X PUT -u admin:admin --header 'Tenant: default_tenant' \
      --header "Content-Type: application/octet-stream" -o /tmp/json \
      http://$manager_ip/api/v3.1/blueprints/ves-agent?application_file_name=blueprint.yaml \
      -T /tmp/blueprint.tar

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
      \"ves_kafka_port\": \"$ves_kafka_port\",
      \"ves_kafka_host\": \"$ves_kafka_host\",
      \"ves_kafka_hostname\": \"$ves_kafka_hostname\",
      \"ves_loglevel\": \"$ves_loglevel\"}"

    log "create a deployment for the blueprint"
    # CLI: cfy deployments create -t default_tenant -b $bp $bp
    curl -s -X PUT -u admin:admin --header 'Tenant: default_tenant' \
      --header "Content-Type: application/json" -o /tmp/json \
      -d "{\"blueprint_id\": \"ves-agent\", \"inputs\": $inputs}" \
      http://$manager_ip/api/v3.1/deployments/ves-agent
    sleep 10

    # CLI: cfy workflows list -d $bp

    log "install the deployment pod and service"
    # CLI: cfy executions start install -d $bp
    curl -s -X POST -u admin:admin --header 'Tenant: default_tenant' \
      --header "Content-Type: application/json" -o /tmp/json \
      -d "{\"deployment_id\":\"ves-agent\", \"workflow_id\":\"install\"}" \
      http://$manager_ip/api/v3.1/executions
  else
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
  fi

  # debug hints
  # sudo docker logs ves-agent
  # sudo docker exec -it ves-agent apt-get install -y wget
  # sudo docker exec -it ves-agent wget http://www-eu.apache.org/dist/kafka/0.11.0.2/kafka_2.11-0.11.0.2.tgz -O /opt/ves/kafka_2.11-0.11.0.2.tgz
  # sudo docker exec -it ves-agent tar -xvzf /opt/ves/kafka_2.11-0.11.0.2.tgz
  # sudo docker exec -it ves-agent kafka_2.11-0.11.0.2/bin/kafka-console-consumer.sh --zookeeper <kafka server ip>:2181 --topic collectd
  # ~/kafka_2.11-0.11.0.2/bin/kafka-console-consumer.sh --zookeeper localhost:2181 --topic collectd
}

function setup_collector() {
  log "setup collector"
  $2 $3 $4

  log "install prerequistes"
  if [[ "$dist" == "ubuntu" ]]; then
    sudo apt-get install -y jq
  else
    sudo yum install -y jq
  fi

  setup_env

  if ! curl http://$ves_influxdb_host/ping ; then
    # TODO: migrate to deployment via Helm
    log "setup influxdb container"
    sudo docker run -d --name=ves-influxdb -p 8086:8086 influxdb
    status=$(sudo docker inspect ves-influxdb | jq -r '.[0].State.Status')
    while [[ "x$status" != "xrunning" ]]; do
      log "InfluxDB container state is ($status)"
      sleep 10
      status=$(sudo docker inspect ves-influxdb | jq -r '.[0].State.Status')
    done
    log "InfluxDB container state is $status"

    log "wait for InfluxDB API to be active"
    while ! curl http://$ves_influxdb_host/ping ; do
      log "InfluxDB API is not yet responding... waiting 10 seconds"
      sleep 10
    done
  fi
  echo "ves_influxdb_host=$ves_influxdb_host"

  log "setup InfluxDB database"
  # TODO: check if pre-existing and skip
  curl -X POST http://$ves_influxdb_host/query \
    --data-urlencode "q=CREATE DATABASE veseventsdb"

  if ! curl http://$ves_grafana_host ; then
    # TODO: migrate to deployment via Helm
    log "install Grafana container"
    sudo docker run -d --name ves-grafana -p 3000:3000 grafana/grafana
    status=$(sudo docker inspect ves-grafana | jq -r '.[0].State.Status')
    while [[ "x$status" != "xrunning" ]]; do
      log "Grafana container state is ($status)"
      sleep 10
      status=$(sudo docker inspect ves-grafana | jq -r '.[0].State.Status')
    done
    log "Grafana container state is $status"
    echo "ves_grafana_host=$ves_grafana_host"

    log "wait for Grafana API to be active"
    while ! curl http://$ves_grafana_host ; do
      log "Grafana API is not yet responding... waiting 10 seconds"
      sleep 10
    done
  fi

  log "add VESEvents datasource to Grafana at http://$ves_grafana_auth@$ves_grafana_host"
  # TODO: check if pre-existing and skip
  cat <<EOF >~/ves/tools/grafana/datasource.json
{ "name":"VESEvents",
  "type":"influxdb",
  "access":"direct",
  "url":"http://$ves_host:8086",
  "password":"root",
  "user":"root",
  "database":"veseventsdb",
  "basicAuth":false,
  "basicAuthUser":"",
  "basicAuthPassword":"",
  "withCredentials":false,
  "isDefault":false,
  "jsonData":null
} 
EOF

  # Use /home/$USER/ instead of ~ with @
  curl -H "Accept: application/json" -H "Content-type: application/json" \
    -X POST -d @/home/$USER/ves/tools/grafana/datasource.json \
    http://$ves_grafana_auth@$ves_grafana_host/api/datasources

  log "add VES dashboard to Grafana at http://$ves_grafana_auth@$ves_grafana_host"
  curl -H "Accept: application/json" -H "Content-type: application/json" \
    -X POST \
    -d @/home/$USER/ves/tools/grafana/Dashboard.json\
    http://$ves_grafana_auth@$ves_grafana_host/api/dashboards/db	

  log "setup collector container"
  # TODO: migrate to deployment via Helm
  sudo docker run -it -d -p 30000:30000 \
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
    -e ves_loglevel=$ves_loglevel \
    --name ves-collector blsaws/ves-collector:latest

  # debug hints
  # curl 'http://172.16.0.5:8086/query?pretty=true&db=veseventsdb&q=SELECT%20moving_average%28%22load-shortterm%22%2C%205%29%20FROM%20%22load%22%20WHERE%20time%20%3E%3D%20now%28%29%20-%205m%20GROUP%20BY%20%22system%22'
  # sudo docker logs ves-collector
  # sudo docker exec -it ves-collector apt-get install -y tcpdump
  # sudo docker exec -it ves-collector tcpdump -A -v -s 0 -i any port 30000
  # curl http://$ves_host:30000
  # sudo docker exec -it ves-collector /bin/bash
}

function clean() {
  log "clean installation"
  master=$1
  workers="$2"
  source ~/k8s_env.sh

  if [[ "$master" == "$workers" ]]; then
    nodes=$master
  else
    nodes="$master $workers"
  fi

  for node in $nodes; do 
    log "remove config for VES at node $node"
    ssh -x -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no \
      $k8s_user@$node <<EOF
sudo rm -rf /home/$k8s_user/ves
sudo rm -rf /home/$k8s_user/collectd
EOF
  done

  log "VES datasources and dashboards at grafana server, if needed"
  curl -X DELETE \
    http://$ves_grafana_auth@$ves_grafana_host/api/datasources/name/VESEvents
  curl -X DELETE \
    http://$ves_grafana_auth@$ves_grafana_host/api/dashboards/db/ves-demo

  log "Remove VES containers and collectd config at master node"
  ssh -x -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no \
      $k8s_user@$master <<'EOF'
cs="ves-agent ves-collector ves-grafana ves-influxdb ves-barometer"
for c in $cs; do
  sudo docker stop $c
  sudo docker rm -v $c
done
EOF
}

function verify_veseventsdb() {
  source ~/k8s_env.sh
  for host in $1; do
    uuid=$(ssh -x -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no $k8s_user@$host sudo cat /sys/class/dmi/id/product_uuid)
    echo "$host=$uuid"
    result=$(curl -G "http://$ves_influxdb_host/query?pretty=true" --data-urlencode "db=veseventsdb" --data-urlencode "q=SELECT moving_average(\"$3\", 5) FROM \"$2\" WHERE (\"system\" =~ /^($uuid)$/) AND time >= now() - 5m" | jq -r '.results[0].series')
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

case "$1" in
  "collectd")
    setup_collectd
    ;;
  "agent")
    setup_agent $2
    ;;
  "collector")
    setup_collector
    ;;
  "kafka")
    setup_kafka 
    ;;
  "verify")
    verify_veseventsdb "$1" "load" "load-shortterm"
    ;;
  "clean")
    clean $2 "$3"
    ;;
  *)
    grep '#. ' $0
esac
