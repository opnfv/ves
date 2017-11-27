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
#. What this is: Build script for the VES Agent docker image on Ubuntu.
#.
#. Usage:
#.   bash ves-agent.sh <hub-user> <hub-pass>
#.     hub-user: username for dockerhub
#.     hub-pass: password for dockerhub
#.
#. Status: this is a work in progress, under test.

echo; echo "$0 $(date): Update package repos"
sudo apt-get update

echo; echo "$0 $(date): Starting VES agent build process"
if [[ -d /tmp/ves ]]; then rm -rf /tmp/ves; fi

echo; echo "$0 $(date): Cloning VES repo to /tmp/ves"
git clone https://gerrit.opnfv.org/gerrit/ves /tmp/ves

echo; echo "$0 $(date): Building the image"
cd /tmp/ves/build/ves-agent
sudo docker build -t ves-agent .
sudo docker login -u $1 -p $2

echo; echo "$0 $(date): Tagging the image"
id=$(sudo docker images | grep ves-agent | awk '{print $3}')
id=$(echo $id | cut -d ' ' -f 1)
sudo docker tag $id $1/ves-agent:latest

echo; echo "$0 $(date): Pushing the image to dockerhub as $1/ves-agent"
sudo docker push $1/ves-agent
