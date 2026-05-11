FROM node:18-alpine

WORKDIR /app

RUN apk add --no-cache curl \
  && mkdir -p /etc/ssl/certs \
  && curl -fsSL -o /etc/ssl/certs/rds-global-bundle.pem \
  https://truststore.pki.rds.amazonaws.com/global/global-bundle.pem

COPY package*.json ./
RUN npm ci --only=production

COPY . .

EXPOSE 3000

CMD ["node", "src/index.js"]