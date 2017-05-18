/**************************************************************************//**
 * @file
 * Agent for the OPNFV VNF Event Stream (VES) vHello_VES test
 *
 * Copyright 2016-2017 AT&T Intellectual Property, Inc
 * 
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 * 
 * http://www.apache.org/licenses/LICENSE-2.0
 * 
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 * 
 *****************************************************************************/

#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include <getopt.h>
#include <sys/signal.h>
#include <pthread.h>
#include <mcheck.h>
#include <sys/time.h>

#include "evel.h"
#include "evel_demo.h"
#include "evel_test_control.h"

/**************************************************************************//**
 * Definition of long options to the program.
 *
 * See the documentation for getopt_long() for details of the structure's use.
 *****************************************************************************/
static const struct option long_options[] = {
    {"help",     no_argument,       0, 'h'},
    {"id",       required_argument, 0, 'i'},
    {"fqdn",     required_argument, 0, 'f'},
    {"port",     required_argument, 0, 'n'},
    {"path",     required_argument, 0, 'p'},
    {"topic",    required_argument, 0, 't'},
    {"https",    no_argument,       0, 's'},
    {"verbose",  no_argument,       0, 'v'},
    {"cycles",   required_argument, 0, 'c'},
    {"username", required_argument, 0, 'u'},
    {"password", required_argument, 0, 'w'},
    {"nothrott", no_argument,       0, 'x'},
    {0, 0, 0, 0}
  };

/**************************************************************************//**
 * Definition of short options to the program.
 *****************************************************************************/
static const char* short_options = "hi:f:n:p:t:sc:u:w:vx";

/**************************************************************************//**
 * Basic user help text describing the usage of the application.
 *****************************************************************************/
static const char* usage_text =
"evel_demo [--help]\n"
"          --id <Agent host ID>\n"
"          --fqdn <domain>\n"
"          --port <port_number>\n"
"          [--path <path>]\n"
"          [--topic <topic>]\n"
"          [--username <username>]\n"
"          [--password <password>]\n"
"          [--https]\n"
"          [--cycles <cycles>]\n"
"          [--nothrott]\n"
"\n"
"Demonstrate use of the ECOMP Vendor Event Listener API.\n"
"\n"
"  -h         Display this usage message.\n"
"  --help\n"
"\n"
"  -i         The ID of the agent host.\n"
"  --id\n"
"\n"
"  -f         The FQDN or IP address to the RESTful API.\n"
"  --fqdn\n"
"\n"
"  -n         The port number the RESTful API.\n"
"  --port\n"
"\n"
"  -p         The optional path prefix to the RESTful API.\n"
"  --path\n"
"\n"
"  -t         The optional topic part of the RESTful API.\n"
"  --topic\n"
"\n"
"  -u         The optional username for basic authentication of requests.\n"
"  --username\n"
"\n"
"  -w         The optional password for basic authentication of requests.\n"
"  --password\n"
"\n"
"  -s         Use HTTPS rather than HTTP for the transport.\n"
"  --https\n"
"\n"
"  -c         Loop <cycles> times round the main loop.  Default = 1.\n"
"  --cycles\n"
"\n"
"  -v         Generate much chattier logs.\n"
"  --verbose\n"
"\n"
"  -x         Exclude throttling commands from demonstration.\n"
"  --nothrott\n";

#define DEFAULT_SLEEP_SECONDS 3
#define MINIMUM_SLEEP_SECONDS 1

unsigned long long epoch_start = 0;

typedef enum {
  SERVICE_CODEC,
  SERVICE_TRANSCODING,
  SERVICE_RTCP,
  SERVICE_EOC_VQM,
  SERVICE_MARKER
} SERVICE_EVENT;

/*****************************************************************************/
/* Local prototypes.                                                         */
/*****************************************************************************/
static void demo_heartbeat(void);
static void demo_fault(void);
static void demo_measurement(const int interval);
static void demo_mobile_flow(void);
static void demo_service(void);
static void demo_service_event(const SERVICE_EVENT service_event);
static void demo_signaling(void);
static void demo_state_change(void);
static void demo_syslog(void);
static void demo_other(void);

/**************************************************************************//**
 * Global flags related the applicaton.
 *****************************************************************************/

char *app_prevstate = "Stopped";

/**************************************************************************//**
 * Report app state change fault.
 *
 * Reports the change in app state. 
 *
 * param[in]  char *change     The type of change ("Started", "Stopped")
 *****************************************************************************/
void report_app_statechange(char *change) 
{
  printf("report_app_statechange(%s)\n", change);
  EVENT_FAULT * fault = NULL;
  EVEL_ERR_CODES evel_rc = EVEL_SUCCESS;

  fault = evel_new_fault("App state change",
    change,
    EVEL_PRIORITY_HIGH,
    EVEL_SEVERITY_MAJOR);

  if (fault != NULL) {
    evel_fault_type_set(fault, "App state change");
    evel_fault_addl_info_add(fault, "change", change);
    evel_rc = evel_post_event((EVENT_HEADER *)fault);
    if (evel_rc != EVEL_SUCCESS) {
      EVEL_ERROR("Post failed %d (%s)", evel_rc, evel_error_string());
    }
    else {
       EVEL_ERROR("Unable to send new fault report");
    }
  }
}

/**************************************************************************//**
 * Check status of the app container.
 *
 * Checks and reports any change in app state. 
 *
 * param[in]  none
 *****************************************************************************/
void check_app_container_state() {
  printf("Checking status of app container\n");
  FILE *fp;
  int status;
  char state[100];

  fp = popen("sudo docker inspect vHello | grep Status | sed -- 's/,//g' | sed -- 's/\"//g' | sed -- 's/            Status: //g'", "r");
  if (fp == NULL) {
    EVEL_ERROR("popen failed to execute command");
  }

  fgets(state, 100, fp);
  if (strstr(state, "running") != NULL) {
    if (strcmp(app_prevstate,"Stopped") == 0) {
      printf("App state change detected: Started\n");
      report_app_statechange("Started");
      app_prevstate = "Running";
    }
  }
  else {
    if (strcmp(app_prevstate, "Running") == 0) {
      printf("App state change detected: Stopped\n");
      report_app_statechange("Stopped");
      app_prevstate = "Stopped";
    }
  }
  status = pclose(fp);
  if (status == -1) {
    EVEL_ERROR("pclose returned an error");
  }
}

