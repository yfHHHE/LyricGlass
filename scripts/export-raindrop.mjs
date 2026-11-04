// Run only when updating the supplied avatar; runtime needs no JS or npm packages.
import fs from 'node:fs/promises';
import path from 'node:path';
import { pathToFileURL, fileURLToPath } from 'node:url';
import { createHash } from 'node:crypto';
const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const source = path.resolve(process.argv[2] ?? path.join(root, '../raindrop-avatar'));
const THREE = await import(pathToFileURL(path.join(source, 'node_modules/three/build/three.module.js')));
const modelURL = path.join(source, 'src/drop-model.js');
const { createDrop } = await import(pathToFileURL(modelURL));
const model = createDrop(THREE, '#FFF2F6');
const rounded = array => Array.from(array, x => Math.round(x * 1e6) / 1e6);
const meshes = model.group.children.map(mesh => ({
  name: mesh.name,
  positions: rounded(mesh.geometry.attributes.position.array),
  colors: mesh.geometry.attributes.color ? rounded(mesh.geometry.attributes.color.array) : [],
  indices: Array.from(mesh.geometry.index.array),
  color: mesh.material.color.getHexString(THREE.SRGBColorSpace)
}));
const asset = { source: 'raindrop-avatar/src/drop-model.js',
  sha256: createHash('sha256').update(await fs.readFile(modelURL)).digest('hex'), meshes };
await fs.mkdir(path.join(root, 'Resources/Avatar'), { recursive: true });
await fs.writeFile(path.join(root, 'Resources/Avatar/raindrop.json'), JSON.stringify(asset));
await fs.copyFile(path.join(source, 'dist/THREE-LICENSE.txt'), path.join(root, 'Resources/Avatar/THREE-LICENSE.txt'));
console.log(`Exported original geometry: ${meshes.length} meshes, ${meshes.reduce((n,m) => n+m.positions.length/3,0)} vertices`);
