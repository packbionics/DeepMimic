FROM ubuntu:18.04 as glvnd

# Set up libglvnd for OpenGL GUI support
RUN apt-get update && apt-get install -y --no-install-recommends \
        git \
        ca-certificates \
        make \
        automake \
        autoconf \
        libtool \
        pkg-config \
        python \
        libxext-dev \
        libx11-dev \
        x11proto-gl-dev && \
    rm -rf /var/lib/apt/lists/*

WORKDIR /opt/libglvnd
RUN git clone --branch=v1.0.0 https://github.com/NVIDIA/libglvnd.git . && \
    ./autogen.sh && \
    ./configure --prefix=/usr/local --libdir=/usr/local/lib/x86_64-linux-gnu && \
    make -j"$(nproc)" install-strip && \
    find /usr/local/lib/x86_64-linux-gnu -type f -name 'lib*.la' -delete

RUN dpkg --add-architecture i386 && \
    apt-get update && apt-get install -y --no-install-recommends \
        gcc-multilib \
        libxext-dev:i386 \
        libx11-dev:i386 && \
    rm -rf /var/lib/apt/lists/*

# 32-bit libraries
RUN make distclean && \
    ./autogen.sh && \
    ./configure --prefix=/usr/local --libdir=/usr/local/lib/i386-linux-gnu --host=i386-linux-gnu "CFLAGS=-m32" "CXXFLAGS=-m32" "LDFLAGS=-m32" && \
    make -j"$(nproc)" install-strip && \
    find /usr/local/lib/i386-linux-gnu -type f -name 'lib*.la' -delete


FROM tensorflow/tensorflow:1.13.1-gpu-py3

COPY --from=glvnd /usr/local/lib/x86_64-linux-gnu /usr/local/lib/x86_64-linux-gnu
COPY --from=glvnd /usr/local/lib/i386-linux-gnu /usr/local/lib/i386-linux-gnu

COPY internal/10_nvidia.json /usr/local/share/glvnd/egl_vendor.d/10_nvidia.json

RUN echo '/usr/local/lib/x86_64-linux-gnu' >> /etc/ld.so.conf.d/glvnd.conf && \
    echo '/usr/local/lib/i386-linux-gnu' >> /etc/ld.so.conf.d/glvnd.conf && \
    ldconfig

ENV LD_LIBRARY_PATH /usr/local/lib/x86_64-linux-gnu:/usr/local/lib/i386-linux-gnu${LD_LIBRARY_PATH:+:${LD_LIBRARY_PATH}}

ENV NVIDIA_DRIVER_CAPABILITIES ${NVIDIA_DRIVER_CAPABILITIES},display

ARG USER
ARG HOME

ENV LANG=C.UTF-8 LC_ALL=C.UTF-8 USER=$USER HOME=$HOME

RUN echo "The working directory is: $HOME"
RUN echo "The user is: $USER"

RUN mkdir -p $HOME
WORKDIR $HOME

RUN apt-get update && apt-get install -y \
        sudo \
        git \
        && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

# install dependencies
RUN apt-get update && DEBIAN_FRONTEND=noninteractive apt-get install -y \
    build-essential \
    curl \
    nano \
    vim \
    python-numpy \
    cmake \
    xorg-dev \
    freeglut3-dev \
    wget

RUN apt-get install -y mesa-utils \
    && apt-get install -y clang \
    && apt-get install -y cmake \
    && apt-get install wget

RUN wget https://github.com/bulletphysics/bullet3/archive/2.88.tar.gz \
    && mv 2.88.tar.gz bullet3-2.88.tar.gz \
    && tar xvzf bullet3-2.88.tar.gz \
    && cd bullet3-2.88 \
    && sed -i 's/-DUSE_DOUBLE_PRECISION=ON/-DUSE_DOUBLE_PRECISION=OFF/g' build_cmake_pybullet_double.sh\
    && ./build_cmake_pybullet_double.sh \
    && cd build_cmake \
    && make install \
    && cd ../.. && rm -r bullet3-2.88 && rm bullet3-2.88.tar.gz


RUN wget https://gitlab.com/libeigen/eigen/-/archive/3.3.7/eigen-3.3.7.tar.gz \
    && tar -xvf eigen-3.3.7.tar.gz\
    && cd ./eigen-3.3.7 \
    && mkdir build && cd build \
    && cmake .. \
    && make install \
    && cd ../.. && rm -r eigen-3.3.7 && rm eigen-3.3.7.tar.gz

RUN wget -O glew-2.1.0.tar.gz "https://sourceforge.net/projects/glew/files/glew/2.1.0/glew-2.1.0.tgz/download" \
    && tar -xvf glew-2.1.0.tar.gz \
    && cd ./glew-2.1.0 \
    && make && make install && make clean \
    && ln -s /usr/lib64/libGLEW.so.2.1 /usr/lib/libGLEW.so.2.1 \
    && cd .. && rm -r glew-2.1.0 && rm glew-2.1.0.tar.gz

RUN wget -O swig-4.0.0.tar.gz "https://downloads.sourceforge.net/swig/swig-4.0.0.tar.gz" \
    && tar -xvf swig-4.0.0.tar.gz \
    && cd swig-4.0.0 \
    && ./configure --without-pcre \
    && make && make install \
    && cd .. && rm -r swig-4.0.0 && rm swig-4.0.0.tar.gz

RUN apt-get install -y libopenmpi-dev
RUN pip install PyOpenGL PyOpenGL_accelerate
RUN pip install mpi4py

COPY . $HOME/DeepMimic

RUN cd $HOME/DeepMimic/DeepMimicCore \
    && make python
