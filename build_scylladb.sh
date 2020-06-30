#!/bin/bash
# © Copyright IBM Corporation 2020.
# LICENSE: Apache License, Version 2.0 (http://www.apache.org/licenses/LICENSE-2.0)
#
# Usage:
# build_scylladb.sh -h


#==============================================================================
set -e -o pipefail

PACKAGE_NAME="ScyllaDB"
PACKAGE_VERSION="4.0.3"
SOURCE_ROOT="$(pwd)"

FORCE="false"
LOG_FILE="$SOURCE_ROOT/logs/${PACKAGE_NAME}-${PACKAGE_VERSION}-$(date +"%F-%T").log"

PATCH_URL="https://raw.githubusercontent.com/linux-on-ibm-z/scripts/master/${PACKAGE_NAME}/3.3.1/patch"

NINJA_VERSION=1.8.2

PREFIX=/usr/local
declare -a CENV

TARGET=native
TOOLSET=gcc
CMAKE=/usr/local/bin/cmake

#==============================================================================
mkdir -p "$SOURCE_ROOT/logs"

error() { echo "Error: ${*}"; exit 1; }
errlog() { echo "Error: ${*}" |& tee -a "$LOG_FILE"; exit 1; }

msg() { echo "${*}"; }
log() { echo "${*}" >> "$LOG_FILE"; }
msglog() { echo "${*}" |& tee -a "$LOG_FILE"; }


trap cleanup 0 1 2 ERR

#==============================================================================
#Set the Distro ID
if [ -f "/etc/os-release" ]; then
  source "/etc/os-release"
else
  error "Unknown distribution"
fi
DISTRO="$ID-$VERSION_ID"

#==============================================================================
checkPrequisites()
{
  if [ -z "$TARGET" ]; then
    error "No target architecture specified with -z"
  else
    log "Building ScyllaDB on target $TARGET"
  fi

  if command -v "sudo" >/dev/null; then
    msglog "Sudo : Yes"
  else
    msglog "Sudo : No "
    error "sudo is required. Install using apt, yum or zypper based on your distro."
  fi

  if [[ "$FORCE" == "true" ]]; then
    msglog "Force - install without confirmation message"
  else
    # Ask user for prerequisite installation
    msg "As part of the installation , dependencies would be installed/upgraded."
    while true; do
      read -r -p "Do you want to continue (y/n) ? : " yn
      case $yn in
      [Yy]*)
        log "User responded with Yes."
        break
        ;;
      [Nn]*) exit ;;
      *) msg "Please provide confirmation to proceed." ;;
      esac
    done
  fi
}


#==============================================================================
cleanup()
{
  rm -f $SOURCE_ROOT/cryptopp/cryptopp565.zip
  rm -f $SOURCE_ROOT/v${NINJA_VERSION}.zip
  echo "Cleaned up the artifacts."
}


