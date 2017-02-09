.. This work is licensed under a
.. Creative Commons Attribution 4.0 International License.
.. http://creativecommons.org/licenses/by/4.0
.. (c) 2015-2017 AT&T Intellectual Property, Inc

===================
OPNFV VES Use Cases
===================

Implemented in Current Release
------------------------------

VES Hello World
...............

The VES Hello World demo runs in a multi-node bare metal or virtual install,
adding VES agents for the hosts (bare metal, VMs) and apps. Data is collected
by `collectd <https://collectd.org/>`_ and sent in JSON format via HTTP to a the
VES collector agent.

This use case is a basic TOSCA blueprint-based test using Tacker as the VNFM:
a single-node simple python web server, connected to two internal networks (private and admin),
and accessible via a floating IP. This is based upon the OpenStack Tacker project's 'tosca-vnfd-hello-world' blueprint,
as modified/extended for testing of Tacker-supported features as of OpenStack Newton.


Information on and links to the VES Hello World demo can be
found on the `VES Demo page <https://wiki.opnfv.org/display/ves/vHello_VES+Demo>`_.


