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

# Contributing

For general contribution guideline, please check the [Apache Ozone repository](https://github.com/apache/ozone/blob/master/CONTRIBUTING.md).

Development of the `ozone-runner` image happens on branch `master`.  Relevant changes are cherry-picked to branch `jdk11` (used for versions before Ozone 2.0), `jdk8` (for testing Ozone client Java version compatibility) and `slim` (a variant without dev/test tools, used by other projects).

## Local Build and Test

### Building

The image can be built simply by running the helper script `build.sh`:

```bash
$ ./build.sh
...
 => => naming to docker.io/apache/ozone-runner:dev
```

This will create a single-platform image for your architecture.

### Testing

To try the image locally with Ozone acceptance tests, define the version to be used:

```bash
export OZONE_RUNNER_VERSION=dev
```

then run [acceptance tests](https://github.com/apache/ozone/blob/master/hadoop-ozone/dist/src/main/compose/README.md) as needed.

## GitHub Workflows

If this is your first time working on the image, please enable GitHub Actions workflows after forking the repo.

### Building

Whenever changes are pushed to your fork, GitHub builds a multi-platform image (for `amd64` and `arm64`), and tags it with the commit SHA.  These images can be shared with other developers for feedback.  Workflow runs are listed at `https://github.com/<username>/ozone-docker-runner/actions`, images at `https://github.com/<username>/ozone-docker-runner/pkgs/container/ozone-runner`.

### Testing

To run complete Ozone CI with the custom image:

1. Create a new branch in your clone of `apache/ozone`.
2. Update `OZONE_RUNNER_IMAGE` to `ghcr.io/<username>/ozone-runner` in [check.yml](https://github.com/apache/ozone/blob/23b0505d2ee27004f6e6c770de09e03853cf7643/.github/workflows/check.yml#L137).
3. Update `docker.ozone-runner.version` to `<commit SHA>` in [hadoop-ozone/dist/pom.xml](https://github.com/apache/ozone/blob/23b0505d2ee27004f6e6c770de09e03853cf7643/hadoop-ozone/dist/pom.xml#L28).
4. Commit the change and push to your fork of `apache/ozone`.

## Publishing Docker Tags (for committers)

1. Fetch changes to your local clone.
2. Add a Git tag for the commit following the existing pattern `<date>-<n>-<flavor>`, where
    - `<n>` starts at 1, and is incremented if multiple images need to be published the same day)
    - `<flavor>` is one of: `jdk21`, `jdk11`, `jdk8`, `slim`
3. Push the Git tag to the official repo (`apache/ozone-docker-runner`).  This will trigger a workflow to apply the tag to the Docker image.
4. Set `Fix Version` of the Jira issue to `runner-<date>-<n>-<flavor>`

## Updating Variants

1. Cherry-pick changes from `master` to other variants:
    - If the change is relevant for Ozone 1.x versions, cherry-pick it to the `jdk11` branch.
    - If the change is not restricted to server-side components, cherry-pick it to the `jdk8` branch.
    - If the change is not restricted to dev/test tools, cherry-pick it to the `slim` branch.
2. Push the branch to your fork
3. If CI in your fork passes, push the same branch to `apache/ozone-docker-runner`
4. Tag commits as described earlier.