#==============================================================================
# Build and install pkgs common to all distros.
#
configureAndInstall()
{
  local ver=1
  declare -a options
  msg "Configuration and Installation started"

#----------------------------------------------------------
  ver=3.5.2
  msg "Installing antlr $ver"
  cd "$SOURCE_ROOT"

  URL=https://github.com/antlr/antlr3/archive/${ver}.tar.gz
  curl -sSL $URL | tar xzf - || error "antlr $ver"
  cd antlr3-${ver}
  sudo cp runtime/Cpp/include/antlr3* ${PREFIX}/include/

  cd antlr-complete
  MAVEN_OPTS="-Xmx4G" mvn
  echo 'java -cp '"$(pwd)"'/target/antlr-complete-3.5.2.jar org.antlr.Tool $@' | sudo tee ${PREFIX}/bin/antlr3
  sudo chmod +x ${PREFIX}/bin/antlr3

#----------------------------------------------------------
  ver=1.68.0
  local uver=${ver//\./_}
  msg "Building Boost $ver"

  cd "$SOURCE_ROOT"
  URL=https://dl.bintray.com/boostorg/release/${ver}/source/boost_${uver}.tar.gz
  curl -sSL $URL | tar xzf - || error "Boost $ver"
  cd boost_${uver}

  sed -i 's/array\.hpp/array_wrapper.hpp/g' boost/numeric/ublas/matrix.hpp
  sed -i 's/array\.hpp/array_wrapper.hpp/g' boost/numeric/ublas/storage.hpp

  ./bootstrap.sh

  options=( toolset=$TOOLSET variant=release link=shared
            runtime-link=shared threading=multi --without-python
          )

  ./b2 ${options[@]} stage
  sudo ${CENV[@]} ./b2 ${options[@]} install

#----------------------------------------------------------
  ver=0.9.3
  msg "Building Thrift $ver"

  cd "$SOURCE_ROOT"
  URL=http://archive.apache.org/dist/thrift/${ver}/thrift-${ver}.tar.gz
  curl -sSL $URL | tar xzf - || error "Thrift $ver"
  cd thrift-${ver}
  ./configure --without-java --without-lua --without-go --disable-tests --disable-tutorial
  make -j 8
  sudo make install

#----------------------------------------------------------
# https://fmt.dev/latest/usage.html#building-the-library
# commit d6cea50d01d7779ecb5ae4da0d785d9bba47a2f7
  msg "Building fmt"

  cd "$SOURCE_ROOT"
  git clone https://github.com/fmtlib/fmt.git
  cd fmt
  git checkout d6cea50d01d7779e
  mkdir build
  cd build
  $CMAKE -DFMT_TEST=OFF -DCMAKE_CXX_STANDARD=17 ..
  make
  sudo make install

#----------------------------------------------------------
  ver=0.6.2
  msg "Building yaml-cpp $ver"

  cd "$SOURCE_ROOT"
  URL=https://github.com/jbeder/yaml-cpp/archive/yaml-cpp-${ver}.tar.gz
  curl -sSL $URL | tar xzf - || error "yaml-cpp $ver"
  cd yaml-cpp-yaml-cpp-${ver}
  mkdir build
  cd build
  $CMAKE ..
  make
  sudo make install


#----------------------------------------------------------
  ver=${PACKAGE_VERSION}
  msg "Cloning scylla $ver"

  cd "$SOURCE_ROOT"
  git clone https://github.com/scylladb/scylla.git
  cd scylla
  git checkout scylla-${ver}
  git submodule update --init --recursive

  curl -sSL ${PATCH_URL}/seastar.diff | patch -d seastar -p1 || error "seastar.diff"
  curl -sSL https://raw.githubusercontent.com/prankkelkar/ConvinienceScripts/master/scylla.diff | patch -p1 || error "scylla.diff"
  sed -i 's/#warning.*/asm(".cfi_undefined r14");/g' $SOURCE_ROOT/scylla/seastar/src/core/thread.cc

  msg "Building scylla"

  export PKG_CONFIG_PATH=$PREFIX/lib/pkgconfig${PKG_CONFIG_PATH:+:${PKG_CONFIG_PATH}}
  msg "PKG_CONFIG_PATH=$PKG_CONFIG_PATH"

  local cflags="-I${PREFIX}/include -I${PREFIX}/include/boost"
  cflags+=" -L${PREFIX}/lib -L${PREFIX}/lib64 "

  ./configure.py --mode release --target ${TARGET} --debuginfo 1 \
    --static-thrift --cflags "${cflags}" --ldflags="-Wl,--build-id=sha1" \
    --compiler "${CXX}" --c-compiler "${CC}"

  ninja -j 8

  if [ "$?" -ne "0" ]; then
    error "Build  for ScyllaDB failed. Please check the error logs."
  else
    msg "Build  for ScyllaDB completed successfully. "
  fi

  runTest
}


#==============================================================================
runTest()
{
  set +e
  if [[ "$TESTS" == "true" ]]; then
    log "TEST Flag is set, continue with running test "
    cd "$SOURCE_ROOT/scylla"
      ./test.py --mode release
      msg "Test execution completed. "
  fi
  set -e
}


#==============================================================================
logDetails()
{
  log "**************************** SYSTEM DETAILS ***************************"
  cat "/etc/os-release" >>"$LOG_FILE"
  cat /proc/version >>"$LOG_FILE"
  log "***********************************************************************"

  msg "Detected $PRETTY_NAME"
  msglog "Request details: PACKAGE NAME=$PACKAGE_NAME, VERSION=$PACKAGE_VERSION"
}


#==============================================================================
printHelp()
{
  cat <<eof

  Usage:
  build_scylladb.sh [-z (z13|z14|native)] [-y] [-d] [-t]
  where:
   -z select target architecture - default: native
   -y install-without-confirmation
   -d debug
   -t test
eof
}

###############################################################################
while getopts "h?dyt?z:" opt
do
  case "$opt" in
    h | \?) printHelp; exit 0; ;;
    d) set -x; ;;
    y) FORCE="true"; ;;
    z) TARGET=$OPTARG; ;;
    t) TESTS="true"; ;;
  esac
