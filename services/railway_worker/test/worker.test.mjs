import test from 'node:test';
import assert from 'node:assert/strict';
import {createHmac, randomUUID} from 'node:crypto';
import {mkdtemp, readFile, rm, stat} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {Sandbox as InstalledSdk} from 'railway';
import {canonical, hash, validate, verify, MAX_OUTPUT} from '../contract.mjs';
import {State} from '../state.mjs';
import {execute, bounded, bootstrap} from '../runtime.mjs';
import {configFromEnv, origin, transport, runCycle, reconcile, deliverPending, HttpError, checkpointReady} from '../bridge.mjs';
import {loadAssets} from '../assets.mjs';

const secret = 's'.repeat(40);
function payload(files = {'app/controllers/events_controller.rb':'# fixture only\n'}) {
  const encoded = Object.fromEntries(Object.entries(files).map(([path,text]) => [path, Buffer.from(text).toString('base64')]));
  return {version:1, job_id:randomUUID(), tenant_id:randomUUID(), session_id:randomUUID(), exercise:'rails.events.v1',
    issued_at:Math.floor(Date.now()/1000), expires_at:Math.floor(Date.now()/1000)+120, timeout_seconds:60,
    source_revision:hash(canonical(Object.fromEntries(Object.entries(files).map(([path,text]) => [path,hash(text)])))), files:encoded};
}
function signed(value) { return {payload:value, signature:createHmac('sha256', secret).update(canonical(value)).digest('hex')}; }
async function fixture(t, changes = {}) {
  const directory = await mkdtemp(join(tmpdir(), 'interview-railway-'));
  t.after(() => rm(directory, {recursive:true, force:true}));
  const state = new State(directory); await state.init();
  const calls = [], config = {checkpoint:'test-checkpoint', connection:{token:'provider-secret', environmentId:randomUUID()},
    workerId:randomUUID(), signingKey:secret, dailyLimit:10};
  config.environmentId = config.connection.environmentId;
  const sandbox = {id:randomUUID(), environmentId:config.environmentId, networkIsolation:'ISOLATED', domains:[], idleTimeoutMinutes:1,
    files:{async write(...args) { calls.push(['write', ...args]); if (changes.writeError) throw Error('provider detail that must remain private'); }},
    async exec(command, options) {
      calls.push(['exec', command, options]);
      if (command.endsWith(' probe')) return {exitCode:changes.probeFail ? 1 : 0, stdout:'policy probe', stderr:'', timedOut:false, truncated:false};
      if (command.includes('bootstrap.sh')) return {exitCode:changes.buildFail ? 1 : 0};
      if (command.startsWith('find ')) return {exitCode:0};
      if (changes.execError) throw Error('private provider diagnostic');
      options.onStdout?.(changes.output || '12 runs, 158 assertions, 0 failures, 0 errors, 0 skips\n');
      options.onStderr?.('fixture stderr\n');
      if (options.signal?.aborted) throw options.signal.reason;
      return {exitCode:changes.exitCode ?? 0, timedOut:changes.timedOut || false, truncated:changes.truncated || false};
    },
    async checkpoint(name) { calls.push(['checkpoint', name]); },
    async destroy() { calls.push(['destroy']); if (changes.cleanupFail) throw Error('private cleanup diagnostic'); }
  };
  const Sandbox = {
    async create(...args) { calls.push(['create', ...args]); if (changes.createError) throw Error('provider create failed'); return sandbox; },
    async connect(id) { calls.push(['connect',id]); return sandbox; },
    async checkpoints() { return [{key:config.checkpoint}]; }
  };
  return {Sandbox, config, state, calls, sandbox, changes};
}

