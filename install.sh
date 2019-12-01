#!/bin/bash
set -e
set -o pipefail

# script version
SCRIPT_VERSION="1.24.0-27"

# Absolute path to this script
SCRIPT=$(readlink -f "$0")
# Absolute path to the script directory
BASEDIR=$(dirname "$SCRIPT")

NODE_ROLE="aio"
INSTALL_METHOD="online"
LOG_FILE="/var/log/gravity-installer.log"
S3_BUCKET_URL="https://gravity-bundles.s3.eu-central-1.amazonaws.com"

# Gravity options
K8S_BASE_NAME="anv-base-k8s"
K8S_BASE_VERSION="1.0.13"
K8S_BASE_REPO_VERSION="${K8S_BASE_VERSION}"

K8S_INFRA_NAME="k8s-infra"
K8S_INFRA_VERSION="1.0.11"
K8S_INFRA_REPO_VERSION="${K8S_INFRA_VERSION}"

PRODUCT_NAME="bettertomorrow"
PRODUCT_VERSION="1.24.0-27"
PRODUCT_REPO_VERSION="${PRODUCT_VERSION}"

# NVIDIA driver options
NVIDIA_DRIVER_METHOD="container"
NVIDIA_DRIVER_VERSION="410-104"
NVIDIA_DRIVER_PACKAGE_VERSION="1.0.1"
NVIDIA_DRIVER_REPO_VERSION="${NVIDIA_DRIVER_PACKAGE_VERSION}"

# UBUNTU Options
APT_REPO_FILE_NAME="apt-repo-20190821.tar"

# RHEL/CENTOS options
RHEL_PACKAGES_FILE_NAME="rhel-packages-20190923.tar"
RHEL_NVIDIA_DRIVER_URL="http://us.download.nvidia.com/XFree86/Linux-x86_64/410.104/NVIDIA-Linux-x86_64-410.104.run"
RHEL_NVIDIA_DRIVER_FILE="${RHEL_NVIDIA_DRIVER_URL##*/}"

INSTALL_PRODUCT="false"
SKIP_K8S_BASE="false"
SKIP_K8S_INFRA="false"
SKIP_PRODUCT="false"
SKIP_DRIVERS="false"
SKIP_MD5_CHECK="false"
DOWNLOAD_ONLY="false"
SKIP_CLUSTER_CHECK="false"
MIGRATION_EXIST="false"

# Network options
POD_NETWORK_CIDR="10.244.0.0/16"
SERVICE_CIDR="10.172.0.0/16"

echo "------ Staring Gravity installer $(date '+%Y-%m-%d %H:%M:%S')  ------" >${LOG_FILE} 2>&1

## Permissions check
if [[ ${EUID} -ne 0 ]]; then
   echo "Error: This script must be run as root."
   echo "Installation failed, please contact support."
   exit 1
fi

## Get home Dir of the current user
if [ ${SUDO_USER} ]; then
  user=${SUDO_USER}
else
  user=`whoami`
fi

if [ "${user}" == "root" ]; then
  user_home_dir="/${user}"
else
  user_home_dir="/home/${user}"
fi

