FROM lambci/lambda:build-python3.7
MAINTAINER Ingo Müller <ingo.mueller@inf.ethz.ch>

# Packages
RUN touch /var/lib/rpm/* && \
    yum install -y \
        # General
        gcc72 \
        gcc72-c++ \
        wget \
        xz \
        zlib-devel \
        # AWS SDK dependencies
        libcurl-devel \
        openssl-devel \
        libuuid-devel \
        pulseaudio-libs-devel \
        # JITQ dependencies
        graphviz-devel \
        && \
    yum remove -y \
        cmake \
        llvm \
        && \
    yum -y clean all

# Clang+LLVM
RUN mkdir /opt/clang+llvm-11.0.0/ && \
    cd /opt/clang+llvm-11.0.0/ && \
    wget --progress=dot:giga https://github.com/llvm/llvm-project/releases/download/llvmorg-11.0.0/clang+llvm-11.0.0-x86_64-linux-gnu-ubuntu-16.04.tar.xz -O - \
         | tar -x -I xz --strip-components=1 && \
    for file in bin/*; \
    do \
        ln -s $PWD/$file /usr/bin/$(basename $file)-11.0; \
    done && \
    ln -s libomp.so /opt/clang+llvm-11.0.0/lib/libomp.so.5 && \
    update-alternatives --install /usr/bin/clang++ clang++ /usr/bin/clang++-11.0 100 && \
    update-alternatives --install /usr/bin/clang clang /usr/bin/clang-11.0 100

ENV CMAKE_PREFIX_PATH $CMAKE_PREFIX_PATH:/opt/clang+llvm-11.0.0

# CMake
RUN mkdir /opt/cmake-3.18.4/ && \
    cd /opt/cmake-3.18.4/ && \
    wget --progress=dot:giga https://cmake.org/files/v3.18/cmake-3.18.4-Linux-x86_64.tar.gz -O - \
        | tar -xz --strip-components=1 && \
    for file in bin/*; \
    do \
        ln -s $PWD/$file /usr/bin/$(basename $file); \
    done

# Boost
RUN cd /tmp/ && \
    wget --progress=dot:giga https://dl.bintray.com/boostorg/release/1.74.0/source/boost_1_74_0.tar.gz -O - \
        | tar -xz && \
    cd /tmp/boost_1_74_0 && \
    ./bootstrap.sh --prefix=/opt/boost-1.74.0 --with-toolset=clang && \
    ./b2 -j$(nproc) \
        toolset=clang cxxflags="-std=c++17 -D_GLIBCXX_USE_CXX11_ABI" \
        numa=on define=BOOST_FIBERS_SPINLOCK_TTAS_ADAPTIVE_FUTEX  \
        # Needed by arrow
        --with-regex \
        # Needed by JITQ
        --with-context \
        --with-fiber \
        --with-filesystem \
        --with-program_options \
        --with-system \
        --with-stacktrace \
        install && \
    cd / && \
    rm -rf /tmp/boost_1_74_0

ENV CMAKE_PREFIX_PATH $CMAKE_PREFIX_PATH:/opt/boost-1.74.0

# AWS SDK
RUN mkdir -p /tmp/aws-sdk-cpp && \
    cd /tmp/aws-sdk-cpp && \
    wget --progress=dot:giga https://github.com/aws/aws-sdk-cpp/archive/1.7.138.tar.gz -O - \
        | tar -xz --strip-components=1 && \
    mkdir -p /tmp/aws-sdk-cpp/build && \
    cd /tmp/aws-sdk-cpp/build && \
    CXX=clang++ CC=clang CXXFLAGS=-D_GLIBCXX_USE_CXX11_ABI \
        cmake \
            -DBUILD_ONLY="s3" \
            -DCMAKE_BUILD_TYPE=Release \
            -DCPP_STANDARD=17 \
            -DENABLE_TESTING=OFF \
            -DCUSTOM_MEMORY_MANAGEMENT=OFF \
            -DCMAKE_INSTALL_PREFIX=/opt/aws-sdk-cpp-1.7/ \
            -DAWS_DEPS_INSTALL_DIR:STRING=/opt/aws-sdk-cpp-1.7/ \
            .. && \
    make -j$(nproc) install && \
    rm -rf /tmp/aws-sdk-cpp

ENV CMAKE_PREFIX_PATH $CMAKE_PREFIX_PATH:/opt/aws-sdk-cpp-1.7

# Build arrow and pyarrow
RUN mkdir -p /tmp/arrow && \
    cd /tmp/arrow && \
    wget --progress=dot:giga https://github.com/apache/arrow/archive/apache-arrow-0.14.1.tar.gz -O - \
        | tar -xz --strip-components=1 && \
    { \
        echo 'diff --git a/cpp/CMakeLists.txt b/cpp/CMakeLists.txt'; \
        echo 'index d4b90c7bc..7075310a6 100644'; \
        echo '--- a/cpp/CMakeLists.txt'; \
        echo '+++ b/cpp/CMakeLists.txt'; \
        echo '@@ -648,8 +648,8 @@ if(ARROW_STATIC_LINK_LIBS)'; \
        echo '   add_dependencies(arrow_dependencies ${ARROW_STATIC_LINK_LIBS})'; \
        echo ' endif()'; \
        echo ''; \
        echo '-set(ARROW_SHARED_PRIVATE_LINK_LIBS ${ARROW_STATIC_LINK_LIBS} ${BOOST_SYSTEM_LIBRARY}'; \
        echo '-                                   ${BOOST_FILESYSTEM_LIBRARY} ${BOOST_REGEX_LIBRARY})'; \
        echo '+set(ARROW_SHARED_PRIVATE_LINK_LIBS ${ARROW_STATIC_LINK_LIBS} ${BOOST_FILESYSTEM_LIBRARY}'; \
        echo '+                                   ${BOOST_SYSTEM_LIBRARY} ${BOOST_REGEX_LIBRARY})'; \
        echo ''; \
        echo ' list(APPEND ARROW_STATIC_LINK_LIBS ${BOOST_SYSTEM_LIBRARY} ${BOOST_FILESYSTEM_LIBRARY}'; \
        echo '             ${BOOST_REGEX_LIBRARY})'; \
        echo 'diff --git a/cpp/thirdparty/versions.txt b/cpp/thirdparty/versions.txt'; \
        echo 'index d960cb0d0..397a4bd98 100644'; \
        echo '--- a/cpp/thirdparty/versions.txt'; \
        echo '+++ b/cpp/thirdparty/versions.txt'; \
        echo '@@ -28,7 +28,7 @@ BROTLI_VERSION=v1.0.7'; \
        echo ' BZIP2_VERSION=1.0.6'; \
        echo ' CARES_VERSION=1.15.0'; \
        echo ' DOUBLE_CONVERSION_VERSION=v3.1.4'; \
        echo '-FLATBUFFERS_VERSION=v1.10.0'; \
        echo '+FLATBUFFERS_VERSION=v1.12.0'; \
        echo ' GBENCHMARK_VERSION=v1.4.1'; \
        echo ' GFLAGS_VERSION=v2.2.0'; \
        echo ' GLOG_VERSION=v0.3.5'; \
    } | patch -p1 && \
    pip3 install -r /tmp/arrow/python/requirements-build.txt && \
    mkdir -p /tmp/arrow/cpp/build && \
    cd /tmp/arrow/cpp/build && \
    CXXFLAGS="-Wl,-rpath=/opt/boost-1.74.0/lib/ -D_GLIBCXX_USE_CXX11_ABI" \
        CXX=clang++ CC=clang \
            cmake \
                -DCMAKE_BUILD_TYPE=Release \
                -DCMAKE_CXX_STANDARD=17 \
                -DCMAKE_INSTALL_PREFIX=/tmp/arrow/dist \
                -DCMAKE_INSTALL_LIBDIR=lib \
                -DARROW_WITH_RAPIDJSON=ON \
                -DARROW_PARQUET=ON \
                -DARROW_PYTHON=ON \
                -DARROW_FLIGHT=OFF \
                -DARROW_GANDIVA=OFF \
                -DARROW_BUILD_UTILITIES=OFF \
                -DARROW_CUDA=OFF \
                -DARROW_ORC=OFF \
                -DARROW_JNI=OFF \
                -DARROW_TENSORFLOW=OFF \
                -DARROW_HDFS=OFF \
                -DARROW_BUILD_TESTS=OFF \
                -DARROW_RPATH_ORIGIN=ON \
                .. && \
    make -j$(nproc) install && \
    cd /tmp/arrow/python && \
    CXXFLAGS="-Wl,-rpath=/opt/boost-1.74.0/lib/ -D_GLIBCXX_USE_CXX11_ABI" \
        CXX=clang++ CC=clang \
        PYARROW_WITH_PARQUET=1 ARROW_HOME=/tmp/arrow/dist \
            python3 setup.py build_ext --bundle-arrow-cpp bdist_wheel && \
    mkdir -p /opt/arrow-0.14/share && \
    cp /tmp/arrow/python/dist/*.whl /opt/arrow-*/share &&\
    cp -r /tmp/arrow/dist/* /opt/arrow-*/ && \
    cd / && rm -rf /tmp/arrow

ENV CMAKE_PREFIX_PATH $CMAKE_PREFIX_PATH:/opt/arrow-0.14
