# Building Kubernetes

The DRAFT instructions provided below specify the steps to build Kubernetes version v1.17.4 on Linux on IBM Z for the following distributions:

* Ubuntu (16.04, 18.04)

_**General Notes:**_
* _When following the steps below please use a standard permission user unless otherwise specified._
* _A directory `/<source_root>/` will be referred to in these instructions, this is a temporary writable directory anywhere you'd like to place it._
* _Docker-ce versions between 17.06 and 18.02 have a known [issue](https://github.com/docker/for-linux/issues/238) on IBM Z. This has been fixed in version 18.03_

### Prerequisites:
* Docker (Refer instructions mentioned [here](https://docs.docker.com/install/linux/docker-ce/ubuntu/))

_**Note:**_ These build instructions were tested with docker version 18.06 at the time of creation of this document. 

## Step 1: Install dependancies

```bash
#Set <source_root> variable
export SOURCE_ROOT=/<source_root>/
sudo apt-get update
sudo apt-get install git make wget
```

## Step 2: Install kubeadm

Please follow official documentation [here](https://kubernetes.io/docs/setup/production-environment/tools/kubeadm/install-kubeadm/) to install kubeadm, kubelet and kubectl.

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
    docker build . -t k8s.gcr.io/kube-proxy:1.17.4
    ```

#### 3.2) Setup Kubernetes cluster

* Initializing your control-plane node
    ```bash
    sudo swapoff -a
    sudo kubeadm init --pod-network-cidr=10.244.0.0/16
    ```

*  Enable kubectl to work for non-root user
    ```bash
    mkdir -p $HOME/.kube
    sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
    sudo chown $(id -u):$(id -g) $HOME/.kube/config
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