function showhelp {
   echo ""
   echo "Gravity Oneliner Installer"
   echo ""
   echo "OPTIONS:"
   echo "  [-r|--node-role] Current node role [aio|backend|edge] (default: aio)"
   echo "  [-m|--install-method] Installation method [online|airgap] (default: online)"
   echo "  [-p|--product-name] Product name to install"
   echo "  [-v|--product-version] Product version to install [Default: ${PRODUCT_VERSION}]"
   echo "  [--download-only] Download all the installation files to the same location as this script"
   echo "  [--os-package] Select OS package to download, Force download only [redhat|ubuntu] (default: machine OS)"
   echo "  [--download-dashboard] Skip the installation of K8S infra charts layer"
   echo "  [--base-url] Base URL for downloading the installation files [Default: https://gravity-bundles.s3.eu-central-1.amazonaws.com]"
   echo "  [--auto-install-product] Automatic installation of a product"
   echo "  [--add-migration-chart] Install also the migration chart"
   echo "  [--k8s-base-version] K8S base image version [Default: ${K8S_BASE_VERSION}]"
   echo "  [--k8s-infra-version] K8S infra image [Default:${K8S_INFRA_VERSION}]"
   echo "  [--pod-network-cidr] Config pod network CIDR [Default: ${POD_NETWORK_CIDR}]"
   echo "  [--service-cidr] Config service CIDR [Default: ${SERVICE_CIDR}]"
   echo "  [--driver-method] NVIDIA driver installation method [host, container. Default: ${NVIDIA_DRIVER_METHOD}]"
   echo "  [--driver-version] NVIDIA driver version (requires --driver-method=container) [410-104, 418-113. Default: ${NVIDIA_DRIVER_VERSION}]"   
   echo "  [--skip-cluster-check] Skip cluster checks (preflight) if the cluster is already installed"
   echo "  [--skip-md5-check] Skip md5 checksum"
   echo "  [--skip-k8s-base] Skip the installation of K8S base layer"
   echo "  [--skip-k8s-infra] Skip the installation of K8S infra charts layer"
   echo "  [--skip-drivers] Skip the installation of Nvidia drivers"
   echo "  [--skip-product] Skip the installation of product"
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
        -r|--node-role)
        shift
            NODE_ROLE=${1:-$NODE_ROLE}
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
            INSTALL_PRODUCT="true"
        shift
        continue
        ;;
        --skip-product)
            SKIP_PRODUCT="true"
        shift
        continue
        ;;
        --skip-md5-check)
            SKIP_MD5_CHECK="true"
        shift
        continue
        ;;        
        --add-migration-chart)
            MIGRATION_EXIST="true"
        shift
        continue
        ;;
        --download-dashboard)
            DASHBOARD_EXIST="true"
        shift
        continue
        ;;
        --driver-method)
        shift
            NVIDIA_DRIVER_METHOD=${1:-$NVIDIA_DRIVER_METHOD}
        shift
        continue
        ;;
        --driver-version)
        shift
            NVIDIA_DRIVER_VERSION=${1:-$NVIDIA_DRIVER_VERSION}
        shift
        continue
        ;;
        --k8s-base-repo-version)
        shift
            K8S_BASE_REPO_VERSION=${1:-$K8S_BASE_REPO_VERSION}
        shift
        continue
        ;;
        --k8s-infra-repo-version)
        shift
            K8S_INFRA_REPO_VERSION=${1:-$K8S_INFRA_REPO_VERSION}
        shift
        continue
        ;;
        --product-repo-version)
        shift
            PRODUCT_REPO_VERSION=${1:-$PRODUCT_REPO_VERSION}
        shift
        continue
        ;;
        --nvidia-driver-repo-version)
        shift
            NVIDIA_DRIVER_REPO_VERSION=${1:-$NVIDIA_DRIVER_REPO_VERSION}
        shift
        continue
        ;;
        --os-package)
        shift
            OS_PACKAGE=${1:-$OS_PACKAGE}
        shift
            DOWNLOAD_ONLY="true"
        continue
        ;;
        --pod-network-cidr)
        shift
            POD_NETWORK_CIDR=${1:-$POD_NETWORK_CIDR}
        shift
        continue
        ;;
        --service-cidr)
        shift
            SERVICE_CIDR=${1:-$SERVICE_CIDR}
        shift
        continue
        ;;
    esac
    break
done

# evaluate variables after providing script arguments
PRODUCT_MIGRATION_NAME="migration-workflow-${PRODUCT_NAME}"
RHEL_PACKAGES_FILE_URL="${S3_BUCKET_URL}/repos/${RHEL_PACKAGES_FILE_NAME}"
APT_REPO_FILE_URL="${S3_BUCKET_URL}/repos/${APT_REPO_FILE_NAME}"
UBUNTU_NVIDIA_DRIVER_CONTAINER_URL="${S3_BUCKET_URL}/nvidia-driver/${NVIDIA_DRIVER_REPO_VERSION}/nvidia-driver-${NVIDIA_DRIVER_VERSION}-ubuntu1804-${NVIDIA_DRIVER_PACKAGE_VERSION}.tar.gz"
UBUNTU_NVIDIA_DRIVER_CONTAINER_MD5_URL="${S3_BUCKET_URL}/nvidia-driver/${NVIDIA_DRIVER_REPO_VERSION}/nvidia-driver-${NVIDIA_DRIVER_VERSION}-ubuntu1804-${NVIDIA_DRIVER_PACKAGE_VERSION}.md5"
RHEL_NVIDIA_DRIVER_CONTAINER_URL="${S3_BUCKET_URL}/nvidia-driver/${NVIDIA_DRIVER_REPO_VERSION}/nvidia-driver-${NVIDIA_DRIVER_VERSION}-rhel7-${NVIDIA_DRIVER_PACKAGE_VERSION}.tar.gz"
RHEL_NVIDIA_DRIVER_CONTAINER_MD5_URL="${S3_BUCKET_URL}/nvidia-driver/${NVIDIA_DRIVER_REPO_VERSION}/nvidia-driver-${NVIDIA_DRIVER_VERSION}-rhel7-${NVIDIA_DRIVER_PACKAGE_VERSION}.md5"
UBUNTU_NVIDIA_DRIVER_CONTAINER_FILE="${UBUNTU_NVIDIA_DRIVER_CONTAINER_URL##*/}"
RHEL_NVIDIA_DRIVER_CONTAINER_FILE="${RHEL_NVIDIA_DRIVER_CONTAINER_URL##*/}"

