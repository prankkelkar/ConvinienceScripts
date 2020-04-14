#!/bin/bash
# © Copyright IBM Corporation 2019, 2020
# LICENSE: Apache License, Version 2.0 (http://www.apache.org/licenses/LICENSE-2.0)
#
# Instructions:
# Download build script: wget https://raw.githubusercontent.com/linux-on-ibm-z/scripts/master/ApacheCassandra/3.11.5/build_cassandra.sh
# Execute build script: bash build_cassandra.sh    (provide -h for help)

set -e -o pipefail
set +x
PACKAGE_NAME="HBase"
PACKAGE_VERSION="2.2.3"
CURDIR="$(pwd)"
SOURCE_ROOT="$(pwd)"

sudo zypper install -y git wget tar make gcc java-1_8_0-openjdk java-1_8_0-openjdk-devel ant ant-junit ant-nodeps net-tools gcc-c++ unzip awk gzip curl

#Install Maven
cd $SOURCE_ROOT
wget https://archive.apache.org/dist/maven/maven-3/3.3.9/binaries/apache-maven-3.3.9-bin.tar.gz
tar zxf apache-maven-3.3.9-bin.tar.gz

#Set Env
export JAVA_HOME=/usr/lib64/jvm/java-1.8.0-openjdk-1.8.0
export PATH=$JAVA_HOME/bin:$PATH 
export MAVEN_OPTS="-Xms1024m -Xmx1024m -XX:MaxPermSize=1024m"
export PATH=$SOURCE_ROOT/apache-maven-3.3.9/bin:$PATH
java -version
mvn --version

cd $SOURCE_ROOT
git clone git://github.com/apache/hbase.git
cd hbase
git checkout rel/2.2.3

#Install Protobuf 2.5.0
cd $SOURCE_ROOT
wget https://github.com/google/protobuf/releases/download/v2.5.0/protobuf-2.5.0.tar.gz
tar zxvf protobuf-2.5.0.tar.gz
cd protobuf-2.5.0
wget https://raw.githubusercontent.com/google/protobuf/v2.6.0/src/google/protobuf/stubs/atomicops_internals_generic_gcc.h -P src/google/protobuf/stubs/ 
sed -i '185i #elif defined(GOOGLE_PROTOBUF_ARCH_S390)' src/google/protobuf/stubs/atomicops.h
sed -i '186i #include <google/protobuf/stubs/atomicops_internals_generic_gcc.h>' src/google/protobuf/stubs/atomicops.h

sed -i '60i #elif defined(__s390x__)' src/google/protobuf/stubs/platform_macros.h
sed -i '61i #define GOOGLE_PROTOBUF_ARCH_S390 1' src/google/protobuf/stubs/platform_macros.h
sed -i '62i #define GOOGLE_PROTOBUF_ARCH_64_BIT 1' src/google/protobuf/stubs/platform_macros.h
./configure
make
make check
sudo make install
export LD_LIBRARY_PATH=/usr/local/lib
protoc --version
mvn install:install-file -DgroupId=com.google.protobuf -DartifactId=protoc -Dversion=2.5.0 -Dclassifier=linux-s390_64 -Dpackaging=exe -Dfile=$SOURCE_ROOT/protobuf-2.5.0/src/.libs/protoc

#Install Protobuf 3.x
sudo zypper install -y autoconf automake bzip2 gawk gcc-c++ git gzip libtool make tar wget zlib-devel
cd $SOURCE_ROOT
git clone https://github.com/protocolbuffers/protobuf.git
cd protobuf
git checkout v3.5.1
git submodule update --init --recursive
cat <<EOF > "patch_proto.diff"
--git a/src/google/protobuf/stubs/atomicops_internals_generic_gcc.h b/src/google/protobuf/stubs/atomicops_internals_generic_gcc.h
index 0b0b06c..075c406 100644
--- a/src/google/protobuf/stubs/atomicops_internals_generic_gcc.h
+++ b/src/google/protobuf/stubs/atomicops_internals_generic_gcc.h
@@ -146,6 +146,14 @@ inline Atomic64 NoBarrier_Load(volatile const Atomic64* ptr) {
   return __atomic_load_n(ptr, __ATOMIC_RELAXED);
 }

+inline Atomic64 Release_CompareAndSwap(volatile Atomic64* ptr,
+                                       Atomic64 old_value,
+                                       Atomic64 new_value) {
+  __atomic_compare_exchange_n(ptr, &old_value, new_value, false,
+                              __ATOMIC_RELEASE, __ATOMIC_ACQUIRE);
+  return old_value;
+}
+
 #endif // defined(__LP64__)

 }  // namespace internal
EOF

git apply patch_proto.diff
./autogen.sh
./configure
make  
mvn install:install-file -DgroupId=com.google.protobuf -DartifactId=protoc -Dversion=3.5.1-1 -Dclassifier=linux-s390_64 -Dpackaging=exe -Dfile=$SOURCE_ROOT/protobuf/src/.libs/protoc
export LD_LIBRARY_PATH=$LD_LIBRARY_PATH:$SOURCE_ROOT/protobuf/src/.libs:$SOURCE_ROOT/protobuf-2.5.0/src/.libs
cd $SOURCE_ROOT/hbase
mvn package -DskipTests

set +e

cd $SOURCE_ROOT/hbase
sed -i "s/900/9000/" pom.xml
sed -i "s/MediumTests/IntegrationTests/g" ./hbase-procedure/src/test/java/org/apache/hadoop/hbase/procedure2/store/TestProcedureStoreTracker.java
sed -i "s/MediumTests/IntegrationTests/g" ./hbase-mapreduce/src/test/java/org/apache/hadoop/hbase/snapshot/TestExportSnapshotWithTemporaryDirectory.java
sed -i "s/SmallTests/IntegrationTests/g" ./hbase-server/src/test/java/org/apache/hadoop/hbase/regionserver/TestMemStoreLAB.java
sed -i "s/SmallTests/IntegrationTests/g" ./hbase-common/src/test/java/org/apache/hadoop/hbase/types/TestCopyOnWriteMaps.java
sed -i "s/MediumTests/IntegrationTests/g" ./hbase-mapreduce/src/test/java/org/apache/hadoop/hbase/snapshot/TestExportSnapshotNoCluster.java
mvn test -fn 2>&1 | tee -a testlog
		
set -e

echo "installation completed"
