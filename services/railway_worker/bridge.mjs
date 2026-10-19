import {setTimeout as sleep} from 'node:timers/promises';
import {WorkerError, UUID, OPERATIONS, resultFor, verify} from './contract.mjs';
import {bounded, destroySandbox, execute} from './runtime.mjs';

export function origin(value) {
  let url;
  try { url = new URL(value); } catch { throw new WorkerError('invalid_control_plane_url'); }
  if (url.username || url.password || url.search || url.hash || url.pathname !== '/' ||
      (url.protocol !== 'https:' && !(url.protocol === 'http:' && ['localhost','127.0.0.1','[::1]'].includes(url.hostname)))) throw new WorkerError('invalid_control_plane_url');
  return url.origin;
}

export class HttpError extends WorkerError {
  constructor(status) { super('control_plane_http_error'); this.status = status; }
}

export function transport(base, key, fetchImpl = fetch) {
  base = origin(base);
  return async (path, data) => {
    const response = await fetchImpl(base + path, {method:'POST', redirect:'error', signal:AbortSignal.timeout(15000),
      headers:{Authorization:`Bearer ${key}`, 'Content-Type':'application/json'}, body:JSON.stringify(data)});
    if (!response.ok) { await response.body?.cancel(); throw new HttpError(response.status); }
    const chunks = []; let bytes = 0;
    for await (const chunk of response.body) {
      bytes += chunk.byteLength;
      if (bytes > 2 * 1024 * 1024) throw new WorkerError('control_plane_response_limit');
      chunks.push(Buffer.from(chunk));
    }
    return JSON.parse(Buffer.concat(chunks).toString('utf8'));
  };
}

export function configFromEnv(env = process.env) {
  const issues = [];
  if (env.INTERVIEW_RAILWAY_EXECUTION_ENABLED !== '1') issues.push('execution_disabled');
  if (!env.RAILWAY_API_TOKEN) issues.push('railway_api_token_missing');
  if (!UUID.test(env.RAILWAY_ENVIRONMENT_ID || '')) issues.push('railway_environment_id_missing');
  if (!UUID.test(env.INTERVIEW_WORKER_ID || '')) issues.push('worker_id_missing');
  if (Buffer.byteLength(env.INTERVIEW_WORKER_BRIDGE_KEY || '') < 32) issues.push('bridge_key_missing');
  if (Buffer.byteLength(env.INTERVIEW_WORKER_SIGNING_KEY || '') < 32) issues.push('signing_key_missing');
  let base;
  try { base = origin(env.INTERVIEW_CONTROL_PLANE_URL); } catch { issues.push('control_plane_url_missing_or_invalid'); }
  const dailyLimit = Number(env.INTERVIEW_RAILWAY_DAILY_JOB_LIMIT || 10);
  if (!Number.isInteger(dailyLimit) || dailyLimit < 1 || dailyLimit > 100) issues.push('invalid_daily_job_limit');
  return {issues, enabled:issues.length === 0, environmentId:env.RAILWAY_ENVIRONMENT_ID, workerId:env.INTERVIEW_WORKER_ID,
    bridgeKey:env.INTERVIEW_WORKER_BRIDGE_KEY, signingKey:env.INTERVIEW_WORKER_SIGNING_KEY, base, dailyLimit,
    // Explicit auth avoids inheriting a CLI/project token or custom API endpoint.
    connection:{token:env.RAILWAY_API_TOKEN, environmentId:env.RAILWAY_ENVIRONMENT_ID, authType:'bearer', verbose:false,
      fetch:(url, options) => fetch(url, {...options, redirect:'error', signal:AbortSignal.timeout(20000)})}};
}

export async function checkpointReady(Sandbox, config) {
  const checkpoints = await bounded(() => Sandbox.checkpoints(config.connection), 25000);
  if (!checkpoints.some(checkpoint => checkpoint.key === config.checkpoint)) throw new WorkerError('checkpoint_not_built');
}

export async function reconcile({Sandbox, config, state}, now = Date.now()) {
  for (const record of await state.records()) {
    if (record.sandbox_id && (record.result || record.deadline_at <= now)) {
      try {
        const sandbox = await bounded(() => Sandbox.connect(record.sandbox_id, config.connection), 25000);
        if (sandbox.environmentId !== config.environmentId) throw new WorkerError('cleanup_environment_mismatch');
        await destroySandbox(sandbox); record.sandbox_id = null;
      } catch (error) { if (error.name === 'SandboxNotFoundError') record.sandbox_id = null; }
      await state.save(record);
    }
    if (!record.result && record.lease_token && record.deadline_at <= now) {
      record.result = resultFor(record.payload, {status:'infrastructure_error', exit_code:null, output:'Worker interrupted before a confirmed result. Run again explicitly.'});
      record.phase = record.sandbox_id ? 'cleanup_pending' : 'finished';
      await state.save(record);
    }
  }
}

export async function deliverPending(state, request) {
  for (const record of await state.records()) {
    if (!record.result || !record.lease_token || record.delivered || record.rejected) continue;
    try {
      await request(`/internal/executions/${record.job_id}/result`, {lease_token:record.lease_token, result:record.result});
      record.delivered = true;
    } catch (error) {
      if (![404,409].includes(error.status)) throw error;
      record.rejected = error.status;
    }
    await state.save(record);
  }
}

export async function runCycle(dependencies) {
  const {Sandbox, config, state, request, signal} = dependencies;
  await reconcile(dependencies);
  await deliverPending(state, request);
  if ((await state.records()).some(record => record.sandbox_id)) throw new WorkerError('cleanup_or_previous_execution_pending');
  const today = new Date().toISOString().slice(0,10);
  const used = (await state.records()).filter(record => record.payload.tenant_id && new Date(record.created_at).toISOString().slice(0,10) === today).length;
  if (used >= config.dailyLimit) return {status:'daily_job_limit_reached'};
  if (signal?.aborted) return {status:'stopped'};
  const heartbeat = () => request('/internal/workers/heartbeat', {worker_id:config.workerId, capabilities:OPERATIONS});
  await heartbeat();
  const leased = await request('/internal/workers/lease', {worker_id:config.workerId});
  if (!leased.job) return {status:'idle'};
  const payload = verify(leased.job, config.signingKey);
  const record = await state.claim(payload, leased.lease_token);
  const keepAlive = setInterval(() => heartbeat().catch(() => {}), 15000);
  try { await execute(payload, {...dependencies, record}); }
  finally { clearInterval(keepAlive); }
  await deliverPending(state, request);
  return {job_id:payload.job_id, status:record.result.status};
}

export async function bridge(dependencies, {once = false, log = console.log} = {}) {
  await checkpointReady(dependencies.Sandbox, dependencies.config);
  let previousMessage, delay = 2000;
  while (!dependencies.signal?.aborted) {
    let message;
    try { message = JSON.stringify(await runCycle(dependencies)); delay = 2000; }
    catch (error) { message = JSON.stringify({status:'worker_waiting', error:error instanceof WorkerError ? error.code : 'connection_or_provider_error'}); delay = Math.min(delay * 2, 30000); }
    if (message !== previousMessage) log(message);
    previousMessage = message;
    if (once) break;
    try { await sleep(delay, undefined, {signal:dependencies.signal}); } catch { break; }
  }
}
