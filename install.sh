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
K8S_BASE_VERSION="1.0.8"

K8S_INFRA_NAME="k8s-infra"
K8S_INFRA_VERSION="1.0.6"

PRODUCT_NAME="bettertomorrow"
PRODUCT_VERSION="1.24.0-6"
PRODUCT_MIGRATION_NAME="migration-workflow-${PRODUCT_NAME}"

# UBUNTU Options
APT_REPO_FILE_NAME="apt-repo-20190821.tar"
APT_REPO_FILE_URL="${S3_BUCKET_URL}/repos/${APT_REPO_FILE_NAME}"
UBUNTU_NVIDIA_DRIVER="https://gravity-bundles.s3.eu-central-1.amazonaws.com/nvidia-driver/nvidia-driver-418.40.04-ubuntu18.04.tar.gz"

# RHEL/CENTOS options
RHEL_PACKAGES_FILE_NAME="rhel-packages-20190821.tar"
RHEL_PACKAGES_FILE_URL="${S3_BUCKET_URL}/repos/${RHEL_PACKAGES_FILE_NAME}"
RHEL_NVIDIA_DRIVER="https://gravity-bundles.s3.eu-central-1.amazonaws.com/nvidia-driver/nvidia-driver-418.40.04-rhel7.tar.gz"

INSTALL_PRODUCT=false
SKIP_K8S_BASE=false
SKIP_K8S_INFRA=false
SKIP_PRODUCT=false
SKIP_DRIVERS=false
DOWNLOAD_ONLY=false
SKIP_CLUSTER_CHECK=false
MIGRATION_EXIST=false

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
   echo "  [--base-url] Base url for downloading the files [default:https://gravity-bundles.s3.eu-central-1.amazonaws.com]"
   echo "  [--k8s-base-version] K8S base image version [default:1.0.6]"
   echo "  [--skip-k8s-base] Skip installation of k8s base"
   echo "  [--k8s-infra-version] K8S infra image [default:1.0.6]"
   echo "  [--skip-k8s-infra] Skip installation of k8s infra charts"
   echo "  [--skip-drivers] Skip installation of Nvidia drivers"
   echo "  [-p|--product-name] Product name to install"
   echo "  [-v|--product-version] Product version to install [default:1.23.1-6]"
   echo "  [--auto-install-product] auto install product"
   echo "  [--add-migration-chart] add also the migration chart"
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
            DOWNLOAD_ONLY="true"
        shift
        continue
        ;;
        --skip-cluster-check)
            SKIP_CLUSTER_CHECK="true"
        shift
        continue
        ;;
        --skip-drivers)
            SKIP_DRIVERS="true"
        shift
        continue
        ;;
        --base-url)
        shift
            S3_BUCKET_URL=${1:-$S3_BUCKET_URL}
        shift
        continue
        ;;
        -k|--k8s-base-version)
        shift
            K8S_BASE_VERSION=${1:-$K8S_BASE_VERSION}
        shift
        continue
        ;;
        --skip-k8s-base)
            SKIP_K8S_BASE="true"
        shift
        continue
        ;;
        -n|--k8s-infra-version)
        shift
            K8S_INFRA_VERSION=${1:-$K8S_INFRA_VERSION}
        shift
        continue
        ;;
        --skip-k8s-infra)
            SKIP_K8S_INFRA="true"
        shift
        continue
        ;;
        -p|--product-name)
        shift
            PRODUCT_NAME=${1:-$PRODUCT_NAME}
        shift
        continue
        ;;
        -v|--product-version)
        shift
            PRODUCT_VERSION=${1:-$PRODUCT_VERSION}
        shift
        continue
        ;;
        --auto-install-product)
        #shift
            INSTALL_PRODUCT="true"
        shift
        continue
        ;;
        --add-migration-chart)
        #shift
            MIGRATION_EXIST="true"
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
          #KUBECTL_EXISTS=true
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

function install_aria2(){
  ARIA2_VERSION="1.34.0"
  ARIA2_URL="https://github.com/q3aql/aria2-static-builds/releases/download/v${ARIA2_VERSION}/aria2-${ARIA2_VERSION}-linux-gnu-64bit-build1.tar.bz2"
  if [ ! -x "$(command -v aria2c)" ]; then
    curl -fSsL -o /tmp/aria2-${ARIA2_VERSION}-linux-gnu-64bit-build1.tar.bz2 ${ARIA2_URL} >>${LOG_FILE} 2>&1
    tar jxf /tmp/aria2-${ARIA2_VERSION}-linux-gnu-64bit-build1.tar.bz2 -C /tmp >>${LOG_FILE} 2>&1
    pushd /tmp/aria2-${ARIA2_VERSION}-linux-gnu-64bit-build1
    make install >>${LOG_FILE} 2>&1
    popd
  fi
}

