# Tessera self-hosted server — dev image (one-command local stack).
FROM node:22-slim
WORKDIR /app

COPY package*.json tsconfig.json ./
RUN npm ci || npm install

COPY src ./src
RUN npm run build

EXPOSE 3001
CMD ["node", "dist/index.js"]
