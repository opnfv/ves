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
# What this is: A Dockerfile for building an OPFNV VES Agent container image.
#
# Status: this is a work in progress, under test.
#

FROM ubuntu:xenial

MAINTAINER Bryan Sullivan

RUN apt-get update
RUN apt-get install -y apt-utils
RUN apt-get -y upgrade
RUN apt-get update
RUN apt-get install -y git

# Required for VES collector
RUN apt-get install -y python-pip python-jsonschema
RUN pip install requests

RUN mkdir /opt/ves

# Clone VES Collector
RUN git clone https://github.com/att/evel-test-collector.git /opt/ves/evel-test-collector

COPY monitor.py /opt/ves/evel-test-collector/code/collector/monitor.py
COPY start.sh /opt/ves/start.sh
ENTRYPOINT ["/bin/bash", "/opt/ves/start.sh"]
