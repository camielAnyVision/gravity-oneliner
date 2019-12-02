#!/usr/bin/env bash

echo "Getting Master Join Token"
JOIN_TOKEN=$(gravity exec gravity status --token)
echo "Getting Master IP Address"
MASTER_IP=$(gravity exec gravity status --output=json | jq -r .cluster.nodes[0].advertise_ip)

echo ""
echo "RUN the following commands on the node as root to join node to cluster"
echo ""
echo ""
echo "==================================================================="
echo ""
echo "curl -k -H \"Authorization: Bearer ${JOIN_TOKEN}\" https://${MASTER_IP}:32009/portal/v1/gravity -o /usr/local/bin/gravity"
echo chmod +x /usr/local/bin/gravity
echo gravity join ${MASTER_IP} --token=${JOIN_TOKEN} --role=edge --cloud-provider=generic
echo ""
echo "====================================================================="
