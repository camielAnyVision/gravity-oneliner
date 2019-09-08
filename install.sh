#!/bin/bash

set -e

# Absolute path to this script
SCRIPT=$(readlink -f "$0")
# Absolute path to the script directory
BASEDIR=$(dirname "$SCRIPT")
INSTALL_MODE="aio"
INSTALL_METHOD="online"
K8S_BASE_NAME="anv-base-k8s"
K8S_BASE_VERSION="1.0.5"
K8S_INFRA_NAME="k8s-infra"
K8S_INFRA_VERSION="1.0.5"
LOG_FILE="/var/log/gravity-installer.log"
PRODUCT_NAME="bettertomorrow"
PRODUCT_VERSION="1.23.1-5"
APT_REPO_FILE_NAME="apt-repo-20190821.tar"
NVIDIA_DRIVERS_VERSION="410.104-1"
RHEL_PACKAGES="rhel-packages-20190821.tar"
INSTALL_PRODUCT=true
SKIP_K8S_BASE=false
SKIP_K8S_INFRA=false
SKIP_PRODUCT=false
SKIP_DRIVERS=false


## Permissions check
if [[ $EUID -ne 0 ]]; then
   echo "Error: This script must be run as root." | tee -a ${LOG_FILE}
   echo "Installation failed, please contact support." | tee -a ${LOG_FILE}
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
   echo "Gravity Oneliner Installer"
   echo ""
   echo "OPTIONS:"
   echo "  [-i|--install-mode] Installation mode [default:aio, cluster]"
   echo "  [m|--install-method] Installation method [default:online, airgap (need extra files on same dir as this script)]"
   echo "  [-k|--k8s-base-version] K8S base image version [default:1.0.5]"
   echo "  [-n|--k8s-infra-version] K8S infra image [default:1.0.5]"
   echo "  [-p|--product-name] Product name to install"
   echo "  [-s|--product-version] Product version to install [default:1.23.1-5]"
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
        -i|--install-mode)
        shift
            INSTALL_MODE=${1:-aio}
        shift
        continue
        ;;
        -m|--install-method)
        shift
            INSTALL_METHOD=${1:-online}
        shift
        continue
        ;;
        -k|--k8s-base-version)
        shift
            K8S_BASE_VERSION=${1:-1.0.5}
        shift
        continue
        ;;
        -n|--k8s-infra-version)
        shift
            K8S_INFRA_VERSION=${1:-1.0.5}
        shift
        continue
        ;;
        -p|--product-name)
        shift
            PRODUCT_NAME=${1:-bettertomorrow}
        shift
        continue
        ;;
        -s|--product-version)
        shift
            PRODUCT_VERSION=${1:-1.23.1-5}
        shift
        continue
        ;;
    esac
    break
done


