#!/usr/bin/env bash


NOCOLOR='\033[0m'
RED='\033[0;31m'
GREEN='\033[0;32m'
ORANGE='\033[0;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
LIGHTGRAY='\033[0;37m'
DARKGRAY='\033[1;30m'
LIGHTRED='\033[1;31m'
LIGHTGREEN='\033[1;32m'
YELLOW='\033[1;33m'
LIGHTBLUE='\033[1;34m'
LIGHTPURPLE='\033[1;35m'
LIGHTCYAN='\033[1;36m'
WHITE='\033[1;37m'

function get_join_command() {
role=$1
echo -e ${LIGHTBLUE}
echo "Getting Master Join Token"
JOIN_TOKEN=$(gravity exec gravity status --token)
echo "Getting Master IP Address"
MASTER_IP=$(gravity exec gravity status --output=json | ./jq -r .cluster.nodes[0].advertise_ip)
echo "RUN the following commands on the node as root to join node to cluster"
echo ""
echo ""
echo "==================================================================="
echo ""
echo "curl -k -H \"Authorization: Bearer ${JOIN_TOKEN}\" https://${MASTER_IP}:32009/portal/v1/gravity -o /usr/local/bin/gravity"
echo chmod +x /usr/local/bin/gravity
echo gravity join ${MASTER_IP} --token=${JOIN_TOKEN} --role=$1
echo ""
echo -e "=====================================================================${WHITE}"

}

## MAIN

echo -e ${YELLOW}
echo "Join Node tool"
echo "=============="
declare -a nodeProfiles=("edge" "backend[master]")
n=1
for i in ${!nodeProfiles[@]}
do
    num=$(expr $i + 1)
    echo $num "${nodeProfiles[$i]}"
done
echo -e ${WHITE}
read -p "Please choose:" choose

case $choose in 
    1) myrole="edge"
       get_join_command $myrole
       ;; 
    2) myrole="backend"
       get_join_command $myrole
       ;;
    3) myrole="backend"
       get_join_command $myrole
       ;;
    *) echo -e "${RED}Wrong option..Exit${WHITE}";
       exit 1;;
esac 

