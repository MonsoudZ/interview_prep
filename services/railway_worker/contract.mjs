import {createHash, createHmac, timingSafeEqual} from 'node:crypto';

export const OPERATIONS = ['rails.events.v1', 'rails.events.prepare.v1'];
export const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/;
export const MAX_OUTPUT = 262144;
export class WorkerError extends Error {
  constructor(code) { super(code); this.code = code; }
}
export const hash = value => createHash('sha256').update(value).digest('hex');

// Match Ruby JSON.generate and Python ensure_ascii=True, including non-BMP pairs.
export function canonical(value) {
  const sort = item => Array.isArray(item) ? item.map(sort) : item && typeof item === 'object'
    ? Object.fromEntries(Object.keys(item).sort().map(key => [key, sort(item[key])])) : item;
  return JSON.stringify(sort(value)).replace(/[\u007f-\uffff]/g, char => '\\u' + char.charCodeAt(0).toString(16).padStart(4, '0'));
}

export function validate(payload, now = Date.now() / 1000) {
  const fields = ['version','job_id','tenant_id','session_id','exercise','issued_at','expires_at','timeout_seconds','source_revision','files'].sort();
  if (!payload || Array.isArray(payload) || Object.keys(payload).sort().join() !== fields.join() || payload.version !== 1) throw new WorkerError('invalid_contract');
  if (!['job_id','tenant_id','session_id'].every(field => typeof payload[field] === 'string' && UUID.test(payload[field]))) throw new WorkerError('invalid_identity');
  if (!OPERATIONS.includes(payload.exercise)) throw new WorkerError('unsupported_exercise');
  if (!['issued_at','expires_at','timeout_seconds'].every(field => Number.isSafeInteger(payload[field])) || payload.timeout_seconds < 1 || payload.timeout_seconds > 60) throw new WorkerError('invalid_deadline');
  if (payload.issued_at > now + 30 || payload.expires_at <= now || payload.expires_at <= payload.issued_at || payload.expires_at - payload.issued_at > 300) throw new WorkerError('expired_job');
  const files = payload.files;
  if (!files || Array.isArray(files) || typeof files !== 'object' || Object.keys(files).length < 1 || Object.keys(files).length > 128) throw new WorkerError('invalid_files');
  let bytes = 0;
  const hashes = {};
  for (const [path, encoded] of Object.entries(files)) {
    const valid = path.length <= 240 && /^[A-Za-z0-9_./-]+$/.test(path) && !path.split('/').some(part => ['', '.', '..'].includes(part)) &&
      ((path.startsWith('app/') && path.endsWith('.rb')) || ['config/routes.rb','db/schema.rb'].includes(path));
    if (!valid || typeof encoded !== 'string' || encoded.length > 1400000) throw new WorkerError('invalid_source');
    const decoded = Buffer.from(encoded, 'base64');
    if (decoded.toString('base64') !== encoded) throw new WorkerError('invalid_base64');
    try { new TextDecoder('utf-8', {fatal:true}).decode(decoded); } catch { throw new WorkerError('invalid_utf8'); }
    bytes += decoded.length; hashes[path] = hash(decoded);
  }
  if (bytes > 1024 * 1024 || hash(canonical(hashes)) !== payload.source_revision) throw new WorkerError('source_revision_mismatch');
  return payload;
}

export function verify(envelope, secret) {
  if (Buffer.byteLength(secret || '') < 32 || !envelope || Object.keys(envelope).sort().join() !== 'payload,signature' || typeof envelope.signature !== 'string' || !/^[0-9a-f]{64}$/.test(envelope.signature)) throw new WorkerError('invalid_signature');
  const expected = createHmac('sha256', secret).update(canonical(envelope.payload)).digest();
  if (!timingSafeEqual(expected, Buffer.from(envelope.signature, 'hex'))) throw new WorkerError('invalid_signature');
  return validate(envelope.payload);
}

export function resultFor(payload, values) {
  return {version:1, job_id:payload.job_id, tenant_id:payload.tenant_id, session_id:payload.session_id,
    source_revision:payload.source_revision, grading_authority:'execution-evidence-only; candidate code can influence in-process tests',
    runtime_provider:'railway_sandbox', ...values};
}
