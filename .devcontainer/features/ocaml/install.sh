#!/bin/sh
set -eu
set -x

echo "Activating feature 'OCaml'"
PACKAGES=${PACKAGES:-$@}
BASE_PACKAGES=${BASE_PACKAGES-"dune ocaml-lsp-server ocamlformat ocamlformat-rpc"}
OPTIONAL_PACKAGES=${OPTIONAL_PACKAGES:-}
SYSTEM_PACKAGES=${SYSTEM_PACKAGES:-}
PIN_PACKAGES=${PIN_PACKAGES:-}
REPOSITORIES=${REPOSITORIES:-}
OCAML_VERSION=${VERSION:-4.14.3}
OPAM_OPTIONS=''
if [ -n "${OPTIONS:-}" ]; then
    OPAM_OPTIONS="--packages=ocaml-variants.${OCAML_VERSION}+options,${OPTIONS}"
fi
echo "Selected OCaml:$OCAML_VERSION base packages: ${BASE_PACKAGES} packages: $PACKAGES optional: ${OPTIONAL_PACKAGES} with ${OPAM_OPTIONS} ${SYSTEM_PACKAGES}"

# From https://github.com/devcontainers/features/blob/main/src/git/install.sh
apt_get_update()
{
    if [ "$(find /var/lib/apt/lists/* | wc -l)" = "0" ]; then
        echo "Running apt-get update..."
        apt-get update -y
    fi
}

# Checks if packages are installed and installs them if not
check_packages() {
    if ! dpkg -s "$@" > /dev/null 2>&1; then
        apt_get_update
        if ! apt-get -o Acquire::Retries=3 -y install --no-install-recommends "$@"; then
            apt-get update -y
            apt-get -o Acquire::Retries=3 -y install --no-install-recommends "$@"
        fi
    fi
}

export DEBIAN_FRONTEND=noninteractive

USERNAME="${USERNAME:-"${_REMOTE_USER:-"automatic"}"}"
UPDATE_RC="${UPDATE_RC:-"true"}"

# Determine the appropriate non-root user
if [ "${USERNAME}" = "auto" ] || [ "${USERNAME}" = "automatic" ]; then
    USERNAME=""
    POSSIBLE_USERS="vscode node codespace $(awk -v val=1000 -F ":" '$3==val{print $1}' /etc/passwd)"
    for CURRENT_USER in $POSSIBLE_USERS; do
        if id -u "${CURRENT_USER}" > /dev/null 2>&1; then
            USERNAME="${CURRENT_USER}"
            break
        fi
    done
    if [ "${USERNAME}" = "" ]; then
        USERNAME=root
    fi
elif [ "${USERNAME}" = "none" ] || ! id -u ${USERNAME} > /dev/null 2>&1; then
    USERNAME=root
fi

updaterc() {
    if [ "${UPDATE_RC}" = "true" ]; then
        echo "Updating /etc/bash.bashrc and /etc/zsh/zshrc..."
        if [ -f /etc/bash.bashrc ]; then
            /bin/echo -e "$1" >> /etc/bash.bashrc
        fi
        if [ -f "/etc/zsh/zshrc" ]; then
            /bin/echo -e "$1" >> /etc/zsh/zshrc
        fi
    fi
}

export OPAMROOT="/opt/opam"
export OPAMYES="true"
export OPAMCONFIRMLEVEL="unsafe-yes"

rc="$(cat << EOF
# >>> OCaml >>>
export OPAMROOT="$OPAMROOT"
# <<< OCaml <<<
EOF
)"
updaterc "$rc"

check_packages\
 ${SYSTEM_PACKAGES}\
 opam\

