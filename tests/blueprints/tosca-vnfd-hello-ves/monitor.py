#!/usr/bin/env python
#
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
# What this is: Monitor and closed-loop policy agent as part of the OPNFV VES 
# vHello_VES demo. 
#
# Status: this is a work in progress, under test.

with open('/home/ubuntu/ves.log') as f:
  while True:
    line = f.readline()
    if line:
#      print line,
      if "requestRate" in line:
#         print line,
         rate = line[27:-2]
         print 'request rate: {0}'.format(rate)
#....5....1....5....2....5....3....5
#            "requestRate": 2264,

