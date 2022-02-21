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

FROM golang:1.17.6-buster
RUN GO111MODULE=off go get -u github.com/rexray/gocsi/csc

FROM centos:7.9.2009
# Required for cmake3 package
RUN yum -y install epel-release
RUN yum -y install \
      gcc gcc-c++ \
      make \
      which \
      cmake3 \
      perl
RUN ln -s /usr/bin/cmake3 /usr/bin/cmake
RUN export GFLAGS_VER=2.2.2 \
      && curl -LSs -o gflags-src.tar.gz https://github.com/gflags/gflags/archive/v${GFLAGS_VER}.tar.gz \
      && tar zxvf gflags-src.tar.gz \
      && rm gflags-src.tar.gz \
      && cd gflags-${GFLAGS_VER} \
      && mkdir build \
      && cd build \
      && cmake .. \
      && make -j$(nproc) \
      && make install \
      && cd ../.. \
      && rm -rf gflags-${GFLAGS_VER}
RUN export ZSTD_VER=1.5.2 \
      && curl -LSs -o zstd-src.tar.gz https://github.com/facebook/zstd/archive/v${ZSTD_VER}.tar.gz \
      && tar zxvf zstd-src.tar.gz \
      && rm zstd-src.tar.gz \
      && cd zstd-${ZSTD_VER} \
      && make -j$(nproc) \
      && make install \
      && cd .. \
      && rm -rf zstd-${ZSTD_VER}
RUN export ROCKSDB_VER=6.28.2 \
      && curl -LSs -o rocksdb-src.tar.gz https://github.com/facebook/rocksdb/archive/v${ROCKSDB_VER}.tar.gz \
      && tar xzvf rocksdb-src.tar.gz \
      && rm rocksdb-src.tar.gz \
      && mv rocksdb-${ROCKSDB_VER} rocksdb \
      && cd rocksdb \
      && make -j$(nproc) ldb

FROM centos:7.9.2009
RUN rpm -Uvh https://dl.fedoraproject.org/pub/epel/epel-release-latest-7.noarch.rpm
RUN yum install -y \
      bzip2 \
      java-11-openjdk-devel \
      jq \
      nmap-ncat \
      python3 python3-pip \
      snappy \
      sudo \
      wget \
      zlib \
      diffutils
RUN sudo python3 -m pip install --upgrade pip

COPY --from=0 /go/bin/csc /usr/bin/csc
COPY --from=1 /rocksdb/ldb /usr/local/bin/ldb
COPY --from=1 /usr/local/lib /usr/local/lib/

#For executing inline smoketest
RUN pip3 install awscli robotframework boto3

#dumb init for proper init handling
RUN wget -O /usr/local/bin/dumb-init https://github.com/Yelp/dumb-init/releases/download/v1.2.5/dumb-init_1.2.5_x86_64
RUN chmod +x /usr/local/bin/dumb-init

#byteman test for development
ADD https://repo.maven.apache.org/maven2/org/jboss/byteman/byteman/4.0.9/byteman-4.0.9.jar /opt/byteman.jar
RUN chmod o+r /opt/byteman.jar

#async profiler for development profiling
RUN cd /opt && \
    curl -L https://github.com/jvm-profiling-tools/async-profiler/releases/download/v2.6/async-profiler-2.6-linux-x64.tar.gz | tar xvz && \
    mv async-profiler-2.6-linux-x64 profiler

ENV JAVA_HOME=/usr/lib/jvm/jre/
ENV LD_LIBRARY_PATH /usr/local/lib
ENV PATH /opt/hadoop/libexec:$PATH:/opt/hadoop/bin

RUN groupadd --gid 1000 hadoop
RUN useradd --uid 1000 hadoop --gid 100 --home /opt/hadoop
RUN chmod 755 /opt/hadoop
RUN echo "hadoop ALL=(ALL) NOPASSWD: ALL" >> /etc/sudoers

RUN chown hadoop /opt

# Prep for Kerberized cluster
RUN mkdir -p /etc/security/keytabs && chmod -R a+wr /etc/security/keytabs 
ADD krb5.conf /etc/
RUN chmod 644 /etc/krb5.conf
RUN yum install -y krb5-workstation

# CSI / k8s / fuse / goofys dependency
RUN wget https://github.com/kahing/goofys/releases/download/v0.24.0/goofys -O /usr/bin/goofys
RUN chmod 755 /usr/bin/goofys
RUN yum install -y fuse

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
