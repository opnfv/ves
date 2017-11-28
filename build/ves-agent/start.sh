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
#. What this is: Startup script for the OPNFV VES Agent running under docker.

echo "$ves_kafka_host $ves_kafka_hostname" >>/etc/hosts
echo "ves_kafka_hostname=$ves_kafka_hostname"
echo "*** /etc/hosts ***"
cat /etc/hosts

cd /opt/ves/barometer/3rd_party/collectd-ves-app/ves_app
cat <<EOF >ves_app_config.conf
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

cat ves_app_config.conf
echo "ves_mode=$ves_mode"

if [[ "$ves_loglevel" == "" ]]; then 
  ves_loglevel=ERROR
fi

python ves_app.py --events-schema=$ves_mode.yaml --loglevel $ves_loglevel \
  --config=ves_app_config.conf

# Dump ves_app.log if the command above exits (fails)
echo "*** ves_app.log ***"
cat ves_app.log
