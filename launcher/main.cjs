'use strict';

const { app, BrowserWindow, dialog, ipcMain, shell } = require('electron');
const path = require('node:path');
const fs = require('node:fs');
const fsp = require('node:fs/promises');
const crypto = require('node:crypto');
const net = require('node:net');
const { Readable, Transform } = require('node:stream');
const { pipeline } = require('node:stream/promises');
const { spawn } = require('node:child_process');

const installRoot = path.resolve(__dirname, '../../..');
const packagedGameRoot = path.join(installRoot, 'Rokira');
const userData = app.getPath('userData');
const settingsPath = path.join(userData, 'settings.json');
const configPath = path.join(__dirname, 'launcher-config.json');
const logFile = path.join(userData, 'launcher.log');
let win;
let settings = {};

function log(message) {
  try { fs.appendFileSync(logFile, `${new Date().toISOString()} ${message}\n`); } catch {}
}

function readJson(file, fallback = {}) {
  try { return JSON.parse(fs.readFileSync(file, 'utf8')); } catch { return fallback; }
}

function writeSettings(next) {
  settings = next;
  fs.mkdirSync(userData, { recursive: true });
  fs.writeFileSync(settingsPath, JSON.stringify(settings, null, 2), 'utf8');
}

function getConfig() {
  const config = readJson(configPath);
  const manifestUrl = process.env.ROKIRA_MANIFEST_URL || config.manifestUrl;
  if (!manifestUrl) throw new Error('O endereço de atualização ainda não foi configurado.');
  const parsed = new URL(manifestUrl);
  if (parsed.protocol !== 'https:') throw new Error('A atualização só pode usar uma conexão HTTPS segura.');
  const newsUrl = config.newsUrl ? new URL(config.newsUrl) : null;
  if (newsUrl && newsUrl.protocol !== 'https:') throw new Error('As notícias só podem usar uma conexão HTTPS segura.');
  return { manifestUrl: parsed.href, newsUrl: newsUrl?.href || null };
}

function validClientFolder(folder) {
  if (!folder || !fs.existsSync(path.join(folder, 'data.grf'))) return false;
  return ['BGM', 'System', 'AI'].every((name) => fs.existsSync(path.join(folder, name)));
}

function detectClientFolder() {
  const candidates = [
    settings.clientFolder,
    'C:\\Gravity\\Ragnarok Online',
    'C:\\Ragnarok Online',
    'C:\\Program Files (x86)\\Gravity\\Ragnarok Online',
    'C:\\Program Files\\Gravity\\Ragnarok Online',
  ].filter(Boolean);
  return candidates.find(validClientFolder) || null;
}

function activeGameRoot() {
  const candidates = [packagedGameRoot, installRoot];
  return candidates.find((folder) => fs.existsSync(path.join(folder, 'cliente-windows', 'Ragnarok Classico.exe'))
    && fs.existsSync(path.join(folder, 'client-assets', 'index.html'))) || packagedGameRoot;
}

function checkFiles() {
  const gameRoot = activeGameRoot();
  const required = [
    path.join(gameRoot, 'cliente-windows', 'Ragnarok Classico.exe'),
    path.join(gameRoot, 'client-assets', 'index.html'),
  ];
  const missing = required.filter((file) => !fs.existsSync(file));
  const baseVersion = getInstalledVersion('base');
  const patchVersion = getInstalledVersion('patch');
  const clientFolder = detectClientFolder();
  return {
    clientReady: missing.length === 0 && Boolean(baseVersion) && Boolean(patchVersion),
    baseFilesReady: missing.length === 0,
    baseVersion,
    patchVersion,
    officialReady: Boolean(clientFolder),
    clientFolder,
    missing: missing.map((file) => path.basename(file)),
  };
}

function getInstalledVersion(channel) {
  const gameRoot = activeGameRoot();
  const record = readJson(path.join(gameRoot, `.rokira-${channel}-version.json`));
  return typeof record.version === 'string' ? record.version : null;
}

async function getManifest() {
  const { manifestUrl } = getConfig();
  const response = await fetch(manifestUrl, { cache: 'no-store', signal: AbortSignal.timeout(15000) });
  if (!response.ok) throw new Error(`Não foi possível consultar a atualização (HTTP ${response.status}).`);
  const manifest = await response.json();
  validateManifest(manifest);
  return manifest;
}

