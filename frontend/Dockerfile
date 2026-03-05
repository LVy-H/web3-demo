FROM node:lts
WORKDIR /app

# Copy dependency definitions
COPY package*.json ./

# Install dependencies
RUN npm install

# Copy application files
COPY . .

# Bind Vite to all network interfaces
ENV HOST=0.0.0.0

# Expose frontend port
EXPOSE 5173

# Start the application, passing host so the container exposes the port
CMD ["npm", "run", "dev", "--", "--host", "0.0.0.0"]
