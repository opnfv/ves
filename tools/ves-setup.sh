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
#. What this is: Setup script for VES agent framework.
#. With this script VES support can be installed in one or more hosts, with:
#. - a dedicated or shared Kafka server for collection of events from collectd
#. - VES collectd agents running in host or guest mode
#. - VES monitor (test collector)
#.  A typical multi-node install could involve these steps:
#.  - Install Kafka server on one of the hosts, or use a pre-installed server
#.    accessible from the agent hosts.
#.  - Install the VES collector (for testing) on one of the hosts, or use a
#.    pre-installed VES collector e.g. from the ONAP project.
#.  - Install the VES agent on each host.
#.  - As needed, install the VES agent on each virtual host. This could include
#.    pre-installed VES agents in VM or container images, which are configured
#.    upon virtual host deployment, or agent install/config as part of virtual
#.    host deploy. NOTE: support for pre-installed VES agents is a WIP.
#.
#. Prerequisites:
#. - Ubuntu Xenial (Centos support to be provided)
#. - passwordless sudo setup for user running this script
#. - shell environment variables setup as below (for non-default setting)
#.   ves_mode: install mode (host|guest) for VES collectd plugin (default: host)
#.   ves_host: VES collector IP or hostname (default: 127.0.0.1)
#.   ves_port: VES collector port (default: 30000)
#.   ves_path: REST path optionalRoutingPath element (default: empty)
#.   ves_topic: REST path topicName element (default: empty)
#.   ves_https: use HTTPS instead of HTTP (default: false)
#.   ves_user: username for basic auth with collector (default: empty)
#.   ves_pass: password for basic auth with collector (default: empty)
#.   ves_interval: frequency in sec for collectd data reports (default: 20)
#.   ves_version: VES API version (default: 5.1)
#.   ves_kafka_port: kafka port (default: 9092)
#.   ves_kafka_host: kafka host IP or hostname (default: 127.0.0.1)
#.
#. Usage:
#.   wget https://raw.githubusercontent.com/opnfv/ves/master/tools/ves-setup.sh
#.   bash ves-setup.sh <agent|collector|kafka>
#.     agent: setup VES agent in host or guest mode
#.     collector: setup VES collector (test collector) 
#.     kafka: setup kafka server for VES events from collect agent(s)
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
  sudo apt-get install -y default-jre
  sudo apt-get install -y zookeeperd
  sudo apt-get install -y python-pip
  sudo pip install kafka-python
}

function setup_kafka() {
  log "setup kafka server"
  common_prereqs

  log "get and unpack kafka_2.11-0.11.0.0.tgz"
  wget "http://www-eu.apache.org/dist/kafka/0.11.0.0/kafka_2.11-0.11.0.0.tgz"
  tar -xvzf kafka_2.11-0.11.0.0.tgz

  log "set delete.topic.enable=true"
  sed -i -- 's/#delete.topic.enable=true/delete.topic.enable=true/' \
    kafka_2.11-0.11.0.0/config/server.properties
  grep delete.topic.enable kafka_2.11-0.11.0.0/config/server.properties
  # TODO: Barometer VES guide to clarify hostname must be in /etc/hosts
  echo "$(ip route get 8.8.8.8 | awk '{print $NF; exit}') $HOSTNAME" |\
    sudo tee -a /etc/hosts
  sudo nohup kafka_2.11-0.11.0.0/bin/kafka-server-start.sh \
    kafka_2.11-0.11.0.0/config/server.properties \
    > kafka_2.11-0.11.0.0/kafka.log 2>&1 &
  # TODO: find a test that does not hang the script at 
  #echo "Hello, World" | kafka_2.11-0.11.0.0/bin/kafka-console-producer.sh \
  #  --broker-list localhost:9092 --topic TopicTest > /dev/null
  #kafka_2.11-0.11.0.0/bin/kafka-console-consumer.sh --zookeeper \
  #  localhost:2181 --topic TopicTest --from-beginning
}