function validateManifest(manifest) {
  if (!manifest || manifest.format !== 2) throw new Error('A configuração de atualização precisa da estrutura segura base + patch.');
  if (!manifest.server || !Array.isArray(manifest.ports) || !manifest.ports.length || manifest.ports.some((p) => !Number.isInteger(p) || p < 1 || p > 65535)) {
    throw new Error('A configuração de conexão do jogo está incompleta.');
  }
  for (const channel of ['base', 'patch']) {
    const release = manifest[channel];
    if (!release || !/^\d+\.\d+\.\d+(?:[-+][\w.-]+)?$/.test(release.version || '')) throw new Error(`A versão ${channel} não está configurada.`);
    if (typeof release.packageUrl !== 'string' || new URL(release.packageUrl).protocol !== 'https:') throw new Error(`O pacote ${channel} não usa HTTPS.`);
    const requiredPolicy = channel === 'base' ? 'rokira-base-v1' : 'rokira-patch-v1';
    if (release.contentPolicy !== requiredPolicy) throw new Error(`O pacote ${channel} não tem a política de conteúdo esperada.`);
    if (!/^[a-f\d]{64}$/i.test(release.sha256 || '') || !Number.isSafeInteger(release.size) || release.size < 1 || release.size > 2_000_000_000) throw new Error(`A verificação de integridade do pacote ${channel} está inválida.`);
  }
}

function tcp(host, port, timeout = 3500) {
  return new Promise((resolve) => {
    const socket = net.connect(port, host);
    const finish = (online) => { socket.destroy(); resolve(online); };
    socket.setTimeout(timeout, () => finish(false));
    socket.once('error', () => finish(false));
    socket.once('connect', () => finish(true));
  });
}

async function serverStatus() {
  const manifest = await getManifest();
  const checks = await Promise.all(manifest.ports.map((port) => tcp(manifest.server, port)));
  return { online: checks.every(Boolean), ports: manifest.ports.map((port, index) => ({ port, online: checks[index] })) };
}

function safeExtract(zipPath, channel) {
  return new Promise((resolve, reject) => {
    const scriptPath = path.join(__dirname, 'Install-ClientPackage.ps1');
    const child = spawn('powershell.exe', ['-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass', '-File', scriptPath, '-ZipPath', zipPath, '-InstallRoot', installRoot, '-Channel', channel], { windowsHide: true });
    let output = '';
    child.stdout.on('data', (chunk) => { output += chunk.toString(); });
    child.stderr.on('data', (chunk) => { output += chunk.toString(); });
    child.once('error', reject);
    child.once('exit', (code) => code === 0 ? resolve() : reject(new Error(output.trim() || 'O pacote não passou pela validação de arquivos.')));
  });
}

async function downloadUpdate(channel) {
  const manifest = await getManifest();
  const release = manifest[channel];
  if (!release) throw new Error(`O pacote ${channel} não está configurado.`);
  const requiredPolicy = channel === 'base' ? 'rokira-base-v1' : 'rokira-patch-v1';
  if (release.contentPolicy !== requiredPolicy) throw new Error(`O pacote ${channel} está bloqueado até ser validado e publicado no manifesto.`);
  const downloads = path.join(userData, 'updates');
  await fsp.mkdir(downloads, { recursive: true });
  const partial = path.join(downloads, `Rokira-${channel}-${release.version}.zip.partial`);
  const zip = path.join(downloads, `Rokira-${channel}-${release.version}.zip`);
  const response = await fetch(release.packageUrl, { cache: 'no-store', signal: AbortSignal.timeout(30 * 60 * 1000) });
  if (!response.ok || !response.body) throw new Error(`O download do cliente falhou (HTTP ${response.status}).`);
  if (new URL(response.url).protocol !== 'https:') throw new Error('O download foi redirecionado para uma conexão insegura.');
  const hash = crypto.createHash('sha256');
  let received = 0;
  const total = Number(response.headers.get('content-length')) || release.size;
  const meter = new Transform({
    transform(chunk, _encoding, callback) {
      hash.update(chunk);
      received += chunk.length;
      win?.webContents.send('rokira:download-progress', { received, total, percent: Math.min(100, Math.round(received * 100 / total)) });
      callback(null, chunk);
    },
  });
  try {
    await pipeline(Readable.fromWeb(response.body), meter, fs.createWriteStream(partial));
    if (received !== release.size || hash.digest('hex').toLowerCase() !== release.sha256.toLowerCase()) {
      throw new Error('A verificação SHA-256 do download falhou.');
    }
    await fsp.rename(partial, zip);
    await safeExtract(zip, channel);
    const gameRoot = activeGameRoot();
    await fsp.mkdir(gameRoot, { recursive: true });
    await fsp.writeFile(path.join(gameRoot, `.rokira-${channel}-version.json`), JSON.stringify({ version: release.version, sha256: release.sha256, installedAt: new Date().toISOString() }, null, 2));
    await fsp.rm(zip, { force: true });
    return { ok: true, channel, version: release.version };
  } catch (error) {
    await fsp.rm(partial, { force: true }).catch(() => {});
    await fsp.rm(zip, { force: true }).catch(() => {});
    throw error;
  }
}

