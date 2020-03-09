#!/bin/bash
set -e -o pipefail

CURDIR="$(pwd)"
KUBERNETES_VERSION="$(curl -s https://storage.googleapis.com/kubernetes-release/release/stable.txt)"

# Print the usage message
function printHelp() {
	echo
	echo "Usage: "
	echo "Please make sure u have make, curl and git "
	echo "  kubefix.sh [-v kubernetes version]  "
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

git clone https://github.com/kubernetes/kubernetes.git
cd kubernetes/build/debian-iptables
make build ARCH=s390x


cd $CURDIR
docker run --rm -v $CURDIR:/tmp k8s.gcr.io/kube-proxy:$KUBERNETES_VERSION cp /usr/local/bin/kube-proxy /tmp


cat <<EOF > "Dockerfile"
FROM staging-k8s.gcr.io/debian-iptables-s390x:v12.0.1
COPY kube-proxy /usr/local/bin/kube-proxy
EOF

docker build . -t k8s.gcr.io/kube-proxy:$KUBERNETES_VERSION

