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
  echo "  [-h|--help] help"
  echo "  [-a|--all] Perform all arguments"
  echo "  [-s|--backup-secrets] Backup secrets"
  echo "  [-k|--disable-k3s] Disable k3s"
  echo "  [-d|--disable-docker] Disable Docker"
  echo "  [-n|--remove-nvidia-docker] Remove Nvidia-docker"
  echo "  [-v|--remove-nvidia-drivers] Remove Nvidia drivers"
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
        -s|--backup-secrets)
        shift
            BACKUP_SECRETS=${1:-false}
        shift
        continue
        ;;
        -k|--disable-k3s)
        shift
            DISABLE_K3S=${1:-false}
        shift
        continue
        ;;
        -d|--disable-docker)
        shift
            DISABLE_DOCKER=${1:-false}
        shift
        continue
        ;;
        -n|--remove-nvidia-docker)
        shift
            REMOVE_NVIDIA_DOCKER=${1:-false}
        shift
        continue
        ;;
        -v|--remove-nvidia-drivers)
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
  mkdir -p /opt/backup/secrets
  echo "###########################"
  echo "# Backing up secrets. . . #"
  echo "###########################"
  secrets_list=$(kubectl get secret | tail -n +2 | awk '{print $1}')
  relevant_secrets_list=("redis-secret" "mongodb-secret" "rabbitmq-secret" "ingress-basic-auth-secret")
  for secret in $secrets_list
  do
    if [[ " ${relevant_secrets_list[@]} " =~ " ${secret} " ]]; then
      echo "Backing up secret $secret"
      kubectl get secret $secret -o yaml | grep -v "^  \(creation\|resourceVersion\|selfLink\|uid\)" > /opt/backup/secrets/$secret.yaml
    fi
  done

}

function remove_nvidia_drivers(){
  if [ -x "$(command -v apt-get)" ]; then
    if dpkg-query --show nvidia-driver-410 ; then
      echo "Nvidia driver is already on the right version (410)"
    else
      echo "###############################"
      echo "# Removing Nvidia driver. . . #"
      echo "###############################"
      apt remove -y --purge nvidia-* cuda-*
      apt autoremove
      add-apt-repository -y --remove ppa:graphics-drivers/ppa
    fi
  elif [ -x "$(command -v yum)" ]; then
    if rpm -q --quiet nvidia-driver-410*; then
      echo "Nvidia driver is already on the right version (410)"
    else
      echo "###############################"
      echo "# Removing Nvidia driver. . . #"
      echo "###############################"
      ./$(ls -la | grep NVIDIA-Linux | awk '{print $NF}') --silent --no-install-compat32-libs --uninstall
    fi
  fi
}

function remove_nvidia_docker(){
  if [ -x "$(command -v apt-get)" ]; then
    if  [ -x "$(command -v nvidia-docker)" ]; then
      echo "###############################"
      echo "# Removing Nvidia-Docker. . . #"
      echo "###############################"
      apt remove -y --purge nvidia-docker*
      apt autoremove
    fi
  elif [ -x "$(command -v yum)" ]; then
      echo "###############################"
      echo "# Removing Nvidia-Docker. . . #"
      echo "###############################"
      yum remove -y nvidia*
  fi
}

function disable_k3s(){
  echo "###################################"
  echo "# Stopping and disabling K3S. . . #"
  echo "###################################"
  systemctl stop k3s
  systemctl disable k3s
}

function disable_docker(){
  echo "############################################"
  echo "# Killing and removing all containers. . . #"
  echo "############################################"
  docker kill $(docker ps -q)
  docker rm $(docker ps -aq)
  docker system prune -f
  echo "######################################"
  echo "# Stopping and disabling Docker. . . #"
  echo "######################################"
  systemctl stop docker
  systemctl disable docker
}

if [[ $BACKUP_SECRETS ]]; then
  backup_secrets
elif [[ $DISABLE_K3S ]]; then
  disable_k3s
elif [[ $DISABLE_DOCKER ]]; then
  disable_docker
elif [[ $REMOVE_NVIDIA_DOCKER ]]; then
  remove_nvidia_docker
elif [[ $REMOVE_NVIDIA_DRIVERS ]]; then
  remove_nvidia_drivers
elif [[ $ALL ]]; then
  backup_secrets
  disable_k3s
  disable_docker
  remove_nvidia_docker
  remove_nvidia_drivers
fi

