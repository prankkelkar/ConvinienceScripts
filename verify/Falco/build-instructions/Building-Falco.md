# Building Falco

The instructions provided below specify the steps to build Falco version 0.18.0 on Linux on IBM Z for following distributions:

*    Ubuntu (16.04, 18.04, 19.10)
*    RHEL (7.5, 7.6, 7.7, 8.0)

_**General Notes:**_
* _When following the steps below please use a root user unless otherwise specified._
* _A directory `/<source_root>/` will be referred to in these instructions, this is a temporary writable directory anywhere you'd like to place it._


## Step 1: Install dependencies
  ```
  export SOURCE_ROOT=/<source_root>/
  ```

  * Ubuntu (16.04, 18.04, 19.10)
    ```sh
    sudo apt-get update
    sudo apt-get install -y autoconf automake build-essential cmake curl elfutils git libelf-dev libssl-dev libtool linux-headers-$(uname -r) lua5.1 lua5.1-dev patch pkg-config rpm sudo wget
    ```

  * RHEL (7.5, 7.6, 7.7, 8.0)
    ```sh
    sudo yum install -y autoconf automake c-ares curl elfutils-libelf elfutils-libelf-devel gcc gcc-c++ git glibc glibc-devel libcurl-devel libstdc++ libstdc++-devel libtool libyaml make patch pkgconfig readline-devel rpm-build sudo vim wget zlib-devel kernel-`uname -r` kernel-devel-`uname -r` kernel-headers-`uname -r`
    ```

  * Install cmake v3.7.2 (Only for RHEL)
    ```sh
    cd $SOURCE_ROOT
    wget https://cmake.org/files/v3.7/cmake-3.7.2.tar.gz
    tar xzf cmake-3.7.2.tar.gz
    cd cmake-3.7.2
    ./configure --prefix=/usr/
    ./bootstrap --system-curl --parallel=16
    make -j16
    sudo make install
    export PATH=/usr/local/bin:$PATH
    cmake --version
    ```
  * Install Lua v5.1 (Only for RHEL)
    ```sh
    cd $SOURCE_ROOT
    wget http://www.lua.org/ftp/lua-5.1.tar.gz
    tar zxf lua-5.1.tar.gz
    cd lua-5.1
    make linux
    make install
    cp /usr/local/bin/lua* /usr/bin/
    lua -v
    ```

## Step 2: Congifure Sysdig
  
  * Clone Sysdig source code
    ```sh
    cd $SOURCE_ROOT
    git clone https://github.com/draios/sysdig.git
    cd sysdig
    git checkout falco/0.18.0
    ```

  * Create `$SOURCE_ROOT/protobuf-3.5.0.patch` with the following content
    ```
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
    ```


  * Create file  `$SOURCE_ROOT/sysdig/scap_fds.c.patch` with the following content `userspace/libscap/scap_fds.c`
    ```diff
    diff --git a/userspace/libscap/scap_fds.c b/userspace/libscap/scap_fds.c
    index 56ced1a7..1f1847f6 100644
    --- a/userspace/libscap/scap_fds.c
    +++ b/userspace/libscap/scap_fds.c
    @@ -25,6 +25,7 @@ limitations under the License.
     #include "scap_savefile.h"
     #include <sys/stat.h>
     #include <sys/types.h>
    +#include <sys/sysmacros.h>
     #include <fcntl.h>
     #include "uthash.h"
     #ifdef _WIN32

    ```
  * Apply the patch
    ```bash
    patch -l $SOURCE_ROOT/sysdig/userspace/libscap/scap_fds.c scap_fds.c.patch
    ```

## Step 3: Download, configure and build Falco

#### 3.1)  Download Falco
```
cd $SOURCE_ROOT
git clone https://github.com/falcosecurity/falco.git
cd falco
git checkout 0.18.0
```

