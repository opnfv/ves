#!/usr/bin/env python
#
# Copyright 2016-2017 AT&T Intellectual Property, Inc
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
# ves_onap_demo.
#
# Status: this is a work in progress, under test.

from rest_dispatcher import PathDispatcher, set_404_content
from wsgiref.simple_server import make_server
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
from functools import partial
import requests

monitor_mode = "f"
vdu_id = ['','','','','','']
summary_e = ['***** Summary of key stats *****','','','']
summary_c = ['Collectd agents:']
status = ['','Started','Started','Started']
base_url = ''
template_404 = b'''POST {0}'''
columns = 0
rows = 0

class JSONObject:
  def __init__(self, d):
    self.__dict__ = d

__all__ = []
__version__ = 0.1
__date__ = '2015-12-04'
__updated__ = '2015-12-04'

TESTRUN = False
DEBUG = False
PROFILE = False

#------------------------------------------------------------------------------
# Address of influxdb server.
#------------------------------------------------------------------------------

influxdb = '127.0.0.1'

#------------------------------------------------------------------------------
# Credentials we expect clients to authenticate themselves with.
#------------------------------------------------------------------------------
vel_username = ''
vel_password = ''

#------------------------------------------------------------------------------
# The JSON schema which we will use to validate events.
#------------------------------------------------------------------------------
vel_schema = None

#------------------------------------------------------------------------------
# The JSON schema which we will use to validate client throttle state.
#------------------------------------------------------------------------------
throttle_schema = None

#------------------------------------------------------------------------------
# The JSON schema which we will use to provoke throttling commands for testing.
#------------------------------------------------------------------------------
test_control_schema = None

#------------------------------------------------------------------------------
# Pending command list from the testControl API
# This is sent as a response commandList to the next received event.
#------------------------------------------------------------------------------
pending_command_list = None

#------------------------------------------------------------------------------
# Logger for this module.
#------------------------------------------------------------------------------
logger = None

def listener(environ, start_response, schema):
    '''
    Handler for the Vendor Event Listener REST API.

    Extract headers and the body and check that:

      1)  The client authenticated themselves correctly.
      2)  The body validates against the provided schema for the API.

    '''
    logger.info('Got a Vendor Event request')
    print('==== ' + time.asctime() + ' ' + '=' * 49)

    #--------------------------------------------------------------------------
    # Extract the content from the request.
    #--------------------------------------------------------------------------
    length = int(environ.get('CONTENT_LENGTH', '0'))
    logger.debug('Content Length: {0}'.format(length))
    body = environ['wsgi.input'].read(length)
    logger.debug('Content Body: {0}'.format(body))

    mode, b64_credentials = string.split(environ.get('HTTP_AUTHORIZATION',
                                                     'None None'))
    # logger.debug('Auth. Mode: {0} Credentials: {1}'.format(mode,
    #                                                     b64_credentials))
    logger.debug('Auth. Mode: {0} Credentials: ****'.format(mode))
    if (b64_credentials != 'None'):
        credentials = b64decode(b64_credentials)
    else:
        credentials = None

    # logger.debug('Credentials: {0}'.format(credentials))
    logger.debug('Credentials: ****')

    #--------------------------------------------------------------------------
    # If we have a schema file then check that the event matches that expected.
    #--------------------------------------------------------------------------
    if (schema is not None):
        logger.debug('Attempting to validate data: {0}\n'
                     'Against schema: {1}'.format(body, schema))
        try:
            decoded_body = json.loads(body)
            jsonschema.validate(decoded_body, schema)
            logger.info('Event is valid!')
            print('Valid body decoded & checked against schema OK:\n'
                  '{0}'.format(json.dumps(decoded_body,
                                          sort_keys=True,
                                          indent=4,
                                          separators=(',', ': '))))

        except jsonschema.SchemaError as e:
            logger.error('Schema is not valid! {0}'.format(e))
            print('Schema is not valid! {0}'.format(e))

        except jsonschema.ValidationError as e:
            logger.warn('Event is not valid against schema! {0}'.format(e))
            print('Event is not valid against schema! {0}'.format(e))
            print('Bad JSON body decoded:\n'
                  '{0}'.format(json.dumps(decoded_body,
                                         sort_keys=True,
                                         indent=4,
                                         separators=(',', ': '))))

        except Exception as e:
            logger.error('Event invalid for unexpected reason! {0}'.format(e))
            print('Schema is not valid for unexpected reason! {0}'.format(e))
    else:
        logger.debug('No schema so just decode JSON: {0}'.format(body))
        try:
            decoded_body = json.loads(body)
            print('Valid JSON body (no schema checking) decoded:\n'
                  '{0}'.format(json.dumps(decoded_body,
                                         sort_keys=True,
                                         indent=4,
                                         separators=(',', ': '))))
            logger.info('Event is valid JSON but not checked against schema!')

        except Exception as e:
            logger.error('Event invalid for unexpected reason! {0}'.format(e))
            print('JSON body not valid for unexpected reason! {0}'.format(e))

    #--------------------------------------------------------------------------
    # See whether the user authenticated themselves correctly.
    #--------------------------------------------------------------------------
    if (credentials == (vel_username + ':' + vel_password)):
        logger.debug('Authenticated OK')
