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
# What this is: Enhancements to the OpenStack Interop Challenge "Lampstack"
# blueprint to add OPNFV VES event capture.
#
# Status: this is a work in progress, under test.
#
# How to use:
#   $ bash vLamp_Ansible_VES.sh

echo "$0: Add ssh key"
eval $(ssh-agent -s)
ssh-add /tmp/ansible/ansible

echo "$0: setup OpenStack environment"
source /tmp/ansible/admin-openrc.sh

$BALANCER=$(openstack server show balancer | awk "/ addresses / { print \$6 }")
sudo cp /tmp/ansible/ansible /tmp/ansible/lampstack
sudo chown $USER /tmp/ansible/lampstack
ssh -i /tmp/ansible/lampstack ubuntu@$BALANCER

#  scp -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no ~/congress/env.sh $CTLUSER@$CONTROLLER_HOST1:/home/$CTLUSER/congress

echo "$0: Enable haproxy logging"
# Example /var/log/haproxy.log entries after logging enabled
# Oct  6 20:03:34 balancer haproxy[2075]: 192.168.37.199:36193 [06/Oct/2016:20:03:34.349] webfarm webfarm/ws10.0.0.9 107/0/1/1/274 304 144 - - ---- 1/1/1/0/0 0/0 "GET /wp-content/themes/iribbon/elements/lib/images/boxes/slidericon.png HTTP/1.1"
# Oct  6 20:03:34 balancer haproxy[2075]: 192.168.37.199:36194 [06/Oct/2016:20:03:34.365] webfarm webfarm/ws10.0.0.10 95/0/0/1/258 304 144 - - ---- 0/0/0/0/0 0/0 "GET /wp-content/themes/iribbon/elements/lib/images/boxes/blueprint.png HTTP/1.1"
ssh -x -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no ubuntu@$BALANCER <<EOF
sudo sed -i -- 's/#$ModLoad imudp/$ModLoad imudp/g' /etc/rsyslog.conf
sudo sed -i -- 's/#$UDPServerRun 514/$UDPServerRun 514\n$UDPServerAddress 127.0.0.1/g' /etc/rsyslog.conf
sudo service rsyslog restart
EOF