function is_kubectl_exists() {
  ## Check if this machine is part of an existing Kubernetes cluster
  if gravity status --quiet; then
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

function is_tar_files_exists(){
    for file in ${K8S_BASE_NAME}-${K8S_BASE_VERSION}.tar ${K8S_INFRA_NAME}-${K8S_INFRA_VERSION}.tar.gz ${PRODUCT_NAME}-${PRODUCT_VERSION}.tar.gz; do
        if [[ ! -f $file ]] ; then
            echo "Missing $file it's required for installation to success"
            exit 1
        fi
    done
}

function online_packages_installation () {
  echo "" | tee -a ${LOG_FILE}
  echo "=====================================================================" | tee -a ${LOG_FILE}
  echo "==                Installing Packages, please wait...               ==" | tee -a ${LOG_FILE}
  echo "=====================================================================" | tee -a ${LOG_FILE}
  echo "" | tee -a ${LOG_FILE}  
  if [ -x "$(command -v curl)" ] && [ -x "$(command -v ansible)" ]; then
      true
  else
      if [ -x "$(command -v apt-get)" ]; then
          set -e
          apt-get -qq update >>${LOG_FILE} 2>&1
          apt-get -qq install -y --no-install-recommends curl software-properties-common >>${LOG_FILE} 2>&1
          apt-add-repository --yes --update ppa:ansible/ansible >>${LOG_FILE} 2>&1
          apt-get -qq install -y ansible >>${LOG_FILE} 2>&1
          set +e
      elif [ -x "$(command -v yum)" ]; then
          set -e
          #yum install -y curl > /dev/null
          curl -o epel-release-latest-7.noarch.rpm https://dl.fedoraproject.org/pub/epel/epel-release-latest-7.noarch.rpm >>${LOG_FILE} 2>&1
          rpm -ivh epel-release-latest-7.noarch.rpm || true >>${LOG_FILE} 2>&1
          yum install -y epel-release >>${LOG_FILE} 2>&1
          yum install -y python python-pip >>${LOG_FILE} 2>&1
          pip install --upgrade pip >>${LOG_FILE} 2>&1
          #pip install markupsafe xmltodict pywinrm > /dev/null
          yum install -y ansible >>${LOG_FILE} 2>&1
          set +e
      fi
  fi
}

function nvidia_drivers_installation () {
  if [ -x "$(command -v apt-get)" ]; then
    if dpkg-query --show nvidia-driver-410 ; then
      echo "nvidia driver nvidia-driver-410 already installed"
    else
      echo "Installing nvidia driver nvidia-driver-410"
      if [[ $INSTALL_METHOD = "online" ]]; then
        apt-key adv --fetch-keys http://developer.download.nvidia.com/compute/cuda/repos/ubuntu1804/x86_64/7fa2af80.pub
        sh -c 'echo "deb http://developer.download.nvidia.com/compute/cuda/repos/ubuntu1804/x86_64 /" > /etc/apt/sources.list.d/cuda.list'
      else
        mkdir -p /opt/packages
        tar -xf ${BASEDIR}/${APT_REPO_FILE_NAME} -C /opt/packages >>${LOG_FILE} 2>&1
        mkdir -p /etc/apt-orig
        rsync -q -a --ignore-existing /etc/apt/ /etc/apt-orig/ >>${LOG_FILE} 2>&1
        rm -rf /etc/apt/sources.list.d/*
        echo "deb [arch=amd64 trusted=yes allow-insecure=yes] http://$(hostname --ip-address | awk '{print $1}'):8085/ bionic main" > /etc/apt/sources.list
      fi
      apt-get update>>${LOG_FILE} 2>&1
      echo "Remove old nvidia drivers if exist"
      apt remove -y --purge *nvidia* cuda* >>${LOG_FILE} 2>&1
      set -e
      apt-get install -y --no-install-recommends cuda-drivers=410.104-1 >>${LOG_FILE} 2>&1
      set +e
    fi
  elif [ -x "$(command -v yum)" ]; then
    #rpm -q --quiet nvidia-driver-410.104*
    if rpm -q --quiet nvidia-driver-410*; then
      echo "nvidia driver nvidia-driver-410 already installed"
    else
      echo "Installing nvidia driver nvidia-driver-410"
      mkdir -p /tmp/drivers
      if [[ $INSTALL_METHOD = "online" ]]; then
        yum install -y gcc kernel-devel >>${LOG_FILE} 2>&1
        if [ ! -f "/tmp/drivers/Linux-x86_64/410.104/NVIDIA-Linux-x86_64-410.104.run" ]; then
          echo "Downloading NVIDIA drivers"
          curl http://us.download.nvidia.com/XFree86/Linux-x86_64/410.104/NVIDIA-Linux-x86_64-410.104.run \
          --output /tmp/drivers/NVIDIA-Linux-x86_64-410.104.run >>${LOG_FILE} 2>&1
        fi
      else
        curl http://$(hostname --ip-address | awk '{print $1}')/${RHEL_PACKAGES} \
        --output /tmp/drivers/${RHEL_PACKAGES} >>${LOG_FILE} 2>&1
        tar -xf /tmp/drivers/rhel-packages-<upload date>.tar -C /tmp/drivers && yum install -y /tmp/drivers/*.rpm >>${LOG_FILE} 2>&1
        
        curl http://$(hostname --ip-address | awk '{print $1}')/NVIDIA-Linux-x86_64-410.104.run \
        --output /tmp/drivers/NVIDIA-Linux-x86_64-410.104.run >>${LOG_FILE} 2>&1
      fi
      yum remove -y *nvidia* cuda* >>${LOG_FILE} 2>&1
      set -e
      chmod +x /tmp/drivers/NVIDIA-Linux-x86_64-410.104.run >>${LOG_FILE} 2>&1
      /tmp/drivers/NVIDIA-Linux-x86_64-410.104.run --silent --no-install-compat32-libs >>${LOG_FILE} 2>&1
      set +e
    fi
  fi
}

function install_gravity() {
  ## Install gravity
  if [[ "$SKIP_K8S_BASE" = false ]]; then
    echo "" | tee -a ${LOG_FILE}
    echo "=====================================================================" | tee -a ${LOG_FILE}
    echo "==                Installing Gravity, please wait...               ==" | tee -a ${LOG_FILE}
    echo "=====================================================================" | tee -a ${LOG_FILE}
    echo "" | tee -a ${LOG_FILE}
    set -e
    if [[ $INSTALL_METHOD = "online" ]]; then
      curl -fSLo ${BASEDIR}/${K8S_BASE_NAME}-${K8S_BASE_VERSION}.tar https://gravity-bundles.s3.eu-central-1.amazonaws.com/anv-base-k8s/on-demand-all-caps/${K8S_BASE_NAME}-${K8S_BASE_VERSION}.tar 2> >(tee -a ${LOG_FILE} >&2)
    else
      tar xf ${BASEDIR}/${K8S_BASE_NAME}-${K8S_BASE_VERSION}.tar | tee -a ${LOG_FILE}
    fi
    
    ./gravity install \
        --cloud-provider=generic \
        --pod-network-cidr="10.244.0.0/16" \
        --service-cidr="10.100.0.0/16" \
        --vxlan-port=8472 \
        --cluster=cluster.local \
        --flavor=aio \
        --role=aio | tee -a ${LOG_FILE}
  fi
}

function create_admin() {
  cat <<'EOF' > admin.yaml
---
kind: user
version: v2
metadata:
  name: "admin"
spec:
  type: "admin"
  password: "Passw0rd123"
  roles: ["@teleadmin"]
EOF
  gravity resource create admin.yaml
  rm -f admin.yaml
}

function install_gravity_app() {
  echo "Installing app $1 version $2"
  gravity ops connect --insecure https://localhost:3009 admin Passw0rd123 | tee -a ${LOG_FILE}
  gravity app import --force --insecure --ops-url=https://localhost:3009 ${BASEDIR}/${1}-${2}.tar.gz | tee -a ${LOG_FILE}
  gravity app pull --force --insecure --ops-url=https://localhost:3009 gravitational.io/${1}:${2} | tee -a ${LOG_FILE}
  gravity exec gravity app export gravitational.io/${1}:${2} | tee -a ${LOG_FILE}
  gravity exec gravity app hook --env=rancher=true gravitational.io/${1}:${2} install | tee -a ${LOG_FILE}
}

function install_k8s_infra_app() {

  ## Install infra package
  if [[ $INSTALL_METHOD = "online" ]]; then
    curl -fSLo ${BASEDIR}/${K8S_INFRA_NAME}-${K8S_INFRA_VERSION}.tar.gz https://gravity-bundles.s3.eu-central-1.amazonaws.com/k8s-infra/development/${K8S_INFRA_NAME}-${K8S_INFRA_VERSION}.tar.gz 2> >(tee -a ${LOG_FILE} >&2)
  fi
  install_gravity_app ${K8S_INFRA_NAME} ${K8S_INFRA_VERSION}

}

function install_product_app() {
  if [[ $INSTALL_METHOD = "online" ]]; then
    curl -fSLo ${PRODUCT_NAME}-${PRODUCT_VERSION}.tar.gz https://gravity-bundles.s3.eu-central-1.amazonaws.com/products/${PRODUCT_NAME}/registry-variable/${PRODUCT_NAME}-${PRODUCT_VERSION}.tar.gz 2> >(tee -a ${LOG_FILE} >&2)
  fi
  install_gravity_app ${PRODUCT_NAME} ${PRODUCT_VERSION}

}

echo "Installing mode $INSTALL_MODE with method $INSTALL_METHOD"

is_kubectl_exists
echo $KUBECTL_EXISTS

if [[ $INSTALL_METHOD = "online" ]]; then
  online_packages_installation
  nvidia_drivers_installation
  install_gravity
  create_admin
  install_k8s_infra_app
  install_product_app
else
  is_tar_files_exists
  install_gravity
  create_admin
  install_k8s_infra_app
  nvidia_drivers_installation
  install_product_app
fi