#        print('Authenticated OK')

        #----------------------------------------------------------------------
        # Respond to the caller. If we have a pending commandList from the
        # testControl API, send it in response.
        #----------------------------------------------------------------------
        global pending_command_list
        if pending_command_list is not None:
            start_response('202 Accepted',
                           [('Content-type', 'application/json')])
            response = pending_command_list
            pending_command_list = None

            print('\n'+ '='*80)
            print('Sending pending commandList in the response:\n'
                  '{0}'.format(json.dumps(response,
                                          sort_keys=True,
                                          indent=4,
                                          separators=(',', ': '))))
            print('='*80 + '\n')
            yield json.dumps(response)
        else:
            start_response('202 Accepted', [])
            yield ''
    else:
        logger.warn('Failed to authenticate OK; creds: ' +  credentials)
        print('Failed to authenticate agent credentials: ', credentials, 
		  'against expected ', vel_username, ':', vel_password)

        #----------------------------------------------------------------------
        # Respond to the caller.
        #----------------------------------------------------------------------
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

    save_event(body)

#--------------------------------------------------------------------------
# Send event to influxdb
#--------------------------------------------------------------------------
def send_to_influxdb(event,pdata):
  url = 'http://{}/write?db=veseventsdb'.format(influxdb)
  print('Send {} to influxdb at {}: {}'.format(event,influxdb,pdata))
  r = requests.post(url, data=pdata, headers={'Content-Type': 'text/plain'})
  print('influxdb return code {}'.format(r.status_code))
  if r.status_code != 204:
    print('*** Influxdb save failed, return code {} ***'.format(r.status_code))

#--------------------------------------------------------------------------
# Save event data
#--------------------------------------------------------------------------
def save_event(body):
  jobj = json.loads(body)
  e = json.loads(body, object_hook=JSONObject)

  domain = jobj['event']['commonEventHeader']['domain']
  timestamp = jobj['event']['commonEventHeader']['lastEpochMicrosec']
  agent = jobj['event']['commonEventHeader']['reportingEntityName'].upper(	)
  if "LOCALHOST" in agent:
    agent = "computehost"
  source = jobj['event']['commonEventHeader']['sourceId'].upper(	)

  if e.event.commonEventHeader.domain == "heartbeat":
    print('Found Heartbeat')
    send_to_influxdb(event,'heartbeat,system={},sequence={}'.format(agent,e.event.commonEventHeader.sequence))

  if 'measurementsForVfScalingFields' in jobj['event']:
    print('Found measurementsForVfScalingFields')

