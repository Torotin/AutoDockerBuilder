# GitHub Actions Workflow Generator for Docker Self-Hosted

## Description

A small Bash script (`generate-workflow.sh`) that takes a YAML template and a variables file, substitutes environment variables, and writes a ready-to-use GitHub Actions workflow into `.github/workflows/${PROJECT_NAME}-Docker-Selfhosted.yml`.

## Requirements

* Bash (≥ 4) with `envsubst` support
* `docker-workflow-template.yaml` in the project root
* `.envsubst-vars` file with your environment settings
* Write access to `.github/workflows/`

## Installation & Setup

1. Clone your repo and `cd` into it.
2. Make the script executable:

   ```bash
   chmod +x generate-workflow.sh
   ```
3. Create or update `.envsubst-vars` with your variables (see next section).

## Configuration Variables

In `.envsubst-vars` (no quotes, one per line):

```bash
PROJECT_NAME=your_project_name           # used in workflow name and Docker tags
REPO_EXT_URL=https://…/repo.git          # external repo URL to clone
REPO_EXT_NAME=owner/repo                 # owner/repo for GitHub API
DOCKER_REPO=username/your_project        # Docker Hub repo
WORKDIR=external                         # folder to clone external repo into
TAR_DIR=tarballs                         # where to save .tar.gz images
ARTIFACT_DIR=artifacts                   # where to store helper files
CUSTOM_FILES_GLOB="Dockerfile*,…"        # glob for triggering on push
CUSTOM_DOCKERFILE=custom/Dockerfile      # optional override Dockerfile
CUSTOM_ENTRYPOINT=custom/entrypoint.sh
CUSTOM_INIT=custom/init.sh
CUSTOM_CONFIG=custom/config.yaml
CRON_SCHEDULE="0 0 * * *"                # cron for scheduled runs
```

Make sure `PROJECT_NAME`, `REPO_EXT_URL` and `DOCKER_REPO` are set; the script will error out otherwise.

## Usage

Run:

```bash
./generate-workflow.sh
```

It will:

1. Check for the template and `.envsubst-vars`.
2. Load and export variables.
3. Verify required variables.
4. Substitute into the template and write to `.github/workflows/${PROJECT_NAME}-Docker-Selfhosted.yml`.
5. Print the output path on success.

## Template Overview

```yaml
name: ${PROJECT_NAME}-Docker-Selfhosted

on:
  workflow_dispatch:          # manual trigger with inputs for builds/releases
  push:                      # on changes to this workflow or custom files
  schedule:                  # cron trigger

env:                         # all key vars passed to jobs

jobs:
  prepare:                   # clean, install deps, fetch latest tag, decide skip
  build:                     # multi-arch build & push with Buildx
  release:                   # save image tar, create GitHub Release, cleanup
```

* **prepare**

  * Cleans workspace
  * Installs `jq`, `curl`, `tree`
  * Fetches latest tag via GitHub API
  * Sets `skip` flag based on existing tags or inputs
* **build**

  * Determines target platforms (amd64, arm64, 386)
  * Clones external repo at the selected tag
  * Replaces Docker context if overrides provided
  * Logs into Docker Hub and runs Buildx
* **release**

  * Pulls and saves the `latest` image as a `.tar.gz`
  * Generates a Markdown list of platforms
  * Publishes a GitHub Release with badges and artifacts
  * Cleans up old workflow runs

## Example

.envsubst-vars:

```bash
PROJECT_NAME=myapp
REPO_EXT_URL=https://github.com/example/external-repo.git
REPO_EXT_NAME=example/external-repo
DOCKER_REPO=example/myapp
WORKDIR=external
TAR_DIR=tarballs
ARTIFACT_DIR=artifacts
CUSTOM_FILES_GLOB="Dockerfile*"
CUSTOM_DOCKERFILE=custom/Dockerfile
CUSTOM_ENTRYPOINT=custom/entrypoint.sh
CUSTOM_INIT=custom/init.sh
CUSTOM_CONFIG=custom/config.yaml
CRON_SCHEDULE="30 3 * * *"
```

```bash
./generate-workflow.sh
# → ✅ Workflow successfully generated: .github/workflows/myapp-Docker-Selfhosted.yml
```