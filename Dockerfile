# Licensed to the Apache Software Foundation (ASF) under one
# or more contributor license agreements.  See the NOTICE file
# distributed with this work for additional information
# regarding copyright ownership.  The ASF licenses this file
# to you under the Apache License, Version 2.0 (the
# "License"); you may not use this file except in compliance
# with the License.  You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

FROM golang:1.17.8-buster AS go
RUN go install github.com/rexray/gocsi/csc@latest
# Compile latest goofys for arm64 if necessary, which doesn't have a released binary
RUN set -eux ; \
    ARCH="$(arch)"; \
    if [ ${ARCH} = "aarch64" ]; then \
        git clone https://github.com/kahing/goofys.git ; \
        cd goofys ; \
        git checkout 08534b2 ; \
        go build ; \
        mv goofys /go/bin/ ; \
    elif [ ${ARCH} = "x86_64" ]; then \
        curl -L https://github.com/kahing/goofys/releases/download/v0.24.0/goofys -o /go/bin/goofys ; \
    else \
        echo "Unsupported architecture: ${ARCH}"; \
        exit 1 ; \
    fi

FROM centos:7.9.2009 AS builder
# Required for cmake3 and gcc 10
RUN yum -y install epel-release centos-release-scl
RUN set -eux ; \
    yum -y install \
      devtoolset-10-gcc-c++ \
      make \
      which \
      cmake3 \
      perl ; \
    yum clean all
RUN ln -s /usr/bin/cmake3 /usr/bin/cmake
# Add gcc 10 bin path
ENV PATH=/opt/rh/devtoolset-10/root/usr/bin:$PATH
RUN export GFLAGS_VER=2.2.2 \
      && curl -LSs https://github.com/gflags/gflags/archive/v${GFLAGS_VER}.tar.gz | tar zxv \
      && cd gflags-${GFLAGS_VER} \
      && mkdir build \
      && cd build \
      && cmake .. \
      && make -j$(nproc) \
      && make install \
      && cd ../.. \
      && rm -r gflags-${GFLAGS_VER}
RUN export ZSTD_VER=1.5.2 \
      && curl -LSs https://github.com/facebook/zstd/archive/v${ZSTD_VER}.tar.gz | tar zxv \
      && cd zstd-${ZSTD_VER} \
      && make -j$(nproc) \
      && make install \
      && cd .. \
      && rm -r zstd-${ZSTD_VER}
RUN export ROCKSDB_VER=7.0.4 \
      && curl -LSs https://github.com/facebook/rocksdb/archive/v${ROCKSDB_VER}.tar.gz | tar zxv \
      && mv rocksdb-${ROCKSDB_VER} rocksdb \
      && cd rocksdb \
      && make -j$(nproc) ldb \
      && mv ldb .. \
      && cd .. \
      && rm -r rocksdb

FROM centos:7.9.2009
RUN rpm -Uvh https://dl.fedoraproject.org/pub/epel/epel-release-latest-7.noarch.rpm
RUN set -eux ; \
    yum install -y \
      bzip2 \
      java-11-openjdk-devel \
      jq \
      nmap-ncat \
      python3 python3-pip \
      snappy \
      sudo \
      zlib \
      diffutils \
      krb5-workstation \
      fuse ; \
    yum clean all
RUN sudo python3 -m pip install --upgrade pip

COPY --from=go /go/bin/csc /usr/bin/csc
COPY --from=builder /ldb /usr/local/bin/ldb
COPY --from=builder /usr/local/lib /usr/local/lib/

#For executing inline smoketest
RUN set -eux ; \
    pip3 install awscli robotframework boto3 ; \
    rm -r ~/.cache/pip

#dumb init for proper init handling
RUN set -eux ; \
    ARCH="$(arch)"; \
    case "${ARCH}" in \
        x86_64) \
            url='https://github.com/Yelp/dumb-init/releases/download/v1.2.5/dumb-init_1.2.5_x86_64'; \
            sha256='e874b55f3279ca41415d290c512a7ba9d08f98041b28ae7c2acb19a545f1c4df'; \
            ;; \
        aarch64) \
            url='https://github.com/Yelp/dumb-init/releases/download/v1.2.5/dumb-init_1.2.5_aarch64'; \
            sha256='b7d648f97154a99c539b63c55979cd29f005f88430fb383007fe3458340b795e'; \
            ;; \
        *) echo "Unsupported architecture: ${ARCH}"; exit 1 ;; \
    esac; \
    curl -L ${url} -o dumb-init ; \
    echo "${sha256} *dumb-init" | sha256sum -c - ; \
    chmod +x dumb-init ; \
    mv dumb-init /usr/local/bin/dumb-init

