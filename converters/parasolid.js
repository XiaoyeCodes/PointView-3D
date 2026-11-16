const { execFile } = require('node:child_process');
const fs = require('node:fs/promises');
const os = require('node:os');
const path = require('node:path');
const { promisify } = require('node:util');

const run = promisify(execFile);

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
  throw Object.assign(new Error('导入 X_T 需要 Siemens NX。请在服务端配置 UGII_BASE_DIR 并重启服务。'), { status: 503 });
}

async function convertParasolid(inputPath, outputPath) {
  const runner = await findJournalRunner();
  const work = await fs.mkdtemp(path.join(os.tmpdir(), 'pointview-xt-'));
  try {
    await fs.copyFile(inputPath, path.join(work, 'input.x_t'));
    try {
      await run(runner, [path.join(__dirname, 'parasolid.py')], {
        cwd: work, windowsHide: true, timeout: 5 * 60 * 1000,
      });
      await fs.access(path.join(work, 'mesh.json'));
    } catch (error) {
      const detail = await fs.readFile(path.join(work, 'error.txt'), 'utf8').catch(() => '');
      if (error.killed) throw new Error('NX 转换超时，请检查 NX 许可或尝试较小的模型。');
      throw new Error('NX 无法生成预览，请检查文件版本、几何及 NX 许可。' + (detail ? ' ' + detail : ''));
    }
    await fs.copyFile(path.join(work, 'mesh.json'), outputPath);
  } finally {
    await fs.rm(work, { recursive: true, force: true, maxRetries: 3 });
  }
}

module.exports = { convertParasolid };
