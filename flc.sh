#!/bin/bash
export CURDIR=$PWD
export SOURCE_ROOT=$PWD
sudo apt-get update
sudo apt-get install -y curl sudo wget git 
#Dependancies
sudo apt-get install -y build-essential cmake autoconf wget automake patch elfutils libelf-dev pkg-config libtool linux-headers-$(uname -r)

sudo apt-get install -y libssl-dev rpm

#Insrall lua 5.1
sudo apt-get install -y lua5.1 lua5.1-dev

#get falco and sysdig
#git clone -b 0.17.0 https://github.com/falcosecurity/falco.git
git clone https://github.com/falcosecurity/falco.git
cd falco
git checkout 0.17.1

#apply patch 
cat >falco.patch <<-"EOF"
diff --git a/CMakeLists.txt b/CMakeLists.txt
index e15bf65..b885856 100644
--- a/CMakeLists.txt
+++ b/CMakeLists.txt
@@ -465,7 +465,7 @@ else()
 		URL_MD5 "dc3494689a0dce7cf44e7a99c72b1f30"
 		BUILD_COMMAND ${CMD_MAKE}
 		BUILD_IN_SOURCE 1
-		CONFIGURE_COMMAND ./configure --enable-static LIBS=-L${LIBYAML_SRC}/.libs CFLAGS=-I${LIBYAML_INCLUDE} CPPFLAGS=-I${LIBYAML_INCLUDE} LUA_INCLUDE=-I${LUAJIT_INCLUDE} LUA=${LUAJIT_SRC}/luajit
+		CONFIGURE_COMMAND ./configure --enable-static LIBS=-L${LIBYAML_SRC}/.libs CFLAGS=-I${LIBYAML_INCLUDE} CPPFLAGS=-I${LIBYAML_INCLUDE} LUA_INCLUDE=-I${LUAJIT_INCLUDE} LUA=/usr/bin/lua
 		INSTALL_COMMAND sh -c "cp -R ${PROJECT_BINARY_DIR}/lyaml-prefix/src/lyaml/lib/* ${PROJECT_SOURCE_DIR}/userspace/engine/lua")
 endif()
 
@@ -572,6 +572,7 @@ else()
 		URL "https://github.com/google/protobuf/releases/download/v3.5.0/protobuf-cpp-3.5.0.tar.gz"
 		URL_MD5 "e4ba8284a407712168593e79e6555eb2"
 		# TODO what if using system zlib?
+		PATCH_COMMAND cp $ENV{SOURCE_ROOT}/protobuf-3.5.0.patch . && patch -p0 -i protobuf-3.5.0.patch
 		CONFIGURE_COMMAND /usr/bin/env CPPFLAGS=-I${ZLIB_INCLUDE} LDFLAGS=-L${ZLIB_SRC} ./configure --with-zlib --prefix=${PROTOBUF_SRC}/target
 		BUILD_COMMAND ${CMD_MAKE}
 		BUILD_IN_SOURCE 1
@@ -615,7 +616,7 @@ else()
 		BUILD_BYPRODUCTS ${GRPC_LIB} ${GRPCPP_LIB}
 		# TODO s390x support
 		# TODO what if using system zlib
-		PATCH_COMMAND rm -rf third_party/zlib && ln -s ${ZLIB_SRC} third_party/zlib && curl -L https://download.sysdig.com/dependencies/grpc-1.1.4-Makefile.patch | patch
+		PATCH_COMMAND rm -rf third_party/zlib && ln -s ${ZLIB_SRC} third_party/zlib && curl -L https://download.sysdig.com/dependencies/grpc-1.8.1-Makefile.patch | patch
 		INSTALL_COMMAND "")
 endif()
 
@@ -657,7 +658,7 @@ set(CPACK_PACKAGE_RELOCATABLE "OFF")
 set(CPACK_GENERATOR DEB RPM TGZ)
 
 set(CPACK_DEBIAN_PACKAGE_SECTION "utils")
