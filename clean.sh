#!/bin/bash
#set -e

# Absolute path to this script
SCRIPT=$(readlink -f "$0")
# Absolute path to the script directory
BASEDIR=$(dirname "$SCRIPT")


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

function backup_secrets {
  if [ -x "$(command -v kubectl)" ]; then
    mkdir -p /opt/backup/secrets
    echo "#### Backing up Kubernetes secrets..."
    secrets_list=$(kubectl get secrets | tail -n +2 | awk '{print $1}')
    relevant_secrets_list=("redis-secret" "mongodb-secret" "rabbitmq-secret" "ingress-basic-auth-secret")
    for secret in $secrets_list
    do
      if [[ " ${relevant_secrets_list[@]} " =~ " ${secret} " ]]; then
        echo "#### Backing up secret $secret"
        kubectl get secret $secret -o yaml | grep -v "^  \(creation\|resourceVersion\|selfLink\|uid\)" > /opt/backup/secrets/$secret.yaml
      fi
    done
  else
    echo "#### kubectl does not exists, skipping secrets backup phase."
  fi
}

function remove_nvidia_drivers {
  if [ -x "$(command -v apt-get)" ]; then
    if dpkg-query --show nvidia-driver-410 ; then
      echo "Nvidia driver is already on the right version (410)"
    else
      echo "#### Removing Nvidia driver..."
      apt remove -y --purge nvidia-* cuda-*
      apt autoremove
      add-apt-repository -y --remove ppa:graphics-drivers/ppa
    fi
  elif [ -x "$(command -v yum)" ]; then
    if [ $(modinfo nvidia -F version) == "410.104" ]; then
      echo "Nvidia driver is already on the right version (410)"
    else
      echo "#### Removing Nvidia driver..."
      ./$(ls -la | grep NVIDIA-Linux | awk '{print $NF}') --silent --uninstall
    fi
  fi
}

function remove_nvidia_docker {
  if [ -x "$(command -v nvidia-docker)" ]; then
    echo "#### Removing Nvidia-Docker..."
    if [ -x "$(command -v apt-get)" ]; then
      apt remove -y --purge nvidia-docker*
      apt autoremove
    elif [ -x "$(command -v yum)" ]; then
      yum remove -y nvidia-docker*
    fi
  else
    echo "#### nvidia-docker does not exists, skipping nvidia-docker removal phase."
  fi
}

function disable_k3s {
  if systemctl is-active --quiet k3s; then
    echo "#### Stopping k3s service..."
    systemctl stop k3s
    systemctl is-enabled --quiet k3s && echo "#### Disabling k3s service..." && systemctl disable k3s
  else
    echo "#### k3s is not active, skipping k3s service disabling phase."
  fi
  #if [ -x "$(command -v k3s-uninstall.sh)" ]; then
  #  k3s-uninstall.sh
  #else
  #  echo "#### k3s uninstall script does not exists, skipping k3s removal phase."
  #fi
}

function disable_docker {
  if [ -x "$(command -v docker)" ] && systemctl is-active --quiet docker; then
    echo "#### Killing all running containers..."
    docker kill $(docker ps -q)
    echo "#### Removing all stopped containers..."
    docker rm $(docker ps -aq)
    echo "#### Pruning all docker networks..."
    docker network prune -f
    #docker system prune -f
    echo "#### Stopping Docker service..."
    systemctl stop docker
    systemctl is-enabled --quiet docker && echo "#### Disabling Docker service..." && systemctl disable docker
  else
    echo "#### docker does not exists or is disabled, skipping docker service disabling phase."
  fi
  #if [ -x "$(command -v docker)" ] && [ -x "$(command -v apt-get)" ]; then
  #  apt remove -y --purge docker*
  #elif [ -x "$(command -v docker)" ] && [ -x "$(command -v yum)" ]; then
  #  yum remove -y docker*
  #fi
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
        backup_secrets
        disable_k3s
        disable_docker
        #remove_nvidia_docker
        remove_nvidia_drivers
        exit 0
        ;;
        -s|--backup-secrets)
        backup_secrets
        exit 0
        ;;
        -k|--disable-k3s)
        disable_k3s
        exit 0
        ;;
        -d|--disable-docker)
        disable_docker
        exit 0
        ;;
        -n|--remove-nvidia-docker)
        remove_nvidia_docker
        exit 0
        ;;
        -v|--remove-nvidia-drivers)
        remove_nvidia_drivers
        exit 0
        ;;
    esac
    break
done