#### 3.2) Create file `$SOURCE_ROOT/falco/lauxlib.h.patch` with following contents:
```diff
diff --git a/src/lauxlib.h b/src/lauxlib.h
index a44f027..185a31d 100644
--- a/src/lauxlib.h
+++ b/src/lauxlib.h
@@ -7,7 +7,8 @@

 #ifndef lauxlib_h
 #define lauxlib_h
-
+#define luaL_reg luaL_Reg
+#define luaL_getn lua_objlen

 #include <stddef.h>
 #include <stdio.h>
```

#### 3.3) Apply the required patches
  * With LuaJIT:  
  
    * Create file `$SOURCE_ROOT/falco/falco.patch` with following contents:
    ```diff
    diff --git a/CMakeLists.txt b/CMakeLists.txt
    index c297215..28362d9 100644
    --- a/CMakeLists.txt
    +++ b/CMakeLists.txt
    @@ -359,8 +359,8 @@ else()
     	set(LUAJIT_INCLUDE "${LUAJIT_SRC}")
     	set(LUAJIT_LIB "${LUAJIT_SRC}/libluajit.a")
     	ExternalProject_Add(luajit
    -		URL "https://s3.amazonaws.com/download.draios.com/dependencies/LuaJIT-2.0.3.tar.gz"
    -		URL_MD5 "f14e9104be513913810cd59c8c658dc0"
    +		URL "https://github.com/linux-on-ibm-z/LuaJIT/archive/v2.1.zip"
    +		PATCH_COMMAND patch -l "${PROJECT_BINARY_DIR}/luajit-prefix/src/luajit/src/lauxlib.h" $ENV{SOURCE_ROOT}/falco/lauxlib.h.patch
     		CONFIGURE_COMMAND ""
     		BUILD_COMMAND ${CMD_MAKE}
     		BUILD_IN_SOURCE 1
    @@ -571,6 +571,7 @@ else()
     		URL "https://github.com/google/protobuf/releases/download/v3.5.0/protobuf-cpp-3.5.0.tar.gz"
     		URL_MD5 "e4ba8284a407712168593e79e6555eb2"
     		# TODO what if using system zlib?
    +		PATCH_COMMAND cp $ENV{SOURCE_ROOT}/protobuf-3.5.0.patch . && patch -p0 -i protobuf-3.5.0.patch
     		CONFIGURE_COMMAND /usr/bin/env CPPFLAGS=-I${ZLIB_INCLUDE} LDFLAGS=-L${ZLIB_SRC} ./configure --with-zlib --prefix=${PROTOBUF_SRC}/target
     		BUILD_COMMAND ${CMD_MAKE}
     		BUILD_IN_SOURCE 1
    @@ -614,7 +615,7 @@ else()
     		BUILD_BYPRODUCTS ${GRPC_LIB} ${GRPCPP_LIB}
     		# TODO s390x support
     		# TODO what if using system zlib
    -		PATCH_COMMAND rm -rf third_party/zlib && ln -s ${ZLIB_SRC} third_party/zlib && curl -L https://download.sysdig.com/dependencies/grpc-1.1.4-Makefile.patch | patch
    +		PATCH_COMMAND rm -rf third_party/zlib && ln -s ${ZLIB_SRC} third_party/zlib && curl -L https://download.sysdig.com/dependencies/grpc-1.8.1-Makefile.patch | patch
     		INSTALL_COMMAND "")
     endif()
     
    @@ -656,7 +657,7 @@ set(CPACK_PACKAGE_RELOCATABLE "OFF")
     set(CPACK_GENERATOR DEB RPM TGZ)
     
     set(CPACK_DEBIAN_PACKAGE_SECTION "utils")
    -set(CPACK_DEBIAN_PACKAGE_ARCHITECTURE "amd64")
    +set(CPACK_DEBIAN_PACKAGE_ARCHITECTURE "s390x")
     set(CPACK_DEBIAN_PACKAGE_HOMEPAGE "https://www.falco.org")
     set(CPACK_DEBIAN_PACKAGE_DEPENDS "dkms (>= 2.1.0.0)")
     set(CPACK_DEBIAN_PACKAGE_CONTROL_EXTRA "${CMAKE_BINARY_DIR}/scripts/debian/postinst;${CMAKE_BINARY_DIR}/scripts/debian/prerm;${PROJECT_SOURCE_DIR}/scripts/debian/postrm;${PROJECT_SOURCE_DIR}/cpack/debian/conffiles")
    ```   
    
    * Apply the patch
    ```bash
      git apply falco.patch
    ```

    * Apply below changes (Only for RHEL)
      * Create file `$SOURCE_ROOT/falco/CMakeLists.txt.patch` with following contents
      ```diff
      --- CMakeLists.txt.orig	2019-11-06 07:05:58.297572499 +0000
      +++ CMakeLists.txt	2019-11-06 07:08:16.052437258 +0000
      @@ -610,7 +610,7 @@
          URL_MD5 "2fc42c182a0ed1b48ad77397f76bb3bc"
          CONFIGURE_COMMAND ""
          # TODO what if using system openssl, protobuf or cares?
      -		BUILD_COMMAND sh -c "CFLAGS=-Wno-implicit-fallthrough CXXFLAGS=\"-Wno-ignored-qualifiers -Wno-stringop-truncation\" HAS_SYSTEM_ZLIB=false LDFLAGS=-static PATH=${PROTOC_DIR}:$ENV{PATH} PKG_CONFIG_PATH=${OPENSSL_BUNDLE_DIR}:${PROTOBUF_SRC}:${CARES_SRC} make grpc_cpp_plugin static_cxx static_c"
      +		BUILD_COMMAND sh -c "CFLAGS=-Wno-implicit-fallthrough CXXFLAGS=\"-Wno-ignored-qualifiers -Wno-stringop-truncation\" HAS_SYSTEM_ZLIB=false LDFLAGS=\"-L/usr/lib64,-static\" PATH=${PROTOC_DIR}:$ENV{PATH} PKG_CONFIG_PATH=${OPENSSL_BUNDLE_DIR}:${PROTOBUF_SRC}:${CARES_SRC} make grpc_cpp_plugin static_cxx static_c"
          BUILD_IN_SOURCE 1
          BUILD_BYPRODUCTS ${GRPC_LIB} ${GRPCPP_LIB}
          # TODO s390x support

      ```

      * Apply the patch    
      ```bash
      patch -l CMakeLists.txt CMakeLists.txt.patch
      ```

    * Apply below changes (Only for Ubuntu 19.10) 
      * Create file `$SOURCE_ROOT/falco/CMakeLists_txt_grpc.patch` with following contents
      ```diff
      --- CMakeLists.txtOrig	2019-11-25 21:35:55.529504057 -0800
      +++ CMakeLists.txt	2019-11-25 21:36:51.659514059 -0800
      @@ -615,7 +615,7 @@
          BUILD_BYPRODUCTS ${GRPC_LIB} ${GRPCPP_LIB}
          # TODO s390x support
          # TODO what if using system zlib
      -		PATCH_COMMAND rm -rf third_party/zlib && ln -s ${ZLIB_SRC} third_party/zlib && curl -L https://download.sysdig.com/dependencies/grpc-1.8.1-Makefile.patch | patch
      +		PATCH_COMMAND rm -rf third_party/zlib && ln -s ${ZLIB_SRC} third_party/zlib && curl -L https://download.sysdig.com/dependencies/grpc-1.8.1-Makefile.patch | patch && patch -l "${PROJECT_BINARY_DIR}/grpc-prefix/src/grpc/src/core/lib/support/log_linux.cc" $ENV{SOURCE_ROOT}/falco/grpc.patch
          INSTALL_COMMAND "")
       endif()


      ```
      

      * Create `$SOURCE_ROOT/falco/grpc.patch` with following contents  
      ```diff
      diff --git a/src/core/lib/support/log_linux.cc b/src/core/lib/support/log_linux.cc
      index e0e277fe87..f273dfab42 100644
      --- a/src/core/lib/support/log_linux.cc
      +++ b/src/core/lib/support/log_linux.cc
      @@ -39,7 +39,7 @@
       #include <time.h>
       #include <unistd.h>

      -static long gettid(void) { return syscall(__NR_gettid); }
      +static long sys_gettid(void) { return syscall(__NR_gettid); }

       void gpr_log(const char* file, int line, gpr_log_severity severity,
                    const char* format, ...) {
      @@ -65,7 +65,7 @@ extern "C" void gpr_default_log(gpr_log_func_args* args) {
         gpr_timespec now = gpr_now(GPR_CLOCK_REALTIME);
         struct tm tm;
         static __thread long tid = 0;
      -  if (tid == 0) tid = gettid();
      +  if (tid == 0) tid = sys_gettid();

         timer = (time_t)now.tv_sec;
         final_slash = strrchr(args->file, '/');

      ```

       * Apply the patch
        ```bash
            patch -l CMakeLists.txt CMakeLists_txt_grpc.patch
        ```

  * With Lua:  
  
    * Create file `$SOURCE_ROOT/falco/falco.patch` with following contents:
    ```diff
    diff --git a/CMakeLists.txt b/CMakeLists.txt
    index c297215..53779b2 100644
    --- a/CMakeLists.txt
    +++ b/CMakeLists.txt
    @@ -464,7 +464,7 @@ else()
     		URL_MD5 "dc3494689a0dce7cf44e7a99c72b1f30"
     		BUILD_COMMAND ${CMD_MAKE}
     		BUILD_IN_SOURCE 1
    -		CONFIGURE_COMMAND ./configure --enable-static LIBS=-L${LIBYAML_SRC}/.libs CFLAGS=-I${LIBYAML_INCLUDE} CPPFLAGS=-I${LIBYAML_INCLUDE} LUA_INCLUDE=-I${LUAJIT_INCLUDE} LUA=${LUAJIT_SRC}/luajit
    +		CONFIGURE_COMMAND ./configure --enable-static LIBS=-L${LIBYAML_SRC}/.libs CFLAGS=-I${LIBYAML_INCLUDE} CPPFLAGS=-I${LIBYAML_INCLUDE} LUA_INCLUDE=-I${LUAJIT_INCLUDE} LUA=/usr/bin/lua
     		INSTALL_COMMAND sh -c "cp -R ${PROJECT_BINARY_DIR}/lyaml-prefix/src/lyaml/lib/* ${PROJECT_SOURCE_DIR}/userspace/engine/lua")
     endif()
     
    @@ -571,6 +571,7 @@ else()
     		URL "https://github.com/google/protobuf/releases/download/v3.5.0/protobuf-cpp-3.5.0.tar.gz"
     		URL_MD5 "e4ba8284a407712168593e79e6555eb2"
     		# TODO what if using system zlib?
    +		PATCH_COMMAND cp $ENV{SOURCE_ROOT}/protobuf-3.5.0.patch . && patch -p0 -i protobuf-3.5.0.patch
     		CONFIGURE_COMMAND /usr/bin/env CPPFLAGS=-I${ZLIB_INCLUDE} LDFLAGS=-L${ZLIB_SRC} ./configure --with-zlib --prefix=${PROTOBUF_SRC}/target
     		BUILD_COMMAND ${CMD_MAKE}
     		BUILD_IN_SOURCE 1
    @@ -614,7 +615,7 @@ else()
     		BUILD_BYPRODUCTS ${GRPC_LIB} ${GRPCPP_LIB}
     		# TODO s390x support
     		# TODO what if using system zlib
    -		PATCH_COMMAND rm -rf third_party/zlib && ln -s ${ZLIB_SRC} third_party/zlib && curl -L https://download.sysdig.com/dependencies/grpc-1.1.4-Makefile.patch | patch
    +		PATCH_COMMAND rm -rf third_party/zlib && ln -s ${ZLIB_SRC} third_party/zlib && curl -L https://download.sysdig.com/dependencies/grpc-1.8.1-Makefile.patch | patch
     		INSTALL_COMMAND "")
     endif()
     
    @@ -656,7 +657,7 @@ set(CPACK_PACKAGE_RELOCATABLE "OFF")
     set(CPACK_GENERATOR DEB RPM TGZ)
     
     set(CPACK_DEBIAN_PACKAGE_SECTION "utils")
    -set(CPACK_DEBIAN_PACKAGE_ARCHITECTURE "amd64")
    +set(CPACK_DEBIAN_PACKAGE_ARCHITECTURE "s390x")
     set(CPACK_DEBIAN_PACKAGE_HOMEPAGE "https://www.falco.org")
     set(CPACK_DEBIAN_PACKAGE_DEPENDS "dkms (>= 2.1.0.0)")
     set(CPACK_DEBIAN_PACKAGE_CONTROL_EXTRA "${CMAKE_BINARY_DIR}/scripts/debian/postinst;${CMAKE_BINARY_DIR}/scripts/debian/prerm;${PROJECT_SOURCE_DIR}/scripts/debian/postrm;${PROJECT_SOURCE_DIR}/cpack/debian/conffiles")
    diff --git a/userspace/engine/lua/rule_loader.lua b/userspace/engine/lua/rule_loader.lua
    index d6d2427..e6924c0 100644
    --- a/userspace/engine/lua/rule_loader.lua
    +++ b/userspace/engine/lua/rule_loader.lua
    @@ -635,13 +635,14 @@ function load_rules(sinsp_lua_parser,
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
     
    +      if not v['skip-if-unknown-filter'] then
           if (filter_ast.type == "Rule") then
     	 state.n_rules = state.n_rules + 1
     
    @@ -722,7 +723,7 @@ function load_rules(sinsp_lua_parser,
     	 return false, build_error_with_context(v['context'], "Unexpected type in load_rule: "..filter_ast.type)
           end
     
    -      ::next_rule::
    +      end
        end
     
        if verbose then
    ```
    
    * Apply the patch
    ```bash
      git apply falco.patch
    ```

    * Apply below changes (Only for RHEL)
      * Create file `$SOURCE_ROOT/falco/CMakeLists.txt.patch` with following contents 
      ```diff
      --- CMakeLists.txt.orig	2019-11-06 07:05:58.297572499 +0000
      +++ CMakeLists.txt	2019-11-06 07:08:16.052437258 +0000
      @@ -610,7 +610,7 @@
          URL_MD5 "2fc42c182a0ed1b48ad77397f76bb3bc"
          CONFIGURE_COMMAND ""
          # TODO what if using system openssl, protobuf or cares?
      -		BUILD_COMMAND sh -c "CFLAGS=-Wno-implicit-fallthrough CXXFLAGS=\"-Wno-ignored-qualifiers -Wno-stringop-truncation\" HAS_SYSTEM_ZLIB=false LDFLAGS=-static PATH=${PROTOC_DIR}:$ENV{PATH} PKG_CONFIG_PATH=${OPENSSL_BUNDLE_DIR}:${PROTOBUF_SRC}:${CARES_SRC} make grpc_cpp_plugin static_cxx static_c"
      +		BUILD_COMMAND sh -c "CFLAGS=-Wno-implicit-fallthrough CXXFLAGS=\"-Wno-ignored-qualifiers -Wno-stringop-truncation\" HAS_SYSTEM_ZLIB=false LDFLAGS=\"-L/usr/lib64,-static\" PATH=${PROTOC_DIR}:$ENV{PATH} PKG_CONFIG_PATH=${OPENSSL_BUNDLE_DIR}:${PROTOBUF_SRC}:${CARES_SRC} make grpc_cpp_plugin static_cxx static_c"
          BUILD_IN_SOURCE 1
          BUILD_BYPRODUCTS ${GRPC_LIB} ${GRPCPP_LIB}
          # TODO s390x support

      ```

      * Apply the patch    
      ```bash
      patch -l CMakeLists.txt CMakeLists.txt.patch
      ```

    * Apply below changes (Only for Ubuntu 19.10)
      * Create file `$SOURCE_ROOT/falco/CMakeLists_txt_grpc.patch` with following contents 
      ```diff
      --- CMakeLists.txtOrig	2019-11-27 03:18:23.340754021 -0800
      +++ CMakeLists.txt	2019-11-27 03:18:47.370754021 -0800
      @@ -615,7 +615,7 @@
          BUILD_BYPRODUCTS ${GRPC_LIB} ${GRPCPP_LIB}
          # TODO s390x support
          # TODO what if using system zlib
      -		PATCH_COMMAND rm -rf third_party/zlib && ln -s ${ZLIB_SRC} third_party/zlib && curl -L https://download.sysdig.com/dependencies/grpc-1.8.1-Makefile.patch | patch 
      +		PATCH_COMMAND rm -rf third_party/zlib && ln -s ${ZLIB_SRC} third_party/zlib && curl -L https://download.sysdig.com/dependencies/grpc-1.8.1-Makefile.patch | patch && patch -l "${PROJECT_BINARY_DIR}/grpc-prefix/src/grpc/src/core/lib/support/log_linux.cc" $ENV{SOURCE_ROOT}/falco/grpc.patch
          INSTALL_COMMAND "")
       endif()

      ```
      

      * Create `$SOURCE_ROOT/falco/grpc.patch` with following contents
      ```diff
      diff --git a/src/core/lib/support/log_linux.cc b/src/core/lib/support/log_linux.cc
      index e0e277fe87..f273dfab42 100644
      --- a/src/core/lib/support/log_linux.cc
      +++ b/src/core/lib/support/log_linux.cc
      @@ -39,7 +39,7 @@
       #include <time.h>
       #include <unistd.h>

      -static long gettid(void) { return syscall(__NR_gettid); }
      +static long sys_gettid(void) { return syscall(__NR_gettid); }

       void gpr_log(const char* file, int line, gpr_log_severity severity,
                    const char* format, ...) {
      @@ -65,7 +65,7 @@ extern "C" void gpr_default_log(gpr_log_func_args* args) {
         gpr_timespec now = gpr_now(GPR_CLOCK_REALTIME);
         struct tm tm;
         static __thread long tid = 0;
      -  if (tid == 0) tid = gettid();
      +  if (tid == 0) tid = sys_gettid();

         timer = (time_t)now.tv_sec;
         final_slash = strrchr(args->file, '/');

      ```

       * Apply the patch
        ```bash
            patch -l CMakeLists.txt CMakeLists_txt_grpc.patch
        ```
        