/**************************************************************************//**
 * Measure app traffic
 *
 * Reports transactions per second in the last second.
 *
 * param[in]  none
 *****************************************************************************/

double cpu() {
  double a[4], b[4], loadavg;
  FILE *fp;
  int status;

  fp = fopen("/proc/stat","r");
  fscanf(fp,"%*s %lf %lf %lf %lf",&a[0],&a[1],&a[2],&a[3]);
  fclose(fp);
  sleep(1);

  fp = fopen("/proc/stat","r");
  fscanf(fp,"%*s %lf %lf %lf %lf",&b[0],&b[1],&b[2],&b[3]);
  fclose(fp);

  loadavg = ((b[0]+b[1]+b[2]) - (a[0]+a[1]+a[2])) / ((b[0]+b[1]+b[2]+b[3]) - (a[0]+a[1]+a[2]+a[3]));

  return(loadavg);
}

void measure_traffic() {

  printf("Checking app traffic\n");
  EVENT_FAULT * fault = NULL;
  EVEL_ERR_CODES evel_rc = EVEL_SUCCESS;
  EVENT_MEASUREMENT * measurement = NULL;
  FILE *fp;
  int status;
  char count[10];
  time_t rawtime;
  struct tm * timeinfo;
  char period [21];
  char cmd [100];
  int concurrent_sessions = 0;
  int configured_entities = 0;
  double mean_request_latency = 0;
  double measurement_interval = 1;
  double memory_configured = 0;
  double memory_used = 0;
  int request_rate;
  char secs [3];
  int sec;
  double loadavg;

  time (&rawtime);
  timeinfo = localtime (&rawtime);
  strftime(period,21,"%d/%b/%Y:%H:%M:",timeinfo);
  strftime(secs,3,"%S",timeinfo);
  sec = atoi(secs);
  if (sec == 0) sec = 59;
  sprintf(secs, "%02d", sec);
  strncat(period, secs, 21);
  // ....x....1....x....2.
  // 15/Oct/2016:17:51:19
  strcpy(cmd, "sudo docker logs vHello | grep -c ");
  strncat(cmd, period, 100);

  fp = popen(cmd, "r");
  if (fp == NULL) {
    EVEL_ERROR("popen failed to execute command");
  }

  if (fgets(count, 10, fp) != NULL) {
    request_rate = atoi(count);
    printf("Reporting request rate for second: %s as %d\n", period, request_rate);
    measurement = evel_new_measurement(measurement_interval);

    if (measurement != NULL) {
      cpu();
      evel_measurement_type_set(measurement, "HTTP request rate");
      evel_measurement_request_rate_set(measurement, request_rate);
//      evel_measurement_agg_cpu_use_set(measurement, loadavg);
//      evel_measurement_cpu_use_add(measurement, "cpu0", loadavg);

      evel_rc = evel_post_event((EVENT_HEADER *)measurement);
      if (evel_rc != EVEL_SUCCESS) {
        EVEL_ERROR("Post Measurement failed %d (%s)",
                    evel_rc,
                    evel_error_string());
      }
    }
    else {
      EVEL_ERROR("New Measurement failed");
    }
    printf("Processed measurement\n");
  }
  status = pclose(fp);
  if (status == -1) {
    EVEL_ERROR("pclose returned an error");
  }
}

/**************************************************************************//**
 * Global flag to initiate shutdown.
 *****************************************************************************/
static int glob_exit_now = 0;

static char * api_fqdn = NULL;
static int api_port = 0;
static int api_secure = 0;

static void show_usage(FILE* fp)
{
  fputs(usage_text, fp);
}

/**************************************************************************//**
 * Main function.
 *
 * Parses the command-line then ...
 *
 * @param[in] argc  Argument count.
 * @param[in] argv  Argument vector - for usage see usage_text.
 *****************************************************************************/
