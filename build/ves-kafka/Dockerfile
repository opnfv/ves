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
# What this is: A Dockerfile for building a kafka server for use by the OPFNV
# VES framework.
#
# Status: this is a work in progress, under test.
#

FROM ubuntu:xenial

MAINTAINER Bryan Sullivan

RUN apt-get update
RUN apt-get install -y apt-utils
RUN apt-get upgrade -y
RUN apt-get update
# Required for kafka
RUN apt-get install -y default-jre
RUN apt-get install -y python-pip
RUN pip install kafka-python
RUN apt-get install -y wget

RUN mkdir /opt/ves

RUN cd /opt/ves; \
wget http://www-eu.apache.org/dist/kafka/0.11.0.2/kafka_2.11-0.11.0.2.tgz; \
tar -xvzf kafka_2.11-0.11.0.2.tgz; \
sed -i -- 's/#delete.topic.enable=true/delete.topic.enable=true/' \
  kafka_2.11-0.11.0.2/config/server.properties

COPY start.sh /opt/ves/start.sh
ENTRYPOINT ["/bin/bash", "/opt/ves/start.sh"]