function setup_agent() {
  log "setup agent"
  common_prereqs

  log "Install Apache Kafka C/C++ client library"
  sudo apt-get install -y build-essential
  git clone https://github.com/edenhill/librdkafka.git ~/librdkafka
  cd ~/librdkafka
  git checkout -b v0.9.5 v0.9.5
  # TODO: Barometer VES guide to clarify specific prerequisites for Ubuntu
  sudo apt-get install -y libpthread-stubs0-dev
  sudo apt-get install -y libssl-dev
  sudo apt-get install -y libsasl2-dev
  sudo apt-get install -y liblz4-dev
  ./configure --prefix=/usr
  make
  sudo make install
  log "Build collectd with Kafka support"
  git clone https://github.com/collectd/collectd.git ~/collectd
  cd ~/collectd
  # TODO: Barometer VES guide to clarify specific prerequisites for Ubuntu
  sudo apt-get install -y flex bison
  sudo apt-get install -y autoconf
  sudo apt-get install -y libtool
  ./build.sh
  ./configure --with-librdkafka=/usr --without-perl-bindings --enable-perl=no
  make
  sudo make install

  log "install VES agent prerequisites"
  sudo pip install pyyaml

  echo <<EOF >~/ves_env.sh
#!/bin/bash
: ${ves_mode="host"}
: ${ves_host="127.0.0.1"}
: ${ves_port="3000"}
: ${ves_path=""}
: ${ves_topic=""}
: ${ves_https="false"}
: ${ves_user=""}
: ${ves_pass=""}
: ${ves_interval="20"}
: ${ves_version="5.1"}
: ${ves_kafka_host="127.0.0.1"}
: ${ves_kafka_port="9092"}
export ves_mode="$ves_mode"
export ves_port="$ves_port"
export ves_path="$ves_path"
export ves_topic="$ves_topic"
export ves_https="$ves_https"
export ves_user="$ves_user"
export ves_pass="$ves_pass"
export ves_interval="$ves_interval"
export ves_kafka_host="$ves_kafka_host"
export ves_port="$ves_port"
export ves_kafka_port="$ves_kafka_port"
EOF
  source ~/ves_env.sh

  log "clone OPNFV Barometer"
  git clone https://gerrit.opnfv.org/gerrit/barometer ~/barometer

  log "setup ves_app_config.conf"
  cd ~/barometer/3rd_party/collectd-ves-app/ves_app
  echo <<EOF >ves_app_config.conf
[config]
Domain = $ves_host
Port = $ves_port
Path = $ves_path
Topic = $ves_topic
UseHttps = $ves_https
Username = $ves_user
Password = $ves_pass
SendEventInterval = $ves_interval
ApiVersion = $ves_version
KafkaPort = $ves_kafka_port
KafkaBroker = $ves_kafka_host
EOF

  log "setup VES collectd config for VES $ves_mode mode"
  if [[ "$ves_mode" == "host" ]]; then
    # TODO: Barometer VES guide to clarify prerequisites install for Ubuntu
    log "setup additional prerequisites for VES host mode"
    sudo apt-get install -y libxml2-dev libpciaccess-dev libyajl-dev \
      libdevmapper-dev

    # TODO: Barometer VES guide refers to "At least one VM instance should be 
    # up and running by hypervisor on the host." The process needs to accomodate
    # pre-installation of the VES agent *prior* to the first VM being created. 

    echo <<EOF | sudo tee -a /opt/collectd/etc/collectd.conf
LoadPlugin logfile
<Plugin logfile>
  LogLevel info
  File "/opt/collectd/var/log/collectd.log"
  Timestamp true
  PrintSeverity false
</Plugin>

LoadPlugin cpu

LoadPlugin virt
<Plugin virt>
  Connection "qemu:///system"
  RefreshInterval 60
  HostnameFormat uuid
  PluginInstanceFormat name
  ExtraStats "cpu_util"
</Plugin>

LoadPlugin write_kafka
<Plugin write_kafka>
  Property "metadata.broker.list" "$ves_kafka_host:$ves_kafka_port"
  <Topic "collectd">
    Format JSON
  </Topic>
</Plugin>
EOF
  else
    echo <<EOF | sudo tee -a /opt/collectd/etc/collectd.conf
LoadPlugin logfile
<Plugin logfile>
  LogLevel info
  File "/opt/collectd/var/log/collectd.log"
  Timestamp true
  PrintSeverity false
</Plugin>

LoadPlugin cpu

LoadPlugin virt
<Plugin virt>
  Connection "qemu:///system"
  RefreshInterval 60
  HostnameFormat uuid
  PluginInstanceFormat name
  ExtraStats "cpu_util"
</Plugin>

LoadPlugin write_kafka
<Plugin write_kafka>
  Property "metadata.broker.list" "$ves_kafka_host:$ves_kafka_port"
  <Topic "collectd">
    Format JSON
  </Topic>
</Plugin>
EOF
  fi

  log "restart collectd to apply updated config"
  sudo systemctl restart collectd

  log "start VES agent"
  nohup python ves_app.py --events-schema=$ves_mode.yaml \
    --config=ves_app_config.conf > ~/ves_app.stdout.log 2>&1 &
}

function setup_collector() {
  log "setup collector"
}

dist=`grep DISTRIB_ID /etc/*-release | awk -F '=' '{print $2}'`
case "$1" in
  "agent")
    setup_agent
    ;;
  "collector")
    setup_collector
    ;;
  "kafka")
    setup_kafka 
    ;;
  *)
    grep '#. ' $0
esac
