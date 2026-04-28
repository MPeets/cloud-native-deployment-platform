FROM node:18-alpine

WORKDIR /worker

COPY package*.json ./
RUN npm ci --only=production

COPY src ./src

CMD ["npm", "start"]
