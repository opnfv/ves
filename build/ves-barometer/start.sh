#!/bin/bash
# Copyright 2018 AT&T Intellectual Property, Inc
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
# What this is: Startup script for the OPNFV Barometer collectd agent running
# under docker.

rm -f /opt/collectd/etc/collectd.conf.d/*

if [[ "$ves_mode" == "node" ]]; then
  cat <<EOF >/opt/collectd/etc/collectd.conf.d/collectd.conf
# for VES plugin
LoadPlugin logfile
<Plugin logfile>
  LogLevel debug
  File STDOUT
  Timestamp true
  PrintSeverity false
</Plugin>

LoadPlugin csv
<Plugin csv>
 DataDir "/work-dir/collectd/install/var/lib/csv"
 StoreRates false
</Plugin>

LoadPlugin target_set
LoadPlugin match_regex
<Chain "PreCache">
  <Rule "mark_memory_as_host">
    <Match "regex">
      Plugin "^memory$"
    </Match>
    <Target "set">
      PluginInstance "host"
    </Target>
  </Rule>
</Chain>

LoadPlugin cpu
<Plugin cpu>
  ReportByCpu true
  ReportByState true
  ValuesPercentage true
</Plugin>

LoadPlugin interface
LoadPlugin memory
LoadPlugin load
LoadPlugin disk
# TODO: how to set this option only to apply to VMs (not nodes)
LoadPlugin uuid

LoadPlugin write_kafka
<Plugin write_kafka>
  Property "metadata.broker.list" "$ves_kafka_hostname:$ves_kafka_port"
  <Topic "collectd">
    Format JSON
  </Topic>
</Plugin>
EOF

  if [[ -d /etc/nova ]]; then
    cat <<EOF >>~/collectd/collectd.conf
LoadPlugin virt
<Plugin virt>
  Connection "qemu:///system"
  RefreshInterval 60
  HostnameFormat uuid
  PluginInstanceFormat name
  ExtraStats "cpu_util"
</Plugin>
EOF
  fi
else
  cat <<EOF >/opt/collectd/etc/collectd.conf.d/collectd.conf
# for VES plugin
LoadPlugin logfile
<Plugin logfile>
  LogLevel debug
  File STDOUT
  Timestamp true
  PrintSeverity false
</Plugin>

LoadPlugin cpu
<Plugin cpu>
  ReportByCpu true
  ReportByState true
  ValuesPercentage true
</Plugin>

LoadPlugin csv
<Plugin csv>
        DataDir "/tmp"
</Plugin>

LoadPlugin interface
LoadPlugin memory
LoadPlugin load
LoadPlugin disk
LoadPlugin uuid

LoadPlugin write_kafka
<Plugin write_kafka>
  Property "metadata.broker.list" "$ves_kafka_hostname:$ves_kafka_port"
  <Topic "collectd">
    Format JSON
  </Topic>
</Plugin>

LoadPlugin target_set
LoadPlugin match_regex
<Chain "PreCache">
  <Rule "mark_memory_as_guest">
    <Match "regex">
      Plugin "^memory$"
    </Match>
    <Target "set">
      PluginInstance "guest"
    </Target>
  </Rule>
</Chain>
EOF
fi

echo; echo "cat /opt/collectd/etc/collectd.conf.d/collectd.conf"
cat /opt/collectd/etc/collectd.conf.d/collectd.conf

#echo "Delete conf files causing collectd to fail"
#rm -f /opt/collectd/etc/collectd.conf.d/dpdk*.conf
#rm -f /opt/collectd/etc/collectd.conf.d/snmp*.conf
#rm -f /opt/collectd/etc/collectd.conf.d/virt.conf
#rm -f /opt/collectd/etc/collectd.conf.d/mcelog.conf
#rm -f /opt/collectd/etc/collectd.conf.d/rdt.conf
#sed -i -- 's/LoadPlugin cpufreq/#LoadPlugin cpufreq/' /opt/collectd/etc/collectd.conf.d/default_plugins.conf

/opt/collectd/sbin/collectd -f
echo "collectd has exited. sleeping for an hour to enable debugging"
sleep 3600