int main(int argc, char ** argv)
{
  sigset_t sig_set;
  pthread_t thread_id;
  int option_index = 0;
  int param = 0;
  char * api_vmid = NULL;
  char * api_path = NULL;
  char * api_topic = NULL;
  char * api_username = "";
  char * api_password = "";
  int verbose_mode = 0;
  int exclude_throttling = 0;
  int cycles = 2147483647;
  int cycle;
  int measurement_interval = EVEL_MEASUREMENT_INTERVAL_UKNOWN;
  EVENT_HEADER * heartbeat = NULL;
  EVEL_ERR_CODES evel_rc = EVEL_SUCCESS;

  /***************************************************************************/
  /* We're very interested in memory management problems so check behavior.  */
  /***************************************************************************/
  mcheck(NULL);

  if (argc < 2)
  {
    show_usage(stderr);
    exit(-1);
  }
  param = getopt_long(argc, argv,
                      short_options,
                      long_options,
                      &option_index);
  while (param != -1)
  {
    switch (param)
    {
      case 'h':
        show_usage(stdout);
        exit(0);
        break;

      case 'i':
        api_vmid = optarg;
        break;

      case 'f':
        api_fqdn = optarg;
        break;

      case 'n':
        api_port = atoi(optarg);
        break;

      case 'p':
        api_path = optarg;
        break;

      case 't':
        api_topic = optarg;
        break;

      case 'u':
        api_username = optarg;
        break;

      case 'w':
        api_password = optarg;
        break;

      case 's':
        api_secure = 1;
        break;

      case 'c':
        cycles = atoi(optarg);
        break;

      case 'v':
        verbose_mode = 1;
        break;

      case 'x':
        exclude_throttling = 1;
        break;

      case '?':
        /*********************************************************************/
        /* Unrecognized parameter - getopt_long already printed an error     */
        /* message.                                                          */
        /*********************************************************************/
        break;

      default:
        fprintf(stderr, "Code error: recognized but missing option (%d)!\n",
                param);
        exit(-1);
    }

    /*************************************************************************/
    /* Extract next parameter.                                               */
    /*************************************************************************/
    param = getopt_long(argc, argv,
                        short_options,
                        long_options,
                        &option_index);
  }

  /***************************************************************************/
  /* All the command-line has parsed cleanly, so now check that the options  */
  /* are meaningful.                                                         */
  /***************************************************************************/
  if (api_fqdn == NULL)
  {
    fprintf(stderr, "FQDN of the Vendor Event Listener API server must be "
                    "specified.\n");
    exit(1);
  }
  if (api_port <= 0 || api_port > 65535)
  {
    fprintf(stderr, "Port for the Vendor Event Listener API server must be "
                    "specified between 1 and 65535.\n");
    exit(1);
  }
  if (cycles <= 0)
  {
    fprintf(stderr, "Number of cycles around the main loop must be an"
                    "integer greater than zero.\n");
    exit(1);
  }

  /***************************************************************************/
  /* Set up default signal behaviour.  Block all signals we trap explicitly  */
  /* on the signal_watcher thread.                                           */
  /***************************************************************************/
  sigemptyset(&sig_set);
  sigaddset(&sig_set, SIGALRM);
  sigaddset(&sig_set, SIGINT);
  pthread_sigmask(SIG_BLOCK, &sig_set, NULL);

  /***************************************************************************/
  /* Start the signal watcher thread.                                        */
  /***************************************************************************/
  if (pthread_create(&thread_id, NULL, signal_watcher, &sig_set) != 0)
  {
    fprintf(stderr, "Failed to start signal watcher thread.");
    exit(1);
  }
  pthread_detach(thread_id);

  /***************************************************************************/
  /* Version info                                                            */
  /***************************************************************************/
  printf("%s built %s %s\n", argv[0], __DATE__, __TIME__);

  /***************************************************************************/
  /* Initialize the EVEL interface.                                          */
  /***************************************************************************/
  if (evel_initialize(api_fqdn,
                      api_port,
                      api_path,
                      api_topic,
                      api_secure,
                      api_username,
                      api_password,
                      EVEL_SOURCE_VIRTUAL_MACHINE,
                      "EVEL demo client",
                      verbose_mode))
  {
    fprintf(stderr, "Failed to initialize the EVEL library!!!");
    exit(-1);
  }
  else
  {
    EVEL_INFO("Initialization completed");
  }

  /***************************************************************************/
  /* Work out a start time for measurements, and sleep for initial period.   */
  /***************************************************************************/
  struct timeval tv_start;
  gettimeofday(&tv_start, NULL);
  epoch_start = tv_start.tv_usec + 1000000 * tv_start.tv_sec;
  sleep(DEFAULT_SLEEP_SECONDS);

  /***************************************************************************/
  /* MAIN LOOP                                                               */
  /***************************************************************************/
  printf("Starting %d loops...\n", cycles);
  cycle = 0;
  while (cycle++ < cycles)
  {
    EVEL_INFO("MAI: Starting main loop");
    printf("\nStarting main loop %d\n", cycle);

    /*************************************************************************/
    /* A 20s-long repeating cycle of behaviour.                              */
    /*************************************************************************/
    if (exclude_throttling == 0)
    {
      switch (cycle % 20)
      {
        case 1:
          printf("   1 - Resetting throttle specification for all domains\n");
          evel_test_control_scenario(TC_RESET_ALL_DOMAINS,
                                     api_secure,
                                     api_fqdn,
                                     api_port);
          break;

        case 2:
          printf("   2 - Switching measurement interval to 2s\n");
          evel_test_control_meas_interval(2,
                                          api_secure,
                                          api_fqdn,
                                          api_port);
          break;

        case 3:
          printf("   3 - Suppressing fault domain\n");
          evel_test_control_scenario(TC_FAULT_SUPPRESS_FIELDS_AND_PAIRS,
                                     api_secure,
                                     api_fqdn,
                                     api_port);
          break;

        case 4:
          printf("   4 - Suppressing measurement domain\n");
          evel_test_control_scenario(TC_MEAS_SUPPRESS_FIELDS_AND_PAIRS,
                                     api_secure,
                                     api_fqdn,
                                     api_port);
          break;

        case 5:
          printf("   5 - Switching measurement interval to 5s\n");
          evel_test_control_meas_interval(5,
                                          api_secure,
                                          api_fqdn,
                                          api_port);
          break;

        case 6:
          printf("   6 - Suppressing mobile flow domain\n");
          evel_test_control_scenario(TC_MOBILE_SUPPRESS_FIELDS_AND_PAIRS,
                                     api_secure,
                                     api_fqdn,
                                     api_port);
          break;

        case 7:
          printf("   7 - Suppressing state change domain\n");
          evel_test_control_scenario(TC_STATE_SUPPRESS_FIELDS_AND_PAIRS,
                                     api_secure,
                                     api_fqdn,
                                     api_port);
          break;

        case 8:
          printf("   8 - Suppressing signaling domain\n");
          evel_test_control_scenario(TC_SIGNALING_SUPPRESS_FIELDS,
                                     api_secure,
                                     api_fqdn,
                                     api_port);
          break;

        case 9:
          printf("   9 - Suppressing service event domain\n");
          evel_test_control_scenario(TC_SERVICE_SUPPRESS_FIELDS_AND_PAIRS,
                                     api_secure,
                                     api_fqdn,
                                     api_port);
          break;

        case 10:
          printf("   10 - Switching measurement interval to 20s\n");
          evel_test_control_meas_interval(20,
                                          api_secure,
                                          api_fqdn,
                                          api_port);
          break;

        case 11:
          printf("   11 - Suppressing syslog domain\n");
          evel_test_control_scenario(TC_SYSLOG_SUPPRESS_FIELDS_AND_PAIRS,
                                     api_secure,
                                     api_fqdn,
                                     api_port);
          break;

        case 12:
          printf("   12 - Switching measurement interval to 10s\n");
          evel_test_control_meas_interval(10,
                                          api_secure,
                                          api_fqdn,
                                          api_port);
          break;

        case 15:
          printf("   Requesting provide throttling spec\n");
          evel_test_control_scenario(TC_PROVIDE_THROTTLING_SPEC,
                                     api_secure,
                                     api_fqdn,
                                     api_port);
          break;
      }
    }
    fflush(stdout);

    /*************************************************************************/
    /* Send a bunch of events.                                               */
    /*************************************************************************/

    printf("Sending heartbeat\n");
    heartbeat = evel_new_heartbeat();
    if (heartbeat != NULL)
    {
      evel_rc = evel_post_event(heartbeat);
      if (evel_rc != EVEL_SUCCESS)
      {
        EVEL_ERROR("Post failed %d (%s)", evel_rc, evel_error_string());
      }
    }
    else
    {
      EVEL_ERROR("New heartbeat failed");
    }

    check_app_container_state();
    measure_traffic();

//    demo_heartbeat();
//    demo_fault();
//    demo_measurement((measurement_interval ==
//                                            EVEL_MEASUREMENT_INTERVAL_UKNOWN) ?
//                     DEFAULT_SLEEP_SECONDS : measurement_interval);
//    demo_mobile_flow();
//    demo_service();
//    demo_signaling();
//    demo_state_change();
//    demo_syslog();
//    demo_other();

    /*************************************************************************/
    /* MAIN RETRY LOOP.  Check and implement the measurement interval.       */
    /*************************************************************************/
    if (cycle <= cycles)
    {
      int sleep_time;

      /***********************************************************************/
      /* We have a minimum loop time.                                        */
      /***********************************************************************/
      sleep(MINIMUM_SLEEP_SECONDS);

      /***********************************************************************/
      /* Get the latest measurement interval and sleep for the remainder.    */
      /***********************************************************************/
      measurement_interval = evel_get_measurement_interval();
      printf("Measurement Interval = %d\n", measurement_interval);

      if (measurement_interval == EVEL_MEASUREMENT_INTERVAL_UKNOWN)
      {
        sleep_time = DEFAULT_SLEEP_SECONDS - MINIMUM_SLEEP_SECONDS;
      }
      else
      {
        sleep_time = measurement_interval - MINIMUM_SLEEP_SECONDS;
      }
      sleep(sleep_time);
    }
  }

  /***************************************************************************/
  /* We are exiting, but allow the final set of events to be dispatched      */
  /* properly first.                                                         */
  /***************************************************************************/
  sleep(2);
  printf("All done - exiting!\n");
  return 0;
}

