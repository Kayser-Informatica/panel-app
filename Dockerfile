FROM node:8 AS build

WORKDIR /app

COPY . /app

RUN npm install && \
    npm run build:web && \
    ls -la /app/dist/ && \
    ls -la /app/dist/web/ || echo "ERROR: dist/web directory not found!"

FROM nginx:alpine

COPY --from=build --chown=nginx:nginx /app/dist/web /usr/share/nginx/html

EXPOSE 80

CMD ["nginx", "-g", "daemon off;"]
