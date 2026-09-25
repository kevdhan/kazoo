# Cursor cloud agent base image for KAZOO (OTP 22, matches make/erlang_version).
# erlang:22 is Debian buster; its apt repositories are archived, so do not
# apt-get update. git, make, gcc, python3 and wget are already present.
# Pulled from the AWS mirror of the Docker official image; Docker Hub's
# anonymous token endpoint is unreliable from build workers.
FROM public.ecr.aws/docker/library/erlang:22

# Latest erlang.mk requires OTP 23+ and has dropped the package index, so the
# bootstrap in `make deps` fails on OTP 22. install.sh copies this pinned build.
ARG ERLANG_MK_COMMIT=82179575d9191305805c8e6e8107be7c3f80a6be
RUN git clone --quiet https://github.com/ninenines/erlang.mk /opt/emk \
 && git -C /opt/emk checkout --quiet "${ERLANG_MK_COMMIT}" \
 && make -C /opt/emk >/dev/null \
 && test -s /opt/emk/erlang.mk
