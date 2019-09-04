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
PRODUCT_NAME="bettertomorrow"
PRODUCT_VERSION="1.23.1-5"
APT_REPO_FILE_NAME="apt-repo-20190821.tar"
NVIDIA_DRIVERS_VERSION="410.104-1"
SKIP_K8S_BASE=false
SKIP_K8S_INFRA=false
SKIP_PRODUCT=false
SKIP_DRIVERS=false


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
#        --skip-base)
#        shift
#            SKIP_K8S_BASE=${1:-true}
#        shift
#        continue
#        ;;
#        --skip-infra)
#        shift
#            SKIP_K8S_INFRA=${1:-true}
#        shift
#        continue
#        ;;
#        --skip-product)
#        shift
#            SKIP_PRODUCT=${1:-true}
#        shift
#        continue
#        ;;
#        --skip-drivers)
#        shift
#            SKIP_DRIVERS=${1:-true}
#        shift
#        continue
#        ;;
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
    for file in ${K8S_BASE_NAME}-${K8S_BASE_VERSION}.tar ${K8S_INFRA_NAME}-${K8S_INFRA_VERSION}.tar.gz ${PRODUCT_NAME}-${PRODUCT_VERSION}.tar.gz ${APT_REPO_FILE_NAME}; do
        if [[ ! -f $file ]] ; then
            echo "Missing $file it's required for installation to success"
            exit 1
        fi
    done
}


function online_nvidia_drivers_installation () {

# Disable Ansible warnings
export ANSIBLE_LOCALHOST_WARNING=false
export ANSIBLE_DEPRECATION_WARNINGS=false

echo "------ Starting Gravity installer $(date '+%Y-%m-%d %H:%M:%S')  ------" > ${BASEDIR}/gravity-installer.log


echo "" | tee -a ${BASEDIR}/gravity-installer.log
echo "=====================================================================" | tee -a ${BASEDIR}/gravity-installer.log
echo "==             Installing dependencies, please wait...             ==" | tee -a ${BASEDIR}/gravity-installer.log
echo "=====================================================================" | tee -a ${BASEDIR}/gravity-installer.log
echo "" | tee -a ${BASEDIR}/gravity-installer.log


if [ -x "$(command -v curl)" ] && [ -x "$(command -v ansible)" ]; then
    true
else
    if [ -x "$(command -v apt-get)" ]; then
        set -e
        apt-get -qq update > /dev/null
        apt-get -qq install -y --no-install-recommends curl software-properties-common > /dev/null
	apt-add-repository --yes --update ppa:ansible/ansible > /dev/null
	apt-get -qq install -y ansible > /dev/null
        set +e
    elif [ -x "$(command -v yum)" ]; then
        set -e
        #yum install -y curl > /dev/null
        curl -o epel-release-latest-7.noarch.rpm https://dl.fedoraproject.org/pub/epel/epel-release-latest-7.noarch.rpm > /dev/null
	rpm -ivh epel-release-latest-7.noarch.rpm || true > /dev/null
        yum install -y epel-release > /dev/null
        yum install -y python python-pip > /dev/null
        pip install --upgrade pip > /dev/null
        #pip install markupsafe xmltodict pywinrm > /dev/null
        yum install -y ansible > /dev/null
        set +e
    fi
fi

rm -rf /opt/anv-gravity
set -e
mkdir -p /opt/anv-gravity/ansible/roles
cd /opt/anv-gravity/ansible/roles
curl -fsSLo ansible-role-nvidia-driver.tar.gz https://github.com/NVIDIA/ansible-role-nvidia-driver/archive/v1.1.0.tar.gz | tee -a ${BASEDIR}/gravity-installer.log
tar xfz ansible-role-nvidia-driver.tar.gz | tee -a ${BASEDIR}/gravity-installer.log
rm -f ansible-role-nvidia-driver.tar.gz
mv ansible-role-nvidia-driver* nvidia-driver
cd /opt/anv-gravity/ansible
cat <<EOF > main.yml
---
- hosts: localhost
  gather_facts: true
  become: yes
  vars:
    nvidia_driver_package_version: "410.104-1"
    nvidia_driver_skip_reboot: yes
  pre_tasks:
    - name: check if nvidia gpu exist in lspci
      shell: "lspci | grep ' VGA '"
      register: nvidia_device_lspci
      ignore_errors: true
    - name: check if nvidia gpu exist in lshw
      shell: "lshw -C display"
      register: nvidia_device_lshw
      ignore_errors: true
  roles:
    #- { role: os_config, tags: ["os"] }
    - { role: nvidia-driver, tags: ["nvidia-driver"], when: "(((nvidia_device_lspci is defined) and (nvidia_device_lspci.stdout.find('NVIDIA') != -1)) or ((nvidia_device_lshw is defined) and (nvidia_device_lshw.stdout.find('NVIDIA') != -1)))" }
EOF
set +e


echo "" | tee -a ${BASEDIR}/gravity-installer.log
echo "=====================================================================" | tee -a ${BASEDIR}/gravity-installer.log
echo "==             Installing NVIDIA Driver, please wait...            ==" | tee -a ${BASEDIR}/gravity-installer.log
echo "=====================================================================" | tee -a ${BASEDIR}/gravity-installer.log
echo "" | tee -a ${BASEDIR}/gravity-installer.log

## Install nvidia-driver
ansible-playbook --become --become-user=root main.yml -vv | tee -a ${BASEDIR}/gravity-installer.log
if [ $? != 0 ]; then
    echo "" | tee -a ${BASEDIR}/gravity-installer.log
    echo "Installation failed, please contact support." | tee -a ${BASEDIR}/gravity-installer.log
    exit 1
fi

}

