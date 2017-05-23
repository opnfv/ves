/**************************************************************************//**
 * @file
 * Agent for the OPNFV VNF Event Stream (VES) ves_onap_demo test
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
  int status = EVEL_VF_STATUS_ACTIVE;
  
  if (change == "Stopped") {
    status = EVEL_VF_STATUS_IDLE;
  }

  fault = evel_new_fault("App state change",
    change,
    EVEL_PRIORITY_HIGH,
    EVEL_SEVERITY_MAJOR,
    EVEL_SOURCE_VIRTUAL_NETWORK_FUNCTION,
    status);

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

  fp = popen("sudo docker inspect onap-demo | grep Status | sed -- 's/,//g' | sed -- 's/\"//g' | sed -- 's/            Status: //g'", "r");
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
  strcpy(cmd, "sudo docker logs onap-demo | grep -c ");
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