done


#==============================================================================
gettingStarted()
{
  cat <<-eof
        ***********************************************************************
        Usage:
        ***********************************************************************
          ScyllaDB installed successfully.
          Set the environment variables:

          export PATH=${PREFIX}/bin\${PATH:+:\${PATH}}
          LD_LIBRARY_PATH=${PREFIX}/lib64\${LD_LIBRARY_PATH:+:\${LD_LIBRARY_PATH}}
          LD_LIBRARY_PATH+=:${PREFIX}/lib
          LD_LIBRARY_PATH+=:/usr/lib64
          export LD_LIBRARY_PATH

          Run the following commands to use ScyllaDB:
          $SOURCE_ROOT/scylla/build/release/scylla --help

          More information can be found here:
          https://github.com/scylladb/scylla/blob/master/HACKING.md
eof
}


#==============================================================================
buildBinutils()
{
  local ver=2.34
  msg "Building binutils $ver"
  cd "$SOURCE_ROOT"

  URL=http://ftpmirror.gnu.org/binutils/binutils-${ver}.tar.gz
  curl -sSL $URL | tar xzf - || error "binutils $ver"
  cd binutils-${ver}
  mkdir objdir
  cd objdir

  CC=/usr/bin/gcc ../configure --prefix=${PREFIX} --build=s390x-linux-gnu
  make -j 8
  sudo make install

}
#==============================================================================
buildGcc()
{
  local ver=8.3.0
  msg "Building GCC $ver"
  cd "$SOURCE_ROOT"

  URL=https://ftpmirror.gnu.org/gcc/gcc-${ver}/gcc-${ver}.tar.gz
  curl -sSL $URL | tar xzf - || error "GCC $ver"

  cd gcc-${ver}
  ./contrib/download_prerequisites
  mkdir objdir
  cd objdir

  ../configure --enable-languages=c,c++ --prefix=${PREFIX} \
    --enable-shared --enable-threads=posix \
    --disable-multilib --disable-libmpx \
    --with-system-zlib --with-long-double-128 --with-arch=zEC12 \
    --disable-libphobos --disable-werror \
    --build=s390x-linux-gnu --host=s390x-linux-gnu --target=s390x-linux-gnu

  make -j 8 bootstrap
  sudo make install
}


#==============================================================================
# requires libffi-dev
buildPython()
{
  local ver=3.7.4
  msg "Building Python $ver"

  cd "$SOURCE_ROOT"
  URL="https://www.python.org/ftp/python/${ver}/Python-${ver}.tgz"
  curl -sSL $URL | tar xzf - || error "Python $ver"
  cd Python-${ver}
  ./configure
  make
  sudo make install
  pip3 install --user --upgrade pip
}


#==============================================================================
buildCmake()
{
  local ver=3.12.4
  msg "Building cmake $ver"

  cd "$SOURCE_ROOT"
  URL=https://github.com/Kitware/CMake/releases/download/v${ver}/cmake-${ver}.tar.gz
  curl -sSL $URL | tar xzf - || error "cmake $ver"
  cd cmake-${ver}
  ./bootstrap
  make
  sudo make install
}


#==============================================================================
buildAnt()
{
  local ver=1.10.8
  msglog "Installing ant $ver"

  cd "$SOURCE_ROOT"
  URL=https://downloads.apache.org/ant/binaries/apache-ant-${ver}-bin.tar.gz
  curl -sSL $URL | tar xzf - || error "ant $ver"
  export ANT_HOME="$SOURCE_ROOT/apache-ant-${ver}"
  export PATH=$PATH:"$ANT_HOME/bin"
  ant -version |& tee -a "$LOG_FILE"
}


#==============================================================================
# https://github.com/c-ares/c-ares/blob/cares-1_14_0/INSTALL.md
buildCares()
{
  local ver=1.14.0
  msg "Building c-ares $ver"

  cd ${SOURCE_ROOT}
  URL=https://c-ares.haxx.se/download/c-ares-${ver}.tar.gz
  curl -sSL $URL | tar xzf - || error "c-ares $ver"
  cd c-ares-${ver}
  ./configure
  make
  sudo make install
}


