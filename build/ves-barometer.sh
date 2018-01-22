#!/bin/bash
# Copyright 2018 AT&T Intellectual Property, Inc
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
#. What this is: Build script for the OPNFV Barometer collectd agent docker image.
#.
#. Prerequisites:
#.   Docker hub user logged in e.g. via "sudo docker login"
#.
#. Usage:
#.   bash ves-barometer.sh <hub-user> [--no-cache]
#.     hub-user: username for dockerhub
#.     --no-cache
#.
#. NOTE: To allow patch testing, this script will not reclone the VES repo
#. if it exists under /tmp
#.
#. Status: this is a work in progress, under test.

cache="$2"
echo; echo "$0 $(date): Update package repos"
sudo apt-get update

echo; echo "$0 $(date): Starting VES agent build process"
if [[ ! -d /tmp/ves ]]; then
  echo; echo "$0 $(date): Cloning VES repo to /tmp/ves"
  git clone https://gerrit.opnfv.org/gerrit/ves /tmp/ves
fi

echo; echo "$0 $(date): Building the image"
cd /tmp/ves/build/ves-barometer
sudo docker build $cache -t ves-barometer .

echo; echo "$0 $(date): Tagging the image"
id=$(sudo docker images | grep ves-barometer | awk '{print $3}')
id=$(echo $id | cut -d ' ' -f 1)
sudo docker tag $id $1/ves-barometer:latest

echo; echo "$0 $(date): Pushing the image to dockerhub as $1/ves-barometer"
sudo docker push $1/ves-barometer