-set(CPACK_DEBIAN_PACKAGE_ARCHITECTURE "amd64")
+set(CPACK_DEBIAN_PACKAGE_ARCHITECTURE "s390x")
 set(CPACK_DEBIAN_PACKAGE_HOMEPAGE "https://www.falco.org")
 set(CPACK_DEBIAN_PACKAGE_DEPENDS "dkms (>= 2.1.0.0)")
 set(CPACK_DEBIAN_PACKAGE_CONTROL_EXTRA "${CMAKE_BINARY_DIR}/scripts/debian/postinst;${CMAKE_BINARY_DIR}/scripts/debian/prerm;${PROJECT_SOURCE_DIR}/scripts/debian/postrm;${PROJECT_SOURCE_DIR}/cpack/debian/conffiles")
diff --git a/userspace/engine/lua/rule_loader.lua b/userspace/engine/lua/rule_loader.lua
index 42ab9f4..8c55954 100644
--- a/userspace/engine/lua/rule_loader.lua
+++ b/userspace/engine/lua/rule_loader.lua
@@ -17,9 +17,7 @@
 
 --[[
    Compile and install falco rules.
-
    This module exports functions that are called from falco c++-side to compile and install a set of rules.
-
 --]]
 
 local sinsp_rule_utils = require "sinsp_rule_utils"
@@ -598,13 +596,13 @@ function load_rules(sinsp_lua_parser,
 	       if verbose then
 		  print("Skipping rule \""..v['rule'].."\" that contains unknown filter "..filter)
 	       end
-	       goto next_rule
+	       break
 	    else
 	       error("Rule \""..v['rule'].."\" contains unknown filter "..filter)
 	    end
 	 end
       end
-
+      if not v['skip-if-unknown-filter'] then
       if (filter_ast.type == "Rule") then
 	 state.n_rules = state.n_rules + 1
 
@@ -685,7 +683,7 @@ function load_rules(sinsp_lua_parser,
 	 return false, build_error_with_context(v['context'], "Unexpected type in load_rule: "..filter_ast.type)
       end
 
-      ::next_rule::
+      end
    end
 
    if verbose then
@@ -797,6 +795,3 @@ function print_stats()
       print ("   "..name..": "..count)
    end
 end
-
-
-

EOF

git apply falco.patch

cd $CURDIR
git clone https://github.com/draios/sysdig.git
cd sysdig
git checkout 0.26.4
cat >scap_fds.c.patch <<-"EOF"
--- userspace/libscap/scap_fds.c.orig   2019-05-24 18:51:55.000000000 -0500
+++ userspace/libscap/scap_fds.c        2019-06-07 12:13:23.395852735 -0500
@@ -25,6 +25,7 @@
 #include "scap_savefile.h"
 #include <sys/stat.h>
 #include <sys/types.h>
+#include <sys/sysmacros.h>
 #include <fcntl.h>
 #include "uthash.h"
 #ifdef _WIN32
EOF

patch userspace/libscap/scap_fds.c scap_fds.c.patch


cd $SOURCE_ROOT
cat >protobuf-3.5.0.patch <<-"EOF"
--- src/google/protobuf/stubs/atomicops_internals_generic_gcc.h     2019-06-06 18:20:59.506309314 +0000
+++ src/google/protobuf/stubs/atomicops_internals_generic_gcc.h     2019-06-05 19:19:01.626309314 +0000
@@ -146,6 +146,14 @@
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

mkdir -p $CURDIR/falco/build/release 
cd $CURDIR/falco/build/release 
cmake -DUSE_BUNDLED_LUAJIT=false -DFALCO_VERSION=0.17.1 -DCMAKE_VERBOSE_MAKEFILE=On ../../
make
make package

echo "**********************************************************************************************************\n"
echo "Now Run: export  SOURCE_ROOT="$CURDIR
echo "make"
echo "**********************************************************************************************************\n"