#==============================================================================
buildRJson()
{
  local ver=v1.1.0
  msg "Building RapidJson $ver"

  cd "$SOURCE_ROOT"
  git clone https://github.com/Tencent/rapidjson.git
  cd rapidjson
  git checkout ${ver}
  sudo cp -r ./include/rapidjson ${PREFIX}/include
}


#==============================================================================
# Build pkgs required only on RHEL.
buildRHEL()
{
  local ver=1

#----------------------------------------------------------
  buildPython
  python3 --version

#----------------------------------------------------------
  msg "Installing pyparsing, colorama, pyyaml"
  pip3 install --user pyparsing colorama pyyaml

#----------------------------------------------------------
  msg "Building ninja-${NINJA_VERSION}"

  cd "$SOURCE_ROOT"
  curl -sSLO https://github.com/ninja-build/ninja/archive/v${NINJA_VERSION}.zip
  unzip v${NINJA_VERSION}.zip
  cd ninja-${NINJA_VERSION}
  ./configure.py --bootstrap
  sudo cp ninja ${PREFIX}/bin

#----------------------------------------------------------
  buildCmake

#----------------------------------------------------------
  ver=2.3.0
  msg "Building libidn2 $ver"

  cd ${SOURCE_ROOT}
  URL=https://ftp.gnu.org/gnu/libidn/libidn2-${ver}.tar.gz
  curl -sSL $URL | tar xzf - || error "libidn2 $ver"
  cd libidn2-${ver}
  ./configure --disable-doc --disable-gtk-doc
  make
  sudo make install

#----------------------------------------------------------
# commit 26fba7199c365b55e72e054bb2adba097ce04924
  msg "Building numactl master"

  cd ${SOURCE_ROOT}
  git clone https://github.com/numactl/numactl.git
  cd numactl
  git checkout 26fba7199c365b55
  ./autogen.sh
  ./configure
  make
  sudo make install

#----------------------------------------------------------
  buildCares

#----------------------------------------------------------
  ver=6.10
  msg "Building ragel $ver"

  cd "$SOURCE_ROOT"
  URL=http://www.colm.net/files/ragel/ragel-${ver}.tar.gz
  curl -sSL $URL | tar xzf - || error "ragel $ver"
  cd ragel-${ver}
  ./configure
  make -j 8
  sudo make install

#----------------------------------------------------------
  msg "Building cryptopp565"

  cd "$SOURCE_ROOT"
  mkdir cryptopp
  cd cryptopp
  curl -sSLO https://www.cryptopp.com/cryptopp565.zip
  unzip cryptopp565.zip
  CXXFLAGS="-std=c++11 -g -O2" make
  sudo make install

#----------------------------------------------------------
  ver=1.7.7
  msg "Building jsoncpp $ver"

  cd "$SOURCE_ROOT"
  URL=https://github.com/open-source-parsers/jsoncpp/archive/${ver}.tar.gz
  curl -sSL $URL | tar xzf - || error "jsoncpp $ver"
  cd jsoncpp-${ver}
  mkdir -p build/release
  cd build/release
  $CMAKE ../..
  make -j 8
  sudo make install

#----------------------------------------------------------
  ver=5.3.5
  msg "Building LUA $ver"

  cd "$SOURCE_ROOT"
  URL=http://www.lua.org/ftp/lua-${ver}.tar.gz
  curl -sSL $URL | tar xzf - || error "LUA $ver"
  cd lua-${ver}
  make linux
  sudo make install

#----------------------------------------------------------
  buildRJson

#----------------------------------------------------------
  ver=v3.10.1
  msg "Building Protobuf $ver"

  cd "$SOURCE_ROOT"
  git clone https://github.com/protocolbuffers/protobuf.git
  cd protobuf
  git checkout ${ver}
  ./autogen.sh
  ./configure
  make
  sudo make install
}


#==============================================================================
logDetails
checkPrequisites

msglog "Installing $PACKAGE_NAME $PACKAGE_VERSION for $DISTRO"
msglog "Installing the dependencies for ScyllaDB from repository"

case "$DISTRO" in

