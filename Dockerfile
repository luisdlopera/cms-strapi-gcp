FROM node:22-bookworm-slim AS build
WORKDIR /opt/app
COPY package*.json ./
RUN npm ci
COPY . .
RUN npm run build && npm prune --omit=dev

FROM node:22-bookworm-slim AS runtime
ENV NODE_ENV=production
WORKDIR /opt/app
COPY --from=build --chown=node:node /opt/app ./
USER node
EXPOSE 1337
CMD ["npm", "run", "start"]
