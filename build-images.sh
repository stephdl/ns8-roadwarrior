#!/bin/bash

#
# Copyright (C) 2026 Nethesis S.r.l.
# SPDX-License-Identifier: GPL-3.0-or-later
#

# Terminate on error
set -e

# Prepare variables for later use
images=()
# The image will be pushed to GitHub container registry
repobase="${REPOBASE:-ghcr.io/stephdl}"
# Configure the image name
reponame="roadwarrior"
# Node.js 25+ no longer ships Corepack, install it from npm
# renovate: datasource=npm packageName=corepack
corepack_version=0.36.0

# OpenVPN server image, built from openvpn-server/
buildah bud --layers -t "${repobase}/roadwarrior-server" openvpn-server
images+=("${repobase}/roadwarrior-server")

# Create a new empty container image
container=$(buildah from scratch)

# Reuse existing nodebuilder-roadwarrior container, to speed up builds
if ! buildah containers --format "{{.ContainerName}}" | grep -q nodebuilder-roadwarrior; then
    echo "Pulling NodeJS runtime..."
    buildah from --name nodebuilder-roadwarrior -v "${PWD}:/usr/src:Z" docker.io/library/node:26.13.1-slim
    buildah run nodebuilder-roadwarrior sh -c "npm install -g corepack@${corepack_version} && corepack enable"
fi

echo "Build static UI files with node..."
buildah run \
    --workingdir=/usr/src/ui \
    --env="NODE_OPTIONS=--openssl-legacy-provider" \
    nodebuilder-roadwarrior \
    sh -c "yarn install && yarn build"

# Add imageroot directory to the container image
buildah add "${container}" imageroot /imageroot
buildah add "${container}" ui/dist /ui
# The UDP port is a setting of the module, so no port is taken from the node allocator
buildah config --entrypoint=/ \
    --label="org.nethserver.authorizations=node:tunadm,portsadm cluster:accountconsumer" \
    --label="org.nethserver.tcp-ports-demand=0" \
    --label="org.nethserver.udp-ports-demand=1" \
    --label="org.nethserver.rootfull=0" \
    --label="org.nethserver.max-per-node=1" \
    --label="org.nethserver.images=${repobase}/roadwarrior-server:${IMAGETAG:-latest}" \
    "${container}"
# Commit the image
buildah commit "${container}" "${repobase}/${reponame}"

# Append the image URL to the images array
images+=("${repobase}/${reponame}")

#
# Setup CI when pushing to Github.
# Warning! docker::// protocol expects lowercase letters (,,)
if [[ -n "${CI}" ]]; then
    # Set output value for Github Actions
    printf "images=%s\n" "${images[*],,}" >> "${GITHUB_OUTPUT}"
else
    # Just print info for manual push
    printf "Publish the images with:\n\n"
    for image in "${images[@],,}"; do printf "  buildah push %s docker://%s:%s\n" "${image}" "${image}" "${IMAGETAG:-latest}" ; done
    printf "\n"
fi
