#!/usr/bin/env bash
# Prepares deps, core and the callflow/crossbar apps for EUnit on OTP 22.
# Idempotent: safe to rerun on an already prepared tree. Runs from the repo root.
set -euo pipefail

cd "$(git rev-parse --show-toplevel)"

ERLANG_MK_COMMIT=82179575d9191305805c8e6e8107be7c3f80a6be
EMK_DIR=/opt/emk

otp="$(erl -noshell -eval 'io:put_chars(erlang:system_info(otp_release)), halt().' 2>/dev/null || true)"
# On a plain Ubuntu image without OTP 22, install it first; install-ubuntu.sh
# sets KZ_OTP_BOOTSTRAP before calling back into this script.
if [ "$otp" != "22" ] && [ -z "${KZ_OTP_BOOTSTRAP:-}" ] && [ -f .cursor/install-ubuntu.sh ] \
    && grep -qiE '^ID(_LIKE)?=.*(ubuntu|debian)' /etc/os-release 2>/dev/null; then
    export KZ_OTP_BOOTSTRAP=1
    exec bash .cursor/install-ubuntu.sh "$@"
fi
if [ "$otp" != "22" ]; then
    echo "install.sh: expected OTP 22, found OTP ${otp}" >&2
    exit 1
fi

if [ ! -s "$EMK_DIR/erlang.mk" ]; then
    EMK_DIR="$(mktemp -d)"
    git clone --quiet https://github.com/ninenines/erlang.mk "$EMK_DIR"
    git -C "$EMK_DIR" checkout --quiet "$ERLANG_MK_COMMIT"
    make -C "$EMK_DIR" >/dev/null
fi

# Never run `make deps` or plain `make`: its clean-deps step deletes this pinned
# erlang.mk and re-bootstraps the latest one, which fails on OTP 22.
cmp -s "$EMK_DIR/erlang.mk" erlang.mk || cp "$EMK_DIR/erlang.mk" erlang.mk
mkdir -p .erlang.mk

exclude="$(git rev-parse --git-path info/exclude)"
mkdir -p "$(dirname "$exclude")"
touch "$exclude"
for pattern in /erlang.mk /.erlang.mk/ /deps/ '/make/.deps.mk.*' ebin/ '*.beam' '*.app' .eunit/ .deps.rules .test.deps '*.coverdata'; do
    grep -qxF -- "$pattern" "$exclude" || echo "$pattern" >> "$exclude"
done

deps_marker="make/.deps.mk.$(md5sum make/deps.mk | cut -d' ' -f1)"
if [ ! -f "$deps_marker" ] || [ ! -f deps/Makefile ]; then
    rm -rf deps make/.deps.mk.*
    mkdir -p deps
    make -f erlang.mk deps
    cp make/Makefile.deps deps/Makefile
    for attempt in 1 2 3; do
        make -C deps all && break
        if [ "$attempt" = 3 ]; then
            echo "install.sh: deps build failed after 3 attempts" >&2
            exit 1
        fi
        sleep 10
    done
    touch "$deps_marker"
fi

make core JOBS="$(nproc)"
make -C applications/callflow
make -C applications/crossbar

echo "install.sh: ready (OTP ${otp}, $(ls deps | wc -l | tr -d ' ') deps entries)"
