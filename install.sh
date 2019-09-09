#!/bin/bash

set -e

# Absolute path to this script
SCRIPT=$(readlink -f "$0")
# Absolute path to the script directory
BASEDIR=$(dirname "$SCRIPT")
INSTALL_MODE="aio"
INSTALL_METHOD="online"
LOG_FILE="/var/log/gravity-installer.log"
S3_BUCKET_URL="https://gravity-bundles.s3.eu-central-1.amazonaws.com"

# Gravity options
K8S_BASE_NAME="anv-base-k8s"
K8S_BASE_VERSION="1.0.5"

K8S_INFRA_NAME="k8s-infra"
K8S_INFRA_VERSION="1.0.5"

PRODUCT_NAME="bettertomorrow"
PRODUCT_VERSION="1.23.1-5"

# UBUNTU Options
NVIDIA_DRIVERS_VERSION="410.104-1"
APT_REPO_FILE_NAME="apt-repo-20190821.tar"
APT_REPO_FILE_URL="${S3_BUCKET_URL}/repos/${APT_REPO_FILE_NAME}"
# RHEL/CENTOS options
RHEL_PACKAGES_FILE_NAME="rhel-packages-20190821.tar"
RHEL_PACKAGES_FILE_URL="${S3_BUCKET_URL}/repos/${RHEL_PACKAGES_FILE_NAME}"
RHEL_NVIDIA_DRIVER="http://us.download.nvidia.com/XFree86/Linux-x86_64/410.104/NVIDIA-Linux-x86_64-410.104.run"

INSTALL_PRODUCT=false
SKIP_K8S_BASE=false
SKIP_K8S_INFRA=false
SKIP_PRODUCT=false
SKIP_DRIVERS=false
DOWNLOAD_ONLY=false
SKIP_CLUSTER_CHECK=false

echo "------ Staring Gravity installer $(date '+%Y-%m-%d %H:%M:%S')  ------" >${LOG_FILE} 2>&1

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
   echo "  [-m|--install-method] Installation method [default:online, airgap (need extra files on same dir as this script)]"
   echo "  [--download-only] Download all the files to the current location"
   echo "  [--skip-cluster-check] Skip verify if cluster is already installed"
   echo "  [--k8s-base-version] K8S base image version [default:1.0.5]"
   echo "  [--k8s-infra-version] K8S infra image [default:1.0.5]"
   echo "  [-p|--product-name] Product name to install"
   echo "  [--product-version] Product version to install [default:1.23.1-5]"
   echo "  [--auto-install-product] auto install product  [default:1.23.1-5]"
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
            INSTALL_MODE=${1:-$INSTALL_MODE}
        shift
        continue
        ;;
        -m|--install-method)
        shift
            INSTALL_METHOD=${1:-$INSTALL_METHOD}
        shift
        continue
        ;;
        --download-only)
        #shift
            DOWNLOAD_ONLY="true"
        shift
        continue
        ;;
        --skip-cluster-check)
        #shift
            SKIP_CLUSTER_CHECK="true"
        shift
        continue
        ;;        
        -k|--k8s-base-version)
        shift
            K8S_BASE_VERSION=${1:-$K8S_BASE_VERSION}
        shift
        continue
        ;;
        -n|--k8s-infra-version)
        shift
            K8S_INFRA_VERSION=${1:-$K8S_INFRA_VERSION}
        shift
        continue
        ;;
        -p|--product-name)
        shift
            PRODUCT_NAME=${1:-$PRODUCT_NAME}
        shift
        continue
        ;;
        -s|--product-version)
        shift
            PRODUCT_VERSION=${1:-$PRODUCT_VERSION}
        shift
        continue
        ;;
        --auto-install-product)
        #shift
            INSTALL_PRODUCT=${1:-$INSTALL_PRODUCT}
        shift
        continue
        ;;
    esac
    break
done

