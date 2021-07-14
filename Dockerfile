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
RUN mkdir /opt/clang+llvm-11.1.0/ && \
    cd /opt/clang+llvm-11.1.0/ && \
    wget --progress=dot:giga https://github.com/llvm/llvm-project/releases/download/llvmorg-11.1.0/clang+llvm-11.1.0-x86_64-linux-gnu-ubuntu-16.04.tar.xz -O - \
         | tar -x -I xz --strip-components=1 && \
    for file in bin/*; \
    do \
        ln -s $PWD/$file /usr/bin/$(basename $file)-11.1; \
    done && \
    ln -s libomp.so /opt/clang+llvm-11.1.0/lib/libomp.so.5 && \
    update-alternatives --install /usr/bin/clang++ clang++ /usr/bin/clang++-11.1 100 && \
    update-alternatives --install /usr/bin/clang clang /usr/bin/clang-11.1 100

ENV CMAKE_PREFIX_PATH $CMAKE_PREFIX_PATH:/opt/clang+llvm-11.1.0

# CMake
RUN mkdir /opt/cmake-3.21.0/ && \
    cd /opt/cmake-3.21.0/ && \
    wget --progress=dot:giga https://github.com/Kitware/CMake/releases/download/v3.21.0/cmake-3.21.0-linux-x86_64.tar.gz -O - \
        | tar -xz --strip-components=1 && \
    for file in bin/*; \
    do \
        ln -s $PWD/$file /usr/bin/$(basename $file); \
    done

# Boost
RUN cd /tmp/ && \
    wget --progress=dot:giga -O - \
        https://boostorg.jfrog.io/artifactory/main/release/1.76.0/source/boost_1_76_0.tar.gz \
        | tar -xz && \
    cd /tmp/boost_1_76_0 && \
    ./bootstrap.sh --prefix=/opt/boost-1.76.0 --with-toolset=clang && \
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
    rm -rf /tmp/boost_1_76_0

ENV CMAKE_PREFIX_PATH $CMAKE_PREFIX_PATH:/opt/boost-1.76.0

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
    wget --progress=dot:giga https://github.com/apache/arrow/archive/apache-arrow-4.0.1.tar.gz -O - \
        | tar -xz --strip-components=1 && \
    pip3 install -r /tmp/arrow/python/requirements-build.txt && \
    mkdir -p /tmp/arrow/cpp/build && \
    cd /tmp/arrow/cpp/build && \
    CXXFLAGS="-Wl,-rpath=/opt/boost-1.76.0/lib/ -D_GLIBCXX_USE_CXX11_ABI" \
        CXX=clang++ CC=clang \
            cmake \
                -DCMAKE_BUILD_TYPE=Release \
                -DCMAKE_CXX_STANDARD=17 \
                -DCMAKE_INSTALL_PREFIX=/tmp/arrow/dist \
                -DCMAKE_INSTALL_LIBDIR=lib \
                -DARROW_WITH_BROTLI=ON \
                -DARROW_WITH_BZ2=ON \
                -DARROW_WITH_LZ4=ON \
                -DARROW_WITH_RAPIDJSON=ON \
                -DARROW_WITH_SNAPPY=ON \
                -DARROW_WITH_ZLIB=ON \
                -DARROW_WITH_ZSTD=ON \
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
    CXXFLAGS="-Wl,-rpath=/opt/boost-1.76.0/lib/ -D_GLIBCXX_USE_CXX11_ABI" \
        CXX=clang++ CC=clang \
        PYARROW_WITH_PARQUET=1 ARROW_HOME=/tmp/arrow/dist \
            python3 setup.py build_ext --bundle-arrow-cpp bdist_wheel && \
    mkdir -p /opt/arrow-4.0.1/share && \
    cp /tmp/arrow/python/dist/*.whl /opt/arrow-*/share &&\
    cp -r /tmp/arrow/dist/* /opt/arrow-*/ && \
    ln -s arrow /opt/arrow-4.0.1/lib/cmake/parquet && \
    cd / && rm -rf /tmp/arrow

ENV CMAKE_PREFIX_PATH $CMAKE_PREFIX_PATH:/opt/arrow-4.0.1
