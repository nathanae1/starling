# Multi-stage build for the Starling relay. Produces a static musl binary
# in a distroless runtime (single process — no C-tor, no Python, no
# supervisord).
#
# Build from the repo root so the `relay/` workspace and the shared
# `starling-arti` crate are both in context:
#   docker build -f relay/docker/Dockerfile -t starling-relay .

# ---- builder ----------------------------------------------------------------
FROM rust:1-bookworm AS builder

# zig + cargo-zigbuild give painless musl cross-compiles (incl. ring/rustls).
ARG ZIG_VERSION=0.13.0
RUN apt-get update && apt-get install -y --no-install-recommends xz-utils ca-certificates \
    && rm -rf /var/lib/apt/lists/*
RUN ARCH="$(uname -m)" \
    && curl -sSL "https://ziglang.org/download/${ZIG_VERSION}/zig-linux-${ARCH}-${ZIG_VERSION}.tar.xz" \
       | tar -xJ -C /opt \
    && ln -s "/opt/zig-linux-${ARCH}-${ZIG_VERSION}/zig" /usr/local/bin/zig
RUN cargo install cargo-zigbuild

# Pick the musl target for the build platform's arch.
ARG TARGETARCH
RUN case "${TARGETARCH}" in \
      amd64) echo x86_64-unknown-linux-musl > /target.txt ;; \
      arm64) echo aarch64-unknown-linux-musl > /target.txt ;; \
      *) echo "unsupported arch ${TARGETARCH}" && exit 1 ;; \
    esac
RUN rustup target add "$(cat /target.txt)"

WORKDIR /src
COPY . .
RUN cargo zigbuild --release --manifest-path relay/Cargo.toml \
        -p starling-relay --target "$(cat /target.txt)" \
    && cp "relay/target/$(cat /target.txt)/release/starling-relay" /starling-relay

# Empty skeleton for the data dir — distroless has no shell to mkdir with.
RUN mkdir -p /data

# ---- runtime ----------------------------------------------------------------
FROM gcr.io/distroless/static:nonroot
COPY --from=builder /starling-relay /usr/local/bin/starling-relay
# The relay runs as distroless `nonroot` (uid 65532) and must own its data
# dir. Numeric ids avoid a passwd lookup; this COPY must precede VOLUME
# (changes to a volume path after the VOLUME instruction are discarded).
# Named volumes inherit this ownership on first use; bind mounts must be
# `chown -R 65532:65532` on the host.
COPY --from=builder --chown=65532:65532 /data /var/lib/starling-relay
VOLUME ["/var/lib/starling-relay"]
EXPOSE 8088
# Admin UI stays on the config default (127.0.0.1:8088) — unreachable from
# outside the container until the operator opts in. To expose it: set a
# password first (`docker run … set-password`), then run with
# `-e STARLING_RELAY_BIND_ADMIN=0.0.0.0:8088 -p 127.0.0.1:8088:8088`.
ENV STARLING_RELAY_DATA_DIR=/var/lib/starling-relay
ENTRYPOINT ["/usr/local/bin/starling-relay"]
CMD ["serve"]
