FROM node:20-slim

WORKDIR /app

# Install dependencies first for better caching
COPY package*.json ./
RUN npm install --omit=dev

# Copy application source
COPY src/ ./src/

# Expose port
EXPOSE 8000

# Run as non-root user
USER node

# Start the application
CMD ["node", "src/app.js"]
