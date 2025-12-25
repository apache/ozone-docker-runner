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

FROM rockylinux:9.3
RUN set -eux ; \
    dnf install -y \
      bzip2 \
      findutils \
      java-21-openjdk-headless \
      krb5-workstation \
      libxcrypt-compat \
      ncurses \
      openssl \
      procps \
      snappy \
      sudo \
      unzip \
      zlib \
    && dnf clean all


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

ENV JAVA_HOME=/usr/lib/jvm/jre-21-openjdk

ENV PATH=/opt/hadoop/libexec:$PATH:$JAVA_HOME/bin:/opt/hadoop/bin

RUN id=1000; \
    for u in hadoop om dn scm s3g recon httpfs; do \
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
