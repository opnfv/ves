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
RUN apt-get install -y git
# Required for kafka
RUN apt-get install -y default-jre
RUN apt-get install -y zookeeperd
RUN apt-get install -y python-pip
RUN pip install kafka-python
# Required for building collectd
RUN apt-get install -y pkg-config

RUN mkdir /opt/ves

# Build Kafka client
RUN apt-get install -y build-essential
RUN apt-get install -y libpthread-stubs0-dev
RUN apt-get install -y libssl-dev
RUN apt-get install -y libsasl2-dev
RUN apt-get install -y liblz4-dev
RUN /bin/bash -c 'git clone --branch v0.9.5 \
https://github.com/edenhill/librdkafka.git /opt/ves/librdkafka; \
cd /opt/ves/librdkafka; ./configure --prefix=/usr; \
make; make install'

# Install VES Agent
RUN pip install pyaml

RUN git clone https://gerrit.opnfv.org/gerrit/barometer /opt/ves/barometer
# Test patch
RUN /bin/bash -c 'cd /opt/ves/barometer; \
git fetch https://gerrit.opnfv.org/gerrit/barometer \
refs/changes/27/47427/1 && git checkout FETCH_HEAD'

COPY start.sh /opt/ves/start.sh
ENTRYPOINT ["/bin/bash", "/opt/ves/start.sh"]
