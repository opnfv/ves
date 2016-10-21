/**************************************************************************//**
 * @file
 * Agent for the OPNFV VNF Event Stream (VES) vHello_VES test
 *
 * Copyright 2016 AT&T Intellectual Property, Inc
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
#include <string.h>
#include <unistd.h>
#include <getopt.h>
#include <sys/signal.h>
#include <pthread.h>
#include <mcheck.h>
#include <time.h> 

#include "evel.h"
#include "evel_demo.h"

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
    {"username", required_argument, 0, 'u'},
    {"password", required_argument, 0, 'p'},
    {"verbose",  no_argument,       0, 'v'},
    {0, 0, 0, 0}
  };

/**************************************************************************//**
 * Definition of short options to the program.
 *****************************************************************************/
static const char* short_options = "h:i:f:n:u:p:v:";

/**************************************************************************//**
 * Basic user help text describing the usage of the application.
 *****************************************************************************/
static const char* usage_text =
"evel_demo [--help]\n"
"          --id <Agent host ID>\n"
"          --fqdn <domain>\n"
"          --port <port_number>\n"
"          --username <username>\n"
"          --password <password>\n"
"          [--verbose]\n"
"\n"
"Agent for the OPNFV VNF Event Stream (VES) vHello_VES test.\n"
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
"  -u         Username for authentication to the RESTful API.\n"
"  --username\n"
"\n"
"  -p         Password for authentication to the RESTful API.\n"
"  --password\n"
"\n"
"  -v         Generate much chattier logs.\n"
"  --verbose\n";

/**************************************************************************//**
 * Global flags related the applicaton.
 *****************************************************************************/

char *app_prevstate = "Stopped";

/**************************************************************************//**
 * Global flag to initiate shutdown.
 *****************************************************************************/
static int glob_exit_now = 0;

static void show_usage(FILE* fp)
{
  fputs(usage_text, fp);
}

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
    measurement = evel_new_measurement(concurrent_sessions, 
      configured_entities, mean_request_latency, measurement_interval,
      memory_configured, memory_used, request_rate);

    if (measurement != NULL) {
      cpu();
      evel_measurement_type_set(measurement, "HTTP request rate");
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
  char * api_fqdn = NULL;
  int api_port = 0;
  char * api_username = NULL;
  char * api_password = NULL;
  char * api_path = NULL;
  char * api_topic = NULL;
  int api_secure = 0;
  int verbose_mode = 0;
  EVEL_ERR_CODES evel_rc = EVEL_SUCCESS;
  EVENT_HEADER * heartbeat = NULL;
//  EVENT_FAULT * fault = NULL;
//  EVENT_MEASUREMENT * measurement = NULL;
//  EVENT_REPORT * report = NULL;

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

      case 'u':
        api_username = optarg;
        break;

      case 'p':
        api_password = optarg;
        break;

      case 'v':
        verbose_mode = 1;
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
                      "vHello_VES agent",
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
  /* MAIN LOOP                                                               */
  /***************************************************************************/
  while (1)
  {
    EVEL_INFO("MAI: Starting main loop");
//    printf("Starting main loop\n");

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
    /* MAIN RETRY LOOP.  Loop every 10 secs.                                 */
    /* TODO: Listener for throttling back scheduled reports.                 */
    /*************************************************************************/
 //   printf("End of main loop, sleeping for 10 seconds\n");
    fflush(stdout);
    sleep(10);
 }
  /***************************************************************************/
  /* We are exiting, but allow the final set of events to be dispatched      */
  /* properly first.                                                         */
  /***************************************************************************/
  sleep(1);
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