function is_kubectl_exists() {
  if [ "${SKIP_CLUSTER_CHECK}" == "false" ]; then
    ## Check if this machine is part of an existing Kubernetes cluster
    if gravity status --quiet > /dev/null 2>&1; then
      echo "Gravity cluster is already installed"  
      if [ -x "$(command -v kubectl)" ]; then
        if [[ $(kubectl cluster-info) == *'Kubernetes master'*'running'*'https://'* ]]; then
          echo "" | tee -a ${LOG_FILE}
          echo "Error: this machine is a part of an existing Kubernetes cluster, please use the update script or detach the k8s cluster before running this installer." | tee -a ${LOG_FILE}
          exit 1
          KUBECTL_EXISTS=true
        fi
      fi
    fi
  fi
}

function is_tar_files_exists(){
    for file in ${K8S_BASE_NAME}-${K8S_BASE_VERSION}.tar ${K8S_INFRA_NAME}-${K8S_INFRA_VERSION}.tar.gz ${PRODUCT_NAME}-${PRODUCT_VERSION}.tar.gz; do
        if [[ ! -f "${BASEDIR}/$file" ]] ; then
            echo "Missing $file it's required for installation to success" | tee -a ${LOG_FILE}
            exit 1
        fi
    done
}


function download_files(){
  K8S_BASE_URL="${S3_BUCKET_URL}/base-k8s/${K8S_BASE_NAME}/development/${K8S_BASE_NAME}-${K8S_BASE_VERSION}.tar"
  K8S_INFRA_URL="${S3_BUCKET_URL}/${K8S_INFRA_NAME}/development/${K8S_INFRA_NAME}-${K8S_INFRA_VERSION}.tar.gz"
  K8S_PRODUCT_URL="${S3_BUCKET_URL}/products/${PRODUCT_NAME}/registry-variable/${PRODUCT_NAME}-${PRODUCT_VERSION}.tar.gz"

  if [ -x "$(command -v apt-get)" ]; then
    declare -a PACKAGES_TO_DOWNLOAD=("${APT_REPO_FILE_URL}" "${K8S_BASE_URL}" "${K8S_INFRA_URL}" "${K8S_PRODUCT_URL}")
  else
    declare -a PACKAGES_TO_DOWNLOAD=("${RHEL_PACKAGES_FILE_URL}" "${RHEL_NVIDIA_DRIVER}" "${K8S_BASE_URL}" "${K8S_INFRA_URL}" "${K8S_PRODUCT_URL}")
  fi

  for url in "${PACKAGES_TO_DOWNLOAD[@]}"; do
    # run the curl job in the background so we can start another job
    # and disable the progress bar (-s)
    filename=$(echo "${url##*/}")
    if [ ! -f "${BASEDIR}/$filename" ]; then
      echo "Downloading $url" | tee -a ${LOG_FILE}
      curl -fSsLO -C - $url >>${LOG_FILE} 2>&1 &
    else
      echo "The File is already exist under: ${BASEDIR}/$filename" | tee -a ${LOG_FILE}
    fi
  done
  wait #wait for all background jobs to terminate
}

function online_packages_installation() {
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
          #apt-add-repository --yes --update ppa:ansible/ansible >>${LOG_FILE} 2>&1
          #apt-get -qq install -y ansible >>${LOG_FILE} 2>&1
          set +e
      elif [ -x "$(command -v yum)" ]; then
          set -e
          #yum install -y curl > /dev/null
          curl -o epel-release-latest-7.noarch.rpm https://dl.fedoraproject.org/pub/epel/epel-release-latest-7.noarch.rpm >>${LOG_FILE} 2>&1
          rpm -ivh epel-release-latest-7.noarch.rpm || true >>${LOG_FILE} 2>&1
          yum install -y epel-release >>${LOG_FILE} 2>&1
          #yum install -y python python-pip >>${LOG_FILE} 2>&1
          #pip install --upgrade pip >>${LOG_FILE} 2>&1
          #pip install markupsafe xmltodict pywinrm > /dev/null
          #yum install -y ansible >>${LOG_FILE} 2>&1
          set +e
      fi
  fi
}