#byteman test for development
ADD https://repo.maven.apache.org/maven2/org/jboss/byteman/byteman/4.0.18/byteman-4.0.18.jar /opt/byteman.jar
RUN chmod o+r /opt/byteman.jar

#async profiler for development profiling
RUN set -eux ; \
    ARCH="$(arch)" ; \
    case "${ARCH}" in \
        x86_64)  url='https://github.com/jvm-profiling-tools/async-profiler/releases/download/v2.7/async-profiler-2.7-linux-x64.tar.gz' ;; \
        aarch64) url='https://github.com/jvm-profiling-tools/async-profiler/releases/download/v2.7/async-profiler-2.7-linux-arm64.tar.gz' ;; \
        *) echo "Unsupported architecture: ${ARCH}"; exit 1 ;; \
    esac; \
    curl -L ${url} | tar xvz ; \
    mv async-profiler-* /opt/profiler

ENV JAVA_HOME=/usr/lib/jvm/jre/
ENV LD_LIBRARY_PATH=/usr/local/lib
ENV PATH=/opt/hadoop/libexec:$PATH:/opt/hadoop/bin

RUN groupadd --gid 1000 hadoop
RUN useradd --uid 1000 hadoop --gid 1000 --home /opt/hadoop
RUN chmod 755 /opt/hadoop
RUN echo "hadoop ALL=(ALL) NOPASSWD: ALL" >> /etc/sudoers

RUN chown hadoop /opt

RUN groupadd --gid 1001 om
RUN useradd --uid 1001 om --gid 1001 --home /opt/om
RUN chmod 755 /opt/om

RUN groupadd --gid 1002 dn
RUN useradd --uid 1002 dn --gid 1002 --home /opt/dn
RUN chmod 755 /opt/dn

RUN groupadd --gid 1003 scm
RUN useradd --uid 1003 scm --gid 1003 --home /opt/scm
RUN chmod 755 /opt/scm

RUN groupadd --gid 1004 s3g
RUN useradd --uid 1004 s3g --gid 1004 --home /opt/s3g
RUN chmod 755 /opt/s3g

RUN groupadd --gid 1006 recon
RUN useradd --uid 1006 recon --gid 1006 --home /opt/recon
RUN chmod 755 /opt/recon

RUN groupadd --gid 1007 testuser
RUN useradd --uid 1007 testuser --gid 1007 --home /opt/testuser
RUN chmod 755 /opt/testuser

RUN groupadd --gid 1008 testuser2
RUN useradd --uid 1008 testuser2 --gid 1008 --home /opt/testuser2
RUN chmod 755 /opt/testuser2

# Prep for Kerberized cluster
RUN mkdir -p /etc/security/keytabs && chmod -R a+wr /etc/security/keytabs 
ADD krb5.conf /etc/
RUN chmod 644 /etc/krb5.conf

# CSI / k8s / fuse / goofys dependency
COPY --from=go --chmod=755 /go/bin/goofys /usr/bin/goofys

# Create hadoop and data directories. Grant all permission to all on them
RUN mkdir -p /etc/hadoop && mkdir -p /var/log/hadoop && chmod 1777 /etc/hadoop && chmod 1777 /var/log/hadoop
ENV OZONE_LOG_DIR=/var/log/hadoop
ENV OZONE_CONF_DIR=/etc/hadoop
RUN mkdir /data && chmod 1777 /data

# Set default entrypoint (used only if the ozone dir is not bind mounted)
ADD entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod 755 /usr/local/bin/entrypoint.sh

WORKDIR /opt/hadoop
USER hadoop

ENTRYPOINT ["/usr/local/bin/dumb-init", "--", "entrypoint.sh"]
