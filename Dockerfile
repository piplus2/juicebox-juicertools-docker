FROM ubuntu:16.04 AS build-env

ARG CUDA_VERSION=10.1
ARG JUICEBOX_VERSION=1.13.01
ARG JCUDA_ARCHIVE=JCuda-All-10.1.0.zip
ARG JCUDA_DIR=JCuda-All-10.1.0

ENV DEBIAN_FRONTEND=noninteractive \
    LANG=en_US.UTF-8 \
    LC_ALL=en_US.UTF-8 \
    JAVA_HOME=/usr/lib/jvm/java-8-openjdk-amd64 \
    PATH=/usr/local/cuda-${CUDA_VERSION}/bin:$PATH \
    LD_LIBRARY_PATH=/usr/local/cuda-${CUDA_VERSION}/lib64:$LD_LIBRARY_PATH

RUN apt-get update && \
    apt-get install -y --no-install-recommends \
    apt-transport-https \
    ca-certificates \
    dirmngr \
    gnupg \
    wget \
    git \
    unzip \
    build-essential \
    openjdk-8-jdk \
    ant \
    maven \
    locales && \
    rm -rf /var/lib/apt/lists/* && \
    locale-gen en_US.UTF-8

RUN set -eux; \
    apt-key adv --keyserver keyserver.ubuntu.com --recv-keys A4B469963BF863CC; \
    apt-key adv --keyserver keyserver.ubuntu.com --recv-keys F60F4B3D7FA2AF80; \
    echo "deb https://developer.download.nvidia.com/compute/cuda/repos/ubuntu1604/x86_64 /" > /etc/apt/sources.list.d/cuda.list; \
    echo "deb https://developer.download.nvidia.com/compute/machine-learning/repos/ubuntu1604/x86_64 /" > /etc/apt/sources.list.d/nvidia-ml.list; \
    apt-get update; \
    apt-get install -y --no-install-recommends \
    cuda-toolkit-10-1 \
    libcudnn7 \
    libcudnn7-dev; \
    rm -rf /var/lib/apt/lists/*

WORKDIR /opt/jcuda
RUN wget -q http://www.jcuda.org/downloads/${JCUDA_ARCHIVE} && \
    unzip -q ${JCUDA_ARCHIVE} && \
    rm ${JCUDA_ARCHIVE}

WORKDIR /opt/juicebox
RUN wget -qO- https://github.com/aidenlab/Juicebox/archive/refs/tags/v${JUICEBOX_VERSION}.tar.gz | tar -xz

RUN cp /opt/jcuda/${JCUDA_DIR}/* /opt/juicebox/Juicebox-${JUICEBOX_VERSION}/lib/jcuda/

WORKDIR /opt/juicebox/Juicebox-${JUICEBOX_VERSION}
RUN sed -i 's|jdk.home.1.8=/Library/Java/JavaVirtualMachines/jdk-12.0.1.jdk/Contents/Home|jdk.home.1.8=/usr/lib/jvm/java-8-openjdk-amd64/|g' juicebox.properties && \
    sed -i '/^sign\.keystore/s/^/#/' juicebox.properties && \
    sed -i '/^sign\.storepass/s/^/#/' juicebox.properties && \
    sed -i '/^sign\.alias/s/^/#/' juicebox.properties

RUN ant -Djava.home=${JAVA_HOME}

FROM adoptopenjdk/openjdk8:debian-slim AS runtime-env

ARG CUDA_VERSION=10.1
ARG JUICEBOX_VERSION=1.13.01

ENV LANG=en_US.UTF-8 \
    LC_ALL=en_US.UTF-8 \
    PATH=/usr/local/cuda-${CUDA_VERSION}/bin:$PATH \
    LD_LIBRARY_PATH=/usr/lib:/usr/local/cuda-${CUDA_VERSION}/lib64:$LD_LIBRARY_PATH \
    CPATH=/usr/local/cuda-${CUDA_VERSION}/include:$CPATH

COPY --from=build-env /usr/local/cuda-${CUDA_VERSION}/bin/ /usr/local/cuda-${CUDA_VERSION}/bin/
COPY --from=build-env /usr/local/cuda-${CUDA_VERSION}/nvvm/ /usr/local/cuda-${CUDA_VERSION}/nvvm/
COPY --from=build-env /usr/local/cuda-${CUDA_VERSION}/include/ /usr/local/cuda-${CUDA_VERSION}/include/
COPY --from=build-env /usr/local/cuda-${CUDA_VERSION}/lib64/*.so.${CUDA_VERSION} /usr/lib/
COPY --from=build-env /usr/local/cuda-${CUDA_VERSION}/lib64/libcudnn.* /usr/lib/
COPY --from=build-env /usr/local/cuda-${CUDA_VERSION}/lib64/libcublas.* /usr/lib/

RUN set -eux; \
    rm -rf /etc/apt/sources.list.d/*; \
    echo "deb http://archive.debian.org/debian buster main" > /etc/apt/sources.list; \
    echo "deb http://archive.debian.org/debian-security buster/updates main" >> /etc/apt/sources.list; \
    echo 'Acquire::AllowInsecureRepositories "true";' > /etc/apt/apt.conf.d/99archive-insecure; \
    echo 'Acquire::AllowDowngradeToInsecureRepositories "true";' >> /etc/apt/apt.conf.d/99archive-insecure; \
    apt-get update; \
    apt-get install -y --no-install-recommends \
    build-essential \
    libgomp1 \
    locales \
    gawk \
    perl \
    perl-modules; \
    rm -rf /var/lib/apt/lists/*; \
    locale-gen en_US.UTF-8

WORKDIR /app

COPY --from=build-env /opt/juicebox/Juicebox-${JUICEBOX_VERSION}/out/artifacts/* /app

ENV PATH=/app/Juicebox_jar:/app/juicer_tools_jar:$PATH

COPY juicer_tools /usr/local/bin/
RUN chmod +x /usr/local/bin/juicer_tools
