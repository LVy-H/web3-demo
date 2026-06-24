FROM node:22-alpine
# docker CLI so the control plane can drive the host runtime via the mounted socket
RUN apk add --no-cache docker-cli
WORKDIR /app
COPY package*.json ./
RUN npm ci
COPY . .
RUN npm run build
ENV PORT=8787 ADMIN_PORT=8786 DATA_DIR=/app/control-data
EXPOSE 8787
CMD ["node", "dist/index.js"]