#        "measurementsForVfScalingFields": {
#            "additionalMeasurements": [
#                {
#                    "arrayOfFields": [
#                        {
#                            "name": "load-longterm",
#                            "value": "0.34"
#                        },
#                        {
#                            "name": "load-shortterm",
#                            "value": "0.32"
#                        },
#                        {
#                            "name": "load-midterm",
#                            "value": "0.34"
#                        }
#                    ],
#                    "name": "load"
#                }
#            ],

    if 'additionalMeasurements' in jobj['event']['measurementsForVfScalingFields']:
      for meas in jobj['event']['measurementsForVfScalingFields']['additionalMeasurements']:
        name = meas['name']
        pdata = '{},system={}'.format(name,source)
        for field in meas['arrayOfFields']:
          pdata = pdata + ",{}={}".format(field['name'],field['value'])
        i=pdata.find(',', pdata.find('system'))
        pdata = pdata[:i] + ' ' + pdata[i+1:]
        send_to_influxdb("systemLoad", pdata)

#            "cpuUsageArray": [
#                {
#                    "cpuIdentifier": "15",
#                    "cpuIdle": 99.8998998999,
#                    "cpuUsageInterrupt": 0,
#                    "cpuUsageNice": 0,
#                    "cpuUsageSoftIrq": 0,
#                    "cpuUsageSteal": 0,
#                    "cpuUsageSystem": 0,
#                    "cpuUsageUser": 0.1001001001,
#                    "cpuWait": 0,
#                    "percentUsage": 0.0
#                },

    if 'cpuUsageArray' in jobj['event']['measurementsForVfScalingFields']:
      print('Found diskUsageArray')
      for disk in jobj['event']['measurementsForVfScalingFields']['cpuUsageArray']:
        id=disk['cpuIdentifier']
        pdata = 'cpuUsage,system={},cpu={}'.format(source,id)
        d = disk.items()
        for key,val in d:
          if key != 'cpuIdentifier':
            pdata = pdata + ',{}={}'.format(key,val)
        i=pdata.find(',', pdata.find('cpu='))
        pdata = pdata[:i] + ' ' + pdata[i+1:]
        send_to_influxdb("cpuUsage", pdata)

#            "diskUsageArray": [
#                {
#                    "diskIdentifier": "sda",
#                    "diskIoTimeLast": 0.3996139893,
#                    "diskMergedReadLast": 0,
#                    "diskMergedWriteLast": 26.1747155344,
#                    "diskOctetsReadLast": 0,
#                    "diskOctetsWriteLast": 309767.93302,
#                    "diskOpsReadLast": 0,
#                    "diskOpsWriteLast": 10.9893839563,
#                    "diskTimeReadLast": 0,
#                    "diskTimeWriteLast": 0.699324445683
#                },

    if 'diskUsageArray' in jobj['event']['measurementsForVfScalingFields']:
      print('Found diskUsageArray')
      for disk in jobj['event']['measurementsForVfScalingFields']['diskUsageArray']:
        id=disk['diskIdentifier']
        pdata = 'diskUsage,system={},disk={}'.format(source,id)
        d = disk.items()
        for key,val in d:
          if key != 'diskIdentifier':
            pdata = pdata + ',{}={}'.format(key,val)
        i=pdata.find(',', pdata.find('disk='))
        pdata = pdata[:i] + ' ' + pdata[i+1:]
        send_to_influxdb("diskUsage", pdata)

#            "memoryUsageArray": [
#                {
#                    "memoryBuffered": 269056.0,
#                    "memoryCached": 17636956.0,
#                    "memoryFree": 244731658240,
#                    "memorySlabRecl": 753160.0,
#                    "memorySlabUnrecl": 210800.0,
#                    "memoryUsed": 6240064.0,
#                    "vmIdentifier": "opnfv01"
#                }
#            ],

    if 'memoryUsageArray' in jobj['event']['measurementsForVfScalingFields']:
      print('Found memoryUsageArray')
      pdata = 'memoryUsage,system={}'.format(source)
      vmid=e.event.measurementsForVfScalingFields.memoryUsageArray[0].vmIdentifier
      d = jobj['event']['measurementsForVfScalingFields']['memoryUsageArray'][0].items()
      for key,val in d:
        if key != 'vmIdentifier':
          pdata = pdata + ',{}={}'.format(key,val)
      i=pdata.find(',', pdata.find('system'))
      pdata = pdata[:i] + ' ' + pdata[i+1:]
      send_to_influxdb("memoryUsage", pdata)

