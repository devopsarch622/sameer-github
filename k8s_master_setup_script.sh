#!/usr/bin/env bash
# this script will setup kubernetes master node
ALLIP=`ip a | grep -w inet | awk '{print $2}' | cut -d "/" -f1`
MEM=`free -m | grep -w "Mem" | awk '{print $2}'`
NODENAME=$(hostname -s)
DT=`date +%d.%b.%y`
WORKERIPLIST=k8s_wn_$DT.txt

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

# To list all the configured IP's in this node and to set k8s master node IP
PS3="Please select your k8s master node IP: "
select ip in $ALLIP
do
echo "You have selected $ip as your k8s master node IP"
break
done
sleep 2
IPADDR=$ip

# Add worker node
> $WORKERIPLIST
while true
do
        IFS= read -p 'Please enter your worker node IP: ' -r wnip
        echo "$wnip" >> $WORKERIPLIST
        read -p "Do you want to add another worker node?[y/n]" -n 1 awn
        echo
        case "$awn" in
                [Yy]) continue
                      echo "$wnip" >> $WORKERIPLIST;;
                   *) break;;
        esac
done

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
fi
systemctl restart containerd

# Now, initialize the master node control plane configurations
kubeadm init --apiserver-advertise-address=$IPADDR  --apiserver-cert-extra-sans=$IPADDR  --pod-network-cidr=192.168.0.0/16 --node-name $NODENAME

# Use the following commands from the output to create the kubeconfig in master so that you can use kubectl 
# to interact with cluster API
mkdir -p $HOME/.kube
sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
sudo chown $(id -u):$(id -g) $HOME/.kube/config

# Execute the following command to install the calico network plugin on the cluster
kubectl apply -f https://docs.projectcalico.org/manifests/calico.yaml

#
kubeadm token create --print-join-command >> $HOME/k8s_worker_setup_script.sh

for i in $(cat $WORKERIPLIST)
do
ssh vagrant@$i 'sudo bash -s' < $HOME/k8s_worker_setup_script.sh	
done