/**************************************************************************//**
 * Signal watcher.
 *
 * Signal catcher for incoming signal processing.  Work out which signal has
 * been received and process it accordingly.
 *
 * param[in]  void_sig_set  The signal mask to listen for.
 *****************************************************************************/
void *signal_watcher(void *void_sig_set)
{
  sigset_t *sig_set = (sigset_t *)void_sig_set;
  int sig = 0;
  int old_type = 0;
  siginfo_t sig_info;

  /***************************************************************************/
  /* Set this thread to be cancellable immediately.                          */
  /***************************************************************************/
  pthread_setcanceltype(PTHREAD_CANCEL_ASYNCHRONOUS, &old_type);

  while (!glob_exit_now)
  {
    /*************************************************************************/
    /* Wait for a signal to be received.                                     */
    /*************************************************************************/
    sig = sigwaitinfo(sig_set, &sig_info);
    switch (sig)
    {
      case SIGALRM:
        /*********************************************************************/
        /* Failed to do something in the given amount of time.  Exit.        */
        /*********************************************************************/
        EVEL_ERROR( "Timeout alarm");
        fprintf(stderr,"Timeout alarm - quitting!\n");
        exit(2);
        break;

      case SIGINT:
        EVEL_INFO( "Interrupted - quitting");
        printf("\n\nInterrupted - quitting!\n");
        glob_exit_now = 1;
        break;
    }
  }

  evel_terminate();
  exit(0);
  return(NULL);
}

/**************************************************************************//**
 * Create and send a heartbeat event.
 *****************************************************************************/
void demo_heartbeat(void)
{
  EVENT_HEADER * heartbeat = NULL;
  EVEL_ERR_CODES evel_rc = EVEL_SUCCESS;

  /***************************************************************************/
  /* Heartbeat                                                               */
  /***************************************************************************/
  heartbeat = evel_new_heartbeat();
  if (heartbeat != NULL)
  {
    evel_rc = evel_post_event(heartbeat);
    if (evel_rc != EVEL_SUCCESS)
    {
      EVEL_ERROR("Post failed %d (%s)", evel_rc, evel_error_string());
    }
  }
  else
  {
    EVEL_ERROR("New Heartbeat failed");
  }
  printf("   Processed Heartbeat\n");
}

/**************************************************************************//**
 * Create and send three fault events.
 *****************************************************************************/
void demo_fault(void)
{
  EVENT_FAULT * fault = NULL;
  EVEL_ERR_CODES evel_rc = EVEL_SUCCESS;

  /***************************************************************************/
  /* Fault                                                                   */
  /***************************************************************************/
  fault = evel_new_fault("An alarm condition",
                         "Things are broken",
                         EVEL_PRIORITY_NORMAL,
                         EVEL_SEVERITY_MAJOR);
  if (fault != NULL)
  {
    evel_rc = evel_post_event((EVENT_HEADER *)fault);
    if (evel_rc != EVEL_SUCCESS)
    {
      EVEL_ERROR("Post failed %d (%s)", evel_rc, evel_error_string());
    }
  }
  else
  {
    EVEL_ERROR("New Fault failed");
  }
  printf("   Processed empty Fault\n");

  fault = evel_new_fault("Another alarm condition",
                         "It broke badly",
                         EVEL_PRIORITY_NORMAL,
                         EVEL_SEVERITY_MAJOR);
  if (fault != NULL)
  {
    evel_fault_type_set(fault, "Bad things happening");
    evel_fault_interface_set(fault, "An Interface Card");
    evel_rc = evel_post_event((EVENT_HEADER *)fault);
    if (evel_rc != EVEL_SUCCESS)
    {
      EVEL_ERROR("Post failed %d (%s)", evel_rc, evel_error_string());
    }
  }
  else
  {
    EVEL_ERROR("New Fault failed");
  }
  printf("   Processed partial Fault\n");

  fault = evel_new_fault("My alarm condition",
                         "It broke very badly",
                         EVEL_PRIORITY_NORMAL,
                         EVEL_SEVERITY_MAJOR);
  if (fault != NULL)
  {
    evel_fault_type_set(fault, "Bad things happen...");
    evel_fault_interface_set(fault, "My Interface Card");
    evel_fault_addl_info_add(fault, "name1", "value1");
    evel_fault_addl_info_add(fault, "name2", "value2");
    evel_rc = evel_post_event((EVENT_HEADER *)fault);
    if (evel_rc != EVEL_SUCCESS)
    {
      EVEL_ERROR("Post failed %d (%s)", evel_rc, evel_error_string());
    }
  }
  else
  {
    EVEL_ERROR("New Fault failed");
  }
  printf("   Processed full Fault\n");
}

/**************************************************************************//**
 * Create and send a measurement event.
 *****************************************************************************/