# Older compiler recipes are not safe to build in parallel: their generated
# dependency graphs can race when opam passes `make -jN`.
OCAML_MAJOR=${OCAML_VERSION%%.*}
OCAML_REST=${OCAML_VERSION#*.}
OCAML_MINOR=${OCAML_REST%%.*}
if [ "${OCAML_MAJOR}" -lt 4 ] || {
    [ "${OCAML_MAJOR}" -eq 4 ] && [ "${OCAML_MINOR}" -lt 14 ];
}; then
    export OPAMJOBS=1
else
    export OPAMJOBS="$(getconf _NPROCESSORS_ONLN)"
fi
opam init --no-setup --disable-sandboxing --bare
eval $(opam env)
opam switch create $OCAML_VERSION ${OPAM_OPTIONS}

# OCaml 4.12 selects ocaml-lsp-server.1.9.0. Its dependencies lack upper bounds
# for two later breaking releases: pp.2.0.0 changes the vendored dune-rpc API,
# and yojson.3.0.0 expands the polymorphic variant consumed by the LSP's JSON
# type. Keep the developer toolchain solvable without weakening the library's
# actual 4.12 floor.
if [ "${OCAML_MAJOR}" -eq 4 ] && [ "${OCAML_MINOR}" -eq 12 ]; then
    opam pin add --no-action pp 1.2.0
    opam pin add --no-action yojson 2.2.2
fi

if [ -n "${REPOSITORIES}" ]; then
    OLDIFS="$IFS"
    IFS=','
    for entry in ${REPOSITORIES}; do
        IFS="$OLDIFS"
        entry=$(echo "$entry" | xargs)
        if [ -n "$entry" ]; then
            repo_name=$(echo "$entry" | awk '{print $1}')
            repo_url=$(echo "$entry" | awk '{print $2}')
            opam repo add "$repo_name" "$repo_url"
        fi
    done
    IFS="$OLDIFS"
    opam update
fi

OPAM_PACKAGES=""
for pkg in ${BASE_PACKAGES} ${PACKAGES}; do
    case "$pkg" in
        *#*)
            pkg_name=$(echo "$pkg" | cut -d'#' -f1)
            pkg_ver=$(echo "$pkg" | cut -d'#' -f2)
            opam pin add --no-action "$pkg_name" "$pkg_ver"
            OPAM_PACKAGES="${OPAM_PACKAGES} ${pkg_name}"
            ;;
        *)
            OPAM_PACKAGES="${OPAM_PACKAGES} ${pkg}"
            ;;
    esac
done

OPTIONAL_OPAM_PACKAGES=""
for pkg in ${OPTIONAL_PACKAGES}; do
    case "$pkg" in
        *#*)
            pkg_name=$(echo "$pkg" | cut -d'#' -f1)
            pkg_ver=$(echo "$pkg" | cut -d'#' -f2)
            opam pin add --no-action "$pkg_name" "$pkg_ver"
            OPTIONAL_OPAM_PACKAGES="${OPTIONAL_OPAM_PACKAGES} ${pkg_name}"
            ;;
        *)
            OPTIONAL_OPAM_PACKAGES="${OPTIONAL_OPAM_PACKAGES} ${pkg}"
            ;;
    esac
done

if [ -n "${PIN_PACKAGES}" ]; then
    OLDIFS="$IFS"
    IFS=','
    for entry in ${PIN_PACKAGES}; do
        IFS="$OLDIFS"
        entry=$(echo "$entry" | xargs)
        if [ -n "$entry" ]; then
            case "$entry" in
                *#*)
                    pkg_name=$(echo "$entry" | cut -d'#' -f1)
                    pkg_ver=$(echo "$entry" | cut -d'#' -f2)
                    opam pin add --no-action "$pkg_name" "$pkg_ver"
                    ;;
                *)
                    pkg_name=$(echo "$entry" | awk '{print $1}')
                    opam pin add --no-action $entry
                    ;;
            esac
            OPAM_PACKAGES="${OPAM_PACKAGES} ${pkg_name}"
        fi
    done
    IFS="$OLDIFS"
fi

# Only the packages declared optional may be dropped; anything in PACKAGES or
# PIN_PACKAGES that opam cannot install must still fail the build.
for pkg in ${OPTIONAL_OPAM_PACKAGES}; do
    # A solver dry run is required here: `opam list --installable` can still
    # match packages whose `available:` filter rejects the current architecture.
    if opam install --show-actions "$pkg" > /dev/null 2>&1; then
        OPAM_PACKAGES="${OPAM_PACKAGES} ${pkg}"
    else
        echo "Skipping optional package '$pkg': not installable for this switch/platform" >&2
    fi
done

if [ -n "${OPAM_PACKAGES}" ]; then
    opam install ${OPAM_PACKAGES}
fi

opam clean --repo-cache
opam list
chown -R ${USERNAME}:${USERNAME} $OPAMROOT

apt-get autoremove -y
apt-get clean -y
rm -rf /var/lib/apt/lists/*