#            "vNicPerformanceArray": [
#                {
#                    "receivedDiscardedPacketsAccumulated": 0,
#                    "receivedErrorPacketsAccumulated": 0,
#                    "receivedOctetsAccumulated": 476.801524578,
#                    "receivedTotalPacketsAccumulated": 2.90000899705,
#                    "transmittedDiscardedPacketsAccumulated": 0,
#                    "transmittedErrorPacketsAccumulated": 0,
#                    "transmittedOctetsAccumulated": 230.100735749,
#                    "transmittedTotalPacketsAccumulated": 1.20000372292,
#                    "vNicIdentifier": "eno4",
#                    "valuesAreSuspect": "true"
#                },

    if 'vNicPerformanceArray' in jobj['event']['measurementsForVfScalingFields']:
      print('Found vNicPerformanceArray')
      for vnic in jobj['event']['measurementsForVfScalingFields']['vNicPerformanceArray']:
        vnid=vnic['vNicIdentifier']
        pdata = 'vNicPerformance,system={},vnic={}'.format(vmid,vnid)
        d = vnic.items()
        for key,val in d:
          if key != 'vNicIdentifier':
            pdata = pdata + ',{}={}'.format(key,val)
        i=pdata.find(',', pdata.find('vnic'))
        pdata = pdata[:i] + ' ' + pdata[i+1:]
        send_to_influxdb("vNicPerformance", pdata)

def test_listener(environ, start_response, schema):
    '''
    Handler for the Test Collector Test Control API.

    There is no authentication on this interface.

    This simply stores a commandList which will be sent in response to the next
    incoming event on the EVEL interface.
    '''
    global pending_command_list
    logger.info('Got a Test Control input')
    print('============================')
    print('==== TEST CONTROL INPUT ====')

    #--------------------------------------------------------------------------
    # GET allows us to get the current pending request.
    #--------------------------------------------------------------------------
    if environ.get('REQUEST_METHOD') == 'GET':
        start_response('200 OK', [('Content-type', 'application/json')])
        yield json.dumps(pending_command_list)
        return

    #--------------------------------------------------------------------------
    # Extract the content from the request.
    #--------------------------------------------------------------------------
    length = int(environ.get('CONTENT_LENGTH', '0'))
    logger.debug('TestControl Content Length: {0}'.format(length))
    body = environ['wsgi.input'].read(length)
    logger.debug('TestControl Content Body: {0}'.format(body))

    #--------------------------------------------------------------------------
    # If we have a schema file then check that the event matches that expected.
    #--------------------------------------------------------------------------
    if (schema is not None):
        logger.debug('Attempting to validate data: {0}\n'
                     'Against schema: {1}'.format(body, schema))
        try:
            decoded_body = json.loads(body)
            jsonschema.validate(decoded_body, schema)
            logger.info('TestControl is valid!')
            print('TestControl:\n'
                  '{0}'.format(json.dumps(decoded_body,
                                          sort_keys=True,
                                          indent=4,
                                          separators=(',', ': '))))

        except jsonschema.SchemaError as e:
            logger.error('TestControl Schema is not valid: {0}'.format(e))
            print('TestControl Schema is not valid: {0}'.format(e))

        except jsonschema.ValidationError as e:
            logger.warn('TestControl input not valid: {0}'.format(e))
            print('TestControl input not valid: {0}'.format(e))
            print('Bad JSON body decoded:\n'
                  '{0}'.format(json.dumps(decoded_body,
                                          sort_keys=True,
                                          indent=4,
                                          separators=(',', ': '))))

        except Exception as e:
            logger.error('TestControl input not valid: {0}'.format(e))
            print('TestControl Schema not valid: {0}'.format(e))
    else:
        logger.debug('Missing schema just decode JSON: {0}'.format(body))
        try:
            decoded_body = json.loads(body)
            print('Valid JSON body (no schema checking) decoded:\n'
                  '{0}'.format(json.dumps(decoded_body,
                                          sort_keys=True,
                                          indent=4,
                                          separators=(',', ': '))))
            logger.info('TestControl input not checked against schema!')

        except Exception as e:
            logger.error('TestControl input not valid: {0}'.format(e))
            print('TestControl input not valid: {0}'.format(e))

    #--------------------------------------------------------------------------
    # Respond to the caller. If we received otherField 'ThrottleRequest',
    # generate the appropriate canned response.
    #--------------------------------------------------------------------------
    pending_command_list = decoded_body
    print('===== TEST CONTROL END =====')
    print('============================')
    start_response('202 Accepted', [])
    yield ''

