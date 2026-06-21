# Tessera self-hosted server — dev image (one-command local stack).
FROM node:22-slim
WORKDIR /app

COPY package*.json tsconfig.json tsconfig.build.json ./
RUN npm ci || npm install

COPY src ./src
RUN npm run build

EXPOSE 3001
# Append-only ballot log + server key live here — mount a volume to persist them.
ENV DATA_DIR=/app/data
CMD ["node", "dist/index.js"]
