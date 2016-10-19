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

from wsgiref.simple_server import make_server, WSGIRequestHandler
import sys
import os
import platform
import traceback
import time
from argparse import ArgumentParser, ArgumentDefaultsHelpFormatter
import ConfigParser
import logging.handlers
from base64 import b64decode
import string
import json
import jsonschema
import select

report_time = ''
requestRate = ''
monitor_mode = "f"
summary = ['***** Summary of key stats *****','','','']
status = ['','unknown','unknown','unknown']
vdu = 0
base_url = ''
template_404 = b'''POST {0}'''
columns = 0
rows = 0

class JSONObject:
  def __init__(self, d):
    self.__dict__ = d

class NoLoggingWSGIRequestHandler(WSGIRequestHandler):
  def log_message(self, format, *args):
    pass

def print_there(x, y, text):
  sys.stdout.write("\x1b7\x1b[%d;%df%s\x1b8" % (x, y, text))
  sys.stdout.flush()

base_url = ''
template_404 = b'''POST {0}'''

def notfound_404(environ, start_response):
  print('Unexpected URL/Method: {0} {1}'.format(
                                           environ['REQUEST_METHOD'].upper(),
                                           environ['PATH_INFO']))
  start_response('404 Not Found', [ ('Content-type', 'text/plain') ])
  return [template_404.format(base_url)]

class PathDispatcher:
  def __init__(self):
    self.pathmap = { }

  def __call__(self, environ, start_response):
    #----------------------------------------------------------------------
    # Extract the method and path from the environment.
    #----------------------------------------------------------------------
    method = environ['REQUEST_METHOD'].lower()
    path = environ['PATH_INFO']

    #----------------------------------------------------------------------
    # See if we have a handler for this path, and if so invoke it.
    # Otherwise, return a 404.
    #----------------------------------------------------------------------
    handler = self.pathmap.get((method, path), notfound_404)
    return handler(environ, start_response)

  def register(self, method, path, function):
    print('Registering for {0} at {1}'.format(method, path))
    self.pathmap[method.lower(), path] = function
    return function

#--------------------------------------------------------------------------
# Event processing
#--------------------------------------------------------------------------
def process_event(e):
  global status
  global summary

  epoch = e.event.commonEventHeader.lastEpochMicrosec

  report_time = time.strftime('%Y-%m-%d %H:%M:%S', 
                  time.localtime(int(epoch)/1000000))

  host = e.event.commonEventHeader.reportingEntityName
  if 'VDU1' in host or 'vdu1' in host: vdu = 1
  if 'VDU2' in host or 'vdu2' in host: vdu = 2
  if 'VDU3' in host or 'vdu3' in host: vdu = 3

  domain = e.event.commonEventHeader.domain

  if e.event.commonEventHeader.functionalRole == 'vHello_VES agent':
    if domain == 'measurementsForVfScaling':
      aggregateCpuUsage = e.event.measurementsForVfScaling.aggregateCpuUsage
      requestRate = e.event.measurementsForVfScaling.requestRate
      summary[vdu] = "VDU" + str(vdu) + " state=" + status[vdu] + ", tps=" + str(requestRate) + ", cpu=" + str(aggregateCpuUsage)
      if monitor_mode == "c": print '{0} *** VDU{1} state={2}, tps={3}'.format(
        report_time, vdu, status[vdu], str(requestRate))

    if domain == 'fault':
      alarmCondition = e.event.faultFields.alarmCondition
      specificProblem = e.event.faultFields.specificProblem
#    status[vdu] = e.event.faultFields.vfStatus
      status[vdu] = e.event.faultFields.specificProblem
      if monitor_mode == "c": print '{0} *** VDU{1} state: {2}'.format(
        report_time, vdu, status[vdu])

# print_there only works if SSH'd to the VM manually - need to investigate
#  print_there(1,columns-56,summary)
    for s in summary:
      print '{0}'.format(s)

#--------------------------------------------------------------------------
# Main monitoring and logging procedure
#--------------------------------------------------------------------------
def ves_monitor(environ, start_response):

  # Check for keyboard input
  if sys.stdin in select.select([sys.stdin], [], [], 0)[0]:
    line = sys.stdin.readline()
    if "f" in line: monitor_mode = "f"
    if "c" in line: monitor_mode = "c"

  print('==== ' + time.asctime() + ' ' + '=' * 49)

  #--------------------------------------------------------------------------
  # Extract the content from the request.
  #--------------------------------------------------------------------------
  length = int(environ.get('CONTENT_LENGTH', '0'))
  body = environ['wsgi.input'].read(length)

  mode, b64_credentials = string.split(environ.get('HTTP_AUTHORIZATION',
                                                     'None None'))
  if (b64_credentials != 'None'):
      credentials = b64decode(b64_credentials)
  else:
      credentials = None

  #--------------------------------------------------------------------------
  # See whether the user authenticated themselves correctly.
  #--------------------------------------------------------------------------
  if (credentials == (vel_username + ':' + vel_password)):
    start_response('204 No Content', [])
    yield ''
  else:
    print('Failed to authenticate agent')
    start_response('401 Unauthorized', [ ('Content-type',
                                          'application/json')])
    req_error = { 'requestError': {
                    'policyException': {
                      'messageId': 'POL0001',
                       'text': 'Failed to authenticate'
                    }
                  }
                }
    yield json.dumps(req_error)

  #--------------------------------------------------------------------------
  # Decode the JSON body
  #--------------------------------------------------------------------------

  try:
    decoded_body = json.loads(body)
    print('{0}'.format(json.dumps(decoded_body,
                                sort_keys=True,
                                indent=4,
                                separators=(',', ': '))))
    decoded_body = json.loads(body, object_hook=JSONObject)
    process_event(decoded_body)

  except Exception as e:
    print('JSON body is not valid for unexpected reason! {0}'.format(e))

