FROM node:16-alpine AS build

WORKDIR /app

# Copy package files
COPY package*.json ./

# Install dependencies
RUN npm install

# Copy source code
COPY . .

# Build web version
RUN npm run build:web

# Verify build output exists
RUN ls -la /app/dist/web || (echo "Build failed - dist/web directory not found" && exit 1)

FROM nginx:alpine

# Copy built files from build stage
COPY --from=build --chown=nginx:nginx /app/dist/web /usr/share/nginx/html

EXPOSE 80

CMD ["nginx", "-g", "daemon off;"]
