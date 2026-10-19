#!/usr/bin/env node
import {randomUUID} from 'node:crypto';
import {resolve} from 'node:path';
import {Sandbox} from 'railway';
import {loadAssets} from './assets.mjs';
import {State} from './state.mjs';
import {bridge, checkpointReady, configFromEnv, reconcile, transport} from './bridge.mjs';
import {bootstrap, execute} from './runtime.mjs';
import {verify, WorkerError} from './contract.mjs';

try {
  const [command = 'doctor', ...args] = process.argv.slice(2);
  if (!['doctor','check','plan','bootstrap','bridge','reap','run'].includes(command) || args.some(arg => arg !== '--once')) throw new WorkerError('usage: node cli.mjs doctor|check|plan|bootstrap|bridge|reap|run [--once]');
  const assets = await loadAssets(), config = {...configFromEnv(), checkpoint:assets.checkpoint};
  if (command === 'plan' || command === 'doctor') {
    console.log(JSON.stringify({ready:config.enabled, issues:config.issues, executed:false, checkpoint:assets.checkpoint,
      assets:assets.assets.length, isolation:'ISOLATED VM plus required non-root network/PID/mount namespaces',
      resources:{cpu:1, memoryGB:2, idleTimeoutMinutes:1}, daily_job_limit:config.dailyLimit}, null, 2));
    if (command === 'doctor' && !config.enabled) process.exitCode = 2;
  } else {
    if (!config.enabled) throw new WorkerError(`configuration_incomplete: ${config.issues.join(', ')}`);
    const state = new State(process.env.INTERVIEW_WORKER_STATE || resolve(import.meta.dirname, '.state'));
    await state.init();
    const controller = new AbortController();
    for (const signal of ['SIGINT','SIGTERM']) process.once(signal, () => controller.abort(new WorkerError('worker_stopping')));
    const dependencies = {Sandbox, config, state, request:transport(config.base, config.bridgeKey), signal:controller.signal};
    if (command === 'check') {
      await checkpointReady(Sandbox, config);
      console.log(JSON.stringify({status:'checkpoint_available', checkpoint:assets.checkpoint, executed:false}));
    } else if (command === 'bootstrap') {
      await reconcile(dependencies);
      if ((await state.records()).some(record => record.sandbox_id)) throw new WorkerError('cleanup_or_previous_execution_pending');
      const record = await state.claim({job_id:randomUUID()}, null);
      console.log(JSON.stringify({status:'preparing_runtime', checkpoint:assets.checkpoint}));
      console.log(JSON.stringify(await bootstrap({...dependencies, assets, record})));
    } else if (command === 'reap') {
      await reconcile(dependencies);
      console.log(JSON.stringify({cleanup_pending:(await state.records()).filter(record => record.sandbox_id).length}));
    } else if (command === 'run') {
      // Direct signed-job entry point for opt-in integration verification. There
      // is no local-code fallback, and manual runs consume the same job quota.
      const chunks = []; let bytes = 0;
      for await (const chunk of process.stdin) {
        bytes += chunk.length;
        if (bytes > 2 * 1024 * 1024) throw new WorkerError('job_request_limit');
        chunks.push(chunk);
      }
      const payload = verify(JSON.parse(Buffer.concat(chunks)), config.signingKey);
      await reconcile(dependencies);
      if ((await state.records()).some(record => record.sandbox_id)) throw new WorkerError('cleanup_or_previous_execution_pending');
      const today = new Date().toISOString().slice(0,10);
      const used = (await state.records()).filter(record => record.payload.tenant_id && new Date(record.created_at).toISOString().slice(0,10) === today).length;
      if (used >= config.dailyLimit) throw new WorkerError('daily_job_limit_reached');
      await checkpointReady(Sandbox, config);
      const record = await state.claim(payload, null);
      console.log(JSON.stringify(await execute(payload, {...dependencies, record})));
    } else await bridge(dependencies, {once:args.includes('--once')});
  }
} catch (error) {
  // Never print provider HTTP bodies, environment values, or lease credentials.
  console.error(JSON.stringify({status:'worker_stopped', error:error instanceof WorkerError ? error.code : 'provider_or_local_configuration_error'}));
  process.exitCode = 2;
}
