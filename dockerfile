FROM node:lts-alpine3.9
WORKDIR /app
COPY ./package.json ./
RUN npm install
COPY . .
RUN npm run build
CMD ["npm", "run", "start:prod"]
