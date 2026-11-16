const { execFile } = require('node:child_process');
const fs = require('node:fs/promises');
const os = require('node:os');
const path = require('node:path');
const { promisify } = require('node:util');

const run = promisify(execFile);
const kernelExe = path.join(__dirname, '..', 'runtime', 'parasolid-win-x64', 'PointViewXt.exe');

async function findJournalRunner() {
  const { UGII_ROOT_DIR, UGII_BASE_DIR } = process.env;
  const dirs = [UGII_ROOT_DIR];
  if (UGII_BASE_DIR) {
    dirs.push(path.join(UGII_BASE_DIR, 'NXBIN'), path.join(UGII_BASE_DIR, 'UGII'));
  }
  for (const dir of dirs.filter(Boolean)) {
    const runner = path.join(dir, process.platform === 'win32' ? 'run_journal.exe' : 'run_journal');
    if (await fs.stat(runner).then(stat => stat.isFile(), () => false)) return runner;
  }
  throw Object.assign(new Error('未找到 X_T 转换器。请配置项目的 Parasolid 运行库，或安装 NX 并设置 UGII_BASE_DIR。'), { status: 503 });
}

async function convertParasolid(inputPath, outputPath) {
  const portable = process.platform === 'win32' && process.arch === 'x64'
    && await fs.stat(kernelExe).then(stat => stat.isFile(), () => false);
  const runner = portable ? kernelExe : await findJournalRunner();
  const work = await fs.mkdtemp(path.join(os.tmpdir(), 'pointview-xt-'));
  try {
    const mesh = path.join(work, 'mesh.json');
    const args = portable ? [path.resolve(inputPath), mesh] : [path.join(__dirname, 'parasolid.py')];
    if (!portable) await fs.copyFile(inputPath, path.join(work, 'input.x_t'));
    try {
      await run(runner, args, {
        cwd: work, windowsHide: true, timeout: 5 * 60 * 1000,
      });
      await fs.access(mesh);
    } catch (error) {
      if (error.killed) throw new Error('X_T 转换超时。');
      const detail = portable ? error.stderr?.trim() : await fs.readFile(path.join(work, 'error.txt'), 'utf8').catch(() => '');
      throw new Error('无法生成 X_T 预览，请检查文件版本和转换器运行环境。' + (detail ? ' ' + detail : ''));
    }
    await fs.copyFile(mesh, outputPath);
  } finally {
    await fs.rm(work, { recursive: true, force: true, maxRetries: 3 });
  }
}

module.exports = { convertParasolid };
