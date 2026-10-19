import {WorkerError, MAX_OUTPUT, resultFor, validate} from './contract.mjs';

export const resourceOptions = Object.freeze({idleTimeoutMinutes:1, resources:{cpu:1, memoryGB:2}, networkIsolation:'ISOLATED', domains:[], env:{}});

export async function bounded(operation, milliseconds, late) {
  let timer, expired = false;
  const work = Promise.resolve().then(operation);
  // A create can finish after our deadline. Destroy that late VM as well.
  work.then(value => { if (expired && late) Promise.resolve(late(value)).catch(() => {}); }, () => {});
  try {
    return await Promise.race([work, new Promise((_, reject) => { timer = setTimeout(() => { expired = true; reject(new WorkerError('provider_timeout')); }, milliseconds); })]);
  } finally { clearTimeout(timer); }
}

export function assertSandbox(sandbox, config) {
  if (sandbox.environmentId !== config.environmentId || sandbox.networkIsolation !== 'ISOLATED' || sandbox.domains.length !== 0 || sandbox.idleTimeoutMinutes !== 1) throw new WorkerError('sandbox_policy_mismatch');
}

export async function destroySandbox(sandbox) {
  await bounded(() => sandbox.destroy(), 15000);
}

async function lateCleanup(sandbox, state, record) {
  record.sandbox_id = sandbox.id; record.phase = 'cleanup_pending';
  await state.save(record);
  try { await destroySandbox(sandbox); record.sandbox_id = null; }
  finally { await state.save(record); }
}

export async function execute(payload, {Sandbox, config, state, record, signal}) {
  validate(payload);
  const start = performance.now();
  let sandbox, result = resultFor(payload, {status:'infrastructure_error', exit_code:null, output:'Execution infrastructure did not complete.'});
  try {
    if (signal?.aborted) throw new WorkerError('worker_stopping');
    sandbox = await bounded(() => Sandbox.create(config.checkpoint, {...config.connection, ...resourceOptions}), 30000, value => lateCleanup(value, state, record));
    record.sandbox_id = sandbox.id; record.phase = 'running'; await state.save(record);
    assertSandbox(sandbox, config);
    const probe = await bounded(() => sandbox.exec('/bin/bash /opt/runner/launch.sh 10 probe', {timeoutSec:12, maxOutputBytes:8192, ephemeral:true, signal}), 18000);
    if (probe.exitCode !== 0 || probe.timedOut || probe.truncated) throw new WorkerError('runtime_isolation_unavailable');
    if (signal?.aborted) throw new WorkerError('worker_stopping');
    await bounded(() => sandbox.files.write('/opt/runner/job.json', JSON.stringify({files:payload.files}), {mode:0o600}), 15000);
    let output = Buffer.alloc(0), exceeded = false;
    const controller = new AbortController();
    const aborted = () => controller.abort(new WorkerError('worker_stopping'));
    signal?.addEventListener('abort', aborted, {once:true});
    if (signal?.aborted) aborted();
    const capture = chunk => {
      const bytes = Buffer.from(chunk);
      const available = MAX_OUTPUT - output.length;
      output = Buffer.concat([output, bytes.subarray(0, available)]);
      if (bytes.length > available) { exceeded = true; controller.abort(new WorkerError('output_limit')); }
    };
    try {
      const mode = payload.exercise.endsWith('.prepare.v1') ? 'prepare' : 'tests';
      const execution = await bounded(() => sandbox.exec(`/bin/bash /opt/runner/launch.sh ${payload.timeout_seconds} ${mode}`, {
        timeoutSec:payload.timeout_seconds + 5, signal:controller.signal, ephemeral:true,
        captureOutput:false, maxOutputBytes:MAX_OUTPUT, onStdout:capture, onStderr:capture
      }), (payload.timeout_seconds + 16) * 1000);
      const status = exceeded || execution.truncated ? 'output_limit' : execution.timedOut || execution.exitCode === 124 ? 'timed_out' :
        execution.exitCode === 0 ? 'execution_completed' : [70,137,null].includes(execution.exitCode) || execution.exitCode < 0 ? 'infrastructure_error' : 'execution_failed';
      result = resultFor(payload, {status, exit_code:execution.exitCode, output:output.toString('utf8'), output_truncated:exceeded || execution.truncated});
    } catch (error) {
      result = resultFor(payload, {status:exceeded ? 'output_limit' : 'infrastructure_error', exit_code:null,
        output:output.toString('utf8') + (exceeded ? '' : '\nExecution interrupted; no successful result was confirmed.'), output_truncated:exceeded});
    } finally { signal?.removeEventListener('abort', aborted); }
  } catch (error) {
    result = resultFor(payload, {status:'infrastructure_error', exit_code:null, output:`Runtime unavailable (${error instanceof WorkerError ? error.code : 'provider_error'}). No candidate outcome was inferred.`});
  } finally {
    if (sandbox) {
      try { await destroySandbox(sandbox); record.sandbox_id = null; }
      catch { result.status = 'infrastructure_error'; result.cleanup_error = 'Sandbox destruction was not confirmed; cleanup will retry.'; }
    }
    result.output = new TextDecoder().decode(Buffer.from(result.output).subarray(0, MAX_OUTPUT), {stream:true});
    result.duration_seconds = Math.round((performance.now() - start) / 10) / 100;
    record.phase = record.sandbox_id ? 'cleanup_pending' : 'finished'; record.result = result;
    await state.save(record);
  }
  return result;
}