test('installed SDK exposes the documented lifecycle API and assets are content addressed', async () => {
  for (const name of ['create','connect','checkpoints']) assert.equal(typeof InstalledSdk[name], 'function');
  const first = await loadAssets(), second = await loadAssets();
  assert.equal(first.checkpoint, second.checkpoint);
  assert.match(first.checkpoint, /^interview-rails-v1-[0-9a-f]{32}$/);
  assert.ok(first.assets.some(asset => asset.path.endsWith('/probe.rb')));
  assert.ok(first.assets.every(asset => !asset.path.includes('reference')));
  assert.ok(first.assets.find(asset => asset.path.endsWith('/Gemfile.lock')).data.includes(Buffer.from('PLATFORMS\n  ruby')));
});

test('contract accepts signed UTF-8 source and rejects tampering, expiry, traversal and corrupt base64', () => {
  const value = payload({'app/models/event.rb':'# café 🧪\n'});
  assert.equal(verify(signed(value), secret).source_revision, value.source_revision);
  assert.throws(() => verify({...signed(value), signature:'0'.repeat(64)}, secret), /invalid_signature/);
  assert.throws(() => verify(signed(value), 'short'), /invalid_signature/);
  assert.throws(() => validate({...value, expires_at:0}), /expired_job/);
  assert.throws(() => validate({...value, timeout_seconds:180}), /invalid_deadline/);
  assert.throws(() => validate({...value, job_id:[value.job_id]}), /invalid_identity/);
  assert.throws(() => validate(payload({'app/../escape.rb':'bad'})), /invalid_source/);
  assert.throws(() => validate({...value, files:{'app/models/event.rb':'@@@'}}), /invalid_base64/);
  assert.throws(() => validate({...value, source_revision:'f'.repeat(64)}), /source_revision_mismatch/);
  assert.throws(() => validate(payload({'test/integration/events_test.rb':'bad'})), /invalid_source/);
});

test('configuration is disabled by default and rejects unsafe origins', () => {
  assert.ok(configFromEnv({}).issues.includes('execution_disabled'));
  for (const url of ['http://example.com','https://key@example.com','https://example.com/path','https://example.com/?token=x']) assert.throws(() => origin(url));
  assert.equal(origin('http://127.0.0.1:3100/'), 'http://127.0.0.1:3100');
  assert.equal(origin('https://studio.example.test'), 'https://studio.example.test');
});

test('transport scopes credentials to the configured origin and forbids redirects', async () => {
  const calls = [];
  const request = transport('https://studio.example.test', 'bridge-secret', async (url, options) => {
    calls.push({url, options}); return new Response(JSON.stringify({ok:true}));
  });
  assert.deepEqual(await request('/internal/workers/heartbeat', {worker_id:randomUUID()}), {ok:true});
  assert.equal(calls[0].options.redirect, 'error');
  assert.equal(calls[0].options.headers.Authorization, 'Bearer bridge-secret');
  assert.equal(calls[0].url, 'https://studio.example.test/internal/workers/heartbeat');
});

test('successful execution uses fixed resources, non-secret env, a probe and mandatory cleanup', async t => {
  const deps = await fixture(t), value = payload(), record = await deps.state.claim(value, 'lease');
  const result = await execute(value, {...deps, record});
  assert.equal(result.status, 'execution_completed'); assert.equal(result.runtime_provider, 'railway_sandbox');
  assert.match(result.output, /12 runs, 158 assertions/);
  const [,checkpoint, options] = deps.calls.find(call => call[0] === 'create');
  assert.equal(checkpoint, deps.config.checkpoint); assert.equal(options.networkIsolation, 'ISOLATED');
  assert.deepEqual(options.env, {}); assert.deepEqual(options.domains, []);
  assert.deepEqual(options.resources, {cpu:1, memoryGB:2}); assert.equal(options.idleTimeoutMinutes, 1);
  assert.equal(deps.calls.filter(call => call[0] === 'destroy').length, 1);
  const writes = deps.calls.filter(call => call[0] === 'write');
  assert.deepEqual(JSON.parse(writes[0][2]), {files:value.files}); assert.equal(writes[0][3].mode, 0o600);
  const receipt = (await deps.state.records())[0];
  assert.equal(receipt.sandbox_id, null); assert.equal(receipt.result.source_revision, value.source_revision);
  assert.equal(receipt.payload.files, undefined);
  assert.equal((await stat(deps.state.path(value.job_id))).mode & 0o777, 0o600);
});