async function selectClientFolder() {
  const result = await dialog.showOpenDialog(win, { title: 'Selecione a pasta do Ragnarok instalado', properties: ['openDirectory'] });
  if (result.canceled || !result.filePaths[0]) return { ok: false, canceled: true };
  const folder = result.filePaths[0];
  if (!validClientFolder(folder)) return { ok: false, error: 'Essa pasta precisa conter data.grf e as pastas BGM, System e AI.' };
  writeSettings({ ...settings, clientFolder: folder });
  return { ok: true, folder };
}

function play() {
  const status = checkFiles();
  if (!status.clientReady) return { ok: false, error: 'O cliente Rokira não está instalado ou precisa ser atualizado.' };
  if (!status.officialReady) return { ok: false, error: 'Selecione a pasta do cliente oficial para continuar.' };
  const gameRoot = activeGameRoot();
  const exe = path.join(gameRoot, 'cliente-windows', 'Ragnarok Classico.exe');
  const clientFolder = status.clientFolder;
  const env = {
    ...process.env,
    BGM_PATH: path.join(clientFolder, 'BGM'),
    SYSTEM_PATH: path.join(clientFolder, 'System'),
    AI_PATH: path.join(clientFolder, 'AI'),
    ROKIRA_CLIENT_DATA: clientFolder,
  };
  const child = spawn(exe, [], { cwd: gameRoot, detached: true, windowsHide: false, stdio: 'ignore', env });
  child.once('error', (error) => log(`game launch failed: ${error.message}`));
  child.unref();
  return { ok: true };
}

ipcMain.handle('rokira:check-files', () => checkFiles());
ipcMain.handle('rokira:get-installed-version', (_event, channel) => getInstalledVersion(channel));
ipcMain.handle('rokira:get-manifest', () => getManifest());
ipcMain.handle('rokira:server-status', () => serverStatus());
ipcMain.handle('rokira:download-update', (_event, channel) => downloadUpdate(channel));
ipcMain.handle('rokira:select-client-folder', () => selectClientFolder());
ipcMain.handle('rokira:play', () => play());
ipcMain.handle('rokira:news', async () => {
  const fallback = readJson(path.join(__dirname, 'news.json'), []);
  try {
    const config = getConfig();
    const manifest = await getManifest();
    const endpoint = manifest.newsUrl || config.newsUrl;
    if (!endpoint || new URL(endpoint).protocol !== 'https:') return fallback;
    const response = await fetch(endpoint, { cache: 'no-store', signal: AbortSignal.timeout(6000) });
    if (!response.ok) return fallback;
    const items = await response.json();
    return Array.isArray(items) ? items.slice(0, 3) : fallback;
  } catch { return fallback; }
});

function createWindow() {
  win = new BrowserWindow({
    show: false,
    width: 1180,
    height: 760,
    minWidth: 1180,
    maxWidth: 1180,
    minHeight: 760,
    maxHeight: 760,
    resizable: false,
    maximizable: false,
    fullscreenable: false,
    title: 'Rokira Launcher',
    backgroundColor: '#08131d',
    icon: path.join(__dirname, 'logo.png'),
    webPreferences: { preload: path.join(__dirname, 'preload.cjs'), contextIsolation: true, sandbox: true, nodeIntegration: false },
  });
  win.setMenu(null);
  win.once('ready-to-show', () => { win.show(); win.focus(); });
  win.webContents.on('did-fail-load', (_event, code, description) => log(`did-fail-load ${code}: ${description}`));
  win.webContents.setWindowOpenHandler(({ url }) => {
    if (url.startsWith('https://')) shell.openExternal(url);
    return { action: 'deny' };
  });
  win.loadFile(path.join(__dirname, 'index.html')).catch((error) => log(`loadFile: ${error.stack || error.message}`));
}

app.setName('Rokira Launcher');
app.setAppUserModelId('com.rokira.launcher');
settings = readJson(settingsPath);
process.on('uncaughtException', (error) => log(`uncaughtException: ${error.stack || error.message}`));
process.on('unhandledRejection', (error) => log(`unhandledRejection: ${error?.stack || error}`));
if (!app.requestSingleInstanceLock()) app.quit();
else app.whenReady().then(createWindow).catch((error) => log(`ready: ${error.stack || error.message}`));
app.on('window-all-closed', () => app.quit());
