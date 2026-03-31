FROM node:18-alpine

WORKDIR /app

RUN addgroup -g 1001 -S nodeapp && adduser -S nodeapp -u 1001 -G nodeapp

COPY package.json package-lock.json* ./
RUN if [ -f package-lock.json ]; then npm ci --omit=dev; else npm install --omit=dev; fi

COPY . .
RUN chown -R nodeapp:nodeapp /app

USER nodeapp

EXPOSE 3000
CMD ["node", "index.js"]
