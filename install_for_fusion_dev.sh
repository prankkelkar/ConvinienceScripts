#/bin/bash!

WORK_DIR=/root/work
mdkir -p $WORK_DIR

#install basic deps
apt-get update
apt-get install vim git wget curl make tar zip unzip gzip

##Install go
wget https://go.dev/dl/go1.16.12.linux-amd64.tar.gz
export PATH=$PATH:/usr/local/go/bin


#set GOPATH
export GOPATH=$WORK_DIR/go

##install docker
curl -fsSL https://get.docker.com -o get-docker.sh
chmod +x get-docker.sh
bash get-docker.sh


# install kubectl
curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
curl -LO "https://dl.k8s.io/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl.sha256"
echo "$(<kubectl.sha256) kubectl" | sha256sum --check
chmod +x kubectl
cp kubectl /usr/local/bin/


#get oc
wget --no-check-certificate https://downloads-openshift-console.apps.isf-service.cp.fyre.ibm.com/amd64/linux/oc.tar 
tar xvf oc.tar
cp oc /usr/local/bin/


#install krew plugin from https://krew.sigs.k8s.io/docs/user-guide/setup/install/
( set -x; cd "$(mktemp -d)" &&   OS="$(uname | tr '[:upper:]' '[:lower:]')" &&   ARCH="$(uname -m | sed -e 's/x86_64/amd64/' -e 's/\(arm\)\(64\)\?.*/\1\2/' -e 's/aarch64$/arm64/')" &&   curl -fsSLO "https://github.com/kubernetes-sigs/krew/releases/latest/download/krew.tar.gz" &&   tar zxvf krew.tar.gz &&   KREW=./krew-"${OS}_${ARCH}" &&   "$KREW" install krew; )

export PATH="${PATH}:${HOME}/.krew/bin"


# command to install opm
curl -fsSLO "https://mirror.openshift.com/pub/openshift-v4/x86_64/clients/ocp/latest/opm-linux.tar.gz" &&   tar zxvf opm-linux.tar.gz && mv ./opm /usr/local/bin/


# commands installing operator sdk v1.9.0
wget https://github.com/operator-framework/operator-sdk/releases/download/v1.9.0/operator-sdk_linux_amd64
chmod +x /usr/local/bin/operator-sdk
cp operator-sdk /usr/local/bin/


#oc bash completion (optional)  https://docs.openshift.com/container-platform/4.6/cli_reference/openshift_cli/configuring-cli.html
cd /etc/bash_completion.d/
oc completion bash > oc_bash_completion



# docker software install command (install version 20.10.7)
# https://docs.docker.com/engine/install/centos/
#sudo yum remove docker \
                  docker-client \
                  docker-client-latest \
                  docker-common \
                  docker-latest \
                  docker-latest-logrotate \
                  docker-logrotate \
                  docker-engine
#sudo yum install -y yum-utils
#sudo yum-config-manager \
    --add-repo \
    https://download.docker.com/linux/centos/docker-ce.repo
#sudo yum install docker-ce docker-ce-cli containerd.io
#yum list docker-ce --showduplicates | sort -r
#VERSION_STRING=
#sudo yum install docker-ce-<VERSION_STRING> docker-ce-cli-<VERSION_STRING> containerd.io

#docker pull registry.access.redhat.com/ubi8/ubi-minimal:8.4-200

# make install command
yum install make

# curl install command
yum install curl

# install kubectl
curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
curl -LO "https://dl.k8s.io/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl.sha256"
echo "$(<kubectl.sha256) kubectl" | sha256sum --check
chmod +x kubectl
cp kubectl /usr/local/bin/

# install git
yum install git

# installing oc cli
subscription-manager list --available --matches '*OpenShift*'
echo "Please provide pool id from above run"
read poolid
subscription-manager attach --pool=$poolid
# please change this based on rhel version
subscription-manager repos --enable="rhocp-4.4-for-rhel-8-x86_64-rpms"
#subscription-manager repos --enable="rhel-7-server-ose-4.4-rpms"
yum install openshift-clients


# install krew plugin to kubectl
( set -x; cd "$(mktemp -d)" &&   OS="$(uname | tr '[:upper:]' '[:lower:]')" &&   ARCH="$(uname -m | sed -e 's/x86_64/amd64/' -e 's/\(arm\)\(64\)\?.*/\1\2/' -e 's/aarch64$/arm64/')" &&   curl -fsSLO "https://github.com/kubernetes-sigs/krew/releases/latest/download/krew.tar.gz" &&   tar zxvf krew.tar.gz &&   KREW=./krew-"${OS}_${ARCH}" &&   "$KREW" install krew; )

export PATH="${PATH}:${HOME}/.krew/bin"

# install operator plugin
kubectl krew install operator


#yum install glibc

# commands installing operator sdk
RELEASE_VERSION=v1.9.0
curl -OJL https://github.com/operator-framework/operator-sdk/releases/download/${RELEASE_VERSION}/operator-sdk-${RELEASE_VERSION}-x86_64-linux-gnu
curl -OJL https://github.com/operator-framework/operator-sdk/releases/download/${RELEASE_VERSION}/operator-sdk-${RELEASE_VERSION}-x86_64-linux-gnu.asc
chmod +x operator-sdk-${RELEASE_VERSION}-x86_64-linux-gnu
sudo cp operator-sdk-${RELEASE_VERSION}-x86_64-linux-gnu /usr/local/bin/operator-sdk
rm operator-sdk-${RELEASE_VERSION}-x86_64-linux-gnu
operator-sdk version

# command to install opm
curl -fsSLO "https://mirror.openshift.com/pub/openshift-v4/x86_64/clients/ocp/latest/opm-linux.tar.gz" &&   tar zxvf opm-linux.tar.gz && mv ./opm /usr/local/bin/
