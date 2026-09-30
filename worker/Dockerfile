FROM node:22-alpine

WORKDIR /worker

RUN apk add --no-cache curl \
  && mkdir -p /etc/ssl/certs \
  && curl -fsSL -o /etc/ssl/certs/rds-global-bundle.pem \
  https://truststore.pki.rds.amazonaws.com/global/global-bundle.pem

COPY --chown=node:node package*.json ./
RUN npm ci --omit=dev

COPY --chown=node:node src ./src

USER node
CMD ["node", "src/worker.js"]
