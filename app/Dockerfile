FROM node:22-alpine

WORKDIR /app

RUN apk add --no-cache curl \
  && mkdir -p /etc/ssl/certs \
  && curl -fsSL -o /etc/ssl/certs/rds-global-bundle.pem \
  https://truststore.pki.rds.amazonaws.com/global/global-bundle.pem

COPY package*.json ./
RUN npm ci --omit=dev

COPY . .

EXPOSE 3000

CMD ["node", "src/index.js"]