#----------------------------------------------------------
"ubuntu-16.04" )
  sudo apt-get update >/dev/null

  sudo apt-get install -y openjdk-8-jdk libaio-dev \
    systemtap-sdt-dev lksctp-tools xfsprogs \
    libyaml-dev openssl libevent-dev \
    libmpfr-dev libmpcdec-dev liblz4-dev \
    libssl-dev libsystemd-dev libhwloc-dev \
    libsctp-dev libsnappy-dev libpciaccess-dev libxml2-dev xfslibs-dev \
    libgnutls28-dev libiconv-hook-dev mpi-default-dev libbz2-dev \
    libxslt-dev libjsoncpp-dev ragel \
    libprotobuf-dev protobuf-compiler libcrypto++-dev \
    libtool perl ant libffi-dev \
    automake make git gcc g++ maven ninja-build \
    unzip bzip2 wget curl xz-utils texinfo \
    diffutils liblua5.3-dev libnuma-dev libunistring-dev \
    pigz ragel rapidjson-dev stow patch |& tee -a "$LOG_FILE"

#~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
  buildBinutils |& tee -a "$LOG_FILE"
  buildGcc |& tee -a "$LOG_FILE"

# C/C++ environment settings
  export PATH=${PREFIX}/bin${PATH:+:${PATH}}

  LD_LIBRARY_PATH=${PREFIX}/lib64${LD_LIBRARY_PATH:+:${LD_LIBRARY_PATH}}
  LD_LIBRARY_PATH+=:${PREFIX}/lib
  LD_LIBRARY_PATH+=:/usr/lib64
  export LD_LIBRARY_PATH

  LD_RUN_PATH=${PREFIX}/lib64${LD_RUN_PATH:+:${LD_RUN_PATH}}
  LD_RUN_PATH+=:${PREFIX}/lib
  LD_RUN_PATH+=:/usr/lib64
  export LD_RUN_PATH

  export CC=${PREFIX}/bin/gcc
  export CXX=${PREFIX}/bin/g++

  CENV=(PATH=$PATH LD_LIBRARY_PATH=$LD_LIBRARY_PATH
        LD_RUN_PATH=$LD_RUN_PATH
        CC=$CC CXX=$CXX
        )
  msglog "${CENV[@]}"

  gcc -v |& tee -a "$LOG_FILE"
  TOOLSET=gcc

  sudo rm /usr/lib/s390x-linux-gnu/libstdc++.so.6
  sudo ln -s /usr/local/lib64/libstdc++.so.6.0.25 /usr/lib/s390x-linux-gnu/libstdc++.so.6

#~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
  buildPython |& tee -a "$LOG_FILE"
  python3 --version |& tee -a "$LOG_FILE"

#~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
  msglog "Installing pyparsing, colorama, pyyaml"
  pip3 install --user pyparsing colorama pyyaml

#~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
  buildCmake |& tee -a "$LOG_FILE"
  buildCares |& tee -a "$LOG_FILE"
  buildRJson |& tee -a "$LOG_FILE"
  configureAndInstall |& tee -a "$LOG_FILE"
;;


#----------------------------------------------------------
"ubuntu-18.04" )
  sudo apt-get update >/dev/null

  sudo apt-get install -y openjdk-8-jdk libaio-dev \
    systemtap-sdt-dev lksctp-tools xfsprogs \
    libyaml-dev openssl libevent-dev \
    libmpfr-dev libmpcdec-dev liblz4-dev \
    libssl1.0-dev libsystemd-dev libhwloc-dev \
    libsctp-dev libsnappy-dev libpciaccess-dev libxml2-dev xfslibs-dev \
    libgnutls28-dev libiconv-hook-dev mpi-default-dev libbz2-dev \
    libxslt-dev libjsoncpp-dev libc-ares-dev ragel \
    libprotobuf-dev protobuf-compiler libcrypto++-dev \
    libtool perl ant libffi-dev \
    automake make git maven ninja-build \
    unzip bzip2 wget curl xz-utils texinfo \
    diffutils gcc-8 g++-8 liblua5.3-dev libnuma-dev libunistring-dev \
    pigz ragel rapidjson-dev stow patch |& tee -a "$LOG_FILE"

