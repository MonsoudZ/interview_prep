import {mkdir, open, readFile, rename, readdir, unlink} from 'node:fs/promises';
import {resolve, join} from 'node:path';
import {randomUUID} from 'node:crypto';
import {UUID, WorkerError} from './contract.mjs';

export class State {
  constructor(directory) { this.directory = resolve(directory); }
  async init() { await mkdir(this.directory, {recursive:true, mode:0o700}); }
  path(id) { if (!UUID.test(id)) throw new WorkerError('invalid_job_id'); return join(this.directory, `job-${id}.json`); }
  async claim(payload, leaseToken) {
    const handle = await open(this.path(payload.job_id), 'wx', 0o600).catch(error => { throw new WorkerError(error.code === 'EEXIST' ? 'job_already_claimed' : 'state_unavailable'); });
    const identity = Object.fromEntries(['job_id','tenant_id','session_id','source_revision'].map(key => [key, payload[key]]));
    const record = {job_id:payload.job_id, payload:identity, lease_token:leaseToken, phase:'claimed',
      created_at:Date.now(), deadline_at:Date.now() + 165000, sandbox_id:null};
    try { await handle.writeFile(JSON.stringify(record)); await handle.sync(); } finally { await handle.close(); }
    return record;
  }
  async save(record) {
    const target = this.path(record.job_id), temporary = `${target}.${randomUUID()}.tmp`;
    const handle = await open(temporary, 'wx', 0o600);
    try { await handle.writeFile(JSON.stringify(record)); await handle.sync(); } finally { await handle.close(); }
    await rename(temporary, target);
  }
  async records() {
    const names = (await readdir(this.directory)).filter(name => /^job-[0-9a-f-]{36}\.json$/.test(name)).sort();
    return Promise.all(names.map(async name => JSON.parse(await readFile(join(this.directory, name), 'utf8'))));
  }
  async removeTemporaryFiles() {
    // Temporary records never authorize runtime deletion. Keep complete receipts for replay protection.
    for (const name of await readdir(this.directory)) if (/^job-[0-9a-f-]{36}\.json\.[0-9a-f-]{36}\.tmp$/.test(name)) await unlink(join(this.directory, name));
  }
}
