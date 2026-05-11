FROM node:18-alpine

WORKDIR /worker

RUN apk add --no-cache curl \
  && mkdir -p /etc/ssl/certs \
  && curl -fsSL -o /etc/ssl/certs/rds-global-bundle.pem \
  https://truststore.pki.rds.amazonaws.com/global/global-bundle.pem

COPY package*.json ./
RUN npm ci --only=production

COPY src ./src

CMD ["npm", "start"]
