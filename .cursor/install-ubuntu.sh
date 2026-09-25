#!/usr/bin/env bash
# Fallback for images without a Dockerfile base (Cursor's default Ubuntu 24.04).
# Installs a precompiled OTP 22 into /opt/otp22, OpenSSL 1.1 (which that build
# links against), and the pinned erlang.mk into /opt/emk, then runs install.sh.
# Idempotent: a prepared machine only reruns install.sh. Runs from the repo root.
set -euo pipefail

cd "$(git rev-parse --show-toplevel)"

OTP_VERSION=22.3.4.27
OTP_DIR=/opt/otp22
EMK_DIR=/opt/emk
ERLANG_MK_COMMIT=82179575d9191305805c8e6e8107be7c3f80a6be
OPENSSL_SRC_VERSION=1.1.1w

SUDO=""
[ "$(id -u)" = 0 ] || SUDO=sudo
export DEBIAN_FRONTEND=noninteractive

# OTP 22 is only published for Ubuntu 20.04; it runs on 24.04 once libssl1.1 is present.
case "$(dpkg --print-architecture)" in
    amd64)
        otp_url="https://builds.hex.pm/builds/otp/ubuntu-20.04/OTP-${OTP_VERSION}.tar.gz"
        ssl_pool=http://archive.ubuntu.com/ubuntu/pool/main/o/openssl/
        ;;
    arm64)
        otp_url="https://builds.hex.pm/builds/otp/arm64/ubuntu-20.04/OTP-${OTP_VERSION}.tar.gz"
        ssl_pool=http://ports.ubuntu.com/ubuntu-ports/pool/main/o/openssl/
        ;;
    *)
        echo "install-ubuntu.sh: unsupported architecture $(dpkg --print-architecture)" >&2
        exit 1
        ;;
esac
arch="$(dpkg --print-architecture)"

# The default image's cc/c++ are clang, but the rebar port compiler builds C++
# NIFs (jiffy) with g++ and -flto; linking those GCC LTO objects through clang
# fails ("plugin needed to handle lto object" / "cannot find -lstdc++"). Install
# g++ and the libstdc++ headers matching the default gcc so the pinned
# CC=gcc/CXX=g++ toolchain (exported before install.sh) links cleanly.
# rabbit_common's codegen invokes `python`; 24.04 only ships python3.
gcc_major="$(gcc -dumpversion 2>/dev/null | cut -d. -f1 || true)"
pkgs=(build-essential g++ ca-certificates curl wget git python3 python-is-python3 libncurses6 libtinfo6 zlib1g-dev perl)
[ -n "$gcc_major" ] && pkgs+=("libstdc++-${gcc_major}-dev")
missing=()
for p in "${pkgs[@]}"; do
    dpkg-query -W -f='${Status}' "$p" 2>/dev/null | grep -q "install ok installed" || missing+=("$p")
done
if [ "${#missing[@]}" -gt 0 ]; then
    $SUDO apt-get update -qq
    $SUDO apt-get install -y -qq --no-install-recommends "${missing[@]}"
fi

if ! ldconfig -p | grep -q 'libcrypto\.so\.1\.1 '; then
    tmp="$(mktemp -d)"
    deb="$(curl -fsSL "$ssl_pool" | grep -oE "libssl1\.1_1\.1\.1f-1ubuntu2[.0-9]*_${arch}\.deb" | sort -u -t_ -k2,2V | tail -1 || true)"
    if [ -n "$deb" ] && curl -fsSL -o "$tmp/$deb" "$ssl_pool$deb"; then
        $SUDO dpkg -i "$tmp/$deb"
    else
        echo "install-ubuntu.sh: libssl1.1 .deb unavailable, building OpenSSL ${OPENSSL_SRC_VERSION}" >&2
        curl -fsSL -o "$tmp/openssl.tar.gz" \
            "https://github.com/openssl/openssl/releases/download/OpenSSL_${OPENSSL_SRC_VERSION//./_}/openssl-${OPENSSL_SRC_VERSION}.tar.gz"
        tar -xzf "$tmp/openssl.tar.gz" -C "$tmp"
        (cd "$tmp/openssl-${OPENSSL_SRC_VERSION}" \
            && ./config shared --prefix=/opt/openssl-1.1 --openssldir=/opt/openssl-1.1/ssl >/dev/null \
            && make -j"$(nproc)" >/dev/null \
            && $SUDO make install_sw >/dev/null)
        echo /opt/openssl-1.1/lib | $SUDO tee /etc/ld.so.conf.d/openssl-1.1.conf >/dev/null
        $SUDO ldconfig
    fi
    rm -rf "$tmp"
fi

otp_release() {
    "$OTP_DIR/bin/erl" -noshell -eval 'io:put_chars(erlang:system_info(otp_release)), halt().' 2>/dev/null || true
}
if [ "$(otp_release)" != "22" ]; then
    tmp="$(mktemp -d)"
    curl -fsSL --retry 3 -o "$tmp/otp.tar.gz" "$otp_url"
    $SUDO rm -rf "$OTP_DIR"
    $SUDO mkdir -p "$OTP_DIR"
    $SUDO tar -xzf "$tmp/otp.tar.gz" -C "$OTP_DIR" --strip-components=1
    (cd "$OTP_DIR" && $SUDO ./Install -minimal "$OTP_DIR" >/dev/null)
    rm -rf "$tmp"
fi

# Symlinks cover non-login, non-interactive shells; profile.d and .bashrc cover the rest.
for bin in "$OTP_DIR"/bin/*; do
    $SUDO ln -sfn "$bin" "/usr/local/bin/$(basename "$bin")"
done
echo "export PATH=${OTP_DIR}/bin:\$PATH" | $SUDO tee /etc/profile.d/otp22.sh >/dev/null
grep -qxF "export PATH=${OTP_DIR}/bin:\$PATH" "$HOME/.bashrc" 2>/dev/null \
    || echo "export PATH=${OTP_DIR}/bin:\$PATH" >> "$HOME/.bashrc"
export PATH="${OTP_DIR}/bin:$PATH"

erl -noshell -eval 'ok = application:ensure_started(crypto), <<_:128>> = crypto:hash(md5, <<"x">>), halt().'

if [ "$(git -C "$EMK_DIR" rev-parse HEAD 2>/dev/null || true)" != "$ERLANG_MK_COMMIT" ] || [ ! -s "$EMK_DIR/erlang.mk" ]; then
    $SUDO rm -rf "$EMK_DIR"
    $SUDO git clone --quiet https://github.com/ninenines/erlang.mk "$EMK_DIR"
    $SUDO git -C "$EMK_DIR" checkout --quiet "$ERLANG_MK_COMMIT"
    $SUDO make -C "$EMK_DIR" >/dev/null
fi

# Force GCC for every C/C++ dep. The image's default `cc`/`c++` are clang, and
# mixing clang linking with g++-compiled -flto objects breaks the jiffy build.
export CC=gcc CXX=g++ AR=gcc-ar RANLIB=gcc-ranlib

# `make core JOBS=$(nproc)` occasionally loses a race (erlc exits with
# bad_directory); install.sh is idempotent, so one rerun finishes the tree.
bash .cursor/install.sh || {
    echo "install-ubuntu.sh: install.sh failed, retrying once" >&2
    bash .cursor/install.sh
}
