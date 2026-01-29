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

FROM rockylinux/rockylinux:9
RUN set -eux ; \
    dnf install -y \
      bzip2 \
      diffutils \
      findutils \
      fuse \
      jq \
      krb5-workstation \
      libxcrypt-compat \
      lsof \
      ncurses \
      net-tools \
      nmap-ncat \
      openssl \
      procps \
      python3 python3-pip \
      snappy \
      sudo \
      unzip \
      zlib \
    && dnf clean all \
    && ln -sf /usr/bin/python3 /usr/bin/python
RUN python3 -m pip install --upgrade pip

# CSI / k8s / fuse / goofys dependency
COPY --from=go /go/bin/csc /usr/bin/csc
# S3 FUSE support - mountpoint-s3
ARG MOUNTPOINT_S3_VERSION=1.19.0
RUN set -eux ; \
    ARCH="$(arch)"; \
    case "${ARCH}" in \
        x86_64)  arch='x86_64' ;; \
        aarch64) arch='arm64' ;; \
        *) echo "Unsupported architecture: ${ARCH}"; exit 1 ;; \
    esac; \
    curl -L "https://s3.amazonaws.com/mountpoint-s3-release/${MOUNTPOINT_S3_VERSION}/${arch}/mount-s3-${MOUNTPOINT_S3_VERSION}-${arch}.rpm" -o mount-s3.rpm ; \
    dnf install -y mount-s3.rpm ; \
    rm -f mount-s3.rpm

# Install rclone for smoketest
ARG RCLONE_VERSION=1.69.3
RUN set -eux ; \
    ARCH="$(arch)" ; \
    case "${ARCH}" in \
        x86_64)  arch='amd64' ;; \
        aarch64) arch='arm64' ;; \
        *) echo "Unsupported architecture: ${ARCH}"; exit 1 ;; \
    esac; \
    curl -L -o /tmp/package.rpm "https://downloads.rclone.org/v${RCLONE_VERSION}/rclone-v${RCLONE_VERSION}-linux-${arch}.rpm"; \
    dnf install -y /tmp/package.rpm; \
    rm -f /tmp/package.rpm


#For executing inline smoketest
RUN set -eux ; \
    pip3 install awscli==1.38.15 robotframework==6.1.1 boto3==1.37.15 ; \
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
ARG BYTEMAN_VERSION=4.0.25
ENV BYTEMAN_HOME=/opt/byteman
RUN cd /tmp && \
    curl -L -o byteman.zip https://downloads.jboss.org/byteman/${BYTEMAN_VERSION}/byteman-download-${BYTEMAN_VERSION}-bin.zip && \
    unzip -j -d byteman byteman.zip && \
    mkdir -p ${BYTEMAN_HOME}/lib && \
    mv byteman/byteman.jar byteman/byteman-submit.jar ${BYTEMAN_HOME}/lib/ && \
    mv byteman/bmsubmit.sh /usr/local/bin/bmsubmit && \
    chmod +x /usr/local/bin/bmsubmit && \
    rm -rf byteman.zip byteman && \
    chmod -R a+rX ${BYTEMAN_HOME} && \
    ln -s ${BYTEMAN_HOME}/lib/byteman.jar /opt/byteman.jar

#async profiler for development profiling
RUN set -eux ; \
    ARCH="$(arch)" ; \
    case "${ARCH}" in \
        x86_64)  url='https://github.com/jvm-profiling-tools/async-profiler/releases/download/v2.9/async-profiler-2.9-linux-x64.tar.gz' ;; \
        aarch64) url='https://github.com/jvm-profiling-tools/async-profiler/releases/download/v2.9/async-profiler-2.9-linux-arm64.tar.gz' ;; \
        *) echo "Unsupported architecture: ${ARCH}"; exit 1 ;; \
    esac; \
    curl -L ${url} | tar xvz ; \
    mv async-profiler-* /opt/profiler