void demo_measurement(const int interval)
{
  EVENT_MEASUREMENT * measurement = NULL;
  MEASUREMENT_LATENCY_BUCKET * bucket = NULL;
  MEASUREMENT_VNIC_USE * vnic_use = NULL;
  EVEL_ERR_CODES evel_rc = EVEL_SUCCESS;

  /***************************************************************************/
  /* Measurement                                                             */
  /***************************************************************************/
  measurement = evel_new_measurement(interval);
  if (measurement != NULL)
  {
    evel_measurement_type_set(measurement, "Perf management...");
    evel_measurement_conc_sess_set(measurement, 1);
    evel_measurement_cfg_ents_set(measurement, 2);
    evel_measurement_mean_req_lat_set(measurement, 4.4);
    evel_measurement_mem_cfg_set(measurement, 6.6);
    evel_measurement_mem_used_set(measurement, 3.3);
    evel_measurement_request_rate_set(measurement, 6);
    evel_measurement_agg_cpu_use_set(measurement, 8.8);
    evel_measurement_cpu_use_add(measurement, "cpu1", 11.11);
    evel_measurement_cpu_use_add(measurement, "cpu2", 22.22);
    evel_measurement_fsys_use_add(measurement,"00-11-22",100.11, 100.22, 33,
                                  200.11, 200.22, 44);
    evel_measurement_fsys_use_add(measurement,"33-44-55",300.11, 300.22, 55,
                                  400.11, 400.22, 66);

    bucket = evel_new_meas_latency_bucket(20);
    evel_meas_latency_bucket_low_end_set(bucket, 0.0);
    evel_meas_latency_bucket_high_end_set(bucket, 10.0);
    evel_meas_latency_bucket_add(measurement, bucket);

    bucket = evel_new_meas_latency_bucket(30);
    evel_meas_latency_bucket_low_end_set(bucket, 10.0);
    evel_meas_latency_bucket_high_end_set(bucket, 20.0);
    evel_meas_latency_bucket_add(measurement, bucket);

    vnic_use = evel_new_measurement_vnic_use("eth0", 100, 200, 3, 4);
    evel_vnic_use_bcast_pkt_in_set(vnic_use, 1);
    evel_vnic_use_bcast_pkt_out_set(vnic_use, 2);
    evel_vnic_use_mcast_pkt_in_set(vnic_use, 5);
    evel_vnic_use_mcast_pkt_out_set(vnic_use, 6);
    evel_vnic_use_ucast_pkt_in_set(vnic_use, 7);
    evel_vnic_use_ucast_pkt_out_set(vnic_use, 8);
    evel_meas_vnic_use_add(measurement, vnic_use);

    vnic_use = evel_new_measurement_vnic_use("eth1", 110, 240, 13, 14);
    evel_vnic_use_bcast_pkt_in_set(vnic_use, 11);
    evel_vnic_use_bcast_pkt_out_set(vnic_use, 12);
    evel_vnic_use_mcast_pkt_in_set(vnic_use, 15);
    evel_vnic_use_mcast_pkt_out_set(vnic_use, 16);
    evel_vnic_use_ucast_pkt_in_set(vnic_use, 17);
    evel_vnic_use_ucast_pkt_out_set(vnic_use, 18);
    evel_meas_vnic_use_add(measurement, vnic_use);

    evel_measurement_errors_set(measurement, 1, 0, 2, 1);

    evel_measurement_feature_use_add(measurement, "FeatureA", 123);
    evel_measurement_feature_use_add(measurement, "FeatureB", 567);

    evel_measurement_codec_use_add(measurement, "G711a", 91);
    evel_measurement_codec_use_add(measurement, "G729ab", 92);

    evel_measurement_media_port_use_set(measurement, 1234);

    evel_measurement_vnfc_scaling_metric_set(measurement, 1234.5678);

    evel_measurement_custom_measurement_add(measurement,
                                            "Group1", "Name1", "Value1");
    evel_measurement_custom_measurement_add(measurement,
                                            "Group2", "Name1", "Value1");
    evel_measurement_custom_measurement_add(measurement,
                                            "Group2", "Name2", "Value2");

    /*************************************************************************/
    /* Work out the time, to use as end of measurement period.               */
    /*************************************************************************/
    struct timeval tv_now;
    gettimeofday(&tv_now, NULL);
    unsigned long long epoch_now = tv_now.tv_usec + 1000000 * tv_now.tv_sec;
    evel_start_epoch_set(&measurement->header, epoch_start);
    evel_last_epoch_set(&measurement->header, epoch_now);
    epoch_start = epoch_now;
    evel_reporting_entity_name_set(&measurement->header, "measurer");
    evel_reporting_entity_id_set(&measurement->header, "measurer_id");

    evel_rc = evel_post_event((EVENT_HEADER *)measurement);
    if (evel_rc != EVEL_SUCCESS)
    {
      EVEL_ERROR("Post Measurement failed %d (%s)",
                 evel_rc,
                 evel_error_string());
    }
  }
  else
  {
    EVEL_ERROR("New Measurement failed");
  }
  printf("   Processed Measurement\n");
}

/**************************************************************************//**
 * Create and send three mobile flow events.
 *****************************************************************************/
