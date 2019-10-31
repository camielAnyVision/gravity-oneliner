#!/bin/bash
set -e

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
  echo "  [-p|--backup-pv-id] Backup SW-filer pv id"
  echo "  [-c|--backup-consul-data] Save consul snapshot"
  echo "  [-k|--remove-k8s] Remove k8s"
  echo "  [-d|--remove-docker] Remove Docker"
  echo "  [-n|--remove-nvidia-docker] Remove Nvidia-docker"
  echo "  [-v|--remove-nvidia-drivers] Remove Nvidia drivers"
  echo ""
}

function backup_secrets {
  if kubectl cluster-info > /dev/null 2&>1; then
    mkdir -p /opt/backup/secrets
    echo "#### Backing up Kubernetes secrets..."
    secrets_list=$(kubectl get secrets --no-headers --output=custom-columns=PHASE:.metadata.name)
    relevant_secrets_list=("redis-secret" "mongodb-secret" "rabbitmq-secret" "ingress-basic-auth-secret")
    for secret in $secrets_list
    do
      if [[ "${relevant_secrets_list[@]}" =~ "${secret}" ]]; then
        echo "#### Backing up secret $secret"
        kubectl get secret $secret -o yaml | grep -v "^  \(creation\|resourceVersion\|selfLink\|uid\)" > /opt/backup/secrets/$secret.yaml
      fi
    done
  else
    echo "#### kubectl does not exists, skipping secrets backup phase."
  fi
}

function backup_consul_data {
  if kubectl cluster-info > /dev/null 2&>1; then
    # Support catching 1.21 deployments
    consul_pod=`kubectl get pods -A | egrep "consul-server|consul-dc01"`
    snapshot_dir="/ssd/consul_data"
    mkdir -p $snapshot_dir
    snapshot_file="consul-backup.snap"
    echo '### Backing up Consul data'
    kubectl exec $consul_pod consul snapshot save $snapshot_file
    kubectl cp $consul_pod:$snapshot_file $snapshot_dir/$snapshot_file
    is_snap=$(file ${snapshot_dir}/${snapshot_file} | grep gzip)
    if [ -z "$is_snap" ]; then
      echo "ERROR: Failed to get consul snapshot"
      exit 1
    fi
    echo 'Consul snapshot saved to ${snapshot_dir}/${snapshot_file}!'
  else
    echo "#### kubectl does not exists, skipping consul backup phase."
  fi
}

function backup_pv_id {
    if kubectl cluster-info > /dev/null 2&>1; then
    echo "#### Backing up Kubernetes PV ID to /opt/backup/pvc_id/filer_pvc_id"
    mkdir -p /opt/backup/pvc_id/
    filer_pv_id=$(kubectl get pvc data-default-seaweedfs-filer-0 --no-headers --output=custom-columns=PHASE:.spec.volumeName)
    echo "Found Filer PV id $filer_pv_id"
    echo ${filer_pv_id} > /opt/backup/pvc_id/filer_pvc_id
    else
    echo "#### kubectl does not exists, skipping secrets backup phase."
    fi
}

function remove_nvidia_drivers {
  if [ -x "$(command -v nvidia-smi)" ]; then
    nvidia_version=$(nvidia-smi --query-gpu=driver_version --format=csv,noheader || true)
  fi
  if [[ "${nvidia_version}" =~ "410."* ]] ; then
    echo "nvidia driver version 410 is already installed, skipping."
  else
    echo "#### Removing Nvidia Driver ${nvidia_version} and Nvidia Docker..."
    if [ -x "$(command -v apt-get)" ]; then
      set +e
      # remove if installed from apt
      apt remove -y --purge *nvidia* cuda*
      apt autoremove
      add-apt-repository -y --remove ppa:graphics-drivers/ppa
      # remove if installed from runfile
      nvidia-uninstall --silent --uninstall > /dev/null 2>&1
      set -e
    elif [ -x "$(command -v yum)" ]; then
      set +e
      # remove if installed from yum
      yum remove *nvidia* cuda* -y
      yum autoremove -y
      # remove if installed from runfile
      nvidia-uninstall --silent --uninstall > /dev/null 2>&1
      set -e
    fi
  fi
}

