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

import os
import time
import sys
import select

report_time = ""
request_rate = ""
app_state = ""
mode = "f"
summary = ""
status = ""

def print_there(x, y, text):
     sys.stdout.write("\x1b7\x1b[%d;%df%s\x1b8" % (x, y, text))
     sys.stdout.flush()

a,b = os.popen('stty size', 'r').read().split()
columns = int(b)

with open('/home/ubuntu/ves.log') as f:
  while True:
    if sys.stdin in select.select([sys.stdin], [], [], 0)[0]:
      line = sys.stdin.readline()
      if "f" in line: mode = "f"
      if "c" in line: mode = "c"
      # Update screen as the <cr> messed up the display!
      print_there(1,columns-56,summary)
      print_there(2,columns-56,status)

    line = f.readline()
    if line:
      if mode == "f": 
        print line,

      if "lastEpochMicrosec" in line:
#0....5....1....5....2....5....3....5....4....5....5
#            "lastEpochMicrosec": 1476552393091008,
# Note: the above is expected, but sometimes it's in a different position or
# corrupted with other output for some reason...

        fields = line.split( )
        e = fields[1][0:-1]
        if e.isdigit():
#          print "report_time: ", e, "\n"
          report_time = time.strftime('%Y-%m-%d %H:%M:%S', 
            time.localtime(int(e)/1000000))

      if "requestRate" in line:
#....5....1....5....2....5....3....5
#            "requestRate": 2264,
        request_rate = line[27:-2]
        summary = report_time + " app state: " + app_state + ", request rate: " + request_rate 
        print_there(1,columns-56,summary)
#2016-10-16 17:15:29 app state: Started, request rate: 99
#....5....1....5....2....5....3....5....4....5....5....5....6
        if mode == "c": print '{0} *** app state: {1}\trequest rate: {2}'.format(
          report_time, app_state, request_rate)

      if "\"specificProblem\": \"Started\"" in line:
        app_state = "Started"
        status = report_time + " app state change: Started"
        if mode == "c": print '{0} *** app state change: Started'.format(report_time)

      if "\"specificProblem\": \"Stopped\"" in line:
        app_state = "Stopped"
        status = report_time + " app state change: Stopped"
        if mode == "c": print '{0} *** app state change: Stopped'.format(report_time)

      print_there(1,columns-56,summary)
      print_there(2,columns-56,status)

