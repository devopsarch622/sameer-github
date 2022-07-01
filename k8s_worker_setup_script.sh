#!/usr/bin/env bash
# Check if not root user and if the Memory is less than required
if [ ! $EUID -eq 0 ]
 then
  echo "Please run $0 as root or sudo user"
  exit 1
 elif [ $MEM -lt 1700 ]
  then
   echo "System memory is ${MEM}MB required minimum 1700MB"
   exit 2
fi

# Enable iptables bridged traffic
modprobe br_netfilter
cat <<EOF | sudo tee /etc/modules-load.d/k8s.conf
br_netfilter
EOF
cat <<EOF | sudo tee /etc/sysctl.d/k8s.conf
net.bridge.bridge-nf-call-ip6tables = 1
net.bridge.bridge-nf-call-iptables = 1
EOF
sysctl --system

# Disable swap and remove the entries from the fstab file
swapoff -a
sed -i '/ swap / s/^\(.*\)$/#\1/g' /etc/fstab

# Install the required packages for Docker
apt-get update -y
    apt-get install -y \
    apt-transport-https \
    ca-certificates \
    curl \
    gnupg \
    lsb-release

# Add the Docker GPG key and apt repository
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg
 echo \
  "deb [arch=amd64 signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu \
  $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

# Install the Docker community edition
sudo apt-get update -y
apt-get install docker-ce docker-ce-cli containerd.io -y

# Add the docker daemon configurations to use systemd as the cgroup driver
cat <<EOF | sudo tee /etc/docker/daemon.json
{
  "exec-opts": ["native.cgroupdriver=systemd"],
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "100m"
  },
  "storage-driver": "overlay2"
}
EOF

# Start and enable the docker service
systemctl enable docker
systemctl daemon-reload
systemctl restart docker

# Install the required dependencies
apt-get update -y
apt-get install -y apt-transport-https ca-certificates curl
curl -fsSLo /usr/share/keyrings/kubernetes-archive-keyring.gpg https://packages.cloud.google.com/apt/doc/apt-key.gpg

# Add the GPG key and apt repository.
echo "deb [signed-by=/usr/share/keyrings/kubernetes-archive-keyring.gpg] https://apt.kubernetes.io/ kubernetes-xenial main" | sudo tee /etc/apt/sources.list.d/kubernetes.list

# Update apt and install kubelet, kubeadm, and kubectl
apt-get update -y
apt-get install -y kubelet kubeadm kubectl

# To handle runtime.v1alpha2.RuntimeService error
if [ -f /etc/containerd/config.toml ]
then
rm -f /etc/containerd/config.toml
systemctl restart containerd
fi

#
