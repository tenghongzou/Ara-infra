FROM node:22-alpine

RUN corepack enable && corepack prepare pnpm@latest --activate

WORKDIR /app

COPY administration/package.json administration/pnpm-lock.yaml ./

RUN pnpm install --frozen-lockfile

COPY administration/ .

EXPOSE 3000

CMD ["pnpm", "dev", "--host"]
