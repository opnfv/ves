#!/bin/bash
# Copyright 2016 AT&T Intellectual Property, Inc
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
# What this is: Startup script for a simple web server as part of the
# ves_onap_demo test of the OPNFV VES project.
#
# Status: this is a work in progress, under test.
#
# How to use:
# Intended to be invoked from ves_onap_demo.sh
# $ bash start.sh type params
#   type: type of VNF component [webserver|vfw|vlb|monitor|collectd]
#     webserver|vfw|vlb| params: ID CollectorIP username password
#     collector params: ID CollectorIP username password
#     monitor params: VDU1_ID VDU1_ID VDU1_ID username password
#   ID: VM ID
#   CollectorIP: IP address of the collector
#   username: Username for Collector RESTful API authentication
#   password: Password for Collector RESTful API authentication

setup_collectd () {
  guest=$1
  echo "$0: Install prerequisites"
  dist=`grep DISTRIB_ID /etc/*-release | awk -F '=' '{print $2}'`
  if [ "$dist" == "Ubuntu" ]; then
    conf="/etc/collectd/collectd.conf"
  else
    conf="/etc/collectd.conf"
  fi

  if [ "$dist" == "Ubuntu" ]; then
    sudo apt-get update
    sudo apt-get install -y collectd
  else
    sudo yum update -y
    sudo yum install -y epel-release
    sudo yum install -y collectd
    sudo yum install -y collectd-virt
  fi
  cd ~

  echo "$0: Install VES collectd plugin"
  # this is a clone of barometer patch https://gerrit.opnfv.org/gerrit/#/c/35489
  git clone https://gerrit.opnfv.org/gerrit/barometer
  cd barometer
  git pull https://gerrit.opnfv.org/gerrit/barometer refs/changes/89/35489/2
  cd ..

  sudo sed -i -- "s/FQDNLookup true/FQDNLookup false/" $conf
  sudo sed -i -- "s/#LoadPlugin cpu/LoadPlugin cpu/" $conf
  sudo sed -i -- "s/#LoadPlugin disk/LoadPlugin disk/" $conf
  sudo sed -i -- "s/#LoadPlugin interface/LoadPlugin interface/" $conf
  sudo sed -i -- "s/#LoadPlugin memory/LoadPlugin memory/" $conf


  cat <<EOF | sudo tee -a $conf
<LoadPlugin python>
  Globals true
</LoadPlugin>
<Plugin python>
  ModulePath "/home/$USER/barometer/3rd_party/collectd-ves-plugin/ves_plugin/"
  LogTraces true
  Interactive false
  Import "ves_plugin"
<Module ves_plugin>
  Domain "$collector_ip"
  Port 30000
  Path ""
  Topic ""
  UseHttps false
  Username "hello"
  Password "world"
  FunctionalRole "Collectd VES Agent"
</Module>
</Plugin>
LoadPlugin virt
<Plugin virt>
        Connection "qemu:///system"
        RefreshInterval 60
        HostnameFormat name uuid
</Plugin>
<Plugin cpu>
        ReportByCpu false
        ValuesPercentage true
</Plugin>
LoadPlugin aggregation
<Plugin aggregation>
        <Aggregation>
                Plugin "cpu"
                Type "percent"
                GroupBy "Host"
                GroupBy "TypeInstance"
                SetPlugin "cpu-aggregation"
                CalculateAverage true
        </Aggregation>
</Plugin>
LoadPlugin uuid
EOF
  sudo service collectd restart
}

vnfc_common() {
  echo "$0: Install prerequisites"
  sudo apt-get update
  sudo apt-get install -y gcc
  # NOTE: force is required as some packages can't be authenticated...
  sudo apt-get install -y --force-yes libcurl4-openssl-dev
  sudo apt-get install -y make

  echo "$0: Clone agent library"
  cd /home/ubuntu
  rm -rf evel-library
  git clone https://github.com/att/evel-library.git

  echo "$0: Update EVEL_API version (workaround until the library is updated)"
  sed -i -- "s/#define EVEL_API_MAJOR_VERSION 3/#define EVEL_API_MAJOR_VERSION 5/" evel-library/code/evel_library/evel.h
  sed -i -- "s/#define EVEL_API_MINOR_VERSION 0/#define EVEL_API_MINOR_VERSION 0/" evel-library/code/evel_library/evel.h
}

setup_vFW () {
  vnfc_common

  echo "$0: Build evel_library agent"
  cd ~/evel-library/bldjobs
  make
  export LD_LIBRARY_PATH=$LD_LIBRARY_PATH:/home/ubuntu/evel-library/libs/x86_64

  echo "$0: Build agent"
  cd ~/tosca-vnfd-onap-demo/vFW
  make

  echo "$0: Start agent"
  vnic=$(route | grep '^default' | grep -o '[^ ]*$')
  id=$(cut -d ',' -f 3 /mnt/openstack/latest/meta_data.json | cut -d '"' -f 4)
  echo "$0: Starting vpp_measurement_reporter $id $collector_ip 30000 $username $password $vnic vLB"  
  nohup ~/tosca-vnfd-onap-demo/vFW/vpp_measurement_reporter $id $collector_ip 30000 $username $password $vnic vFW -x > /dev/null 2>&1 &
}