void demo_mobile_flow(void)
{
  MOBILE_GTP_PER_FLOW_METRICS * metrics = NULL;
  EVENT_MOBILE_FLOW * mobile_flow = NULL;
  EVEL_ERR_CODES evel_rc = EVEL_SUCCESS;

  /***************************************************************************/
  /* Mobile Flow                                                             */
  /***************************************************************************/
  metrics = evel_new_mobile_gtp_flow_metrics(12.3,
                                             3.12,
                                             100,
                                             2100,
                                             500,
                                             1470409421,
                                             987,
                                             1470409431,
                                             11,
                                             (time_t)1470409431,
                                             "Working",
                                             87,
                                             3,
                                             17,
                                             123654,
                                             4561,
                                             0,
                                             12,
                                             10,
                                             1,
                                             3,
                                             7,
                                             899,
                                             901,
                                             302,
                                             6,
                                             2,
                                             0,
                                             110,
                                             225);
  if (metrics != NULL)
  {
    mobile_flow = evel_new_mobile_flow("Outbound",
                                       metrics,
                                       "TCP",
                                       "IPv4",
                                       "2.3.4.1",
                                       2341,
                                       "4.2.3.1",
                                       4321);
    if (mobile_flow != NULL)
    {
      evel_rc = evel_post_event((EVENT_HEADER *)mobile_flow);
      if (evel_rc != EVEL_SUCCESS)
      {
        EVEL_ERROR("Post Mobile Flow failed %d (%s)",
                   evel_rc,
                   evel_error_string());
      }
    }
    else
    {
      EVEL_ERROR("New Mobile Flow failed");
    }
    printf("   Processed empty Mobile Flow\n");
  }
  else
  {
    EVEL_ERROR("New GTP Per Flow Metrics failed - skipping Mobile Flow");
    printf("   Skipped empty Mobile Flow\n");
  }

  metrics = evel_new_mobile_gtp_flow_metrics(132.0001,
                                             31.2,
                                             101,
                                             2101,
                                             501,
                                             1470409422,
                                             988,
                                             1470409432,
                                             12,
                                             (time_t)1470409432,
                                             "Inactive",
                                             88,
                                             4,
                                             18,
                                             123655,
                                             4562,
                                             1,
                                             13,
                                             11,
                                             2,
                                             4,
                                             8,
                                             900,
                                             902,
                                             303,
                                             7,
                                             3,
                                             1,
                                             111,
                                             226);
  if (metrics != NULL)
  {
    mobile_flow = evel_new_mobile_flow("Inbound",
                                       metrics,
                                       "UDP",
                                       "IPv6",
                                       "2.3.4.2",
                                       2342,
                                       "4.2.3.2",
                                       4322);
    if (mobile_flow != NULL)
    {
      evel_mobile_flow_app_type_set(mobile_flow, "Demo application");
      evel_mobile_flow_app_prot_type_set(mobile_flow, "GSM");
      evel_mobile_flow_app_prot_ver_set(mobile_flow, "1");
      evel_mobile_flow_cid_set(mobile_flow, "65535");
      evel_mobile_flow_con_type_set(mobile_flow, "S1-U");
      evel_mobile_flow_ecgi_set(mobile_flow, "e65535");
      evel_mobile_flow_gtp_prot_type_set(mobile_flow, "GTP-U");
      evel_mobile_flow_gtp_prot_ver_set(mobile_flow, "1");
      evel_mobile_flow_http_header_set(mobile_flow,
                                       "http://www.something.com");
      evel_mobile_flow_imei_set(mobile_flow, "209917614823");
      evel_mobile_flow_imsi_set(mobile_flow, "355251/05/850925/8");
      evel_mobile_flow_lac_set(mobile_flow, "1");
      evel_mobile_flow_mcc_set(mobile_flow, "410");
      evel_mobile_flow_mnc_set(mobile_flow, "04");
      evel_mobile_flow_msisdn_set(mobile_flow, "6017123456789");
      evel_mobile_flow_other_func_role_set(mobile_flow, "MME");
      evel_mobile_flow_rac_set(mobile_flow, "514");
      evel_mobile_flow_radio_acc_tech_set(mobile_flow, "LTE");
      evel_mobile_flow_sac_set(mobile_flow, "1");
      evel_mobile_flow_samp_alg_set(mobile_flow, 1);
      evel_mobile_flow_tac_set(mobile_flow, "2099");
      evel_mobile_flow_tunnel_id_set(mobile_flow, "Tunnel 1");
      evel_mobile_flow_vlan_id_set(mobile_flow, "15");

      evel_rc = evel_post_event((EVENT_HEADER *)mobile_flow);
      if (evel_rc != EVEL_SUCCESS)
      {
        EVEL_ERROR("Post Mobile Flow failed %d (%s)",
                   evel_rc,
                   evel_error_string());
      }
    }
    else
    {
      EVEL_ERROR("New Mobile Flow failed");
    }
    printf("   Processed partial Mobile Flow\n");
  }
  else
  {
    EVEL_ERROR("New GTP Per Flow Metrics failed - skipping Mobile Flow");
    printf("   Skipped partial Mobile Flow\n");
  }

  metrics = evel_new_mobile_gtp_flow_metrics(12.32,
                                             3.122,
                                             1002,
                                             21002,
                                             5002,
                                             1470409423,
                                             9872,
                                             1470409433,
                                             112,
                                             (time_t)1470409433,
                                             "Failed",
                                             872,
                                             32,
                                             172,
                                             1236542,
                                             45612,
                                             2,
                                             122,
                                             102,
                                             12,
                                             32,
                                             72,
                                             8992,
                                             9012,
                                             3022,
                                             62,
                                             22,
                                             2,
                                             1102,
                                             2252);
  if (metrics != NULL)
  {
    evel_mobile_gtp_metrics_dur_con_fail_set(metrics, 12);
    evel_mobile_gtp_metrics_dur_tun_fail_set(metrics, 13);
    evel_mobile_gtp_metrics_act_by_set(metrics, "Remote");
    evel_mobile_gtp_metrics_act_time_set(metrics, (time_t)1470409423);
    evel_mobile_gtp_metrics_deact_by_set(metrics, "Remote");
    evel_mobile_gtp_metrics_con_status_set(metrics, "Connected");
    evel_mobile_gtp_metrics_tun_status_set(metrics, "Not tunneling");
    evel_mobile_gtp_metrics_iptos_set(metrics, 1, 13);
    evel_mobile_gtp_metrics_iptos_set(metrics, 17, 1);
    evel_mobile_gtp_metrics_iptos_set(metrics, 4, 99);
    evel_mobile_gtp_metrics_large_pkt_rtt_set(metrics, 80);
    evel_mobile_gtp_metrics_large_pkt_thresh_set(metrics, 600.0);
    evel_mobile_gtp_metrics_max_rcv_bit_rate_set(metrics, 1357924680);
    evel_mobile_gtp_metrics_max_trx_bit_rate_set(metrics, 235711);
    evel_mobile_gtp_metrics_num_echo_fail_set(metrics, 1);
    evel_mobile_gtp_metrics_num_tun_fail_set(metrics, 4);
    evel_mobile_gtp_metrics_num_http_errors_set(metrics, 2);
    evel_mobile_gtp_metrics_tcp_flag_count_add(metrics, EVEL_TCP_CWR, 10);
    evel_mobile_gtp_metrics_tcp_flag_count_add(metrics, EVEL_TCP_URG, 121);
    evel_mobile_gtp_metrics_qci_cos_count_add(
                                metrics, EVEL_QCI_COS_UMTS_CONVERSATIONAL, 11);
    evel_mobile_gtp_metrics_qci_cos_count_add(
                                            metrics, EVEL_QCI_COS_LTE_65, 122);

    mobile_flow = evel_new_mobile_flow("Outbound",
                                       metrics,
                                       "RTP",
                                       "IPv8",
                                       "2.3.4.3",
                                       2343,
                                       "4.2.3.3",
                                       4323);
    if (mobile_flow != NULL)
    {
      evel_mobile_flow_app_type_set(mobile_flow, "Demo application 2");
      evel_mobile_flow_app_prot_type_set(mobile_flow, "GSM");
      evel_mobile_flow_app_prot_ver_set(mobile_flow, "2");
      evel_mobile_flow_cid_set(mobile_flow, "1");
      evel_mobile_flow_con_type_set(mobile_flow, "S1-U");
      evel_mobile_flow_ecgi_set(mobile_flow, "e1");
      evel_mobile_flow_gtp_prot_type_set(mobile_flow, "GTP-U");
      evel_mobile_flow_gtp_prot_ver_set(mobile_flow, "1");
      evel_mobile_flow_http_header_set(mobile_flow, "http://www.google.com");
      evel_mobile_flow_imei_set(mobile_flow, "209917614823");
      evel_mobile_flow_imsi_set(mobile_flow, "355251/05/850925/8");
      evel_mobile_flow_lac_set(mobile_flow, "1");
      evel_mobile_flow_mcc_set(mobile_flow, "410");
      evel_mobile_flow_mnc_set(mobile_flow, "04");
      evel_mobile_flow_msisdn_set(mobile_flow, "6017123456789");
      evel_mobile_flow_other_func_role_set(mobile_flow, "MMF");
      evel_mobile_flow_rac_set(mobile_flow, "514");
      evel_mobile_flow_radio_acc_tech_set(mobile_flow, "3G");
      evel_mobile_flow_sac_set(mobile_flow, "1");
      evel_mobile_flow_samp_alg_set(mobile_flow, 2);
      evel_mobile_flow_tac_set(mobile_flow, "2099");
      evel_mobile_flow_tunnel_id_set(mobile_flow, "Tunnel 2");
      evel_mobile_flow_vlan_id_set(mobile_flow, "4096");

      evel_rc = evel_post_event((EVENT_HEADER *)mobile_flow);
      if (evel_rc != EVEL_SUCCESS)
      {
        EVEL_ERROR("Post Mobile Flow failed %d (%s)",
                   evel_rc,
                   evel_error_string());
      }
    }
    else
    {
      EVEL_ERROR("New Mobile Flow failed");
    }
    printf("   Processed full Mobile Flow\n");
  }
  else
  {
    EVEL_ERROR("New GTP Per Flow Metrics failed - skipping Mobile Flow");
    printf("   Skipped full Mobile Flow\n");
  }
}

