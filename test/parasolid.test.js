const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs/promises');
const os = require('node:os');
const path = require('node:path');
const { convertParasolid } = require('../converters/parasolid');

test('X_T import preserves both 12 × 23 × 34 mm blocks, their placement and face ranges', async t => {
  const dir = await fs.mkdtemp(path.join(os.tmpdir(), 'pointview-test-'));
  t.after(() => fs.rm(dir, { recursive: true, force: true }));
  const preview = path.join(dir, 'preview.json');
  await convertParasolid(path.join(__dirname, 'fixtures', 'two-blocks.x_t'), preview);
  const { meshes } = JSON.parse(await fs.readFile(preview, 'utf8'));
  assert.equal(meshes.length, 2);
  const origins = [];
  for (const mesh of meshes) {
    const positions = mesh.attributes.position.array;
    const normals = mesh.attributes.normal.array;
    assert.ok(positions.every(Number.isFinite) && normals.every(Number.isFinite));
    assert.equal(normals.length, positions.length);
    assert.ok(mesh.index.array.every(i => Number.isInteger(i) && i >= 0 && i < positions.length / 3));
    assert.equal(mesh.brep_faces.length, 6);
    let next = 0;
    for (const face of mesh.brep_faces) {
      assert.equal(face.first, next);
      assert.ok(face.last >= face.first);
      next = face.last + 1;
    }
    assert.equal(next * 3, mesh.index.array.length);
    const min = [], size = [];
    for (let axis = 0; axis < 3; axis++) {
      const values = positions.filter((_, i) => i % 3 === axis);
      min.push(Math.min(...values));
      size.push(Math.max(...values) - min[axis]);
    }
    assert.ok(size.every((value, i) => Math.abs(value - [12, 23, 34][i]) < 0.001));
    assert.ok(Math.abs(min[1]) < 0.001 && Math.abs(min[2]) < 0.001);
    origins.push(min[0]);
  }
  origins.sort((a, b) => a - b);
  assert.ok(Math.abs(origins[0]) < 0.001 && Math.abs(origins[1] - 50) < 0.001);
});
