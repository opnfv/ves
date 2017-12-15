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
#. What this is: Startup script for a kafka server as used by the OPNFV VES
#. framework.

echo "$zookeeper $zookeeper_host" >>/etc/hosts
cat /etc/hosts
cd /opt/ves

sed -i "s/localhost:2181/$zookeeper_host:2181/" \
  kafka_2.11-0.11.0.2/config/server.properties
grep 2181 kafka_2.11-0.11.0.2/config/server.properties
sed -i "s~#advertised.listeners=PLAINTEXT://your.host.name:9092~advertised.listeners=PLAINTEXT://$kafka_hostname:9092~" \
  kafka_2.11-0.11.0.2/config/server.properties
grep advertised.listeners kafka_2.11-0.11.0.2/config/server.properties

kafka_2.11-0.11.0.2/bin/kafka-server-start.sh \
  kafka_2.11-0.11.0.2/config/server.properties