#~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
# C/C++ environment settings
  export LC_ALL=C
  export PATH=${PREFIX}/bin${PATH:+:${PATH}}

  LD_LIBRARY_PATH=${PREFIX}/lib64${LD_LIBRARY_PATH:+:${LD_LIBRARY_PATH}}
  LD_LIBRARY_PATH+=:${PREFIX}/lib
  LD_LIBRARY_PATH+=:/usr/lib64
  export LD_LIBRARY_PATH

  LD_RUN_PATH=${PREFIX}/lib64${LD_RUN_PATH:+:${LD_RUN_PATH}}
  LD_RUN_PATH+=:${PREFIX}/lib
  LD_RUN_PATH+=:/usr/lib64
  export LD_RUN_PATH

  export CC=/usr/bin/gcc-8
  export CXX=/usr/bin/g++-8

  CENV=(LC_ALL=$LC_ALL PATH=$PATH LD_LIBRARY_PATH=$LD_LIBRARY_PATH
        LD_RUN_PATH=$LD_RUN_PATH
        CC=$CC CXX=$CXX
        )

  msglog "${CENV[@]}"

  gcc -v |& tee -a "$LOG_FILE"
  TOOLSET=gcc-8

#~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
  buildPython |& tee -a "$LOG_FILE"
  python3 --version |& tee -a "$LOG_FILE"

#~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
  msglog "Installing pyparsing, colorama, pyyaml"
  pip3 install --user pyparsing colorama pyyaml

#~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
  buildCmake |& tee -a "$LOG_FILE"
  configureAndInstall |& tee -a "$LOG_FILE"
;;


#----------------------------------------------------------
"rhel-7."*)

#~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
if [[ "$DISTRO" == "rhel-7.8" ]]; then
  set +e
  sudo yum list installed glibc-2.17-307.el7.1.s390 |& tee -a "$LOG_FILE"
  if [[ $? ]]; then
    sudo yum downgrade -y glibc glibc-common |& tee -a "$LOG_FILE"
    sudo yum downgrade -y krb5-libs |& tee -a "$LOG_FILE"
    sudo yum downgrade -y libss e2fsprogs-libs e2fsprogs libcom_err |& tee -a "$LOG_FILE"
    sudo yum downgrade -y libselinux-utils libselinux-python libselinux |& tee -a "$LOG_FILE"
    fi
  set -e
fi

#~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
  sudo yum install -y java-1.8.0-openjdk-devel gnutls-devel libaio-devel \
  systemtap-sdt-devel lksctp-tools-devel xfsprogs-devel snappy-devel \
  libyaml-devel openssl-devel libevent-devel \
  gmp-devel mpfr-devel libmpcdec lz4-devel \
  libatomic libatomic_ops-devel perl-devel \
  automake make git gcc gcc-c++ maven \
  unzip bzip2 wget curl xz-devel texinfo \
  libffi-devel hwloc-devel libpciaccess-devel libxml2-devel \
  libtool diffutils libtool-ltdl-devel trousers-devel \
  libunistring-devel libicu-devel readline-devel \
  lua-devel patch |& tee -a "$LOG_FILE"

#~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
  msglog "Installing stow"
  curl -sSL http://cpanmin.us | sudo perl - --self-upgrade |& tee -a "$LOG_FILE"
  sudo /usr/local/bin/cpanm Stow |& tee -a "$LOG_FILE"

#~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
  buildBinutils |& tee -a "$LOG_FILE"
  buildGcc |& tee -a "$LOG_FILE"

# C/C++ environment settings
  export PATH=${PREFIX}/bin${PATH:+:${PATH}}

  LD_LIBRARY_PATH=${PREFIX}/lib64${LD_LIBRARY_PATH:+:${LD_LIBRARY_PATH}}
  LD_LIBRARY_PATH+=:${PREFIX}/lib
  LD_LIBRARY_PATH+=:/usr/lib64
  export LD_LIBRARY_PATH

  LD_RUN_PATH=${PREFIX}/lib64${LD_RUN_PATH:+:${LD_RUN_PATH}}
  LD_RUN_PATH+=:${PREFIX}/lib
  LD_RUN_PATH+=:/usr/lib64
  export LD_RUN_PATH

  export CC=${PREFIX}/bin/gcc
  export CXX=${PREFIX}/bin/g++

  CENV=(PATH=$PATH LD_LIBRARY_PATH=$LD_LIBRARY_PATH
        LD_RUN_PATH=$LD_RUN_PATH
        CC=$CC CXX=$CXX
        )
  msglog "${CENV[@]}"

  gcc -v |& tee -a "$LOG_FILE"
  TOOLSET=gcc

#~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
  buildRHEL |& tee -a "$LOG_FILE"
  buildAnt
  configureAndInstall |& tee -a "$LOG_FILE"
;;

#----------------------------------------------------------
*)
  errlog "$DISTRO not supported"
;;

esac

gettingStarted |& tee -a "$LOG_FILE"