function cidr_overlap() (
  #check local cidr - This function was copied from the internet!
  subnet1="$1"
  subnet2="$2"
  
  # calculate min and max of subnet1
  # calculate min and max of subnet2
  # find the common range (check_overlap)
  # print it if there is one

  read_range () {
    IFS=/ read ip mask <<<"$1"
    IFS=. read -a octets <<< "$ip";
    set -- "${octets[@]}";
    min_ip=$(($1*256*256*256 + $2*256*256 + $3*256 + $4));
    host=$((32-mask))
    max_ip=$(($min_ip+(2**host)-1))
    printf "%d-%d\n" "$min_ip" "$max_ip"
  }

  check_overlap () {
    IFS=- read min1 max1 <<<"$1";
    IFS=- read min2 max2 <<<"$2";
    if [ "$max1" -lt "$min2" ] || [ "$max2" -lt "$min1" ]; then return; fi
    [ "$max1" -ge "$max2" ] && max="$max2" ||   max="$max1"
    [ "$min1" -le "$min2" ] && min="$min2" || min="$min1"
    printf "%s-%s\n" "$(to_octets $min)" "$(to_octets $max)"
  }

  to_octets () {
    first=$(($1>>24))
    second=$((($1&(256*256*255))>>16))
    third=$((($1&(256*255))>>8))
    fourth=$(($1&255))
    printf "%d.%d.%d.%d\n" "$first" "$second" "$third" "$fourth" 
  }

  range1="$(read_range $subnet1)"
  range2="$(read_range $subnet2)"
  overlap="$(check_overlap $range1 $range2)"
  [ -n "$overlap" ] && echo "Overlap $overlap of $subnet1 and $subnet2"

  # if cidr equal to install parameters exit 1 + echo notice to user
)

function cidr_check() {
  CIDR_LIST=$(ip route | cut -d' ' -f1)
  # This function cheks if there is CIDR overlap with local network and terminates install if true
  # echo ${CIDR_LIST}
  for network in $CIDR_LIST; do
    if [[ $network != "default" ]]; then
        if [[ $( cidr_overlap ${POD_NETWORK_CIDR} ${network}) ]]; then
          echo "Pods network CIDR Exist in network environment!!! Install terminated - nothing was done."
          echo "To run with custom CIDR use --pod-network-cidr"
          exit 1
        fi
        if [[ $( cidr_overlap ${SERVICE_CIDR} ${network}) ]]; then
          echo "Service CIDR Exist in network environment!!! Install terminated - nothing was done."
          echo "To run with custom CIDR use --service-cidr"
          exit 1
        fi
    fi
  done
}

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

  echo "" | tee -a ${LOG_FILE}
  echo "=====================================================================" | tee -a ${LOG_FILE}
  echo "==                Verifying Packages, please wait...               ==" | tee -a ${LOG_FILE}
  echo "=====================================================================" | tee -a ${LOG_FILE}
  echo "" | tee -a ${LOG_FILE}

  declare -a TAR_FILES_LIST=( "yq")
  if [ "${SKIP_K8S_BASE}" == "false" ]; then
    TAR_FILES_LIST+=("${K8S_BASE_NAME}-${K8S_BASE_VERSION}.tar")
  fi

  if [ "${SKIP_K8S_INFRA}" == "false" ]; then
    TAR_FILES_LIST+=("${K8S_INFRA_NAME}-${K8S_INFRA_VERSION}.tar.gz")
  fi

  if [ "${SKIP_PRODUCT}" == "false" ]; then
    TAR_FILES_LIST+=("${PRODUCT_NAME}-${PRODUCT_VERSION}.tar.gz")
  fi

  if [ "${SKIP_DRIVERS}" == "false" ]; then
    if [ -x "$(command -v apt-get)" ]; then
      if [ "${INSTALL_METHOD}" == "airgap" ] && [ "${NVIDIA_DRIVER_METHOD}" == "host" ]; then
        TAR_FILES_LIST+=("${APT_REPO_FILE_NAME}")
      elif [ "${NVIDIA_DRIVER_METHOD}" == "container" ]; then
        TAR_FILES_LIST+=("${UBUNTU_NVIDIA_DRIVER_CONTAINER_FILE}")
      fi
    elif [ -x "$(command -v yum)" ]; then
      if [ "${INSTALL_METHOD}" == "airgap" ] && [ "${NVIDIA_DRIVER_METHOD}" == "host" ]; then
        TAR_FILES_LIST+=("${RHEL_PACKAGES_FILE_NAME}" "${RHEL_NVIDIA_DRIVER_FILE}")
      elif [ "${NVIDIA_DRIVER_METHOD}" == "container" ]; then
        TAR_FILES_LIST+=("${RHEL_NVIDIA_DRIVER_CONTAINER_FILE}")
      else
        TAR_FILES_LIST+=("${RHEL_NVIDIA_DRIVER_FILE}")
      fi
    fi
  fi
  
  for file in "${TAR_FILES_LIST[@]}"; do
      if [[ ! -f "${BASEDIR}/${file}" ]] ; then
          echo "Error: required file ${file} is missing." | tee -a ${LOG_FILE}
          exit 1
      else
        if [ ${SKIP_MD5_CHECK} == "false" ]; then
          if [[ "${file}" == *'.tar'* ]]; then
            md5_checker "${file}"
          fi
        fi
      fi
  done
}