for (const [name, changes, status] of [
  ['candidate failure', {exitCode:1}, 'execution_failed'],
  ['preparation failure', {exitCode:70}, 'infrastructure_error'],
  ['timeout', {timedOut:true, exitCode:-1}, 'timed_out'],
  ['trusted timeout', {exitCode:124}, 'timed_out'],
  ['unconfirmed forced termination', {exitCode:137}, 'infrastructure_error'],
  ['output flood', {output:'x'.repeat(MAX_OUTPUT + 100)}, 'output_limit'],
  ['truncated result', {truncated:true}, 'output_limit'],
  ['connection interruption', {execError:true}, 'infrastructure_error'],
  ['failed cleanup', {cleanupFail:true}, 'infrastructure_error'],
  ['staging failure', {writeError:true}, 'infrastructure_error']
]) test(`${name} remains distinct and attempts cleanup`, async t => {
  const deps = await fixture(t, changes), value = payload(), record = await deps.state.claim(value, 'lease');
  const result = await execute(value, {...deps, record});
  assert.equal(result.status, status); assert.ok(Buffer.byteLength(result.output) <= MAX_OUTPUT);
  assert.ok(deps.calls.some(call => call[0] === 'destroy'));
  if (changes.cleanupFail) assert.ok((await deps.state.records())[0].sandbox_id);
  assert.ok(!result.output.includes('private provider'));
});

test('failed network isolation never uploads or executes candidate source', async t => {
  const deps = await fixture(t, {probeFail:true}), value = payload(), record = await deps.state.claim(value, 'lease');
  const result = await execute(value, {...deps, record});
  assert.equal(result.status, 'infrastructure_error');
  assert.match(result.output, /runtime_isolation_unavailable/);
  assert.ok(!deps.calls.some(call => call[0] === 'write'));
  assert.equal(deps.calls.filter(call => call[0] === 'exec').length, 1);
});

test('incorrect network/private environment policy fails closed', async t => {
  const deps = await fixture(t); deps.sandbox.networkIsolation = 'PRIVATE';
  const value = payload(), record = await deps.state.claim(value, 'lease');
  assert.equal((await execute(value, {...deps, record})).status, 'infrastructure_error');
  assert.ok(!deps.calls.some(call => call[0] === 'exec'));
});

test('late provider creation is torn down after the controller deadline', async () => {
  let destroyed = false, finish;
  const delayed = new Promise(resolve => { finish = resolve; });
  await assert.rejects(bounded(() => delayed, 2, value => value.destroy()), /provider_timeout/);
  finish({async destroy() { destroyed = true; }});
  await new Promise(resolve => setImmediate(resolve));
  assert.equal(destroyed, true);
});

test('bootstrap checks readiness and strips workspace before creating the checkpoint', async t => {
  const deps = await fixture(t), assets = await loadAssets(), record = await deps.state.claim({job_id:randomUUID()}, null);
  const result = await bootstrap({...deps, assets, record});
  assert.equal(result.checkpoint, assets.checkpoint);
  const commands = deps.calls.filter(call => call[0] === 'exec').map(call => call[1]);
  assert.ok(commands.includes('/bin/bash /opt/runner/launch.sh 10 probe'));
  assert.ok(commands.includes('/bin/bash /opt/runner/launch.sh 60 prepare'));
  assert.ok(commands.includes('find /workspace -mindepth 1 -delete'));
  assert.ok(deps.calls.some(call => call[0] === 'checkpoint'));
  assert.ok(deps.calls.some(call => call[0] === 'destroy'));
});

test('failed bootstrap never publishes a checkpoint and still destroys the VM', async t => {
  const deps = await fixture(t, {buildFail:true}), assets = await loadAssets(), record = await deps.state.claim({job_id:randomUUID()}, null);
  await assert.rejects(bootstrap({...deps, assets, record}), /bootstrap_failed/);
  assert.ok(!deps.calls.some(call => call[0] === 'checkpoint'));
  assert.ok(deps.calls.some(call => call[0] === 'destroy'));
});

