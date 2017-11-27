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
#. What this is: Startup script for the OPNFV VES Collector running under docker.

cd /opt/ves
touch monitor.log

sed -i -- \
  "s~log_file = /var/log/att/collector.log~log_file = /opt/ves/collector.log~" \
  evel-test-collector/config/collector.conf
sed -i -- "s/vel_domain = 127.0.0.1/vel_domain = $ves_host/g" \
  evel-test-collector/config/collector.conf
sed -i -- "s/vel_username =/vel_username = $ves_user/g" \
  evel-test-collector/config/collector.conf
sed -i -- "s/vel_password =/vel_password = $ves_pass/g" \
  evel-test-collector/config/collector.conf
sed -i -- "s~vel_path = vendor_event_listener/~vel_path = $ves_path~g" \
  evel-test-collector/config/collector.conf
sed -i -- "s~vel_topic_name = example_vnf~vel_topic_name = $ves_topic~g" \
  evel-test-collector/config/collector.conf
sed -i -- "/vel_topic_name = /a influxdb = $ves_influxdb_host" \
  evel-test-collector/config/collector.conf

python /opt/ves/evel-test-collector/code/collector/monitor.py \
  --config /opt/ves/evel-test-collector/config/collector.conf \
  --influxdb $ves_influxdb_host \
  --section default > /opt/ves/monitor.log 2>&1