function install_nvidia_drivers_airgap() {
    ## if ubuntu
    tar -xf ${BASEDIR}/${APT_REPO_FILE_NAME} -C /opt/packages
    mkdir -p /etc/apt-orig
    rsync -q -a --ignore-existing /etc/apt/ /etc/apt-orig/
    rm -rf /etc/apt/sources.list.d/*
    echo "deb [arch=amd64 trusted=yes allow-insecure=yes] http://$(hostname --ip-address | awk '{print $1}'):8085/ bionic main" > /etc/apt/sources.list
    apt update -y
    apt install cuda-drivers=${NVIDIA_DRIVERS_VERSION}
    ## redhat
}

function install_gravity() {
    ## Install gravity
    if [[ "$SKIP_K8S_BASE" = false ]]; then
        pushd /opt/anv-gravity
        echo "" | tee -a ${BASEDIR}/gravity-installer.log
        echo "=====================================================================" | tee -a ${BASEDIR}/gravity-installer.log
        echo "==                Installing Gravity, please wait...               ==" | tee -a ${BASEDIR}/gravity-installer.log
        echo "=====================================================================" | tee -a ${BASEDIR}/gravity-installer.log
        echo "" | tee -a ${BASEDIR}/gravity-installer.log
        set -e
        if [[ $INSTALL_METHOD = "online" ]]; then
          curl -fSLo ${K8S_BASE_NAME}-${K8S_BASE_VERSION}.tar https://gravity-bundles.s3.eu-central-1.amazonaws.com/anv-base-k8s/on-demand-all-caps/${K8S_BASE_NAME}-${K8S_BASE_VERSION}.tar 2> >(tee -a ${BASEDIR}/gravity-installer.log >&2)
        fi
        tar xf ${K8S_BASE_NAME}-${K8S_BASE_VERSION}.tar | tee -a ${BASEDIR}/gravity-installer.log
        ./gravity install \
            --cloud-provider=generic \
            --pod-network-cidr="10.244.0.0/16" \
            --service-cidr="10.100.0.0/16" \
            --vxlan-port=8472 \
            --cluster=cluster.local \
            --flavor=aio \
            --role=aio | tee -a ${BASEDIR}/gravity-installer.log
        popd
     fi
}

function create_admin() {
  cat <<EOF > admin.yaml
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
}

function install_gravity_app() {
  echo "Installing app $1 version $2"
  gravity ops connect --insecure https://localhost:3009 admin Passw0rd123 | tee -a ${BASEDIR}/gravity-installer.log
  gravity app import --force --insecure --ops-url=https://localhost:3009 ${BASEDIR}/${1}-${2}.tar.gz | tee -a ${BASEDIR}/gravity-installer.log
  gravity app pull --force --insecure --ops-url=https://localhost:3009 gravitational.io/${1}:${2} | tee -a ${BASEDIR}/gravity-installer.log
  gravity exec gravity app export gravitational.io/${1}:${2} | tee -a ${BASEDIR}/gravity-installer.log
  gravity exec gravity app hook --env=rancher=true gravitational.io/${1}:${2} install | tee -a ${BASEDIR}/gravity-installer.log
}

function install_k8s_infra_app() {

  ## Install infra package
  if [[ $INSTALL_METHOD = "online" ]]; then
    curl -fSLo ${K8S_INFRA_NAME}-${K8S_INFRA_VERSION}.tar.gz https://gravity-bundles.s3.eu-central-1.amazonaws.com/k8s-infra/development/${K8S_INFRA_NAME}-${K8S_INFRA_VERSION}.tar.gz 2> >(tee -a ${BASEDIR}/gravity-installer.log >&2)
  fi
  install_gravity_app ${K8S_INFRA_NAME} ${K8S_INFRA_VERSION}

}

function install_product_app() {
  if [[ $INSTALL_METHOD = "online" ]]; then
    curl -fSLo ${PRODUCT_NAME}-${PRODUCT_VERSION}.tar https://gravity-bundles.s3.eu-central-1.amazonaws.com/${PRODUCT_NAME}/registry-variable/${PRODUCT_NAME}-${PRODUCT_VERSION}.tar.gz 2> >(tee -a ${BASEDIR}/gravity-installer.log >&2)
  fi
  install_gravity_app ${PRODUCT_NAME} ${PRODUCT_VERSION}

}


echo "Installing mode $INSTALL_MODE with method $INSTALL_METHOD"

is_kubectl_exists
echo $KUBECTL_EXISTS

if [[ $INSTALL_METHOD = "online" ]]; then
     online_nvidia_drivers_installation
     install_gravity
     create_admin
     install_k8s_infra_app
     install_product_app
else
    is_tar_files_exists
    install_gravity
    create_admin
    install_k8s_infra_app
    install_nvidia_drivers_airgap
    install_product_app
fi
