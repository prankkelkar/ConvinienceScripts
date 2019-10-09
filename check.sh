#!/bin/bash


#
#  Add the steps below in your jenkins file
#
#
#copy all the content of the block comment and add it to your jenkins file in install.groovy step
#Do remember to install wget.
: '
  #(Replace with your package name)
	packageName="python3"
	sles15=""
  #(varaible name should not contain periods. please name variables with this convention:- sles12_3 , rhel7_5 , ubuntu16_04)
	sles12_3="3.6.5" 
	wget https://raw.githubusercontent.com/prankkelkar/myScript/master/check.sh
	. ./check.sh
	if [ $result  == "true" ]; then
  		echo "Going ahead"
	else 
	   echo "failure observed!!!!!! Go fix the receipe"
	   exit 1;
	fi

'

#
# Actual script starts here
#

# Need handling for RHEL 6.10 as it doesn't have os-release file
if [ -f "/etc/os-release" ]; then
	. "/etc/os-release"
else
  export ID="rhel"
  export VERSION_ID="6.x"

fi

DISTRO="$ID-$VERSION_ID"
case "$DISTRO" in
"ubuntu-16.04" | "ubuntu-18.04") 
    sudo apt-get update
	available_version=$(sudo apt-cache policy $packageName | grep Candidate | head -1 | cut -d ' ' -f 4)
  ;;

"rhel-7.3" | "rhel-7.4" | "rhel-7.5" | "rhel-7.6" | "rhel-6.x")
    available_version=$(sudo yum info $packageName | grep Version | head -1 | cut -d ':' -f 2| cut -d ' ' -f 2)
  ;;

"sles-12.3" | "sles-15")
    sudo zypper update -y
    available_version=$(sudo zypper info $packageName | grep Version | head -1 | cut -d ':' -f 2| cut -d ' ' -f 2)
  ;;

*)

esac

DNAME="$ID$VERSION_ID"
DNAME=${DNAME/./_}
result="";

if [[ -z "$available_version" ]]; then
	if [[ ${!DNAME} != "" ]]; then
		echo "Incorrect version supplied. No version available for this package"
		result=false
	else
    		echo "Package does not exist in the repo. going ahead"
    		result="true"
	fi
else
	if [[ $available_version == *"${!DNAME}"* ]]; then
	    echo "Version ${!DNAME} is already available in repo given receipe is intact"
	    result="true"
	else	
            echo "version has been updated to $available_version in the repo. BROKEN receipe"
	    result="false"     
	fi


	if [[ -z "${!DNAME}" && "$available_version" != "" ]]; then
	    echo "version has been updated in the repo."
	    result="false"
	fi
	
fi
