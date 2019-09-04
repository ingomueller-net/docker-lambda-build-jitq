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
        && \
    yum -y clean all

# Clang+LLVM
RUN mkdir /opt/clang+llvm-7.0.1/ && \
    cd /opt/clang+llvm-7.0.1/ && \
    wget --progress=dot:giga http://releases.llvm.org/7.0.1/clang+llvm-7.0.1-x86_64-linux-gnu-ubuntu-16.04.tar.xz -O - \
         | tar -x -I xz --strip-components=1 && \
    for file in bin/*; \
    do \
        ln -s $PWD/$file /usr/bin/$(basename $file)-7.0; \
    done && \
    mv /opt/clang+llvm-7.0.1/lib/libomp.so{,.5} && \
    ln -s libomp.so.5 /opt/clang+llvm-7.0.1/lib/libomp.so && \
    mv /usr/bin/clang{,-3.6} && mv /usr/bin/clang++{,-3.6} && \
    update-alternatives --install /usr/bin/clang++ clang++ /usr/bin/clang++-7.0 100 && \
    update-alternatives --install /usr/bin/clang clang /usr/bin/clang-7.0 100

ENV CMAKE_PREFIX_PATH $CMAKE_PREFIX_PATH:/opt/clang+llvm-7.0.1

# CMake
RUN mkdir /opt/cmake-3.14.5/ && \
    cd /opt/cmake-3.14.5/ && \
    wget -nv https://cmake.org/files/v3.14/cmake-3.14.5-Linux-x86_64.tar.gz -O - \
        | tar -xz --strip-components=1 && \
    for file in bin/*; \
    do \
        ln -s $PWD/$file /usr/bin/$(basename $file); \
    done


# Boost
RUN cd /tmp/ && \
    wget --progress=dot:giga https://dl.bintray.com/boostorg/release/1.70.0/source/boost_1_70_0.tar.gz -O - \
        | tar -xz && \
    cd /tmp/boost_1_70_0 && \
    ./bootstrap.sh --prefix=/opt/boost-1.70.0 --with-toolset=clang && \
    ./b2 -j$(nproc) \
        toolset=clang cxxflags="-std=c++17" \
        --with-filesystem \
        --with-program_options \
        --with-system \
        install && \
    cd / && \
    rm -rf /tmp/boost_1_70_0

ENV CMAKE_PREFIX_PATH $CMAKE_PREFIX_PATH:/opt/boost-1.70.0

# AWS SDK
RUN mkdir -p /tmp/aws-sdk-cpp && \
    cd /tmp/aws-sdk-cpp && \
    wget --progress=dot:giga https://github.com/aws/aws-sdk-cpp/archive/1.7.138.tar.gz -O - \
        | tar -xz --strip-components=1 && \
    mkdir -p /tmp/aws-sdk-cpp/build && \
    cd /tmp/aws-sdk-cpp/build && \
    CXX=clang++-7.0 CC=clang-7.0 \
        cmake \
            -DBUILD_ONLY="s3" \
            -DCMAKE_BUILD_TYPE=Debug \
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
    wget --progress=dot:giga https://github.com/apache/arrow/archive/apache-arrow-0.14.0.tar.gz -O - \
        | tar -xz --strip-components=1 && \
    pip3 install -r /tmp/arrow/python/requirements-build.txt && \
    mkdir -p /tmp/arrow/cpp/build && \
    cd /tmp/arrow/cpp/build && \
    CXX=clang++-7.0 CC=clang-7.0 \
        cmake \
            -DCMAKE_BUILD_TYPE=Debug \
            -DCMAKE_CXX_STANDARD=17 \
            -DCMAKE_INSTALL_PREFIX=/tmp/arrow/dist \
            -DCMAKE_INSTALL_LIBDIR=lib \
            -DBOOST_SOURCE=BUNDLED \
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
    CXX=clang++-7.0 CC=clang-7.0 \
        PYARROW_WITH_PARQUET=1 ARROW_HOME=/tmp/arrow/dist \
            python3 setup.py build_ext --bundle-arrow-cpp bdist_wheel && \
    mkdir -p /opt/arrow-0.14/share && \
    cp /tmp/arrow/python/dist/*.whl /opt/arrow-*/share &&\
    cp -r /tmp/arrow/dist/* /opt/arrow-*/ && \
    cd / && rm -rf /tmp/arrow

ENV CMAKE_PREFIX_PATH $CMAKE_PREFIX_PATH:/opt/arrow-0.14