def main(argv=None):
  global columns
  global rows
  a,b = os.popen('stty size', 'r').read().split()
  rows = int(a)
  columns = int(b)

  if argv is None:
    argv = sys.argv
  else:
    sys.argv.extend(argv)

  try:
    #----------------------------------------------------------------------
    # Setup argument parser so we can parse the command-line.
    #----------------------------------------------------------------------
    parser = ArgumentParser(description='',
                            formatter_class=ArgumentDefaultsHelpFormatter)
    parser.add_argument('-v', '--verbose',
                        dest='verbose',
                        action='count',
                        help='set verbosity level')
    parser.add_argument('-V', '--version',
                        action='version',
                        version='1.0',
                        help='Display version information')
    parser.add_argument('-c', '--config',
                        dest='config',
                        default='/etc/opt/att/collector.conf',
                        help='Use this config file.',
                        metavar='<file>')
    parser.add_argument('-s', '--section',
                        dest='section',
                        default='default',
                        metavar='<section>',
                        help='section to use in the config file')

    #----------------------------------------------------------------------
    # Process arguments received.
    #----------------------------------------------------------------------
    args = parser.parse_args()
    verbose = args.verbose
    config_file = args.config
    config_section = args.section
    #----------------------------------------------------------------------
    # Now read the config file, using command-line supplied values as
    # overrides.
    #----------------------------------------------------------------------
    defaults = {'log_file': 'ves.log',
                'vel_port': '30000',
                'vel_path': '',
                'vel_topic_name': ''
               }
    overrides = {}
    config = ConfigParser.SafeConfigParser(defaults)
    config.read(config_file)

    #----------------------------------------------------------------------
    # extract the values we want.
    #----------------------------------------------------------------------
    log_file = config.get(config_section, 'log_file', vars=overrides)
    vel_port = config.get(config_section, 'vel_port', vars=overrides)
    vel_path = config.get(config_section, 'vel_path', vars=overrides)
    vel_topic_name = config.get(config_section,
                                'vel_topic_name',
                                vars=overrides)
    global vel_username
    global vel_password
    vel_username = config.get(config_section,
                              'vel_username',
                              vars=overrides)
    vel_password = config.get(config_section,
                              'vel_password',
                              vars=overrides)
    vel_schema_file = config.get(config_section,
                                 'schema_file',
                                 vars=overrides)
    base_schema_file = config.get(config_section,
                             'base_schema_file',
                              vars=overrides)

    #----------------------------------------------------------------------
    # Perform some basic error checking on the config.
    #----------------------------------------------------------------------
    if (int(vel_port) < 1024 or int(vel_port) > 65535):
      raise RuntimeError('Invalid Vendor Event Listener port ({0}) '
                         'specified'.format(vel_port))

    if (len(vel_path) > 0 and vel_path[-1] != '/'):
      vel_path += '/'

    #----------------------------------------------------------------------
    # Load up the vel_schema and base_schema, if they exist.
    #----------------------------------------------------------------------
    if (os.path.exists(vel_schema_file)):
        global vel_schema
        vel_schema = json.load(open(vel_schema_file, 'r'))
        if (os.path.exists(base_schema_file)):
          base_schema = json.load(open(base_schema_file, 'r'))
          vel_schema.update(base_schema)

    #----------------------------------------------------------------------
    # We are now ready to get started with processing. Start-up the various
    # components of the system in order:
    #
    #  1) Create the dispatcher.
    #  2) Register the functions for the URLs of interest.
    #  3) Run the webserver.
    #----------------------------------------------------------------------
    root_url = '/{0}eventListener/v{1}{2}'.format(vel_path,
                                               '1',
                                               '/' + vel_topic_name
                                                 if len(vel_topic_name) > 0
                                                 else '')

    base_url = root_url
    dispatcher = PathDispatcher()
    dispatcher.register('GET', root_url, ves_monitor)
    dispatcher.register('POST', root_url, ves_monitor)
    httpd = make_server('', 30000, dispatcher, handler_class=NoLoggingWSGIRequestHandler)
    httpd.serve_forever()

    return 0

  except Exception as e:
    #----------------------------------------------------------------------
    # Handle unexpected exceptions.
    #----------------------------------------------------------------------
    indent = len('VES Monitor') * ' '
    sys.stderr.write('VES Monitor: ' + repr(e) + '\n')
    sys.stderr.write(indent + '  for help use --help\n')
    sys.stderr.write(traceback.format_exc())
    return 2

#------------------------------------------------------------------------------
# MAIN SCRIPT ENTRY POINT.
#------------------------------------------------------------------------------
if __name__ == '__main__':
    sys.exit(main())    
