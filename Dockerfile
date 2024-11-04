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

FROM rockylinux:9.3
RUN set -eux ; \
    dnf install -y \
      bzip2 \
      diffutils \
      findutils \
      fuse \
      jq \
      krb5-workstation \
      lsof \
      ncurses \
      net-tools \
      nmap-ncat \
      openssl \
      procps \
      python3 python3-pip \
      snappy \
      sudo \
      zlib \
    && dnf clean all \
    && ln -sf /usr/bin/python3 /usr/bin/python
RUN sudo python3 -m pip install --upgrade pip

COPY --from=go /go/bin/csc /usr/bin/csc

#For executing inline smoketest
RUN set -eux ; \
    pip3 install awscli robotframework==6.1.1 boto3 ; \
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
RUN curl -Lo /opt/byteman.jar https://repo.maven.apache.org/maven2/org/jboss/byteman/byteman/4.0.23/byteman-4.0.23.jar \
    && chmod o+r /opt/byteman.jar

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

# OpenJDK 17
RUN set -eux ; \
    ARCH="$(arch)"; \
    case "${ARCH}" in \
        x86_64) \
            url='https://download.java.net/java/GA/jdk17.0.2/dfd4a8d0985749f896bed50d7138ee7f/8/GPL/openjdk-17.0.2_linux-x64_bin.tar.gz'; \
            sha256='0022753d0cceecacdd3a795dd4cea2bd7ffdf9dc06e22ffd1be98411742fbb44'; \
            ;; \
        aarch64) \
            url='https://download.java.net/java/GA/jdk17.0.2/dfd4a8d0985749f896bed50d7138ee7f/8/GPL/openjdk-17.0.2_linux-aarch64_bin.tar.gz'; \
            sha256='13bfd976acf8803f862e82c7113fb0e9311ca5458b1decaef8a09ffd91119fa4'; \
            ;; \
        *) echo "Unsupported architecture: ${ARCH}"; exit 1 ;; \
    esac && \
    curl -L ${url} -o openjdk.tar.gz && \
    echo "${sha256} *openjdk.tar.gz" | sha256sum -c - && \
    tar xzvf openjdk.tar.gz -C /usr/local && \
    rm -f openjdk.tar.gz

ENV JAVA_HOME=/usr/local/jdk-17.0.2
# compatibility with Ozone 1.4.0 and earlier compose env.
RUN mkdir -p /usr/lib/jvm && ln -s $JAVA_HOME /usr/lib/jvm/jre

ENV LD_LIBRARY_PATH=/usr/local/lib
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

# CSI / k8s / fuse / goofys dependency
COPY --from=go --chmod=755 /go/bin/goofys /usr/bin/goofys

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