export async function bootstrap({Sandbox, config, assets, state, record, signal}) {
  let sandbox;
  try {
    if (signal?.aborted) throw new WorkerError('worker_stopping');
    sandbox = await bounded(() => Sandbox.create({...config.connection, ...resourceOptions}), 30000, value => lateCleanup(value, state, record));
    record.sandbox_id = sandbox.id; record.phase = 'building'; record.deadline_at = Date.now() + 720000; await state.save(record);
    assertSandbox(sandbox, config);
    for (const asset of assets.assets) {
      if (signal?.aborted) throw new WorkerError('worker_stopping');
      await bounded(() => sandbox.files.write(asset.path, asset.data, {mode:asset.mode}), 15000);
    }
    const build = await bounded(() => sandbox.exec('/bin/bash /opt/runner/bootstrap.sh', {timeoutSec:600, maxOutputBytes:65536, ephemeral:true, signal}), 615000);
    if (build.exitCode !== 0 || build.timedOut) throw new WorkerError('bootstrap_failed');
    const probe = await bounded(() => sandbox.exec('/bin/bash /opt/runner/launch.sh 10 probe', {timeoutSec:12, maxOutputBytes:8192, ephemeral:true, signal}), 18000);
    if (probe.exitCode !== 0 || probe.timedOut) throw new WorkerError('runtime_isolation_unavailable');
    const starter = assets.assets.find(asset => asset.path === '/opt/exercise/app/controllers/events_controller.rb');
    await sandbox.files.write('/opt/runner/job.json', JSON.stringify({files:{'app/controllers/events_controller.rb':starter.data.toString('base64')}}), {mode:0o600});
    const prepared = await bounded(() => sandbox.exec('/bin/bash /opt/runner/launch.sh 60 prepare', {timeoutSec:65, maxOutputBytes:8192, ephemeral:true, signal}), 76000);
    if (prepared.exitCode !== 0 || prepared.timedOut) throw new WorkerError('rails_preparation_failed');
    const reset = await bounded(() => sandbox.exec('find /workspace -mindepth 1 -delete', {timeoutSec:10, maxOutputBytes:8192, ephemeral:true, signal}), 20000);
    if (reset.exitCode !== 0) throw new WorkerError('checkpoint_reset_failed');
    if (signal?.aborted) throw new WorkerError('worker_stopping');
    await bounded(() => sandbox.checkpoint(assets.checkpoint), 60000);
    record.phase = 'checkpoint_ready';
    return {checkpoint:assets.checkpoint, digest:assets.digest};
  } finally {
    if (sandbox) {
      try { await destroySandbox(sandbox); record.sandbox_id = null; }
      finally { await state.save(record); }
    }
  }
}