#### 3.4) Build Falco
```sh
mkdir -p $SOURCE_ROOT/falco/build/release 
cd $SOURCE_ROOT/falco/build/release 
cmake -DFALCO_VERSION=0.18.0 -DCMAKE_VERBOSE_MAKEFILE=On ../../ # For Falco with LuaJIT
cmake -DUSE_BUNDLED_LUAJIT=false -DFALCO_VERSION=0.18.0 -DCMAKE_VERBOSE_MAKEFILE=On ../../ # For Falco with Lua
make
make package
sudo make install
```

#### 3.5) Insert kernel module
    
* Unload any existing module using
    ```sh
    sudo rmmod falco_probe
    ```

* Insert locally built version
    ```sh
    cd $SOURCE_ROOT/falco/build/release 
    sudo insmod driver/falco-probe.ko
    ```

## Step 4: Testing (optional)

```sh
cd $SOURCE_ROOT/falco/build/release 
make tests
```

## Step 5: Validate falco installation (optional)

* Start falco process
    
    ```sh
    sudo falco
    ```
    _**Note:** Run `sudo falco --help` to see available options to run falco. By default, falco logs events to standard error._

* Execute the event_generator program
    
    ```sh
    cd $SOURCE_ROOT/falco/docker/event-generator
    g++ --std=c++0x event_generator.cpp -o event_generator
    sudo ./event_generator -o -a write_binary_dir
    ```
    _**Note:** Use `./event_generator --help` to see all available options._

## Reference:
https://falco.org/docs/ - Official falco documentation

https://falco.org/docs/event-sources/sample-events/ - Further information on using event_generator
