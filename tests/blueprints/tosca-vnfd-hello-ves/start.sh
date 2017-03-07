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
# vHello_VES test of the OPNFV VES project.
#
# Status: this is a work in progress, under test.
#
# How to use:
# Intended to be invoked from vHello_VES.sh
# $ bash start.sh type params
#   type: type of VNF component [monitor|collectd]
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
  git clone https://git.opnfv.org/barometer

  sudo sed -i -- "s/FQDNLookup true/FQDNLookup false/" $conf
  sudo sed -i -- "s/#LoadPlugin cpu/LoadPlugin cpu/" $conf
  sudo sed -i -- "s/#LoadPlugin disk/LoadPlugin disk/" $conf
  sudo sed -i -- "s/#LoadPlugin interface/LoadPlugin interface/" $conf
  sudo sed -i -- "s/#LoadPlugin memory/LoadPlugin memory/" $conf

  if [[ "$guest" == true ]]; then
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
  GuestRunning true
</Module>
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
  else 
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
  GuestRunning false
</Module>
</Plugin>
LoadPlugin virt
<Plugin virt>
        Connection "qemu:///system"
        RefreshInterval 60
        HostnameFormat uuid
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
  fi
  sudo service collectd restart
}

setup_agent () {
  echo "$0: Install prerequisites"
  sudo apt-get install -y gcc
  # NOTE: force is required as some packages can't be authenticated...
  sudo apt-get install -y --force-yes libcurl4-openssl-dev
  sudo apt-get install -y make

  echo "$0: Clone agent library"
  cd /home/ubuntu
  git clone https://github.com/att/evel-library.git

  echo "$0: Clone VES repo"
  git clone https://gerrit.opnfv.org/gerrit/ves

  echo "$0: Use vHello_VES blueprint version of agent_demo.c"
  cp ves/tests/blueprints/tosca-vnfd-hello-ves/evel_demo.c evel-library/code/evel_demo/evel_demo.c
  
  echo "$0: Update parameters and build agent demo"
  # This sed command will add a line after the search line 
  sed -i -- "s/api_port,/30000,/" evel-library/code/evel_demo/evel_demo.c
  sed -i -- "/api_secure,/{n;s/.*/                      \"$username\",/}" evel-library/code/evel_demo/evel_demo.c
  sed -i -- "/\"$username\",/{n;s/.*/                      \"$password\",/}" evel-library/code/evel_demo/evel_demo.c

  echo "$0: Build evel_demo agent"
  cd evel-library/bldjobs
  make
  export LD_LIBRARY_PATH=$LD_LIBRARY_PATH:/home/ubuntu/evel-library/libs/x86_64
  
  echo "$0: Start evel_demo agent"
  id=$(cut -d ',' -f 3 /mnt/openstack/latest/meta_data.json | cut -d '"' -f 4)
  nohup ../output/x86_64/evel_demo --id $id --fqdn $collector_ip --port 30000 --username $username --password $password > /dev/null 2>&1 &

  echo "$0: Start collectd agent running in the VM"
  setup_collectd true
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
  touch /var/log/att/collector.log
  sudo chown ubuntu /home/ubuntu/
  cd /home/ubuntu/
  git clone https://github.com/att/evel-test-collector.git
  sed -i -- "s/vel_username = /vel_username = $1/" evel-test-collector/config/collector.conf
  sed -i -- "s/vel_password = /vel_password = $2/" evel-test-collector/config/collector.conf
  sed -i -- "s~vel_path = vendor_event_listener/~vel_path = ~" evel-test-collector/config/collector.conf
  sed -i -- "s/vel_topic_name = example_vnf/vel_topic_name = /" evel-test-collector/config/collector.conf
  sed -i -- "/vel_topic_name = /a vdu3_id = $vdu3_id" evel-test-collector/config/collector.conf
  sed -i -- "/vel_topic_name = /a vdu2_id = $vdu2_id" evel-test-collector/config/collector.conf
  sed -i -- "/vel_topic_name = /a vdu1_id = $vdu1_id" evel-test-collector/config/collector.conf

  cp monitor.py evel-test-collector/code/collector/monitor.py
#  python evel-test-collector/code/collector/monitor.py --config evel-test-collector/config/collector.conf --section default 
}

type=$1

if [[ "$type" == "monitor" ]]; then
  vdu1_id=$2
  vdu2_id=$3
  vdu3_id=$4
  username=$5
  password=$6
else
  vm_id=$2
  collector_ip=$3
  username=$4
  password=$5
fi

setup_$type $1
exit 0