test('bridge carries an exact signed revision from lease to persisted callback', async t => {
  const deps = await fixture(t), value = payload(), requests = [];
  deps.request = async (path, data) => { requests.push({path,data}); return path.endsWith('/lease') ? {job:signed(value), lease_token:'lease-token'} : {ok:true}; };
  const outcome = await runCycle(deps);
  assert.equal(outcome.status, 'execution_completed');
  const delivery = requests.find(request => request.path.endsWith('/result'));
  assert.equal(delivery.data.result.source_revision, value.source_revision);
  assert.equal(delivery.data.lease_token, 'lease-token');
  assert.equal((await deps.state.records())[0].delivered, true);
  assert.ok(!JSON.stringify(deps.calls.filter(call => call[0] === 'write')).includes('lease-token'));
});

test('invalid signatures and job replay cannot allocate a VM', async t => {
  const deps = await fixture(t), value = payload();
  deps.request = async path => path.endsWith('/lease') ? {job:{...signed(value), signature:'0'.repeat(64)}, lease_token:'lease'} : {ok:true};
  await assert.rejects(runCycle(deps), /invalid_signature/);
  assert.ok(!deps.calls.some(call => call[0] === 'create'));
  await deps.state.claim(value, 'lease');
  deps.request = async path => path.endsWith('/lease') ? {job:signed(value), lease_token:'lease'} : {ok:true};
  await assert.rejects(runCycle(deps), /job_already_claimed/);
  assert.ok(!deps.calls.some(call => call[0] === 'create'));
});

test('failed callback is retried from disk without rerunning candidate code', async t => {
  const deps = await fixture(t), value = payload(); let offline = true;
  deps.request = async path => {
    if (path.endsWith('/lease')) return {job:signed(value), lease_token:'lease'};
    if (path.endsWith('/result') && offline) throw Error('network lost');
    return {ok:true};
  };
  await assert.rejects(runCycle(deps), /network lost/);
  const count = deps.calls.filter(call => call[0] === 'create').length;
  offline = false; await deliverPending(deps.state, deps.request);
  assert.equal((await deps.state.records())[0].delivered, true);
  assert.equal(deps.calls.filter(call => call[0] === 'create').length, count);
});

test('expired callback is retained as rejected rather than silently overwritten', async t => {
  const deps = await fixture(t), value = payload(), record = await deps.state.claim(value, 'lease');
  record.result = {status:'infrastructure_error'}; await deps.state.save(record);
  await deliverPending(deps.state, async () => { throw new HttpError(409); });
  assert.equal((await deps.state.records())[0].rejected, 409);
});

test('watchdog cleans only recorded expired sandboxes and preserves completed evidence', async t => {
  const deps = await fixture(t), value = payload(), record = await deps.state.claim(value, 'lease');
  record.sandbox_id = deps.sandbox.id; record.deadline_at = 0; await deps.state.save(record);
  await reconcile(deps);
  const recovered = (await deps.state.records())[0];
  assert.equal(recovered.sandbox_id, null); assert.equal(recovered.result.status, 'infrastructure_error');
  assert.equal(deps.calls.filter(call => call[0] === 'connect').length, 1);
  assert.ok(!deps.calls.some(call => call[0] === 'create'));
});

test('daily execution limit prevents advertising capacity or taking a lease', async t => {
  const deps = await fixture(t); deps.config.dailyLimit = 1;
  await deps.state.claim(payload(), 'lease');
  deps.request = async () => { throw Error('must not contact queue'); };
  assert.equal((await runCycle(deps)).status, 'daily_job_limit_reached');
});

test('a missing exact checkpoint prevents worker readiness', async t => {
  const deps = await fixture(t); deps.Sandbox.checkpoints = async () => [{key:'unrelated-checkpoint'}];
  await assert.rejects(checkpointReady(deps.Sandbox, deps.config), /checkpoint_not_built/);
});
