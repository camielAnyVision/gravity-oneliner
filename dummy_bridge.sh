#!/bin/bash
set -e

## Get default interface name
DEFAULT_INTERFACE=$(route | awk '/^default/{print $NF}')

## Load the dummy kernel module
modprobe dummy

## Create dummy interface
ip link add gravity0 type dummy

## Create bridge interface
ip link add br0 type bridge

## Bring down the default interface before attaching it to the bridge
ip link set dev ${1:-$DEFAULT_INTERFACE} down

## Add slaves to bridge
ip link set dev ${1:-$DEFAULT_INTERFACE} master br0
ip link set dev gravity0 master br0

## Bring the interfaces up
ip link set dev br0 up
ip link set dev gravity0 up
ip link set dev ${1:-$DEFAULT_INTERFACE} up

## Set bridge IP
#ip addr add 192.168.100.1/24 dev br0
dhclient br0

## Set basic masquerading for ipv4
iptables -I FORWARD -j ACCEPT
# iptables -t nat -I POSTROUTING -s 192.168.100.0/24 -j MASQUERADE
iptables -t nat -A POSTROUTING -o br0 -j MASQUERADE
iptables -t nat -A POSTROUTING -o ${1:-$DEFAULT_INTERFACE} -j MASQUERADE