/**************************************************************************//**
 * Create and send a Service event.
 *****************************************************************************/
void demo_service()
{
  demo_service_event(SERVICE_CODEC);
  demo_service_event(SERVICE_TRANSCODING);
  demo_service_event(SERVICE_RTCP);
  demo_service_event(SERVICE_EOC_VQM);
  demo_service_event(SERVICE_MARKER);
}

void demo_service_event(const SERVICE_EVENT service_event)
{
  EVENT_SERVICE * event = NULL;
  EVEL_ERR_CODES evel_rc = EVEL_SUCCESS;

  event = evel_new_service("vendor_x_id", "vendor_x_event_id");
  if (event != NULL)
  {
    evel_service_type_set(event, "Service Event");
    evel_service_product_id_set(event, "vendor_x_product_id");
    evel_service_subsystem_id_set(event, "vendor_x_subsystem_id");
    evel_service_friendly_name_set(event, "vendor_x_frieldly_name");
    evel_service_correlator_set(event, "vendor_x_correlator");
    evel_service_addl_field_add(event, "Name1", "Value1");
    evel_service_addl_field_add(event, "Name2", "Value2");

    switch (service_event)
    {
      case SERVICE_CODEC:
        evel_service_codec_set(event, "PCMA");
        break;
      case SERVICE_TRANSCODING:
        evel_service_callee_codec_set(event, "PCMA");
        evel_service_caller_codec_set(event, "G729A");
        break;
      case SERVICE_RTCP:
        evel_service_rtcp_data_set(event, "some_rtcp_data");
        break;
      case SERVICE_EOC_VQM:
        evel_service_adjacency_name_set(event, "vendor_x_adjacency");
        evel_service_endpoint_desc_set(event, EVEL_SERVICE_ENDPOINT_CALLER);
        evel_service_endpoint_jitter_set(event, 66);
        evel_service_endpoint_rtp_oct_disc_set(event, 100);
        evel_service_endpoint_rtp_oct_recv_set(event, 200);
        evel_service_endpoint_rtp_oct_sent_set(event, 300);
        evel_service_endpoint_rtp_pkt_disc_set(event, 400);
        evel_service_endpoint_rtp_pkt_recv_set(event, 500);
        evel_service_endpoint_rtp_pkt_sent_set(event, 600);
        evel_service_local_jitter_set(event, 99);
        evel_service_local_rtp_oct_disc_set(event, 150);
        evel_service_local_rtp_oct_recv_set(event, 250);
        evel_service_local_rtp_oct_sent_set(event, 350);
        evel_service_local_rtp_pkt_disc_set(event, 450);
        evel_service_local_rtp_pkt_recv_set(event, 550);
        evel_service_local_rtp_pkt_sent_set(event, 650);
        evel_service_mos_cqe_set(event, 12.255);
        evel_service_packets_lost_set(event, 157);
        evel_service_packet_loss_percent_set(event, 0.232);
        evel_service_r_factor_set(event, 11);
        evel_service_round_trip_delay_set(event, 15);
        break;
      case SERVICE_MARKER:
        evel_service_phone_number_set(event, "0888888888");
        break;
    }

    evel_rc = evel_post_event((EVENT_HEADER *) event);
    if (evel_rc != EVEL_SUCCESS)
    {
      EVEL_ERROR("Post failed %d (%s)", evel_rc, evel_error_string());
    }
  }
  else
  {
    EVEL_ERROR("New Service failed");
  }
  printf("   Processed Service Events\n");
}

/**************************************************************************//**
 * Create and send a Signaling event.
 *****************************************************************************/
