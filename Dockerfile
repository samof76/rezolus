FROM --platform=$BUILDPLATFORM rust:1.89.0 AS builder

# Install cross-compilation tools and libraries for both architectures
RUN dpkg --add-architecture arm64 && \
    apt-get update && apt-get install -y \
    clang \
    build-essential \
    gcc-aarch64-linux-gnu \
    libelf-dev \
    zlib1g-dev \
    libbpf-dev \
    libelf-dev:arm64 \
    zlib1g-dev:arm64 \
    libbpf-dev:arm64 \
    && rm -rf /var/lib/apt/lists/*

# Set up working directory
WORKDIR /app

# Copy Cargo files
COPY . .

RUN rustup target add x86_64-unknown-linux-gnu && \
    rustup target add aarch64-unknown-linux-gnu && \
    rustup component add rustfmt

# Define build argument for target platform
ARG TARGETPLATFORM
ARG TARGETARCH

# Set up cross-compilation environment
RUN case "$TARGETPLATFORM" in \
    "linux/amd64") \
    export CARGO_TARGET_X86_64_UNKNOWN_LINUX_GNU_LINKER=x86_64-linux-gnu-gcc &&\
    export PKG_CONFIG_PATH=/usr/lib/x86_64-linux-gnu/pkgconfig &&\
    cargo build --release --target x86_64-unknown-linux-gnu && \
    cp target/x86_64-unknown-linux-gnu/release/rezolus /app/rezolus \
    ;; \
    "linux/arm64") \
    export CARGO_TARGET_AARCH64_UNKNOWN_LINUX_GNU_LINKER=aarch64-linux-gnu-gcc &&\
    export PKG_CONFIG_PATH=/usr/lib/aarch64-linux-gnu/pkgconfig &&\
    cargo build --release --target aarch64-unknown-linux-gnu && \
    cp target/aarch64-unknown-linux-gnu/release/rezolus /app/rezolus \
    ;; \
    esac

# Latest releases available at https://github.com/aptible/supercronic/releases
ENV SUPERCRONIC_URL=https://github.com/aptible/supercronic/releases/download/v0.2.34/supercronic-linux-${TARGETARCH} \
    SUPERCRONIC=supercronic-linux-${TARGETARCH}

# Setup Supercronic
RUN curl -fsSLO "$SUPERCRONIC_URL" \
    && chmod +x "$SUPERCRONIC" \
    && mv "$SUPERCRONIC" "/usr/local/bin/supercronic"

RUN wget -O /usr/local/bin/dumb-init https://github.com/Yelp/dumb-init/releases/download/v1.2.2/dumb-init_1.2.2_${TARGETARCH} \
    && chmod +x /usr/local/bin/dumb-init

FROM --platform=$BUILDPLATFORM rclone/rclone:master AS rclone

# Final stage: create minimal runtime image
FROM debian:trixie-20250811-slim

# Install runtime dependencies
RUN dpkg --add-architecture arm64 && \
    apt-get update && apt-get install -y \
    ca-certificates \
    libelf1 \
    zlib1g \
    libbpf-dev \
    libelf1:arm64 \
    zlib1g:arm64 \
    libbpf-dev:arm64 \
    && rm -rf /var/lib/apt/lists/*

# Copy the built binary
COPY --from=builder /app/rezolus /usr/local/bin/rezolus
COPY --from=builder /usr/local/bin/supercronic /usr/local/bin/supercronic
COPY --from=builder /usr/local/bin/dumb-init /usr/local/bin/dumb-init
COPY --from=rclone /usr/local/bin/rclone /usr/local/bin/rclone

# Runs "/usr/bin/dumb-init -- /my/script --with --args"
ENTRYPOINT ["/usr/local/bin/dumb-init", "--"]
