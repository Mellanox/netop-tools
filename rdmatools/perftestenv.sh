#!/bin/bash
#
#
mkdir -p /home
addgroup perftest
useradd --create-home -d /home/perftest --gid perftest perftest
chown -R perftest:perftest /home/perftest
