#!/bin/bash
# Start iperf3 server on halo0
pkill -9 iperf3 2>/dev/null || true
sleep 1
nohup iperf3 -s -p 5201 > /tmp/iperf3-srv.log 2>&1 &
sleep 2
ps aux | grep 'iperf3.*-s' | grep -v grep || echo "Server NOT started"
ss -tlnp | grep 5201 || echo "Port 5201 not listening"
