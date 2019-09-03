#!/bin/bash

# Absolute path to this script
SCRIPT=$(readlink -f "$0")
# Absolute path to the script directory
BASEDIR=$(dirname "$SCRIPT")

# Disable Ansible warnings
export ANSIBLE_LOCALHOST_WARNING=false
export ANSIBLE_DEPRECATION_WARNINGS=false

echo "------ Starting Gravity installer $(date '+%Y-%m-%d %H:%M:%S')  ------" > ${BASEDIR}/gravity-installer.log

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

## Check if this machine is part of an existing Kubernetes cluster
if [ -x "$(command -v kubectl)" ]; then
  if ! [[ $(kubectl cluster-info) == *'https://localhost:6443'* ]]; then
    echo "" | tee -a ${BASEDIR}/gravity-installer.log
    echo "Error: this machine is part of an existing Kubernetes cluster, please detach it before running this installer." | tee -a ${BASEDIR}/gravity-installer.log
    echo "Installation failed, please contact support." | tee -a ${BASEDIR}/gravity-installer.log
    exit 1
  fi
fi

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
        yum install -y curl > /dev/null
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
    #nvidia_driver_package_version: "418.67-1"
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

## Install gravity
cd /opt/anv-gravity
echo "" | tee -a ${BASEDIR}/gravity-installer.log
echo "=====================================================================" | tee -a ${BASEDIR}/gravity-installer.log
echo "==                Installing Gravity, please wait...               ==" | tee -a ${BASEDIR}/gravity-installer.log
echo "=====================================================================" | tee -a ${BASEDIR}/gravity-installer.log
echo "" | tee -a ${BASEDIR}/gravity-installer.log
set -e
curl -fSLo anv-base-k8s-1.0.5.tar https://gravity-bundles.s3.eu-central-1.amazonaws.com/anv-base-k8s/on-demand-all-caps/anv-base-k8s-1.0.5.tar 2> >(tee -a ${BASEDIR}/gravity-installer.log >&2)
tar xf anv-base-k8s-1.0.5.tar | tee -a ${BASEDIR}/gravity-installer.log
./gravity install \
	--cloud-provider=generic \
	--pod-network-cidr="10.244.0.0/16" \
	--service-cidr="10.100.0.0/16" \
	--vxlan-port=8472 \
	--cluster=cluster.local \
	--flavor=aio \
	--role=aio | tee -a ${BASEDIR}/gravity-installer.log

create_admin() {
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

if [ $? = 0 ]; then
  ## Provision a cluster admin user
  create_admin | tee -a ${BASEDIR}/gravity-installer.log
  ## Install infra package
  curl -fSLo k8s-infra-1.0.5.tar.gz https://gravity-bundles.s3.eu-central-1.amazonaws.com/k8s-infra/development/k8s-infra-1.0.5.tar.gz 2> >(tee -a ${BASEDIR}/gravity-installer.log >&2)
  gravity ops connect --insecure https://localhost:3009 admin Passw0rd123 | tee -a ${BASEDIR}/gravity-installer.log
  gravity app import --force --insecure --ops-url=https://localhost:3009 k8s-infra-1.0.5.tar.gz | tee -a ${BASEDIR}/gravity-installer.log
  gravity app pull --force --insecure --ops-url=https://localhost:3009 gravitational.io/k8s-infra:1.0.5 | tee -a ${BASEDIR}/gravity-installer.log
  #gravity exec gravity app export gravitational.io/k8s-infra:1.0.5 | tee -a ${BASEDIR}/gravity-installer.log
  gravity exec gravity app hook --env=rancher=true gravitational.io/k8s-infra:1.0.5 install | tee -a ${BASEDIR}/gravity-installer.log
fi
