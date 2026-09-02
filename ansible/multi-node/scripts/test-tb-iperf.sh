#!/bin/bash
# Run iperf3 throughput test between halo0 and halo1 over TB4

# Step 1: Start server on halo0 via a background script
ssh jdella@192.168.7.145 "pkill -f iperf3 2>/dev/null || true"
ssh jdella@192.168.7.145 "bash -c 'nohup iperf3 -s -p 5201 -P 4 > /tmp/tb-iperf3-srv.log 2>&1 & echo \$!'" > /tmp/tb-iperf3-srv-pid.txt
sleep 2

# Verify server
echo "=== Server check on halo0 ==="
ssh jdella@192.168.7.145 "ps aux | grep 'iperf3.*-s' | grep -v grep"

# Step 2: Run client from halo1
echo ""
echo "=== iperf3 client throughput test (10s, 4 parallel streams) ==="
echo "(client on halo1 connecting to server on halo0)"
ssh jdella@192.168.7.179 "iperf3 -c 172.20.0.1 -p 5201 -t 10 -P 4" 2>&1

# Cleanup
ssh jdella@192.168.7.145 "pkill -f 'iperf3 -s' 2>/dev/null || true"