function join_by() { local IFS="$1"; shift; echo "$*"; }

function md5_checker() {
  FILE_NAME="${1}"
  if [ -f "${BASEDIR}/${FILE_NAME}" ] && [ -f "${BASEDIR}/${FILE_NAME%.tar*}.md5" ]; then
    FILE_NAME_MD5=($(md5sum ${BASEDIR}/${FILE_NAME}))
    echo "#### Perform md5 checksum to ${BASEDIR}/${FILE_NAME}" | tee -a ${LOG_FILE}
    if [ "${FILE_NAME_MD5}" != "$(cat ${BASEDIR}/${FILE_NAME%.tar*}.md5)" ]; then
      echo "Error: ${FILE_NAME} checksum does not match, The file wasn't fully downloaded or may corrupted" | tee -a ${LOG_FILE}
      exit 1
    fi
  else
    echo "Error: required file ${BASEDIR}/${FILE_NAME} or ${BASEDIR}/${FILE_NAME%.tar*}.md5 is missing." | tee -a ${LOG_FILE}
    exit 1
  fi
}

function download_files() {
  echo "" | tee -a ${LOG_FILE}
  echo "=====================================================================" | tee -a ${LOG_FILE}
  echo "==                Downloading Packages, please wait...             ==" | tee -a ${LOG_FILE}
  echo "=====================================================================" | tee -a ${LOG_FILE}
  echo "" | tee -a ${LOG_FILE}

  K8S_BASE_URL="${S3_BUCKET_URL}/base-k8s/${K8S_BASE_NAME}/${K8S_BASE_REPO_VERSION}/${K8S_BASE_NAME}-${K8S_BASE_VERSION}.tar"
  K8S_BASE_MD5_URL="${S3_BUCKET_URL}/base-k8s/${K8S_BASE_NAME}/${K8S_BASE_REPO_VERSION}/${K8S_BASE_NAME}-${K8S_BASE_VERSION}.md5"
  K8S_INFRA_URL="${S3_BUCKET_URL}/${K8S_INFRA_NAME}/${K8S_INFRA_REPO_VERSION}/${K8S_INFRA_NAME}-${K8S_INFRA_VERSION}.tar.gz"
  K8S_INFRA_MD5_URL="${S3_BUCKET_URL}/${K8S_INFRA_NAME}/${K8S_INFRA_REPO_VERSION}/${K8S_INFRA_NAME}-${K8S_INFRA_VERSION}.md5"
  K8S_PRODUCT_URL="${S3_BUCKET_URL}/products/${PRODUCT_NAME}/${PRODUCT_REPO_VERSION}/${PRODUCT_NAME}-${PRODUCT_VERSION}.tar.gz"
  K8S_PRODUCT_MD5_URL="${S3_BUCKET_URL}/products/${PRODUCT_NAME}/${PRODUCT_REPO_VERSION}/${PRODUCT_NAME}-${PRODUCT_VERSION}.md5"
  K8S_PRODUCT_MIGRATION_URL="${S3_BUCKET_URL}/products/${PRODUCT_MIGRATION_NAME}/${PRODUCT_REPO_VERSION}/${PRODUCT_MIGRATION_NAME}-${PRODUCT_VERSION}.tar.gz"
  K8S_PRODUCT_MIGRATION_MD5_URL="${S3_BUCKET_URL}/products/${PRODUCT_MIGRATION_NAME}/${PRODUCT_REPO_VERSION}/${PRODUCT_MIGRATION_NAME}-${PRODUCT_VERSION}.md5"

  GRAVITY_PACKAGE_INSTALL_SCRIPT_URL="https://raw.githubusercontent.com/AnyVisionltd/gravity-oneliner/${SCRIPT_VERSION}/gravity_package_installer.sh"
  YQ_URL="https://github.com/mikefarah/yq/releases/download/2.4.0/yq_linux_amd64"
  SCRIPT_URL="https://raw.githubusercontent.com/AnyVisionltd/gravity-oneliner/${SCRIPT_VERSION}/install.sh"

  if [ "${PRODUCT_NAME}" == "bettertomorrow" ]; then
    DASHBOARD_URL="https://s3.eu-central-1.amazonaws.com/anyvision-dashboard/1.24.0/AnyVision-1.24.0-linux-x86_64.AppImage"
  elif [ "${PRODUCT_NAME}" == "facedetect" ]; then
    DASHBOARD_URL="https://s3.eu-central-1.amazonaws.com/facedetect-dashboard/1.24.0/FaceDetect-1.24.0-linux-x86_64.AppImage"
  elif [ "${PRODUCT_NAME}" == "facesearch" ]; then
    DASHBOARD_URL="https://s3.eu-central-1.amazonaws.com/facesearch-dashboard/1.24.0/FaceSearch-1.24.0-linux-x86_64.AppImage"
  fi
 
  ## SHARED PACKAGES TO DOWNLOAD
  declare -a PACKAGES=("${GRAVITY_PACKAGE_INSTALL_SCRIPT_URL}" "${YQ_URL}" "${SCRIPT_URL}")

  if [ ${SKIP_K8S_BASE} == "false" ]; then
    PACKAGES+=("${K8S_BASE_URL}")
    PACKAGES+=("${K8S_BASE_MD5_URL}")
  fi

  if [ ${SKIP_K8S_INFRA} == "false" ]; then
    PACKAGES+=("${K8S_INFRA_URL}")
    PACKAGES+=("${K8S_INFRA_MD5_URL}")
  fi

  if [ ${SKIP_PRODUCT} == "false" ]; then
    PACKAGES+=("${K8S_PRODUCT_URL}")
    PACKAGES+=("${K8S_PRODUCT_MD5_URL}")
    if [ "${MIGRATION_EXIST}" == "true" ]; then
      PACKAGES+=("${K8S_PRODUCT_MIGRATION_URL}")
      PACKAGES+=("${K8S_PRODUCT_MIGRATION_MD5_URL}")
    fi
  fi

  if [ ${SKIP_DRIVERS} == "false" ]; then
    if [[ "${OS_PACKAGE}" == "ubuntu" ]] || [[ -x "$(command -v apt-get)" && -z "${OS_PACKAGE}" ]]; then
      if [ "${NVIDIA_DRIVER_METHOD}" == "container" ]; then
        PACKAGES+=("${UBUNTU_NVIDIA_DRIVER_CONTAINER_URL}")
        PACKAGES+=("${UBUNTU_NVIDIA_DRIVER_CONTAINER_MD5_URL}")
      else
        PACKAGES+=("${APT_REPO_FILE_URL}")
      fi
    elif [[ "${OS_PACKAGE}" == "redhat" ]] || [[ -x "$(command -v yum)" && -z "${OS_PACKAGE}" ]]; then
      if [ "${NVIDIA_DRIVER_METHOD}" == "container" ]; then
        PACKAGES+=("${RHEL_NVIDIA_DRIVER_CONTAINER_URL}")
        PACKAGES+=("${RHEL_NVIDIA_DRIVER_CONTAINER_MD5_URL}")
      else
        PACKAGES+=("${RHEL_PACKAGES_FILE_URL}" "${RHEL_NVIDIA_DRIVER_URL}")
      fi
    fi
  fi

  if [ "${DASHBOARD_EXIST}" == "true" ]; then
    PACKAGES+=("${DASHBOARD_URL}")
  fi

  # remove old script if exist before download
  rm -f ${BASEDIR}/${GRAVITY_PACKAGE_INSTALL_SCRIPT_URL##*/} ${BASEDIR}/${SCRIPT_URL##*/} ${BASEDIR}/*.md5

  declare -a PACKAGES_TO_DOWNLOAD

  for url in "${PACKAGES[@]}"; do
    filename=$(echo "${url##*/}")
    if [ ! -f "${BASEDIR}/${filename}" ] || [ -f "${BASEDIR}/${filename}.aria2" ]; then
      PACKAGES_TO_DOWNLOAD+=("${url}")
    fi
  done

  DOWNLOAD_LIST=$(join_by " " "${PACKAGES_TO_DOWNLOAD[@]}")
  if [ "${DOWNLOAD_LIST}" ]; then
    echo "#### Downloading Files ..." | tee -a ${LOG_FILE}
    echo "Downloading Files: $DOWNLOAD_LIST" >>${LOG_FILE} 2>&1
    aria2c --summary-interval=30 --force-sequential --auto-file-renaming=false --min-split-size=100M --split=10 --max-concurrent-downloads=5 --check-certificate=false ${DOWNLOAD_LIST}
  else
    echo "#### All the packages are already exist under ${BASEDIR}" | tee -a ${LOG_FILE}
  fi

  # check md5
  if [ ${SKIP_MD5_CHECK} == "false" ]; then
    for url in "${PACKAGES[@]}"; do
      file=$(echo "${url##*/}")
      if [[ "${file}" == *'.tar'* ]]; then
        md5_checker "${file}"
      fi
    done
  fi

  ## RENAME DOWNLOADED YQ
  if [ -f yq_linux_amd64 ]; then
    cp -n yq_linux_amd64 yq
  fi

  chmod +x ${BASEDIR}/yq* ${BASEDIR}/*.sh
}

function online_packages_installation() {
  echo "" | tee -a ${LOG_FILE}
  echo "=====================================================================" | tee -a ${LOG_FILE}
  echo "==                Installing Packages, please wait...              ==" | tee -a ${LOG_FILE}
  echo "=====================================================================" | tee -a ${LOG_FILE}
  echo "" | tee -a ${LOG_FILE}
  if [ -x "$(command -v apt-get)" ]; then
       set +e
       echo "#### Updating APT cache..." | tee -a ${LOG_FILE}
       apt-get -qq update >>${LOG_FILE} 2>&1
       set -e
       echo "#### Installing the following packages: curl software-properties-common aria2" | tee -a ${LOG_FILE}
       apt-get -qq install -y --no-install-recommends curl software-properties-common aria2 >>${LOG_FILE} 2>&1
  elif [ -x "$(command -v yum)" ]; then
       set +e
       echo "#### Installing the following packages: bash-completion aria2" | tee -a ${LOG_FILE}
       yum install -y https://dl.fedoraproject.org/pub/epel/epel-release-latest-7.noarch.rpm >>${LOG_FILE} 2>&1
       yum install -y bash-completion aria2 >>${LOG_FILE} 2>&1
       set -e
  fi
  echo "#### Done installing packages." | tee -a ${LOG_FILE}
}

function create_yum_local_repo() {
    cat >  /etc/yum.repos.d/local.repo <<EOF
[local]
name=local
baseurl=http://localhost:8085
enabled=1
gpgcheck=0
protect=0
EOF
}

function nvidia_drivers_container_installation() {
  echo "" | tee -a ${LOG_FILE}
  echo "=====================================================================" | tee -a ${LOG_FILE}
  echo "==              Installing Nvidia Container, please wait...        ==" | tee -a ${LOG_FILE}
  echo "=====================================================================" | tee -a ${LOG_FILE}
  echo "" | tee -a ${LOG_FILE}

  source /etc/os-release
  ## USE ONLY MAJOR VERSION OF RHEL VERSION
  if [[ "${VERSION_ID}" =~ ^[7,8]\.[0-9]+ ]]; then
    VERSION=${VERSION_ID%%.*}
  else
    VERSION=${VERSION_ID//.}
  fi
  ## BUILD DISTRIBUTION STRING
  DISTRIBUTION=${ID}${VERSION}
  if [[ -f "${BASEDIR}/nvidia-driver-${NVIDIA_DRIVER_VERSION}-${DISTRIBUTION}-${NVIDIA_DRIVER_PACKAGE_VERSION}.tar.gz" ]]; then
    install_gravity_app "${BASEDIR}/nvidia-driver-${NVIDIA_DRIVER_VERSION}-${DISTRIBUTION}-${NVIDIA_DRIVER_PACKAGE_VERSION}.tar.gz"
  else
    echo "unable to find the file: ${BASEDIR}/nvidia-driver-${NVIDIA_DRIVER_VERSION}-${DISTRIBUTION}-${NVIDIA_DRIVER_PACKAGE_VERSION}.tar.gz" | tee -a ${LOG_FILE} 
    exit 1
  fi
}

function nvidia_drivers_installation() {
  echo "" | tee -a ${LOG_FILE}
  echo "=====================================================================" | tee -a ${LOG_FILE}
  echo "==                Installing Nvidia Drivers, please wait...               ==" | tee -a ${LOG_FILE}
  echo "=====================================================================" | tee -a ${LOG_FILE}
  echo "" | tee -a ${LOG_FILE}
  if [ -x "$(command -v nvidia-smi)" ]; then
    nvidia_version=$(nvidia-smi --query-gpu=driver_version --format=csv,noheader || true)
  fi

  if [ -x "$(command -v apt-get)" ]; then
    if [[ "${nvidia_version}" == '410'* ]] ; then
      echo "nvidia driver nvidia-driver-410 already installed. Skipping ..." | tee -a ${LOG_FILE}
    else
      echo "Installing nvidia driver nvidia-driver-410" | tee -a ${LOG_FILE}
      if [[ "${INSTALL_METHOD}" == "online" ]]; then
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
      apt-get install -y --no-install-recommends cuda-drivers=410.104-1 >>${LOG_FILE} 2>&1
      nvidia_installed=true
    fi
  elif [ -x "$(command -v yum)" ]; then

    set +e
    x_exist=$(pgrep -x X)
    set -e

    if [ "${x_exist}" != "" ]; then
      echo "Error: You are runnning X server (Desktop GUI). please change to run level 3 in order to stop X server and run again the script" | tee -a ${LOG_FILE}
      echo "In order to diable X server (Desktop GUI)" | tee -a ${LOG_FILE}
      echo "1) systemctl set-default multi-user.target" | tee -a ${LOG_FILE}
      echo "2) tee /etc/modprobe.d/blacklist-nouveau.conf <<< 'blacklist nouveau'" | tee -a ${LOG_FILE}
      echo "3) tee -a /etc/modprobe.d/blacklist-nouveau.conf <<< 'options nouveau modeset=0'" | tee -a ${LOG_FILE}
      echo "4) dracut -f" | tee -a ${LOG_FILE}
      echo "5) reboot" | tee -a ${LOG_FILE}
      echo "6) run the script again" | tee -a ${LOG_FILE}
      echo "In order to re-enable X server (Desktop GUI)" | tee -a ${LOG_FILE}
      echo "systemctl set-default graphical.target && reboot" | tee -a ${LOG_FILE}
      exit 1
    fi

    if [[ "${nvidia_version}" == '410'* ]] ; then
      echo "nvidia driver nvidia-driver-410 already installed" | tee -a ${LOG_FILE}
    else
      echo "Installing nvidia driver nvidia-driver-410" | tee -a ${LOG_FILE}

      if [[ "${INSTALL_METHOD}" == "online" ]]; then
        yum install -y gcc kernel-devel-$(uname -r) kernel-headers-$(uname -r) >>${LOG_FILE} 2>&1
      else
        mkdir -p /opt/packages/public >>${LOG_FILE} 2>&1
        tar -xf ${BASEDIR}/${RHEL_PACKAGES_FILE_NAME} -C /opt/packages/public >>${LOG_FILE} 2>&1
        create_yum_local_repo
        yum install --disablerepo='*' --enablerepo='local' -y gcc kernel-devel-$(uname -r) kernel-headers-$(uname -r) >>${LOG_FILE} 2>&1
      fi
      chmod +x ${BASEDIR}/${RHEL_NVIDIA_DRIVER_FILE} >>${LOG_FILE} 2>&1
      ${BASEDIR}/${RHEL_NVIDIA_DRIVER_FILE} --silent --no-install-compat32-libs >>${LOG_FILE} 2>&1
      nvidia_installed=true
    fi
  fi
}

function install_gravity() {
  ## Install gravity
  if [[ "${SKIP_K8S_BASE}" == "false" ]]; then
    echo "" | tee -a ${LOG_FILE}
    echo "=====================================================================" | tee -a ${LOG_FILE}
    echo "==                Installing Gravity, please wait...               ==" | tee -a ${LOG_FILE}
    echo "=====================================================================" | tee -a ${LOG_FILE}
    echo "" | tee -a ${LOG_FILE}

    echo "### Installting gravity k8s base: ${K8S_BASE_NAME}-${K8S_BASE_VERSION}"
    DIR_K8S_BASE="gravity-base-k8s"
    mkdir -p "${BASEDIR}/${DIR_K8S_BASE}"
    tar -xf "${BASEDIR}/${K8S_BASE_NAME}-${K8S_BASE_VERSION}.tar" -C "${BASEDIR}/${DIR_K8S_BASE}" | tee -a ${LOG_FILE}

    cd ${BASEDIR}/${DIR_K8S_BASE}
    ${BASEDIR}/${DIR_K8S_BASE}/gravity install \
        --cloud-provider=generic \
        --pod-network-cidr=${POD_NETWORK_CIDR} \
        --service-cidr=${SERVICE_CIDR} \
        --service-uid=5000 \
        --vxlan-port=8472 \
        --cluster=cluster.local \
        --flavor=${NODE_ROLE} \
        --role=${NODE_ROLE} | tee -a ${LOG_FILE}
    cd ${BASEDIR}
    
    create_admin
  fi
}

function create_admin() {
  echo "" | tee -a ${LOG_FILE}
  echo "### Create admin" | tee -a ${LOG_FILE}
  echo "" | tee -a ${LOG_FILE}
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

function install_k8s_infra_app() {
  echo "" | tee -a ${LOG_FILE}
  echo "=====================================================================" | tee -a ${LOG_FILE}
  echo "==                Installing infra chart...                        ==" | tee -a ${LOG_FILE}
  echo "=====================================================================" | tee -a ${LOG_FILE}
  echo "" | tee -a ${LOG_FILE}  
  if [[ "${SKIP_K8S_INFRA}" == "false" ]] && [[ -f "${BASEDIR}/${K8S_INFRA_NAME}-${K8S_INFRA_VERSION}.tar.gz" ]]; then
    install_gravity_app "${BASEDIR}/${K8S_INFRA_NAME}-${K8S_INFRA_VERSION}.tar.gz" --env=rancher=true
  else
    echo "### Skipping installing infra charts .." | tee -a ${LOG_FILE}
  fi
}

function install_product_app() {
  echo "" | tee -a ${LOG_FILE}
  echo "=====================================================================" | tee -a ${LOG_FILE}
  echo "==                Installing product chart...                      ==" | tee -a ${LOG_FILE}
  echo "=====================================================================" | tee -a ${LOG_FILE}
  echo "" | tee -a ${LOG_FILE}
  if [[ "${SKIP_PRODUCT}" == "false" ]] && [[ -f "${BASEDIR}/${PRODUCT_NAME}-${PRODUCT_VERSION}.tar.gz" ]]; then
    install_gravity_app "${BASEDIR}/${PRODUCT_NAME}-${PRODUCT_VERSION}.tar.gz" --env=install_product=${INSTALL_PRODUCT}
    if [ "$MIGRATION_EXIST" == "true" ] && [ -f "${BASEDIR}/${PRODUCT_MIGRATION_NAME}-${PRODUCT_VERSION}.tar.gz" ] ; then
      install_gravity_app "${BASEDIR}/${PRODUCT_MIGRATION_NAME}-${PRODUCT_VERSION}.tar.gz" --env=install_product=false
    fi
  else
    echo "### Skipping installing product charts .." | tee -a ${LOG_FILE}
  fi
}

function restore_secrets() {
  if [ -d "/opt/backup/secrets" ]; then
    echo "" | tee -a ${LOG_FILE}
    echo "=====================================================================" | tee -a ${LOG_FILE}
    echo "==                Restoring k8s Secrets...                         ==" | tee -a ${LOG_FILE}
    echo "=====================================================================" | tee -a ${LOG_FILE}
    echo "" | tee -a ${LOG_FILE}
    declare -a relevant_secrets_list=("redis-secret" "mongodb-secret" "rabbitmq-secret" "ingress-basic-auth-secret" "memsql-secret")
    for secret in "${relevant_secrets_list[@]}"
    do
      if [ -f "/opt/backup/secrets/${secret}.yaml" ]; then
        echo "Import secret ${secret}" | tee -a ${LOG_FILE}
        #kubectl create -f /opt/backup/secrets/${secret}.yaml || true >>${LOG_FILE} 2>&1
        cat /opt/backup/secrets/${secret}.yaml | ${BASEDIR}/yq d - metadata.managedFields | kubectl create -f - >>${LOG_FILE} 2>&1 || true
      fi
    done
    #rm -rf /opt/backup/secrets
  fi
}

function restore_sw_filer_data() {
  if [ -f "/opt/backup/pvc_id/filer_pvc_id" ]; then
    echo "" | tee -a ${LOG_FILE}
    echo "=====================================================================" | tee -a ${LOG_FILE}
    echo "==        Restoring SW-Filer Data to /ssd/seaweed-filer/           ==" | tee -a ${LOG_FILE}
    echo "=====================================================================" | tee -a ${LOG_FILE}
    echo "" | tee -a ${LOG_FILE}
    filer_pvc_id=$(cat /opt/backup/pvc_id/filer_pvc_id | head -1)
    if [[ -n "$filer_pvc_id" ]]; then
        /usr/bin/rsync -a -v --stats --ignore-existing /ssd/local-path-provisioner/${filer_pvc_id}/ /ssd/seaweed-filer/
    fi
  fi
}

echo "Installing ${NODE_ROLE} node with method ${INSTALL_METHOD}" | tee -a ${LOG_FILE}

if [[ "${INSTALL_METHOD}" == "online" ]]; then
  online_packages_installation
  download_files
  if [ "${DOWNLOAD_ONLY}" == "true" ]; then
    echo "#### Download only is enabled. will exit" | tee -a ${LOG_FILE}
    exit 0
  fi
  echo "Checking server environment before installing"
  cidr_check
  is_kubectl_exists
  #is_tar_files_exists
  chmod +x ${BASEDIR}/yq* ${BASEDIR}/*.sh
  install_gravity
  #create_admin
  restore_secrets
  restore_sw_filer_data
  install_k8s_infra_app
  if [ "${SKIP_DRIVERS}" == "false" ]; then
    if [ "${NVIDIA_DRIVER_METHOD}" == "container" ]; then
      nvidia_drivers_container_installation
    else
      nvidia_drivers_installation
    fi
  fi  
  install_product_app
else
  echo "Checking server environment before installing"
  cidr_check
  is_kubectl_exists
  is_tar_files_exists
  chmod +x ${BASEDIR}/yq* ${BASEDIR}/*.sh
  install_gravity
  #create_admin
  restore_secrets
  restore_sw_filer_data
  install_k8s_infra_app
  if [ "${SKIP_DRIVERS}" == "false" ]; then
    if [ "${NVIDIA_DRIVER_METHOD}" == "container" ]; then
      nvidia_drivers_container_installation
    else
      nvidia_drivers_installation
    fi
  fi
  install_product_app
fi


echo "=============================================================================================" | tee -a ${LOG_FILE}
echo "                                    Installation Completed!                                  " | tee -a ${LOG_FILE}
echo "=============================================================================================" | tee -a ${LOG_FILE}

if [ ${nvidia_installed} ]; then
  echo "                  New nvidia driver has been installed, Reboot is required!               " | tee -a ${LOG_FILE}
fi
