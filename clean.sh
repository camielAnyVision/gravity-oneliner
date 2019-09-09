#!/bin/bash

set -e

# Absolute path to this script
SCRIPT=$(readlink -f "$0")
# Absolute path to the script directory
BASEDIR=$(dirname "$SCRIPT")
INSTALL_MODE="aio"
INSTALL_METHOD="online"
PRODUCT_NAME="bettertomorrow"
PRODUCT_VERSION="1.23.1-5"


## Permissions check
if [[ $EUID -ne 0 ]]; then
   echo "Error: This script must be run as root." | tee -a ${BASEDIR}/gravity-installer.log
   echo "Installation failed, please contact support." | tee -a ${BASEDIR}/gravity-installer.log
   exit 1
fi

## Get home Dir of the current user
if [ $SUDO_USER ]; then
  user=$SUDO_USER
else
  user=`whoami`
fi

if [ ${user} == "root" ]; then
  user_home_dir="/${user}"
else
  user_home_dir="/home/${user}"
fi

function showhelp {
  echo ""
  echo "Gravity Oneliner Updater"
  echo ""
  echo "OPTIONS:"
  echo "  [-h|help|--help]"
  echo "  [-a|--all] Peform all arguments"
  echo "  [--backup-secrets] Backup secretes"
  echo "  [--disable-k3s] Remove k3s"
  echo "  [--disable-docker] Disable Docker"
  echo "  [--remove-nvidia-docker] Product version to install"
  echo "  [--remove-nvidia-drivers] Remove nvidia drivers"
  echo ""
}

POSITIONAL=()
while test $# -gt 0; do
    key="$1"
    case $key in
        -h|help|--help)
        showhelp
        exit 0
        ;;
        -a|--all)
        shift
            ALL=${1:-false}
        shift
        continue
        ;;
        --backup-secrets)
        shift
            BACKUP_SECRETS=${1:-false}
        shift
        continue
        ;;
        --remove-k3s)
        shift
            REMOVE_K3S=${1:-false}
        shift
        continue
        ;;
        --remove-docker)
        shift
            REMOVE_DOCKER=${1:-false}
        shift
        continue
        ;;
        --remove-nvidia-docker)
        shift
            REMOVE_NVIDIA_DOCKER=${1:-false}
        shift
        continue
        ;;                
        --remove-nvidia-drivers)
        shift
            REMOVE_NVIDIA_DRIVERS=${1:-false}
        shift
        continue
        ;;
    esac
    break
done

function is_kubectl_exists() {
  ## Check if this machine is part of an existing Kubernetes cluster
  if gravity status --quiet > /dev/null 2>&1; then
    echo "Gravity cluster is already installed"  
    if [ -x "$(command -v kubectl)" ]; then
      if [[ $(kubectl cluster-info) == *'Kubernetes master'*'running'*'https://'* ]]; then
        echo "" | tee -a ${LOG_FILE}
        echo "Error: this machine is a part of an existing Kubernetes cluster, please detach it before running this installer." | tee -a ${LOG_FILE}
        exit 1
        KUBECTL_EXISTS=true
      fi
    fi
  fi
}

function backup_secrets(){
  echo "Backup Secrets"

}

function remove_nvidia_drivers(){
  if [ -x "$(command -v apt-get)" ]; then
    if dpkg-query --show nvidia-driver-410 ; then
      echo "already right version"
    else
      echo "Removing nvidia driver"
    fi
  elif [ -x "$(command -v yum)" ]; then
    if rpm -q --quiet nvidia-driver-410*; then
      echo "already right version"
    else
      echo "Removing nvidia driver"
    fi
  fi
}

function remove_nvidia_docker(){
  if [ -x "$(command -v apt-get)" ]; then

  elif [ -x "$(command -v yum)" ]; then

  fi
}

function disable_k3s(){
  echo "Disable K3S"
  systemctl stop k3s
  systemctl disable k3s
}

function disable_docker(){
  echo ""
  echo "stop all containers"
  docker kill $(docker ps -q)
  docker rm $(docker ps -aq)
  docker system prune -f

  systemctl stop docker 
  systemctl disable docker 
}