setup_vLB () {
  vnfc_common

  echo "$0: Build evel_library agent"
  cd ~/evel-library/bldjobs
  make
  export LD_LIBRARY_PATH=$LD_LIBRARY_PATH:/home/ubuntu/evel-library/libs/x86_64

  # TODO: Currently using a single agent for both vFW and vLB as it's all common
  # except for DNS-related aspects not yet implemented.
  echo "$0: Build agent"
  cd ~/tosca-vnfd-onap-demo/vFW
  make

  echo "$0: Start agent"
  vnic=$(route | grep '^default' | grep -o '[^ ]*$')
  id=$(cut -d ',' -f 3 /mnt/openstack/latest/meta_data.json | cut -d '"' -f 4)
  echo "$0: Starting vpp_measurement_reporter $id $collector_ip 30000 $username $password $vnic vLB"  
  nohup ~/tosca-vnfd-onap-demo/vFW/vpp_measurement_reporter $id $collector_ip 30000 $username $password $vnic vLB -x > /dev/null 2>&1 &
}

setup_webserver () {
  vnfc_common

  echo "$0: Use ves_onap_demo blueprint version of agent_demo.c"
  cp ~/tosca-vnfd-onap-demo/evel_demo.c ~/evel-library/code/evel_demo/evel_demo.c

  echo "$0: Build agent"
  cd ~/evel-library/bldjobs
  make
  export LD_LIBRARY_PATH=$LD_LIBRARY_PATH:/home/ubuntu/evel-library/libs/x86_64

  echo "$0: Start agent"
  id=$(cut -d ',' -f 3 /mnt/openstack/latest/meta_data.json | cut -d '"' -f 4)
  nohup ../output/x86_64/evel_demo --id $id --fqdn $collector_ip --port 30000 --username $username --password $password -x > ~/evel_demo.log 2>&1 &
}

setup_monitor () {
  echo "$0: setup VES Monitor"
  echo "$0: install dependencies"
  # Note below: python (2.7) is required due to dependency on module 'ConfigParser'
  sudo apt-get update
  sudo apt-get upgrade -y
  sudo apt-get install -y python python-jsonschema

  echo "$0: setup VES Monitor config"
  sudo mkdir /var/log/att
  sudo chown ubuntu /var/log/att
  touch /var/log/att/monitor.log
  sudo chown ubuntu /home/ubuntu/
  cd /home/ubuntu/
  git clone https://github.com/att/evel-test-collector.git
  sed -i -- "s/vel_username =/vel_username = $username/g" evel-test-collector/config/collector.conf
  sed -i -- "s/vel_password =/vel_password = $password/g" evel-test-collector/config/collector.conf
  sed -i -- "s~vel_path = vendor_event_listener/~vel_path = ~g" evel-test-collector/config/collector.conf
  sed -i -- "s/vel_topic_name = example_vnf/vel_topic_name = /g" evel-test-collector/config/collector.conf
  sed -i -- "/vel_topic_name = /a vdu4_id = $vdu4_id" evel-test-collector/config/collector.conf
  sed -i -- "/vel_topic_name = /a vdu3_id = $vdu3_id" evel-test-collector/config/collector.conf
  sed -i -- "/vel_topic_name = /a vdu2_id = $vdu2_id" evel-test-collector/config/collector.conf
  sed -i -- "/vel_topic_name = /a vdu1_id = $vdu1_id" evel-test-collector/config/collector.conf

  echo "$0: install influxdb and python influxdb library"
  sudo apt-get install -y influxdb
  sudo service influxdb start
  sudo apt-get install -y python-influxdb

  echo "$0: install grafana"
  sudo apt-get install -y grafana
  sudo service grafana-server start
  sudo update-rc.d grafana-server defaults

  echo "$0: Setup InfluxDB datatabase"
  python tosca-vnfd-onap-demo/infsetup.py

  echo "$0: Add datasource to grafana"
  curl http://admin:admin@localhost:3000/api/datasources
  curl -H "Accept: application/json" -H "Content-type: application/json" -X POST -d '{"name":"VESEvents","type":"influxdb","access":"direct","url":"http://localhost:8086","password":"root","user":"root","database":"veseventsdb","basicAuth":false,"basicAuthUser":"","basicAuthPassword":"","withCredentials":false,"isDefault":false,"jsonData":null}' \
    http://admin:admin@localhost:3000/api/datasources

  echo "$0: Import Dashboard.json into grafana"
  curl -H "Accept: application/json" -H "Content-type: application/json" -X POST -d @tosca-vnfd-onap-demo/Dashboard.json http://admin:admin@localhost:3000/api/dashboards/db	

  cp tosca-vnfd-onap-demo/monitor.py evel-test-collector/code/collector/monitor.py
  nohup python evel-test-collector/code/collector/monitor.py --config evel-test-collector/config/collector.conf --section default > ~/monitor.log 2>&1 &
}

type=$1

if [[ "$type" == "monitor" ]]; then
  vdu1_id=$2
  vdu2_id=$3
  vdu3_id=$4
  vdu4_id=$5
  username=$6
  password=$7
else
  collector_ip=$2
  username=$3
  password=$4
fi

setup_$type $1
exit 0
