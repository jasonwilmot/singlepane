# Velocity — Multi-stage build for dev/test environment
# Not used for the macOS app itself, but for backend services and CI

# ── Stage 1: Build ──────────────────────────────────────────
FROM swift:6.0-jammy AS builder

ARG BUILD_CONFIG=Debug

WORKDIR /app

# Cache dependencies first
COPY Package.swift Package.resolved ./
RUN swift package resolve

# Copy source and build
COPY Sources/ Sources/
COPY Tests/ Tests/
COPY Resources/ Resources/

RUN swift build \
    --configuration $(echo $BUILD_CONFIG | tr '[:upper:]' '[:lower:]') \
    -Xswiftc -warnings-as-errors \
    -j $(nproc)

# ── Stage 2: Test ───────────────────────────────────────────
FROM builder AS tester

RUN swift test \
    --parallel \
    --filter "VelocityTests" \
    --xunit-output /app/.build/test-results.xml

# ── Stage 3: Runtime ────────────────────────────────────────
FROM swift:6.0-jammy-slim AS runtime

RUN apt-get update && apt-get install -y --no-install-recommends \
    libsqlite3-0 \
    libarchive13 \
    ca-certificates \
    curl \
    && rm -rf /var/lib/apt/lists/*

RUN groupadd -r velocity && useradd -r -g velocity -m velocity

WORKDIR /app

COPY --from=builder /app/.build/debug/VelocityServer /app/velocity-server
COPY --from=builder /app/Resources /app/Resources

RUN mkdir -p /var/lib/velocity/index /var/lib/velocity/cache \
    && chown -R velocity:velocity /var/lib/velocity /app

USER velocity

ENV VELOCITY_ENV=production
ENV VELOCITY_INDEX_PATH=/var/lib/velocity/index
ENV VELOCITY_CACHE_PATH=/var/lib/velocity/cache

EXPOSE 8080 9090

HEALTHCHECK --interval=30s --timeout=10s --retries=3 \
    CMD curl -f http://localhost:8080/health || exit 1

ENTRYPOINT ["/app/velocity-server"]
CMD ["--host", "0.0.0.0", "--port", "8080"]
