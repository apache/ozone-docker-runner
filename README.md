<!--
  Licensed to the Apache Software Foundation (ASF) under one or more
  contributor license agreements.  See the NOTICE file distributed with
  this work for additional information regarding copyright ownership.
  The ASF licenses this file to You under the Apache License, Version 2.0
  (the "License"); you may not use this file except in compliance with
  the License.  You may obtain a copy of the License at

      http://www.apache.org/licenses/LICENSE-2.0

  Unless required by applicable law or agreed to in writing, software
  distributed under the License is distributed on an "AS IS" BASIS,
  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
  See the License for the specific language governing permissions and
  limitations under the License.
-->

# Apache Ozone **runner** base image

This is the base image to run Apache Hadoop Ozone in docker containers. This is only for test/develop and not for production.

The container doesn't include any Ozone specific jar files or release artifacts just an empty environment which includes all the specific tools to run and test Apache Ozone inside containers.

The image is available as [apache/ozone-runner](https://hub.docker.com/r/apache/ozone-runner). Build is managed by Docker Hub.

## Development

To build the image, please use:

```
DOCKER_BUILDKIT=1 docker build -t apache/ozone-runner:dev .
```

To test it, build [Apache Ozone](https://github.com/apache/ozone):

```
mvn clean verify -DskipTests -Dskip.npx -DskipShade -Ddocker.ozone-runner.version=dev
```

And start the compose cluster:

```
cd hadoop-ozone/dist/target/ozone-*/compose/ozone
docker-compose up -d
```

*After merging PR, a new tag should pushed to the repository to create a new image. Use the convention: `YYYYMMDD-N` for tags where N is a daily counter (see the existing tags as an example).

After tag is published (and built by Docker Hub), the used runner version can be updated by modifying the `docker.ozone-runner.version` version in [hadoop-ozone/dist/pom.xml](https://github.com/apache/ozone/blob/master/hadoop-ozone/dist/pom.xml)

## Building multi-architecture images

To build images with multiple architectures, use `docker buildx`.

For example, to build images for both `linux/amd64` and `linux/arm64`, run:

```bash
docker buildx build --platform linux/amd64,linux/arm64 -t apache/ozone-runner:dev . --progress=plain
```

It might be slow when building the non-native architecture image due to QEMU emulation.