# Hadoop native libary (Hadoop 3.4.1 doesn't have aarch64 binary)
RUN set -eux ; \
    ARCH="$(arch)" ; \
    hadoop_version=3.4.0 ; \
    case "${ARCH}" in \
        x86_64)  file=hadoop-${hadoop_version}.tar.gz ;; \
        aarch64) file=hadoop-${hadoop_version}-aarch64.tar.gz ;; \
        *) echo "Unsupported architecture: ${ARCH}"; exit 1 ;; \
    esac; \
    curl -L "https://www.apache.org/dyn/closer.lua?action=download&filename=hadoop/common/hadoop-${hadoop_version}/$file" -o "hadoop-${hadoop_version}.tar.gz" && \
    tar xzvf hadoop-${hadoop_version}.tar.gz -C /tmp && \
    mv /tmp/hadoop-${hadoop_version}/lib/native/libhadoop.*  /usr/lib/ && \
    rm -rf /tmp/hadoop-${hadoop_version} && \
    rm -f hadoop-${hadoop_version}.tar.gz

# OpenJDK 21
RUN set -eux ; \
    ARCH="$(arch)"; \
    case "${ARCH}" in \
        x86_64) \
            url='https://download.java.net/java/GA/jdk21.0.2/f2283984656d49d69e91c558476027ac/13/GPL/openjdk-21.0.2_linux-x64_bin.tar.gz'; \
            sha256='a2def047a73941e01a73739f92755f86b895811afb1f91243db214cff5bdac3f'; \
            ;; \
        aarch64) \
            url='https://download.java.net/java/GA/jdk21.0.2/f2283984656d49d69e91c558476027ac/13/GPL/openjdk-21.0.2_linux-aarch64_bin.tar.gz'; \
            sha256='08db1392a48d4eb5ea5315cf8f18b89dbaf36cda663ba882cf03c704c9257ec2'; \
            ;; \
        *) echo "Unsupported architecture: ${ARCH}"; exit 1 ;; \
    esac && \
    curl -L ${url} -o openjdk.tar.gz && \
    echo "${sha256} *openjdk.tar.gz" | sha256sum -c - && \
    tar xzvf openjdk.tar.gz -C /usr/local && \
    rm -f openjdk.tar.gz

ENV JAVA_HOME=/usr/local/jdk-21.0.2
# compatibility with Ozone 1.4.0 and earlier compose env.
RUN mkdir -p /usr/lib/jvm && ln -s $JAVA_HOME /usr/lib/jvm/jre

ENV PATH=/opt/hadoop/libexec:$PATH:$JAVA_HOME/bin:/opt/hadoop/bin

RUN id=1000; \
    for u in hadoop om dn scm s3g recon testuser testuser2 httpfs; do \
      groupadd --gid $id $u \
      && useradd --uid $id $u --gid $id --home /opt/$u \
      && mkdir /opt/$u \
      && chmod 755 /opt/$u; \
      id=$(( id + 1 )); \
    done

RUN echo "hadoop ALL=(ALL) NOPASSWD: ALL" >> /etc/sudoers
RUN chown hadoop /opt

# Prep for Kerberized cluster
RUN mkdir -p /etc/security/keytabs && chmod -R a+wr /etc/security/keytabs 
COPY --chmod=644 krb5.conf /etc/

# Create hadoop and data directories. Grant all permission to all on them
RUN mkdir -p /etc/hadoop && mkdir -p /var/log/hadoop && chmod 1777 /etc/hadoop && chmod 1777 /var/log/hadoop
ENV OZONE_LOG_DIR=/var/log/hadoop
ENV OZONE_CONF_DIR=/etc/hadoop
RUN mkdir /data && chmod 1777 /data

# Set default entrypoint (used only if the ozone dir is not bind mounted)
COPY --chmod=755 entrypoint.sh /usr/local/bin/entrypoint.sh

WORKDIR /opt/hadoop
USER hadoop

ENTRYPOINT ["/usr/local/bin/dumb-init", "--", "entrypoint.sh"]