def main(argv=None):
    '''
    Main function for the collector start-up.

    Called with command-line arguments:
        *    --config *<file>*
        *    --section *<section>*
        *    --verbose

    Where:

        *<file>* specifies the path to the configuration file.

        *<section>* specifies the section within that config file.

        *verbose* generates more information in the log files.

    The process listens for REST API invocations and checks them. Errors are
    displayed to stdout and logged.
    '''

    if argv is None:
        argv = sys.argv
    else:
        sys.argv.extend(argv)

    program_name = os.path.basename(sys.argv[0])
    program_version = 'v{0}'.format(__version__)
    program_build_date = str(__updated__)
    program_version_message = '%%(prog)s {0} ({1})'.format(program_version,
                                                         program_build_date)
    if (__import__('__main__').__doc__ is not None):
        program_shortdesc = __import__('__main__').__doc__.split('\n')[1]
    else:
        program_shortdesc = 'Running in test harness'
    program_license = '''{0}

  Created  on {1}.
  Copyright 2015 Metaswitch Networks Ltd. All rights reserved.

  Distributed on an "AS IS" basis without warranties
  or conditions of any kind, either express or implied.

USAGE
'''.format(program_shortdesc, str(__date__))

    try:
        #----------------------------------------------------------------------
        # Setup argument parser so we can parse the command-line.
        #----------------------------------------------------------------------
        parser = ArgumentParser(description=program_license,
                                formatter_class=ArgumentDefaultsHelpFormatter)
        parser.add_argument('-i', '--influxdb',
                            dest='influxdb',
                            default='localhost',
                            help='InfluxDB server addresss')
        parser.add_argument('-v', '--verbose',
                            dest='verbose',
                            action='count',
                            help='set verbosity level')
        parser.add_argument('-V', '--version',
                            action='version',
                            version=program_version_message,
                            help='Display version information')
        parser.add_argument('-a', '--api-version',
                            dest='api_version',
                            default='5',
                            help='set API version')
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
        api_version = args.api_version
        config_file = args.config
        config_section = args.section

        #----------------------------------------------------------------------
        # Now read the config file, using command-line supplied values as
        # overrides.
        #----------------------------------------------------------------------
        defaults = {'log_file': 'collector.log',
                    'vel_port': '12233',
                    'vel_path': '',
                    'vel_topic_name': ''
                   }
        overrides = {}
        config = ConfigParser.SafeConfigParser(defaults)
        config.read(config_file)

        #----------------------------------------------------------------------
        # extract the values we want.
        #----------------------------------------------------------------------
        global influxdb
        global vel_username
        global vel_password
        global vel_topic_name
        influxdb = config.get(config_section, 'influxdb', vars=overrides)
        log_file = config.get(config_section, 'log_file', vars=overrides)
        vel_port = config.get(config_section, 'vel_port', vars=overrides)
        vel_path = config.get(config_section, 'vel_path', vars=overrides)

        vel_topic_name = config.get(config_section,
                                    'vel_topic_name',
                                    vars=overrides)
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
        throttle_schema_file = config.get(config_section,
                                          'throttle_schema_file',
                                          vars=overrides)
        test_control_schema_file = config.get(config_section,
                                           'test_control_schema_file',
                                           vars=overrides)

        #----------------------------------------------------------------------
        # Finally we have enough info to start a proper flow trace.
        #----------------------------------------------------------------------
        global logger
        print('Logfile: {0}'.format(log_file))
        logger = logging.getLogger('monitor')
        if verbose > 0:
            print('Verbose mode on')
            logger.setLevel(logging.DEBUG)
        else:
            logger.setLevel(logging.INFO)
        handler = logging.handlers.RotatingFileHandler(log_file,
                                                       maxBytes=1000000,
                                                       backupCount=10)
        if (platform.system() == 'Windows'):
            date_format = '%Y-%m-%d %H:%M:%S'
        else:
            date_format = '%Y-%m-%d %H:%M:%S.%f %z'
        formatter = logging.Formatter('%(asctime)s %(name)s - '
                                      '%(levelname)s - %(message)s',
                                      date_format)
        handler.setFormatter(formatter)
        logger.addHandler(handler)
        logger.info('Started')

        #----------------------------------------------------------------------
        # Log the details of the configuration.
        #----------------------------------------------------------------------
        logger.debug('Log file = {0}'.format(log_file))
        logger.debug('Influxdb server = {0}'.format(influxdb))
        logger.debug('Event Listener Port = {0}'.format(vel_port))
        logger.debug('Event Listener Path = {0}'.format(vel_path))
        logger.debug('Event Listener Topic = {0}'.format(vel_topic_name))
        logger.debug('Event Listener Username = {0}'.format(vel_username))
        # logger.debug('Event Listener Password = {0}'.format(vel_password))
        logger.debug('Event Listener JSON Schema File = {0}'.format(
                                                              vel_schema_file))
        logger.debug('Base JSON Schema File = {0}'.format(base_schema_file))
        logger.debug('Throttle JSON Schema File = {0}'.format(
                                                         throttle_schema_file))
        logger.debug('Test Control JSON Schema File = {0}'.format(
                                                     test_control_schema_file))

        #----------------------------------------------------------------------
        # Perform some basic error checking on the config.
        #----------------------------------------------------------------------
        if (int(vel_port) < 1024 or int(vel_port) > 65535):
            logger.error('Invalid Vendor Event Listener port ({0}) '
                         'specified'.format(vel_port))
            raise RuntimeError('Invalid Vendor Event Listener port ({0}) '
                               'specified'.format(vel_port))

        if (len(vel_path) > 0 and vel_path[-1] != '/'):
            logger.warning('Event Listener Path ({0}) should have terminating '
                           '"/"!  Adding one on to configured string.'.format(
                                                                     vel_path))
            vel_path += '/'

        #----------------------------------------------------------------------
        # Load up the vel_schema, if it exists.
        #----------------------------------------------------------------------
        if not os.path.exists(vel_schema_file):
            logger.warning('Event Listener Schema File ({0}) not found. '
                           'No validation will be undertaken.'.format(
                                                              vel_schema_file))
        else:
            global vel_schema
            global throttle_schema
            global test_control_schema
            vel_schema = json.load(open(vel_schema_file, 'r'))
            logger.debug('Loaded the JSON schema file')

            #------------------------------------------------------------------
            # Load up the throttle_schema, if it exists.
            #------------------------------------------------------------------
            if (os.path.exists(throttle_schema_file)):
                logger.debug('Loading throttle schema')
                throttle_fragment = json.load(open(throttle_schema_file, 'r'))
                throttle_schema = {}
                throttle_schema.update(vel_schema)
                throttle_schema.update(throttle_fragment)
                logger.debug('Loaded the throttle schema')

            #------------------------------------------------------------------
            # Load up the test control _schema, if it exists.
            #------------------------------------------------------------------
            if (os.path.exists(test_control_schema_file)):
                logger.debug('Loading test control schema')
                test_control_fragment = json.load(
                    open(test_control_schema_file, 'r'))
                test_control_schema = {}
                test_control_schema.update(vel_schema)
                test_control_schema.update(test_control_fragment)
                logger.debug('Loaded the test control schema')

            #------------------------------------------------------------------
            # Load up the base_schema, if it exists.
            #------------------------------------------------------------------
            if (os.path.exists(base_schema_file)):
                logger.debug('Updating the schema with base definition')
                base_schema = json.load(open(base_schema_file, 'r'))
                vel_schema.update(base_schema)
                logger.debug('Updated the JSON schema file')

        #----------------------------------------------------------------------
        # We are now ready to get started with processing. Start-up the various
        # components of the system in order:
        #
        #  1) Create the dispatcher.
        #  2) Register the functions for the URLs of interest.
        #  3) Run the webserver.
        #----------------------------------------------------------------------
        root_url = '/{0}eventListener/v{1}{2}'.\
                   format(vel_path,
                          api_version,
                          '/' + vel_topic_name
                          if len(vel_topic_name) > 0
                          else '')
        throttle_url = '/{0}eventListener/v{1}/clientThrottlingState'.\
                       format(vel_path, api_version)
        set_404_content(root_url)
        dispatcher = PathDispatcher()
        vendor_event_listener = partial(listener, schema = vel_schema)
        dispatcher.register('GET', root_url, vendor_event_listener)
        dispatcher.register('POST', root_url, vendor_event_listener)
        vendor_throttle_listener = partial(listener, schema = throttle_schema)
        dispatcher.register('GET', throttle_url, vendor_throttle_listener)
        dispatcher.register('POST', throttle_url, vendor_throttle_listener)

        #----------------------------------------------------------------------
        # We also add a POST-only mechanism for test control, so that we can
        # send commands to a single attached client.
        #----------------------------------------------------------------------
        test_control_url = '/testControl/v{0}/commandList'.format(api_version)
        test_control_listener = partial(test_listener,
                                        schema = test_control_schema)
        dispatcher.register('POST', test_control_url, test_control_listener)
        dispatcher.register('GET', test_control_url, test_control_listener)

        httpd = make_server('', int(vel_port), dispatcher)
        print('Serving on port {0}...'.format(vel_port))
        httpd.serve_forever()

        logger.error('Main loop exited unexpectedly!')
        return 0

    except KeyboardInterrupt:
        #----------------------------------------------------------------------
        # handle keyboard interrupt
        #----------------------------------------------------------------------
        logger.info('Exiting on keyboard interrupt!')
        return 0

    except Exception as e:
        #----------------------------------------------------------------------
        # Handle unexpected exceptions.
        #----------------------------------------------------------------------
        if DEBUG or TESTRUN:
            raise(e)
        indent = len(program_name) * ' '
        sys.stderr.write(program_name + ': ' + repr(e) + '\n')
        sys.stderr.write(indent + '  for help use --help\n')
        sys.stderr.write(traceback.format_exc())
        logger.critical('Exiting because of exception: {0}'.format(e))
        logger.critical(traceback.format_exc())
        return 2

#------------------------------------------------------------------------------
# MAIN SCRIPT ENTRY POINT.
#------------------------------------------------------------------------------
if __name__ == '__main__':
    if TESTRUN:
        #----------------------------------------------------------------------
        # Running tests - note that doctest comments haven't been included so
        # this is a hook for future improvements.
        #----------------------------------------------------------------------
        import doctest
        doctest.testmod()

    if PROFILE:
        #----------------------------------------------------------------------
        # Profiling performance.  Performance isn't expected to be a major
        # issue, but this should all work as expected.
        #----------------------------------------------------------------------
        import cProfile
        import pstats
        profile_filename = 'collector_profile.txt'
        cProfile.run('main()', profile_filename)
        statsfile = open('collector_profile_stats.txt', 'wb')
        p = pstats.Stats(profile_filename, stream=statsfile)
        stats = p.strip_dirs().sort_stats('cumulative')
        stats.print_stats()
        statsfile.close()
        sys.exit(0)

    #--------------------------------------------------------------------------
    # Normal operation - call through to the main function.
    #--------------------------------------------------------------------------
    sys.exit(main())
