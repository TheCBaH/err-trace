#!/bin/sh
# Re-owns OPAMROOT to the current user, but only the entries that don't
# already match, so the common case (build-time ownership already correct)
# is a cheap no-op instead of an unconditional recursive chown.
#
# features/ocaml/install.sh sets this ownership at image-build time; this
# step covers the case that can't: devcontainer's updateRemoteUserUID remaps
# the container's vscode UID/GID to the host user after the image is built,
# so on a host whose user isn't UID 1000 the baked-in ownership is stale.
set -eu
# Caller (devcontainer.json) runs this under sudo and passes id -u/id -g
# from before that escalation - this script must not compute them itself,
# since by then id -u/id -g would report root, not the target user.
uid="$1"
gid="$2"
root="${OPAMROOT:-/opt/opam}"
find "$root" \( ! -uid "$uid" -o ! -gid "$gid" \) -exec chown "$uid:$gid" {} +
