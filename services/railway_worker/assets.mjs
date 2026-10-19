import {readFile} from 'node:fs/promises';
import {fileURLToPath} from 'node:url';
import {resolve} from 'node:path';
import {canonical, hash} from './contract.mjs';

const root = fileURLToPath(new URL('../../', import.meta.url));
const exercisePaths = ['BRIEF.md','Gemfile','db/schema.rb','config/boot.rb','config/database.yml',
  'config/application.rb','config/environment.rb','config/environments/test.rb','config/routes.rb',
  'bin/prepare.rb','test/test_helper.rb','test/integration/events_test.rb',
  'app/controllers/events_controller.rb','app/controllers/application_controller.rb','app/models/application_record.rb'];

export async function loadAssets() {
  const assets = [];
  for (const path of exercisePaths) assets.push({path:`/opt/exercise/${path}`, data:await readFile(resolve(root, 'experiments/rails-runtime/template', path)), mode:0o644});
  assets.push({path:'/opt/exercise/Gemfile.lock', data:await readFile(resolve(root, 'services/execution_worker/image/dependencies/Gemfile.lock')), mode:0o644});
  assets.push({path:'/opt/runner/run.rb', data:await readFile(resolve(root, 'services/execution_worker/image/run.rb')), mode:0o644});
  for (const name of ['bootstrap.sh','launch.sh','isolated.sh','probe.rb']) assets.push({path:`/opt/runner/${name}`, data:await readFile(new URL(`runtime/${name}`, import.meta.url)), mode:name.endsWith('.sh') ? 0o755 : 0o644});
  const digest = hash(canonical(Object.fromEntries(assets.map(asset => [asset.path, hash(asset.data)]))));
  return {assets, digest, checkpoint:`interview-rails-v1-${digest.slice(0,32)}`};
}
