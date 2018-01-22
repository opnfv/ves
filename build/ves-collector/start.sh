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
#. What this is: Startup script for the OPNFV VES Collector running under docker.

cd /opt/ves
touch monitor.log

sed -i -- \
  "s~log_file = /var/log/att/collector.log~log_file = /opt/ves/collector.log~" \
  evel-test-collector/config/collector.conf
sed -i -- "s/vel_domain = 127.0.0.1/vel_domain = $ves_host/g" \
  evel-test-collector/config/collector.conf
sed -i -- "s/vel_port = 30000/vel_port = $ves_port/g" \
  evel-test-collector/config/collector.conf
sed -i -- "s/vel_username =/vel_username = $ves_user/g" \
  evel-test-collector/config/collector.conf
sed -i -- "s/vel_password =/vel_password = $ves_pass/g" \
  evel-test-collector/config/collector.conf
sed -i -- "s~vel_path = vendor_event_listener/~vel_path = $ves_path~g" \
  evel-test-collector/config/collector.conf
sed -i -- "s~vel_topic_name = example_vnf~vel_topic_name = $ves_topic~g" \
  evel-test-collector/config/collector.conf
sed -i -- "/vel_topic_name = /a influxdb = $ves_influxdb_host:$ves_influxdb_port" \
  evel-test-collector/config/collector.conf

echo; echo "evel-test-collector/config/collector.conf"
cat evel-test-collector/config/collector.conf

echo; echo "wait for InfluxDB API at $ves_influxdb_host:$ves_influxdb_port"
while ! curl http://$ves_influxdb_host:$ves_influxdb_port/ping ; do
  echo "InfluxDB API is not yet responding... waiting 10 seconds"
  sleep 10
done

echo; echo "setup veseventsdb in InfluxDB"
# TODO: check if pre-existing and skip
curl -X POST http://$ves_influxdb_host:$ves_influxdb_port/query \
  --data-urlencode "q=CREATE DATABASE veseventsdb"

echo; echo "wait for Grafana API to be active"
while ! curl http://$ves_grafana_host:$ves_grafana_port ; do
  echo "Grafana API is not yet responding... waiting 10 seconds"
  sleep 10
done

echo; echo "add VESEvents datasource to Grafana"
# TODO: check if pre-existing and skip
cat <<EOF >/opt/ves/datasource.json
{ "name":"VESEvents",
  "type":"influxdb",
  "access":"direct",
  "url":"http://$ves_influxdb_host:$ves_influxdb_port",
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

curl -H "Accept: application/json" -H "Content-type: application/json" \
  -X POST -d @/opt/ves/datasource.json \
  http://$ves_grafana_auth@$ves_grafana_host:$ves_grafana_port/api/datasources

echo; echo "add VES dashboard to Grafana"
curl -H "Accept: application/json" -H "Content-type: application/json" \
  -X POST -d @/opt/ves/Dashboard.json \
  http://$ves_grafana_auth@$ves_grafana_host:$ves_grafana_port/api/dashboards/db	

if [[ "$ves_loglevel" != "" ]]; then 
  python /opt/ves/evel-test-collector/code/collector/monitor.py \
    --config /opt/ves/evel-test-collector/config/collector.conf \
    --influxdb $ves_influxdb_host:$ves_influxdb_port \
    --section default > /opt/ves/monitor.log 2>&1
else
  python /opt/ves/evel-test-collector/code/collector/monitor.py \
    --config /opt/ves/evel-test-collector/config/collector.conf \
    --influxdb $ves_influxdb_host:$ves_influxdb_port \
    --section default
fi