function nvidia_drivers_installation() {
  echo "" | tee -a ${LOG_FILE}
  echo "=====================================================================" | tee -a ${LOG_FILE}
  echo "==                Installing Nvidia Drivers, please wait...               ==" | tee -a ${LOG_FILE}
  echo "=====================================================================" | tee -a ${LOG_FILE}
  echo "" | tee -a ${LOG_FILE}  
  if [ -x "$(command -v apt-get)" ]; then
    if dpkg-query --show nvidia-driver-410 ; then
      echo "nvidia driver nvidia-driver-410 already installed" | tee -a ${LOG_FILE}
    else
      echo "Installing nvidia driver nvidia-driver-410" | tee -a ${LOG_FILE}
      if [[ $INSTALL_METHOD = "online" ]]; then
        apt-key adv --fetch-keys http://developer.download.nvidia.com/compute/cuda/repos/ubuntu1804/x86_64/7fa2af80.pub >>${LOG_FILE} 2>&1
        sh -c 'echo "deb http://developer.download.nvidia.com/compute/cuda/repos/ubuntu1804/x86_64 /" > /etc/apt/sources.list.d/cuda.list'
      else
        mkdir -p /opt/packages >>${LOG_FILE} 2>&1
        tar -xf ${BASEDIR}/${APT_REPO_FILE_NAME} -C /opt/packages >>${LOG_FILE} 2>&1
        mkdir -p /etc/apt-orig >>${LOG_FILE} 2>&1
        rsync -q -a --ignore-existing /etc/apt/ /etc/apt-orig/ >>${LOG_FILE} 2>&1
        rm -rf /etc/apt/sources.list.d/* >>${LOG_FILE} 2>&1
        echo "deb [arch=amd64 trusted=yes allow-insecure=yes] http://$(hostname --ip-address | awk '{print $1}'):8085/ bionic main" > /etc/apt/sources.list
      fi
      apt-get update>>${LOG_FILE} 2>&1
      #echo "Remove old nvidia drivers if exist"
      #apt remove -y --purge *nvidia* cuda* >>${LOG_FILE} 2>&1
      set -e
      apt-get install -y --no-install-recommends cuda-drivers=410.104-1 >>${LOG_FILE} 2>&1
      set +e
    fi
  elif [ -x "$(command -v yum)" ]; then
    #rpm -q --quiet nvidia-driver-410.104*
    if rpm -q --quiet nvidia-driver-410*; then
      echo "nvidia driver nvidia-driver-410 already installed" | tee -a ${LOG_FILE}
    else
      echo "Installing nvidia driver nvidia-driver-410" | tee -a ${LOG_FILE}
      
      if [[ $INSTALL_METHOD = "online" ]]; then
        yum install -y gcc kernel-devel >>${LOG_FILE} 2>&1
        # if [ ! -f "/tmp/drivers/Linux-x86_64/410.104/NVIDIA-Linux-x86_64-410.104.run" ]; then
        #   echo "Downloading NVIDIA drivers"
        #   curl http://us.download.nvidia.com/XFree86/Linux-x86_64/410.104/NVIDIA-Linux-x86_64-410.104.run \
        #   --output ${BASEDIR}/NVIDIA-Linux-x86_64-410.104.run >>${LOG_FILE} 2>&1
        # fi
      else
        # curl http://$(hostname --ip-address | awk '{print $1}')/${RHEL_PACKAGES_FILE_NAME} \
        # --output ${BASEDIR}/${RHEL_PACKAGES_FILE_NAME} >>${LOG_FILE} 2>&1
        mkdir -p /tmp/drivers >>${LOG_FILE} 2>&1
        tar -xf ${BASEDIR}/${RHEL_PACKAGES_FILE_NAME} -C /tmp/drivers && yum install -y /tmp/drivers/*.rpm >>${LOG_FILE} 2>&1
        
        # curl http://$(hostname --ip-address | awk '{print $1}')/NVIDIA-Linux-x86_64-410.104.run \
        # --output /tmp/drivers/NVIDIA-Linux-x86_64-410.104.run >>${LOG_FILE} 2>&1
      fi
      #yum remove -y *nvidia* cuda* >>${LOG_FILE} 2>&1
      set -e
      chmod +x ${BASEDIR}/NVIDIA-Linux-x86_64-410.104.run >>${LOG_FILE} 2>&1
      ${BASEDIR}/NVIDIA-Linux-x86_64-410.104.run --silent --no-install-compat32-libs >>${LOG_FILE} 2>&1
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
    #if [[ $INSTALL_METHOD = "online" ]]; then
    #  curl -fSLo ${BASEDIR}/${K8S_BASE_NAME}-${K8S_BASE_VERSION}.tar https://gravity-bundles.s3.eu-central-1.amazonaws.com/anv-base-k8s/on-demand-all-caps/${K8S_BASE_NAME}-${K8S_BASE_VERSION}.tar 2> >(tee -a ${LOG_FILE} >&2)
    #else
    mkdir -p ${BASEDIR}/${K8S_BASE_NAME}
    tar -xf ${BASEDIR}/${K8S_BASE_NAME}-${K8S_BASE_VERSION}.tar -C ${BASEDIR}/${K8S_BASE_NAME} | tee -a ${LOG_FILE}
    #fi
    
    cd ${BASEDIR}/${K8S_BASE_NAME}
    ${BASEDIR}/${K8S_BASE_NAME}/gravity install \
        --cloud-provider=generic \
        --pod-network-cidr="10.244.0.0/16" \
        --service-cidr="10.100.0.0/16" \
        --vxlan-port=8472 \
        --cluster=cluster.local \
        --flavor=aio \
        --role=aio | tee -a ${LOG_FILE}
    cd ${BASEDIR}
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
  gravity resource create admin.yaml >>${LOG_FILE} 2>&1
  rm -f admin.yaml >>${LOG_FILE} 2>&1
}

function install_gravity_app() {
  echo "" | tee -a ${LOG_FILE}
  echo "=====================================================================" | tee -a ${LOG_FILE}
  echo "==                Installing App $1 version $2, please wait...               ==" | tee -a ${LOG_FILE}
  echo "=====================================================================" | tee -a ${LOG_FILE}
  echo "" | tee -a ${LOG_FILE}  
  gravity ops connect --insecure https://localhost:3009 admin Passw0rd123 >>${LOG_FILE} 2>&1
  gravity app import --force --insecure --ops-url=https://localhost:3009 ${BASEDIR}/${1}-${2}.tar.gz >>${LOG_FILE} 2>&1
  gravity app pull --force --insecure --ops-url=https://localhost:3009 gravitational.io/${1}:${2} >>${LOG_FILE} 2>&1
  gravity exec gravity app export gravitational.io/${1}:${2} >>${LOG_FILE} 2>&1
  
}

function install_k8s_infra_app() {

  ## Install infra package
  # if [[ $INSTALL_METHOD = "online" ]]; then
  #   curl -fSLo ${BASEDIR}/${K8S_INFRA_NAME}-${K8S_INFRA_VERSION}.tar.gz https://gravity-bundles.s3.eu-central-1.amazonaws.com/k8s-infra/development/${K8S_INFRA_NAME}-${K8S_INFRA_VERSION}.tar.gz 2> >(tee -a ${LOG_FILE} >&2)
  # fi
  install_gravity_app ${K8S_INFRA_NAME} ${K8S_INFRA_VERSION}
  gravity exec gravity app hook --env=rancher=true gravitational.io/${K8S_INFRA_NAME}:${K8S_INFRA_VERSION} install | tee -a ${LOG_FILE}
}

function install_product_app() {
  # if [[ $INSTALL_METHOD = "online" ]]; then
  #   curl -fSLo ${PRODUCT_NAME}-${PRODUCT_VERSION}.tar.gz https://gravity-bundles.s3.eu-central-1.amazonaws.com/products/${PRODUCT_NAME}/registry-variable/${PRODUCT_NAME}-${PRODUCT_VERSION}.tar.gz 2> >(tee -a ${LOG_FILE} >&2)
  # fi
  install_gravity_app ${PRODUCT_NAME} ${PRODUCT_VERSION}
  gravity exec gravity app hook --env=install_product=${INSTALL_PRODUCT} gravitational.io/${K8S_INFRA_NAME}:${PRODUCT_VERSION} install | tee -a ${LOG_FILE}
}

# function restore_secrets(){
  
# }

echo "Installing mode $INSTALL_MODE with method $INSTALL_METHOD" | tee -a ${LOG_FILE}
is_kubectl_exists

if [[ $INSTALL_METHOD = "online" ]]; then
  download_files
  if [ "${DOWNLOAD_ONLY}" == "true" ]; then
    echo "Download only is enabled" | tee -a ${LOG_FILE}
    exit 0
  fi
  is_tar_files_exists
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