function join_by() { local IFS="$1"; shift; echo "$*"; }

function download_files(){
  K8S_BASE_URL="${S3_BUCKET_URL}/base-k8s/${K8S_BASE_NAME}/on-demand-nvidia-driver/${K8S_BASE_NAME}-${K8S_BASE_VERSION}.tar"
  K8S_INFRA_URL="${S3_BUCKET_URL}/${K8S_INFRA_NAME}/development/${K8S_INFRA_NAME}-${K8S_INFRA_VERSION}.tar.gz"
  K8S_PRODUCT_URL="${S3_BUCKET_URL}/products/${PRODUCT_NAME}/registry-variable/${PRODUCT_NAME}-${PRODUCT_VERSION}.tar.gz"
  K8S_PRODUCT_MIGRATION_URL="${S3_BUCKET_URL}/products/${PRODUCT_MIGRATION_NAME}/registry-variable/${PRODUCT_MIGRATION_NAME}-${PRODUCT_VERSION}.tar.gz"
  GRAVITY_PACKAGE_INSTALL_SCRIPT_URL="https://github.com/AnyVisionltd/gravity-oneliner/blob/master/gravity_package_installer.sh"
  YQ_URL="https://github.com/AnyVisionltd/gravity-oneliner/blob/nvidia-driver/yq"

  if [ -x "$(command -v apt-get)" ]; then
    #declare -a PACKAGES=("${APT_REPO_FILE_URL}" "${K8S_BASE_URL}" "${K8S_INFRA_URL}" "${K8S_PRODUCT_URL}")
    declare -a PACKAGES=("${UBUNTU_NVIDIA_DRIVER}" "${K8S_BASE_URL}" "${K8S_INFRA_URL}" "${K8S_PRODUCT_URL}")
  else
    #declare -a PACKAGES=("${RHEL_PACKAGES_FILE_URL}" "${RHEL_NVIDIA_DRIVER}" "${K8S_BASE_URL}" "${K8S_INFRA_URL}" "${K8S_PRODUCT_URL}")
    declare -a PACKAGES=("${RHEL_NVIDIA_DRIVER}" "${K8S_BASE_URL}" "${K8S_INFRA_URL}" "${K8S_PRODUCT_URL}")
  fi

  PACKAGES+=("${GRAVITY_PACKAGE_INSTALL_SCRIPT_URL}" "${YQ_URL}")

  if [ "${MIGRATION_EXIST}" == "true" ]; then
    PACKAGES+=("${K8S_PRODUCT_MIGRATION_URL}")
  fi

  declare -a PACKAGES_TO_DOWNLOAD

  for url in "${PACKAGES[@]}"; do
    filename=$(echo "${url##*/}")
    if [ ! -f "${BASEDIR}/${filename}" ] || [ -f "${BASEDIR}/${filename}.aria2" ]; then
      PACKAGES_TO_DOWNLOAD+=("${url}")
    fi
  done

  DOWNLOAD_LIST=$(join_by " " "${PACKAGES_TO_DOWNLOAD[@]}")
  if [ "${DOWNLOAD_LIST}" ]; then
    aria2c --summary-interval=30 --force-sequential --auto-file-renaming=false --min-split-size=100M --split=10 --max-concurrent-downloads=5 ${DOWNLOAD_LIST}
  fi
}

