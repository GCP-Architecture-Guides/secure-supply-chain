# Baseline image for contrast: full Node image, runs as root, no hardening.
FROM node:18

WORKDIR /app

COPY package.json package-lock.json* ./
# Use npm ci when lockfile is present (CI); otherwise npm install for local builds.
RUN if [ -f package-lock.json ]; then npm ci --omit=dev; else npm install --omit=dev; fi

COPY . .

EXPOSE 3000
CMD ["node", "index.js"]