void demo_signaling(void)
{
  EVENT_SIGNALING * event = NULL;
  EVEL_ERR_CODES evel_rc = EVEL_SUCCESS;

  event = evel_new_signaling("vendor_x_id", "vendor_x_event_id");
  if (event != NULL)
  {
    evel_signaling_type_set(event, "Signaling");
    evel_signaling_product_id_set(event, "vendor_x_product_id");
    evel_signaling_subsystem_id_set(event, "vendor_x_subsystem_id");
    evel_signaling_friendly_name_set(event, "vendor_x_frieldly_name");
    evel_signaling_correlator_set(event, "vendor_x_correlator");
    evel_signaling_local_ip_address_set(event, "1.0.3.1");
    evel_signaling_local_port_set(event, "1031");
    evel_signaling_remote_ip_address_set(event, "5.3.3.0");
    evel_signaling_remote_port_set(event, "5330");
    evel_signaling_compressed_sip_set(event, "compressed_sip");
    evel_signaling_summary_sip_set(event, "summary_sip");
    evel_rc = evel_post_event((EVENT_HEADER *) event);
    if (evel_rc != EVEL_SUCCESS)
    {
      EVEL_ERROR("Post failed %d (%s)", evel_rc, evel_error_string());
    }
  }
  else
  {
    EVEL_ERROR("New Signaling failed");
  }
  printf("   Processed Signaling\n");
}

/**************************************************************************//**
 * Create and send a state change event.
 *****************************************************************************/
void demo_state_change(void)
{
  EVENT_STATE_CHANGE * state_change = NULL;
  EVEL_ERR_CODES evel_rc = EVEL_SUCCESS;

  /***************************************************************************/
  /* State Change                                                            */
  /***************************************************************************/
  state_change = evel_new_state_change(EVEL_ENTITY_STATE_IN_SERVICE,
                                       EVEL_ENTITY_STATE_OUT_OF_SERVICE,
                                       "Interface");
  if (state_change != NULL)
  {
    evel_state_change_type_set(state_change, "State Change");
    evel_state_change_addl_field_add(state_change, "Name1", "Value1");
    evel_state_change_addl_field_add(state_change, "Name2", "Value2");
    evel_rc = evel_post_event((EVENT_HEADER *)state_change);
    if (evel_rc != EVEL_SUCCESS)
    {
      EVEL_ERROR("Post failed %d (%s)", evel_rc, evel_error_string());
    }
  }
  else
  {
    EVEL_ERROR("New State Change failed");
  }
  printf("   Processed State Change\n");
}

/**************************************************************************//**
 * Create and send two syslog events.
 *****************************************************************************/
void demo_syslog(void)
{
  EVENT_SYSLOG * syslog = NULL;
  EVEL_ERR_CODES evel_rc = EVEL_SUCCESS;

  /***************************************************************************/
  /* Syslog                                                                  */
  /***************************************************************************/
  syslog = evel_new_syslog(EVEL_SOURCE_VIRTUAL_NETWORK_FUNCTION,
                           "EVEL library message",
                           "EVEL");
  if (syslog != NULL)
  {
    evel_rc = evel_post_event((EVENT_HEADER *)syslog);
    if (evel_rc != EVEL_SUCCESS)
    {
      EVEL_ERROR("Post failed %d (%s)", evel_rc, evel_error_string());
    }
  }
  else
  {
    EVEL_ERROR("New Syslog failed");
  }
  printf("   Processed empty Syslog\n");

  syslog = evel_new_syslog(EVEL_SOURCE_VIRTUAL_MACHINE,
                           "EVEL library message",
                           "EVEL");
  if (syslog != NULL)
  {
    evel_syslog_event_source_host_set(syslog, "Virtual host");
    evel_syslog_facility_set(syslog, EVEL_SYSLOG_FACILITY_LOCAL0);
    evel_syslog_proc_set(syslog, "vnf_process");
    evel_syslog_proc_id_set(syslog, 1423);
    evel_syslog_version_set(syslog, 1);
    evel_syslog_addl_field_add(syslog, "Name1", "Value1");
    evel_syslog_addl_field_add(syslog, "Name2", "Value2");
    evel_syslog_addl_field_add(syslog, "Name3", "Value3");
    evel_syslog_addl_field_add(syslog, "Name4", "Value4");
    evel_rc = evel_post_event((EVENT_HEADER *)syslog);
    if (evel_rc != EVEL_SUCCESS)
    {
      EVEL_ERROR("Post failed %d (%s)", evel_rc, evel_error_string());
    }
  }
  else
  {
    EVEL_ERROR("New Syslog failed");
  }
  printf("   Processed full Syslog\n");
}

/**************************************************************************//**
 * Create and send two other events.
 *****************************************************************************/
void demo_other(void)
{
  EVENT_OTHER * other = NULL;
  EVEL_ERR_CODES evel_rc = EVEL_SUCCESS;

  /***************************************************************************/
  /* Other                                                                   */
  /***************************************************************************/
  other = evel_new_other();
  if (other != NULL)
  {
    evel_rc = evel_post_event((EVENT_HEADER *)other);
    if (evel_rc != EVEL_SUCCESS)
    {
      EVEL_ERROR("Post failed %d (%s)", evel_rc, evel_error_string());
    }
  }
  else
  {
    EVEL_ERROR("New Other failed");
  }
  printf("   Processed empty Other\n");

  other = evel_new_other();
  if (other != NULL)
  {
    evel_other_field_add(other,
                         "Other field 1",
                         "Other value 1");
    evel_rc = evel_post_event((EVENT_HEADER *)other);
    if (evel_rc != EVEL_SUCCESS)
    {
      EVEL_ERROR("Post failed %d (%s)", evel_rc, evel_error_string());
    }
  }
  else
  {
    EVEL_ERROR("New Other failed");
  }
  printf("   Processed small Other\n");

  other = evel_new_other();
  if (other != NULL)
  {
    evel_other_field_add(other,
                         "Other field A",
                         "Other value A");
    evel_other_field_add(other,
                         "Other field B",
                         "Other value B");
    evel_other_field_add(other,
                         "Other field C",
                         "Other value C");
    evel_rc = evel_post_event((EVENT_HEADER *)other);
    if (evel_rc != EVEL_SUCCESS)
    {
      EVEL_ERROR("Post failed %d (%s)", evel_rc, evel_error_string());
    }
  }
  else
  {
    EVEL_ERROR("New Other failed");
  }
  printf("   Processed large Other\n");
}