function online_packages_installation() {
  echo "" | tee -a ${LOG_FILE}
  echo "=====================================================================" | tee -a ${LOG_FILE}
  echo "==                Installing Packages, please wait...              ==" | tee -a ${LOG_FILE}
  echo "=====================================================================" | tee -a ${LOG_FILE}
  echo "" | tee -a ${LOG_FILE}
  if [ -x "$(command -v curl)" ] && [ -x "$(command -v ansible)" ]; then
      true
  else
      if [ -x "$(command -v apt-get)" ]; then
          set +e
          apt-get -qq update >>${LOG_FILE} 2>&1
          set -e
          apt-get -qq install -y --no-install-recommends make curl software-properties-common >>${LOG_FILE} 2>&1
          #apt-add-repository --yes --update ppa:ansible/ansible >>${LOG_FILE} 2>&1
          #apt-get -qq install -y ansible >>${LOG_FILE} 2>&1
      elif [ -x "$(command -v yum)" ]; then
          set +e
          #yum install -y curl > /dev/null
          curl -o epel-release-latest-7.noarch.rpm https://dl.fedoraproject.org/pub/epel/epel-release-latest-7.noarch.rpm >>${LOG_FILE} 2>&1
          rpm -ivh epel-release-latest-7.noarch.rpm || true >>${LOG_FILE} 2>&1
          yum install -y epel-release make >>${LOG_FILE} 2>&1
          set -e
          #yum install -y python python-pip >>${LOG_FILE} 2>&1
          #pip install --upgrade pip >>${LOG_FILE} 2>&1
          #pip install markupsafe xmltodict pywinrm > /dev/null
          #yum install -y ansible >>${LOG_FILE} 2>&1
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
    #set -e
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
        --service-uid=5000 \
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
  PACKAGE_FILE="${1}"
  shift
  ${BASEDIR}/gravity_package_installer.sh "${PACKAGE_FILE}" "$@" | tee -a ${LOG_FILE}
}

function install_nvidia_driver() {
  . /etc/os-release
  ## USE ONLY MAJOR VERSION OF RHEL VERSION
  if [[ "${VERSION_ID}" =~ ^[7,8]\.[0-9]+ ]]; then
    VERSION=${VERSION_ID%%.*}
  else
    VERSION=${VERSION_ID}
  fi
  ## BUILD DISTRIBUTION STRING
  DISTRIBUTION=${ID}${VERSION}
  if [[ "$SKIP_DRIVERS" = false ]] && [[ -f "${BASEDIR}/nvidia-driver-418.40.04-${DISTRIBUTION}.tar.gz" ]]; then
    install_gravity_app "${BASEDIR}/nvidia-driver-418.40.04-${DISTRIBUTION}.tar.gz"
  fi
}

function install_k8s_infra_app() {
  if [[ "$SKIP_K8S_INFRA" = false ]] && [[ -f "${BASEDIR}/${K8S_INFRA_NAME}-${K8S_INFRA_VERSION}.tar.gz" ]]; then
    install_gravity_app "${BASEDIR}/${K8S_INFRA_NAME}-${K8S_INFRA_VERSION}.tar.gz" --env=rancher=true
  fi
}

function install_product_app() {
  if [[ "$SKIP_PRODUCT" = false ]] && [[ -f "${BASEDIR}/${PRODUCT_NAME}-${PRODUCT_VERSION}.tar.gz" ]]; then
    install_gravity_app "${BASEDIR}/${PRODUCT_NAME}-${PRODUCT_VERSION}.tar.gz" --env=install_product=${INSTALL_PRODUCT}
    if [ "$MIGRATION_EXIST" == "true" ] && [ -f "${BASEDIR}/${PRODUCT_MIGRATION_NAME}-${PRODUCT_VERSION}.tar.gz" ] ; then
      install_gravity_app "${BASEDIR}/${PRODUCT_MIGRATION_NAME}-${PRODUCT_VERSION}.tar.gz" --env=install_product=false
    fi
  fi
}

function restore_secrets() {
  relevant_secrets_list=("redis-secret" "mongodb-secret" "rabbitmq-secret" "ingress-basic-auth-secret")
  for secret in $secrets_list
  do
    if [ -f "/opt/backup/secrets/${secret}.yaml" ]; then
      echo "Import secret ${secret}"
      kubectl create secret -f /opt/backup/secrets/${secret}.yaml || true
    fi
  done
  #rm -rf /opt/backup/secrets
}

is_kubectl_exists
echo "Installing mode $INSTALL_MODE with method $INSTALL_METHOD" | tee -a ${LOG_FILE}

if [[ $INSTALL_METHOD = "online" ]]; then
  online_packages_installation
  install_aria2
  download_files
  if [ "${DOWNLOAD_ONLY}" == "true" ]; then
    echo "Download only is enabled" | tee -a ${LOG_FILE}
    exit 0
  fi
  is_tar_files_exists
  install_gravity
  create_admin
  restore_secrets
  install_nvidia_driver
  install_k8s_infra_app
  install_product_app
else
  is_tar_files_exists
  install_gravity
  create_admin
  restore_secrets
  install_nvidia_driver
  install_k8s_infra_app
  install_product_app
fi
