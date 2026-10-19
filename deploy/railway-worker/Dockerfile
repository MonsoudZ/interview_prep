FROM node:22-bookworm-slim
WORKDIR /app/services/railway_worker
COPY services/railway_worker/package.json services/railway_worker/package-lock.json ./
RUN npm ci --ignore-scripts --no-audit --no-fund
COPY services/railway_worker/*.mjs ./
COPY services/railway_worker/runtime ./runtime
COPY experiments/rails-runtime/template /app/experiments/rails-runtime/template
COPY services/execution_worker/image/dependencies/Gemfile.lock /app/services/execution_worker/image/dependencies/Gemfile.lock
COPY services/execution_worker/image/run.rb /app/services/execution_worker/image/run.rb
RUN mkdir -p /var/lib/interview-worker && chown node:node /var/lib/interview-worker
ENV NODE_ENV=production INTERVIEW_WORKER_STATE=/var/lib/interview-worker
USER node
CMD ["node", "cli.mjs", "bridge"]
