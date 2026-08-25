const express = require('express');
const multer = require('multer');
const path = require('path');
const fs = require('fs');

const app = express();
const PORT = process.env.PORT || 3000;

const uploadDir = path.join(__dirname, 'uploads');
if (!fs.existsSync(uploadDir)) fs.mkdirSync(uploadDir, { recursive: true });

const ALLOWED_EXT = ['.obj', '.mtl', '.stp', '.step'];

// 保留原始文件名，若重名则加时间戳前缀，避免互相覆盖
const storage = multer.diskStorage({
  destination: (req, file, cb) => cb(null, uploadDir),
  filename: (req, file, cb) => {
    const safeName = file.originalname.replace(/[^\w.\-]+/g, '_');
    const finalName = fs.existsSync(path.join(uploadDir, safeName))
      ? `${Date.now()}_${safeName}`
      : safeName;
    cb(null, finalName);
  },
});

const upload = multer({
  storage,
  limits: { fileSize: 100 * 1024 * 1024 }, // 单文件最大 100MB（STEP 文件可能比较大）
  fileFilter: (req, file, cb) => {
    const ext = path.extname(file.originalname).toLowerCase();
    if (ALLOWED_EXT.includes(ext)) return cb(null, true);
    cb(new Error('只允许上传 .obj / .mtl / .stp / .step 文件'));
  },
});

app.use(express.static(path.join(__dirname, 'public'), {
  setHeaders: (res, filePath) => {
    // .wasm 需要正确的 MIME 类型，浏览器才能用流式编译加载
    if (filePath.endsWith('.wasm')) {
      res.set('Content-Type', 'application/wasm');
    }
  },
}));
app.use('/uploads', express.static(uploadDir));

// 一次最多接收 3 个文件：obj / mtl / step(stp或step后缀都算这一类)
app.post('/upload', upload.fields([
  { name: 'obj', maxCount: 1 },
  { name: 'mtl', maxCount: 1 },
  { name: 'step', maxCount: 1 },
]), (req, res) => {
  const objFile = req.files?.obj?.[0];
  const mtlFile = req.files?.mtl?.[0];
  const stepFile = req.files?.step?.[0];

  if (!objFile && !stepFile) {
    return res.status(400).json({ error: '必须上传一个 .obj 或 .stp/.step 文件' });
  }

  // STEP 优先：如果同时传了 obj 和 step，认为用户想看精度更高的 STEP
  if (stepFile) {
    return res.json({
      type: 'step',
      modelUrl: `/uploads/${encodeURIComponent(stepFile.filename)}`,
      modelName: stepFile.originalname,
    });
  }

  res.json({
    type: 'obj',
    modelUrl: `/uploads/${encodeURIComponent(objFile.filename)}`,
    mtlUrl: mtlFile ? `/uploads/${encodeURIComponent(mtlFile.filename)}` : '',
    modelName: objFile.originalname,
  });
});

// multer 的错误（比如文件类型不对、超出大小）统一转成 JSON 返回
app.use((err, req, res, next) => {
  if (err) {
    return res.status(400).json({ error: err.message || '上传失败' });
  }
  next();
});

app.listen(PORT, () => {
  console.log(`\n✔ 服务已启动`);
  console.log(`  请在浏览器打开: http://localhost:${PORT}\n`);
});
