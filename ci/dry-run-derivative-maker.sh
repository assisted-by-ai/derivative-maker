#!/bin/bash

## Copyright (C) 2026 - 2026 ENCRYPTED SUPPORT LLC <adrelanos@whonix.org>
## See the file COPYING for copying conditions.

## Drive the dry-run smoke build for .github/workflows/dry-run.yml.
##
## help-steps/run-as-user creates a 'builder' user with passwordless
## sudo, chowns the source tree, and execs the given command as that
## user. This satisfies sanity-tests' "source must not be owned by
## root" check while still letting the build steps that need sudo
## (cowbuilder, mkdir under /var/cache/pbuilder) work.
##
## --unsupported-os true: ubuntu-latest's 'debian:trixie' container
## *should* identify as trixie and pass the OS sanity check, but
## the flag protects the workflow from an unexpected codename detected
## by a build step computing it from apt sources.
##
## A plain 'timeout' wraps the call to ensure this doesn't hang. The
## workflow timeout should also prevent this.
##
## Standalone-runnable: from a checked-out source tree with
## /usr/libexec/helper-scripts symlinked and the apt deps installed
## (see ci/dry-run-install.sh), 'bash ci/dry-run-derivative-maker.sh'
## reproduces what CI does.

set -o errexit
set -o nounset
set -o pipefail
set -o errtrace

## CI guard. Provisions a 'builder' user via run-as-user and chowns
## the source tree - surprising on a developer host. Refuse outside
## CI unless ALLOW_LOCAL=true is set explicitly.
if [ "${CI:-}" != "true" ] && [ "${ALLOW_LOCAL:-}" != "true" ]; then
  printf '%s\n' "${BASH_SOURCE[0]}: refusing to run outside CI (CI != 'true'). Set ALLOW_LOCAL=true to override." >&2
  exit 1
fi

cd -- "$(dirname -- "$(readlink -f -- "${BASH_SOURCE[0]}")")/.."

## Pre-set 'user_name=builder' for help-steps/variables. The script's
## own user-detection precedence (1: caller-provided user_name, 2:
## $SUDO_USER, 3: logname, 4: whoami) honors a pre-set 'user_name'
## first, so this short-circuits the SUDO_USER fallback.
##
## Why this matters in CI: 'run-as-user' invokes the build via
## 'sudo -u builder ...' from root, which makes sudo set
## SUDO_USER=root inside the build. Without this short-circuit,
## variables would set HOMEVAR=/home/root - a nonexistent directory
## not writable by the 'builder' user - and downstream 'mkdir -p
## /home/root/derivative-binary' fails. variables already documents
## this exact pitfall ("HOMEVAR=/home/root would silently point at
## a nonexistent home directory") for the whoami branch but not for
## SUDO_USER. Setting user_name explicitly is the simplest fix and
## keeps the shared build logic untouched.
##
## 'env -' would over-strip; we want to keep PATH (and the rest)
## that the harness set up. Use 'env VAR=val ...' to inject the
## variable into the command's environment.
timeout 1200 \
  ./help-steps/run-as-user --chown "$PWD" -- \
    builder \
    env user_name=builder ./derivative-maker \
      --dry-run true \
      --unsupported-os true \
      --allow-uncommitted true \
      --allow-untagged true \
      --flavor source \
      --target source
