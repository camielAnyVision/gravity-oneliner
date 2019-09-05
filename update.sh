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
   echo "  [m|--update-method] Installation method [online, airgap (need extra files on same dir as this script)]"
   echo "  [-p|--product-name] Product name to install"
   echo "  [-s|--product-version] Product version to install"
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
        -m|--install-method)
        shift
            INSTALL_METHOD=${1:-online}
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
  if [ -x "$(command -v kubectl)" ]; then
    if ! [[ $(kubectl cluster-info) == *'https://localhost:6443'* ]]; then
      echo "" | tee -a ${BASEDIR}/gravity-installer.log
      echo "Error: this machine is part of an existing Kubernetes cluster, please detach it before running this installer." | tee -a ${BASEDIR}/gravity-installer.log
      KUBECTL_EXISTS=true
    fi
  fi
}

function is_tar_files_exists(){
    for file in ${PRODUCT_NAME}-${PRODUCT_VERSION}.tar.gz; do
        if [[ ! -f $file ]] ; then
            echo "Missing $file it's required for installation to success"
            exit 1
        fi
    done
}


function update_gravity_app() {
  echo "Installing app $1 version $2"
  gravity ops connect --insecure https://localhost:3009 admin Passw0rd123 | tee -a ${BASEDIR}/gravity-installer.log
  gravity app import --force --insecure --ops-url=https://localhost:3009 ${BASEDIR}/${1}-${2}.tar.gz | tee -a ${BASEDIR}/gravity-installer.log
  gravity app pull --force --insecure --ops-url=https://localhost:3009 gravitational.io/${1}:${2} | tee -a ${BASEDIR}/gravity-installer.log
  gravity exec gravity app export gravitational.io/${1}:${2} | tee -a ${BASEDIR}/gravity-installer.log
  gravity exec gravity app hook --env=rancher=true gravitational.io/${1}:${2} install | tee -a ${BASEDIR}/gravity-installer.log
}


function update_product_app() {
  if [[ $INSTALL_METHOD = "online" ]]; then
    curl -fSLo ${PRODUCT_NAME}-${PRODUCT_VERSION}.tar.gz https://gravity-bundles.s3.eu-central-1.amazonaws.com/products/${PRODUCT_NAME}/registry-variable/${PRODUCT_NAME}-${PRODUCT_VERSION}.tar.gz 2> >(tee -a ${BASEDIR}/gravity-installer.log >&2)
  fi
  update_gravity_app ${PRODUCT_NAME} ${PRODUCT_VERSION}

}


echo "Installing mode $INSTALL_MODE with method $INSTALL_METHOD"

is_kubectl_exists

if [[ $INSTALL_METHOD = "airgap" ]]; then
    echo "Checking if tar files exists"
    is_tar_files_exists
fi
echo "Updating Product ${PRODUCT_NAME} to version ${PRODUCT_VERSION}"
update_product_app
