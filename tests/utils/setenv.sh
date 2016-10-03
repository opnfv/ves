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
# What this is: OpenStack environment file setup for OPNFV deployments. Sets up
# the environment parameters allowing use of OpenStack CLI commands, and as needed
# for OPNFV test scripts.
#
# Status: this is a work in progress, under test.
#
# How to use:
#   $ wget https://git.opnfv.org/cgit/ves/plain/tests/utils/setenv.sh -O [folder]
#   folder: folder to place the script in
#   $ source /tmp/setenv.sh [target]
#   folder: folder in which to put the created admin-openrc.sh file

# TODO: Find a more precise way to determine the OPNFV install... currently
# this assumes that the script is running on the OPNFV jumphost, and 
# Ubuntu=JOID, Centos=Apex

dist=`grep DISTRIB_ID /etc/*-release | awk -F '=' '{print $2}'`

if [ "$dist" == "Ubuntu" ]; then
  # Ubuntu: assumes JOID-based install, and that this script is being run on the jumphost.
  echo "$0: Ubuntu-based install"
  echo "$0: Create the environment file"
  KEYSTONE_HOST=$(juju status --format=short | awk "/keystone\/0/ { print \$3 }")
  cat <<EOF >$1/admin-openrc.sh
export CONGRESS_HOST=$(juju status --format=short | awk "/openstack-dashboard/ { print \$3 }")
export HORIZON_HOST=$(juju status --format=short | awk "/openstack-dashboard/ { print \$3 }")
export KEYSTONE_HOST=$KEYSTONE_HOST
export CEILOMETER_HOST=$(juju status --format=short | awk "/ceilometer\/0/ { print \$3 }")
export CINDER_HOST=$(juju status --format=short | awk "/cinder\/0/ { print \$3 }")
export GLANCE_HOST=$(juju status --format=short | awk "/glance\/0/ { print \$3 }")
export NEUTRON_HOST=$(juju status --format=short | awk "/neutron-api\/0/ { print \$3 }")
export NOVA_HOST=$(juju status --format=short | awk "/nova-cloud-controller\/0/ { print \$3 }")
export JUMPHOST=$(ifconfig brAdm | awk "/inet addr/ { print \$2 }" | sed 's/addr://g')
export OS_USERNAME=admin
export OS_PASSWORD=openstack
export OS_TENANT_NAME=admin
export OS_AUTH_URL=http://$KEYSTONE_HOST:5000/v2.0
export OS_REGION_NAME=RegionOne
EOF
else
  # Centos: assumes Apex-based install, and that this script is being run on the Undercloud controller VM.
  echo "$0: Centos-based install"
  echo "$0: Setup undercloud environment so we can get overcloud Controller server address"
  source ~/stackrc
  echo "$0: Get address of Controller node"
  export CONTROLLER_HOST1=$(openstack server list | awk "/overcloud-controller-0/ { print \$8 }" | sed 's/ctlplane=//g')
  echo "$0: Create the environment file"
  cat <<EOF >/tmp/VES/admin-openrc.sh
export HORIZON_HOST=$CONTROLLER_HOST1
export CONGRESS_HOST=$CONTROLLER_HOST1
export KEYSTONE_HOST=$CONTROLLER_HOST1
export CEILOMETER_HOST=$CONTROLLER_HOST1
export CINDER_HOST=$CONTROLLER_HOST1
export GLANCE_HOST=$CONTROLLER_HOST1
export NEUTRON_HOST=$CONTROLLER_HOST1
export NOVA_HOST=$CONTROLLER_HOST1
export JUMPHOST=$(ip addr show eth0 | grep "inet\b" | awk '{print $2}' | cut -d/ -f1)
EOF
  cat ~/overcloudrc >>$1/admin-openrc.sh
  source ~/overcloudrc
  export OS_REGION_NAME=$(openstack endpoint list | awk "/ nova / { print \$4 }")
  # sed command below is a workaound for a bug - region shows up twice for some reason
  cat <<EOF | sed '$d' $1/VES/admin-openrc.sh
export OS_REGION_NAME=$OS_REGION_NAME
EOF
fi
source $1/admin-openrc.sh
