# Pinned to bookworm-slim. Image digest pinning (FROM ...@sha256:<digest>)
# is the stronger form but requires registry access; the manifest lookup
# (`docker manifest inspect node:22-bookworm-slim`) was unreachable from
# the build host at patch time, so we fall back to the tag-only form.
# Re-pin to a digest once the registry is reachable.
FROM node:22-bookworm-slim
RUN apt-get update \
    && apt-get install -y --no-install-recommends curl \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*
WORKDIR /app
COPY package*.json ./
RUN npm install
COPY . .
RUN chmod +x docker-entrypoint.sh
EXPOSE 3001
CMD ["./docker-entrypoint.sh"]
