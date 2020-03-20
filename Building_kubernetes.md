# Building Kubernetes

The DRAFT instructions provided below specify the steps to build Kubernetes version v1.17.4 on Linux on IBM Z for the following distributions:

* Ubuntu (16.04, 18.04)
* RHEL (7.5, 7.6, 7.7)
* SLES 12 SP4

_**General Notes:**_
* _When following the steps below please use a standard permission user for ubuntu and super user for rhel and sles._
* _A directory `/<source_root>/` will be referred to in these instructions, this is a temporary writable directory anywhere you'd like to place it._
* _Docker-ce versions between 17.06 and 18.02 have a known [issue](https://github.com/docker/for-linux/issues/238) on IBM Z. This has been fixed in version 18.03_
* _SLES uses btrfs by default. The docker “overlay” driver is not supported with this file-system, so it is sensible to use etx4 in /var/lib/docker.The Kubernetes kubeadm installer will stop if it finds btrfs._

### Prerequisites:
* Docker (Refer instructions mentioned [here](https://docs.docker.com/install/linux/docker-ce/ubuntu/))

_**Note:**_ These build instructions were tested with docker version 18.06 on ubuntu and rhel and docker version 19.03 on sles at the time of creation of this document. 

## Step 1: Install dependancies
```bash
#Set SOURCE_ROOT variable
export SOURCE_ROOT=/<source_root>/
```

* Ubuntu (16.04, 18.04)	
    ```bash
    sudo apt-get update
    sudo apt-get install git make wget
    ```

* RHEL (7.5, 7.6, 7.7)
    ```bash
    yum install git make wget
    ```

* SLES 12 SP4
    ```bash
    zypper install git make wget
    ```

## Step 2: Install kubeadm, kubelet and kubectl

* Ubuntu (16.04, 18.04)	

    Please follow official documentation [here](https://kubernetes.io/docs/setup/production-environment/tools/kubeadm/install-kubeadm/) to install kubeadm, kubelet and kubectl.

* RHEL (7.5, 7.6, 7.7)

    * Configure iptables
        ```bash
        cat <<EOF > /etc/sysctl.d/k8s.conf
        net.bridge.bridge-nf-call-ip6tables = 1
        net.bridge.bridge-nf-call-iptables = 1
        EOF

        sysctl --system
        ```

    * Add repository and install kubeadm, kubelet and kubectl.
        ```bash
        cat <<EOF > /etc/yum.repos.d/kubernetes.repo
        [kubernetes]
        name=Kubernetes
        baseurl=https://packages.cloud.google.com/yum/repos/kubernetes-el7-s390x
        enabled=1
        gpgcheck=1
        repo_gpgcheck=1
        gpgkey=https://packages.cloud.google.com/yum/doc/yum-key.gpg https://packages.cloud.google.com/yum/doc/rpm-package-key.gpg
        EOF

        # Set SELinux in permissive mode (effectively disabling it)
        setenforce 0
        sed -i 's/^SELINUX=enforcing$/SELINUX=permissive/' /etc/selinux/config

        yum install -y kubelet kubeadm kubectl --disableexcludes=kubernetes

        systemctl enable --now kubelet
        ```

* SLES 12 SP4

    * Configure iptables
        ```bash
        cat <<EOF > /etc/sysctl.conf
        net.ipv4.ip_forward=1
        net.ipv4.conf.all.forwarding=1
        net.bridge.bridge-nf-call-iptables=1
        EOF

        sysctl -p
        ```
        
    * Add repository and install kubeadm, kubelet and kubectl.
        ```bash
        zypper addrepo --type yum --gpgcheck-strict --refresh https://packages.cloud.google.com/yum/repos/kubernetes-el7-s390x google-k8s
        rpm --import https://packages.cloud.google.com/yum/doc/rpm-package-key.gpg
        rpm --import https://packages.cloud.google.com/yum/doc/yum-key.gpg
        rpm -q gpg-pubkey --qf '%{name}-%{version}-%{release} --> %{summary}\n'
        
        zypper refresh google-k8s
        zypper install kubelet-1.17.4-0.s390x kubernetes-cni-0.7.5-0.s390x kubeadm-1.17.4-0.s390x cri-tools-1.13.0-0 kubectl-1.17.4-0.s390x
        systemctl enable kubelet.service
        ```
        _**Note:**_ If you encounter `Problem: nothing provides conntrack needed by "package-name"` while installing kubelet for sles, choose `Solution x: break "package-name" by ignoring some of its dependencies`

## Step 3: Create a single control-plane cluster with kubeadm

_**Note:**_ Kube-proxy image is broken for kubernetes v1.17.x for s390x. Addtional steps given below will be needed to fix the kube proxy image. Issue link is [here](https://github.com/kubernetes/kubernetes/issues/87197).

#### 3.1) Fix kube proxy image

* Fetch images needed to setup basic kubernetes cluster
    ```bash
    kubeadm config images pull
    ```
* Build debian-iptables image
    ```bash
    cd $SOURCE_ROOT
    git clone https://github.com/kubernetes/kubernetes.git
    cd kubernetes
    git checkout v1.17.4
    cd build/debian-iptables
    make build ARCH=s390x
    ```
* Fetch kube-proxy binary
    ```bash
    cd $SOURCE_ROOT
    docker run --rm -v $SOURCE_ROOT:/tmp k8s.gcr.io/kube-proxy:v1.17.4 cp /usr/local/bin/kube-proxy /tmp
    ```
* Create Kube-proxy dockerfile
    ```bash
    cat <<EOF > "Dockerfile"
    FROM staging-k8s.gcr.io/debian-iptables-s390x:v12.0.1
    COPY kube-proxy /usr/local/bin/kube-proxy
    EOF
    ```
* Build Kube-proxy image
    ```bash
    docker build . -t k8s.gcr.io/kube-proxy:v1.17.4
    ```

#### 3.2) Setup Kubernetes cluster

* Initializing your control-plane node
    ```bash
    sudo swapoff -a
    sudo kubeadm init --pod-network-cidr=10.244.0.0/16
    ```

*  To start using your cluster, you need to run the following as a regular user
    ```bash
    mkdir -p $HOME/.kube
    sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
    sudo chown $(id -u):$(id -g) $HOME/.kube/config
    ```
* Alternatively, if you are the root user, you can run:
    ```bash
    export KUBECONFIG=/etc/kubernetes/admin.conf
    ```

* Install a Pod network add-on - Flannel 

    ```bash
    kubectl apply -f https://raw.githubusercontent.com/coreos/flannel/2140ac876ef134e0ed5af15c65e414cf26827915/Documentation/kube-flannel.yml
    ```

    _**Note:**_ By default, your cluster will not schedule Pods on the control-plane node for security reasons. If you want to be able to schedule Pods on the control-plane node, for example for a single-machine Kubernetes cluster for development, run:
    ```bash
    kubectl taint nodes --all node-role.kubernetes.io/master-
    ```

## Step 4: Verify Installation

```bash
kubectl get pods --all-namespaces
```

Output should look like this
```
NAMESPACE     NAME                                         READY   STATUS    RESTARTS   AGE
kube-system   coredns-6955765f44-lcfvh                     1/1     Running   0          49m
kube-system   coredns-6955765f44-x95p6                     1/1     Running   0          49m
kube-system   etcd-pras1.fyre.ibm.com                      1/1     Running   0          49m
kube-system   kube-apiserver-pras1.fyre.ibm.com            1/1     Running   0          49m
kube-system   kube-controller-manager-pras1.fyre.ibm.com   1/1     Running   0          49m
kube-system   kube-flannel-ds-s390x-v2q8f                  1/1     Running   0          47m
kube-system   kube-proxy-76ttg                             1/1     Running   0          49m
kube-system   kube-scheduler-pras1.fyre.ibm.com            1/1     Running   0          49m
```
_**Note:**_ It might take some time for pods to come up. 


## Reference:
https://kubernetes.io/docs/setup/production-environment/tools/kubeadm/create-cluster-kubeadm/#join-nodes - Adding new nodes to the cluster

https://kubernetes.io/docs/setup/production-environment/tools/kubeadm/install-kubeadm/ - Official documentation