function remove_nvidia_docker {
  if [ -x "$(command -v nvidia-docker)" ]; then
    echo "#### Removing Nvidia-Docker..."
    if [ -x "$(command -v apt-get)" ]; then
      set +e
      apt remove -y --purge nvidia-docker* nvidia-container* libnvidia-container*
      apt autoremove
      set -e
    elif [ -x "$(command -v yum)" ]; then
      set +e
      yum remove -y nvidia-docker* nvidia-container-* libnvidia-container*
      yum autoremove -y
      set -e

    fi
  else
    echo "#### nvidia-docker does not exists, skipping nvidia-docker removal phase."
  fi
}

function disable_k8s {

  if [ -x "$(command -v k3s-uninstall.sh)" ]; then
    echo "###################################"
    echo "# Uninstalling K3S. . . #"
    echo "###################################"
    systemctl stop k3s
    systemctl is-enabled --quiet k3s && echo "#### Disabling k3s service..." && systemctl disable k3s
    k3s-uninstall.sh
  elif [ -x "$(command -v kubeadm)" ]; then
    echo "###################################"
    echo "# Uninstalling K8S. . . #"
    echo "###################################"
    kubeadm reset --force
    if [ -x "$(command -v apt-get)" ]; then
      apt-get purge kubeadm kubectl kubelet kubernetes-cni kube* -y
      apt-get autoremove -y
    elif [ -x "$(command -v yum)" ]; then
      yum remove kubeadm kubectl kubelet kubernetes-cni kube* -y
      yum autoremove -y
    fi
    rm -rf ~/.kube
    rm -rf /etc/kubernetes
  fi

}

function disable_docker {
  if [ -x "$(command -v docker)" ] && systemctl is-active --quiet docker; then
    echo "############################################"
    echo "# Killing and removing all containers. . . #"
    echo "############################################"
    set +e
    docker kill $(docker ps -q)
    docker rm $(docker ps -aq)
    docker network prune -f
    docker system prune -f
    set -e
    echo "######################################"
    echo "# Uninstalling Docker. . . #"
    echo "######################################"
    systemctl stop docker
    systemctl is-enabled --quiet docker && echo "#### Disabling Docker service..." && systemctl disable docker
    if [ -x "$(command -v apt-get)" ]; then
      apt remove -y --purge docker* container*
      apt autoremove -y
    elif [ -x "$(command -v yum)" ]; then
      yum remove -y docker* container*
      yum autoremove -y
    fi
    if [ -d "/var/lib/docker" ]; then
      rm -rf /var/lib/docker
    fi
    if [ -f /usr/local/bin/docker-compose ]; then
      echo "######################################"
      echo "# Removing docker-compose. . . #"
      echo "######################################"
      rm -f /usr/local/bin/docker-compose
    fi
  else
    echo "#### docker does not exists or is disabled, skipping docker service disabling phase."
  fi
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
        backup_pv_id
        backup_consul_data
        disable_k8s
        remove_nvidia_docker
        disable_docker       
        remove_nvidia_drivers
        shift
        continue
        #exit 0
        ;;
        -s|--backup-secrets)
        backup_secrets
        shift
        continue
        #exit 0
        ;;
        -c|--backup-consul-data)
        backup_consul_data
        shift
        continue
        ;;
        -p|--backup-pv-pvc-data)
        backup_pv_id
        shift
        continue
        #exit 0
        ;;
        -k|--remove-k8s)
        disable_k8s
        exit 0
        ;;
        -d|--remove-docker)
        disable_docker
        shift
        continue
        #exit 0
        ;;
        -n|--remove-nvidia-docker)
        remove_nvidia_docker
        shift
        continue
        #exit 0
        ;;
        -v|--remove-nvidia-drivers)
        remove_nvidia_drivers
        shift
        continue
        #exit 0
        ;;
    esac
    break
done

echo "======================================================"
echo "==               Cleanup Completed!                 =="
echo "======================================================"