FROM node:lts
WORKDIR /app

# Copy dependency definitions
COPY package*.json ./

# Install dependencies
RUN npm install

# Copy application files
COPY . .

# Expose Hardhat default port
EXPOSE 8545

# Make entrypoint executable
RUN chmod +x docker-entrypoint.sh

ENTRYPOINT ["./docker-entrypoint.sh"]
