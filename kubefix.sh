#!/bin/bash
set -e -o pipefail

CURDIR="$(pwd)"
KUBERNETES_VERSION="$(curl -s https://storage.googleapis.com/kubernetes-release/release/stable.txt)"

# Print the usage message
function printHelp() {
	echo
	echo "This script is intented to resolve kube-proxy issue in kubernetes v1.17.x for s390x architecture"
	echo "Issue link: https://github.com/kubernetes/kubernetes/issues/87197"
	echo "Run this script before initializing kubernetes cluster.(Before running 'kubeadm init' command) "
	echo "Usage: "
	echo "Please make sure you have make, curl and git Installed "
	echo "  kubefix.sh [-v kubernetes version]  "
	echo "  For eg: bash kubefix.sh -v v1.17.3  "
	echo
}


while getopts "h?dy?v:" opt; do
	case "$opt" in
	h | \?)
		printHelp
		exit 0
		;;
	d)
		set -x
		;;
	v)
		export KUBERNETES_VERSION=$OPTARG
		;;
	esac
done

#Fist we build debian-base image on s390x since there are issues in cross-compiled image.
git clone https://github.com/kubernetes/kubernetes.git
cd kubernetes/build/debian-iptables
make build ARCH=s390x

#Copy the kube proxy binary from the image
cd $CURDIR
docker run --rm -v $CURDIR:/tmp k8s.gcr.io/kube-proxy:$KUBERNETES_VERSION cp /usr/local/bin/kube-proxy /tmp


cat <<EOF > "Dockerfile"
FROM staging-k8s.gcr.io/debian-iptables-s390x:v12.0.1
COPY kube-proxy /usr/local/bin/kube-proxy
EOF

docker build . -t k8s.gcr.io/kube-proxy:$KUBERNETES_VERSION

echo "Kube-proxy image is built successfully. You can proceed with 'kubeadm init' "
