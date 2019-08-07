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
echo "== Making sure that all dependencies are installed, please wait... ==" | tee -a ${BASEDIR}/gravity-installer.log
echo "=====================================================================" | tee -a ${BASEDIR}/gravity-installer.log
echo "" | tee -a ${BASEDIR}/gravity-installer.log


if [ -x "$(command -v curl)" ] && [ -x "$(command -v ansible)" ]; then
    continue
else
    if [ -x "$(command -v apt-get)" ]; then
        set -e
        apt-get -qq update > /dev/null
        apt-get -qq install -y --no-install-recommends curl software-properties-common > /dev/null
	apt-add-repository --yes --update ppa:ansible/ansible
	apt-get -qq install -y ansible
        set +e
    elif [ -x "$(command -v yum)" ]; then
        set -e
        yum install -y curl
        curl -o epel-release-latest-7.noarch.rpm https://dl.fedoraproject.org/pub/epel/epel-release-latest-7.noarch.rpm
        rpm -ivh epel-release-latest-7.noarch.rpm
        yum install -y epel-release
        yum install -y python python-pip
        pip install --upgrade pip
        pip install markupsafe xmltodict pywinrm
        yum install -y ansible
        set +e
    fi
fi

rm -rf /opt/anv-gravity
mkdir -p /opt/anv-gravity/ansible/roles
cd /opt/anv-gravity/ansible/roles
curl -o ansible-role-nvidia-driver.tar.gz https://github.com/NVIDIA/ansible-role-nvidia-driver/archive/v1.1.0.tar.gz
tar xfz ansible-role-nvidia-driver.tar.gz
rm -f ansible-role-nvidia-driver.tar.gz
mv ansible-role-nvidia-driver* nvidia-driver
cd /opt/anv-gravity/ansible
cat <<EOF > main.yml
---
- hosts: localhost
  gather_facts: true
  become: yes
  vars:
    nvidia_driver_package_version: "418.67-1"
    docker_install_compose: False
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

## Install nvidia-driver
ansible-playbook --become --become-user=root main.yml -vv | tee -a ${BASEDIR}/gravity-installer.log
if [ $? != 0 ]; then
    echo "" | tee -a ${BASEDIR}/gravity-installer.log
    echo "Installation failed, please contact support." | tee -a ${BASEDIR}/gravity-installer.log
    exit 1
fi

## Install gravity
cd /opt/anv-gravity
curl -o anv-base-k8s-1.0.0.tar https://gravity-bundles.s3.eu-central-1.amazonaws.com/anv-base-k8s/anv-base-k8s-1.0.0.tar
tar xf anv-base-k8s-1.0.0.tar
./gravity install | tee -a ${BASEDIR}/gravity-installer.log
