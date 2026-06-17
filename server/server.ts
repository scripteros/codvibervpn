import express from "express";
import cors from "cors";
import { randomBytes } from "crypto";
import { execSync, exec } from "child_process";
import fs from "fs";
import path from "path";

// Simple .env loader (no dotenv dependency needed)
function loadEnv() {
  const envPath = path.join(__dirname, ".env");
  if (fs.existsSync(envPath)) {
    const content = fs.readFileSync(envPath, "utf-8");
    for (const line of content.split("\n")) {
      const trimmed = line.trim();
      if (!trimmed || trimmed.startsWith("#")) continue;
      const eqIdx = trimmed.indexOf("=");
      if (eqIdx === -1) continue;
      const key = trimmed.slice(0, eqIdx).trim();
      const val = trimmed.slice(eqIdx + 1).trim();
      if (!process.env[key]) {
        process.env[key] = val;
      }
    }
  }
}
loadEnv();
import Database from "better-sqlite3";
import bcrypt from "bcryptjs";
import jwt from "jsonwebtoken";

const app = express();
const PORT = parseInt(process.env.PORT || "3008", 10);
const JWT_SECRET = process.env.JWT_SECRET || "vpn-admin-secret-key-2026";
const ADMIN_USERNAME = process.env.ADMIN_USERNAME || "admin";
const ADMIN_PASSWORD_HASH = process.env.ADMIN_PASSWORD || bcrypt.hashSync("admin123", 10);

app.use(cors());
app.use(express.json({ limit: "10mb" }));

// ==================== SQLite Database ====================
const DB_PATH = process.env.DB_PATH || path.join(__dirname, "..", "vpn_admin.db");
const db = new Database(DB_PATH);
db.pragma("journal_mode = WAL");
db.pragma("foreign_keys = ON");

// Create tables
db.exec(`
  CREATE TABLE IF NOT EXISTS users (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    name TEXT NOT NULL,
    email TEXT UNIQUE NOT NULL,
    phone TEXT DEFAULT '',
    password TEXT NOT NULL,
    device TEXT DEFAULT 'any',
    access_days INTEGER DEFAULT 30,
    max_speed TEXT DEFAULT '100 Mbps',
    active INTEGER DEFAULT 1,
    status TEXT DEFAULT 'active',
    created_at TEXT DEFAULT (datetime('now')),
    updated_at TEXT DEFAULT (datetime('now')),
    expires_at TEXT,
    last_login TEXT
  );

  CREATE TABLE IF NOT EXISTS ssh_accounts (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    host TEXT NOT NULL,
    port INTEGER DEFAULT 22,
    username TEXT NOT NULL,
    password TEXT DEFAULT '',
    private_key TEXT DEFAULT '',
    location TEXT DEFAULT '',
    max_speed TEXT DEFAULT '100 Mbps',
    active INTEGER DEFAULT 1,
    created_at TEXT DEFAULT (datetime('now')),
    updated_at TEXT DEFAULT (datetime('now'))
  );

  CREATE TABLE IF NOT EXISTS payloads (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    name TEXT NOT NULL,
    type TEXT NOT NULL DEFAULT 'custom',
    host TEXT DEFAULT '',
    port INTEGER DEFAULT 443,
    payload TEXT DEFAULT '',
    sni TEXT DEFAULT '',
    ssh_account_id INTEGER,
    active INTEGER DEFAULT 1,
    created_at TEXT DEFAULT (datetime('now')),
    updated_at TEXT DEFAULT (datetime('now')),
    FOREIGN KEY (ssh_account_id) REFERENCES ssh_accounts(id) ON DELETE CASCADE
  );

  CREATE TABLE IF NOT EXISTS online_users (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    user_id INTEGER,
    username TEXT NOT NULL,
    device TEXT DEFAULT '',
    ip_address TEXT DEFAULT '',
    connected_at TEXT DEFAULT (datetime('now')),
    last_heartbeat TEXT DEFAULT (datetime('now')),
    bytes_received INTEGER DEFAULT 0,
    bytes_sent INTEGER DEFAULT 0,
    FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
  );

  CREATE TABLE IF NOT EXISTS recent_activity (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    user_id INTEGER,
    action TEXT NOT NULL,
    details TEXT DEFAULT '',
    ip_address TEXT DEFAULT '',
    created_at TEXT DEFAULT (datetime('now')),
    FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE SET NULL
  );
`);

// Ensure admin user exists if not already
const adminExists = db.prepare("SELECT id FROM users WHERE email = ?").get("admin@codviber.com");
if (!adminExists) {
  const hashedPw = bcrypt.hashSync("admin123", 10);
  db.prepare("INSERT INTO users (name, email, password, access_days, status) VALUES (?, ?, ?, ?, ?)")
    .run("Admin", "admin@codviber.com", hashedPw, 365, "active");
}

// Ensure default SSH accounts exist
const sshCount = db.prepare("SELECT COUNT(*) as count FROM ssh_accounts").get() as any;
if (sshCount.count === 0) {
  const insertSSH = db.prepare("INSERT INTO ssh_accounts (host, port, username, password, location) VALUES (?, ?, ?, ?, ?)");
  insertSSH.run("sg1.codviber.com", 22, "vpn-tun", "changeme", "Singapore");
  insertSSH.run("us1.codviber.com", 22, "vpn-tun", "changeme", "United States");
  insertSSH.run("br1.codviber.com", 22, "vpn-tun", "changeme", "Brazil");
}

// Ensure default payloads exist
const payloadCount = db.prepare("SELECT COUNT(*) as count FROM payloads").get() as any;
if (payloadCount.count === 0) {
  const insertPayload = db.prepare("INSERT INTO payloads (name, type, host, port, payload, sni, ssh_account_id) VALUES (?, ?, ?, ?, ?, ?, ?)");
  insertPayload.run("TIM Direct", "tim", "tim.br", 443, "CONNECT [host_port] HTTP/1.1\r\nHost: tim.br\r\n\r\n", "tim.br", 1);
  insertPayload.run("Vivo Direct", "vivo", "vivo.com.br", 443, "CONNECT [host_port] HTTP/1.1\r\nHost: vivo.com.br\r\n\r\n", "vivo.com.br", 2);
  insertPayload.run("Claro Direct", "claro", "claro.com.br", 443, "CONNECT [host_port] HTTP/1.1\r\nHost: claro.com.br\r\n\r\n", "claro.com.br", 3);
}

// ==================== WireGuard ====================
interface VpnClient {
  id: string;
  name: string;
  publicKey: string;
  privateKey: string;
  presharedKey: string;
  allowedIPs: string;
  createdAt: string;
  lastSeen?: string;
  enabled: boolean;
  downloadBytes: number;
  uploadBytes: number;
}

interface VpnStatus {
  interface: string;
  running: boolean;
  publicKey: string;
  listenPort: number;
  clients: number;
  totalDownload: number;
  totalUpload: number;
}

let clients: VpnClient[] = [];
let vpnStatus: VpnStatus = {
  interface: process.env.WG_INTERFACE || "wg0",
  running: false,
  publicKey: "",
  listenPort: 51820,
  clients: 0,
  totalDownload: 0,
  totalUpload: 0,
};

// ==================== Middleware ====================

// Admin auth middleware
function adminAuth(req: any, res: any, next: any) {
  const authHeader = req.headers.authorization;
  if (!authHeader || !authHeader.startsWith("Bearer ")) {
    return res.status(401).json({ ok: false, error: "Token de acesso obrigatório" });
  }
  const token = authHeader.split(" ")[1];
  try {
    const decoded = jwt.verify(token, JWT_SECRET) as any;
    if (decoded.role !== "admin") {
      return res.status(403).json({ ok: false, error: "Acesso restrito a administradores" });
    }
    req.user = decoded;
    next();
  } catch {
    return res.status(401).json({ ok: false, error: "Token inválido ou expirado" });
  }
}

// User auth middleware
function userAuth(req: any, res: any, next: any) {
  const authHeader = req.headers.authorization;
  if (!authHeader || !authHeader.startsWith("Bearer ")) {
    return res.status(401).json({ ok: false, error: "Token de acesso obrigatório" });
  }
  const token = authHeader.split(" ")[1];
  try {
    const decoded = jwt.verify(token, JWT_SECRET) as any;
    req.user = decoded;
    next();
  } catch {
    return res.status(401).json({ ok: false, error: "Token inválido ou expirado" });
  }
}

// ==================== Auth Routes ====================

// Admin login
app.post("/api/auth/login", (req, res) => {
  const { username, password } = req.body;
  
  if (username !== ADMIN_USERNAME) {
    return res.status(401).json({ ok: false, error: "Credenciais inválidas" });
  }
  
  if (!bcrypt.compareSync(password, ADMIN_PASSWORD_HASH)) {
    return res.status(401).json({ ok: false, error: "Credenciais inválidas" });
  }
  
  const token = jwt.sign({ username, role: "admin" }, JWT_SECRET, { expiresIn: "24h" });
  
  // Log activity
  db.prepare("INSERT INTO recent_activity (user_id, action, details) VALUES (?, ?, ?)")
    .run(null, "admin_login", `Admin ${username} logou no sistema`);
  
  res.json({ ok: true, token, user: { username, role: "admin" } });
});

// User login
app.post("/api/auth/user-login", (req, res) => {
  const { email, password } = req.body;
  
  if (!email || !password) {
    return res.status(400).json({ ok: false, error: "Email e senha obrigatórios" });
  }
  
  const user = db.prepare("SELECT * FROM users WHERE email = ?").get(email) as any;
  if (!user) {
    return res.status(401).json({ ok: false, error: "Credenciais inválidas" });
  }
  
  if (!bcrypt.compareSync(password, user.password)) {
    return res.status(401).json({ ok: false, error: "Credenciais inválidas" });
  }
  
  if (!user.active) {
    return res.status(403).json({ ok: false, error: "Conta desativada" });
  }
  
  // Check expiration
  if (user.expires_at && new Date(user.expires_at) < new Date()) {
    return res.status(403).json({ ok: false, error: "Conta expirada" });
  }
  
  // Update last login
  db.prepare("UPDATE users SET last_login = datetime('now') WHERE id = ?").run(user.id);
  
  const token = jwt.sign({ id: user.id, email: user.email, role: "user" }, JWT_SECRET, { expiresIn: "7d" });
  
  res.json({ ok: true, token, user: { id: user.id, name: user.name, email: user.email } });
});

// User register
app.post("/api/auth/register", (req, res) => {
  const { name, email, phone, password } = req.body;
  
  if (!name || !email || !password) {
    return res.status(400).json({ ok: false, error: "Nome, email e senha obrigatórios" });
  }
  
  const existing = db.prepare("SELECT id FROM users WHERE email = ?").get(email);
  if (existing) {
    return res.status(409).json({ ok: false, error: "Email já cadastrado" });
  }
  
  const hashedPw = bcrypt.hashSync(password, 10);
  const expiresAt = new Date(Date.now() + 30 * 24 * 60 * 60 * 1000).toISOString();
  
  const result = db.prepare(
    "INSERT INTO users (name, email, phone, password, access_days, expires_at, status) VALUES (?, ?, ?, ?, ?, ?, ?)"
  ).run(name, email, phone || "", hashedPw, 30, expiresAt, "active");
  
  res.json({ ok: true, message: "Conta criada com sucesso", userId: result.lastInsertRowid });
});

// ==================== User Routes (Admin) ====================

// List all users
app.get("/api/users", adminAuth, (req, res) => {
  const search = (req.query.search as string) || "";
  let query = "SELECT * FROM users";
  let params: any[] = [];
  
  if (search) {
    query += " WHERE name LIKE ? OR email LIKE ? OR phone LIKE ?";
    const searchTerm = `%${search}%`;
    params = [searchTerm, searchTerm, searchTerm];
  }
  
  query += " ORDER BY created_at DESC";
  
  const users = db.prepare(query).all(...params);
  res.json({ ok: true, users });
});

// Get single user
app.get("/api/users/:id", adminAuth, (req, res) => {
  const user = db.prepare("SELECT * FROM users WHERE id = ?").get(req.params.id);
  if (!user) {
    return res.status(404).json({ ok: false, error: "Usuário não encontrado" });
  }
  res.json({ ok: true, user });
});

// Create user
app.post("/api/users", adminAuth, (req, res) => {
  const { name, email, phone, password, device, access_days, max_speed, active } = req.body;
  
  if (!name || !email) {
    return res.status(400).json({ ok: false, error: "Nome e email obrigatórios" });
  }
  
  const existing = db.prepare("SELECT id FROM users WHERE email = ?").get(email);
  if (existing) {
    return res.status(409).json({ ok: false, error: "Email já cadastrado" });
  }
  
  const hashedPw = password ? bcrypt.hashSync(password, 10) : bcrypt.hashSync("123456", 10);
  const days = parseInt(access_days || "30", 10);
  const expiresAt = new Date(Date.now() + days * 24 * 60 * 60 * 1000).toISOString();
  
  const result = db.prepare(
    "INSERT INTO users (name, email, phone, password, device, access_days, max_speed, active, status, expires_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)"
  ).run(name, email, phone || "", hashedPw, device || "any", days, max_speed || "100 Mbps", active !== undefined ? (active ? 1 : 0) : 1, active ? "active" : "pending", expiresAt);
  
  const newUser = db.prepare("SELECT * FROM users WHERE id = ?").get(result.lastInsertRowid);
  
  db.prepare("INSERT INTO recent_activity (user_id, action, details) VALUES (?, ?, ?)")
    .run(null, "user_created", `Usuário ${name} (${email}) criado`);
  
  res.json({ ok: true, user: newUser });
});

// Update user
app.put("/api/users/:id", adminAuth, (req, res) => {
  const { id } = req.params;
  const existing = db.prepare("SELECT * FROM users WHERE id = ?").get(id) as any;
  if (!existing) {
    return res.status(404).json({ ok: false, error: "Usuário não encontrado" });
  }
  
  const { name, email, phone, password, device, access_days, max_speed, active } = req.body;
  
  const updatedName = name || existing.name;
  const updatedEmail = email || existing.email;
  const updatedPhone = phone !== undefined ? phone : existing.phone;
  const updatedDevice = device || existing.device;
  const updatedMaxSpeed = max_speed || existing.max_speed;
  const updatedActive = active !== undefined ? (active ? 1 : 0) : existing.active;
  const updatedStatus = updatedActive ? "active" : "pending";
  
  // Recalculate expiration if access_days provided
  let expiresAt = existing.expires_at;
  if (access_days) {
    const days = parseInt(access_days, 10);
    expiresAt = new Date(Date.now() + days * 24 * 60 * 60 * 1000).toISOString();
  }
  
  if (password) {
    const hashedPw = bcrypt.hashSync(password, 10);
    db.prepare(
      "UPDATE users SET name=?, email=?, phone=?, password=?, device=?, max_speed=?, active=?, status=?, expires_at=?, updated_at=datetime('now') WHERE id=?"
    ).run(updatedName, updatedEmail, updatedPhone, hashedPw, updatedDevice, updatedMaxSpeed, updatedActive, updatedStatus, expiresAt, id);
  } else {
    db.prepare(
      "UPDATE users SET name=?, email=?, phone=?, device=?, max_speed=?, active=?, status=?, expires_at=?, updated_at=datetime('now') WHERE id=?"
    ).run(updatedName, updatedEmail, updatedPhone, updatedDevice, updatedMaxSpeed, updatedActive, updatedStatus, expiresAt, id);
  }
  
  const updatedUser = db.prepare("SELECT * FROM users WHERE id = ?").get(id);
  
  db.prepare("INSERT INTO recent_activity (user_id, action, details) VALUES (?, ?, ?)")
    .run(null, "user_updated", `Usuário ${updatedName} atualizado`);
  
  res.json({ ok: true, user: updatedUser });
});

// Delete user
app.delete("/api/users/:id", adminAuth, (req, res) => {
  const { id } = req.params;
  const existing = db.prepare("SELECT * FROM users WHERE id = ?").get(id) as any;
  if (!existing) {
    return res.status(404).json({ ok: false, error: "Usuário não encontrado" });
  }
  
  db.prepare("DELETE FROM users WHERE id = ?").run(id);
  
  db.prepare("INSERT INTO recent_activity (user_id, action, details) VALUES (?, ?, ?)")
    .run(null, "user_deleted", `Usuário ${existing.name} (${existing.email}) removido`);
  
  res.json({ ok: true, message: "Usuário removido com sucesso" });
});

// Extend user access
app.post("/api/users/:id/extend", adminAuth, (req, res) => {
  const { id } = req.params;
  const { days } = req.body;
  
  if (!days || days < 1) {
    return res.status(400).json({ ok: false, error: "Número de dias inválido" });
  }
  
  const user = db.prepare("SELECT * FROM users WHERE id = ?").get(id) as any;
  if (!user) {
    return res.status(404).json({ ok: false, error: "Usuário não encontrado" });
  }
  
  // Calculate new expiration
  const currentExpiry = user.expires_at ? new Date(user.expires_at) : new Date();
  const newExpiry = new Date(Math.max(currentExpiry.getTime(), Date.now()) + days * 24 * 60 * 60 * 1000);
  
  const addedDays = parseInt(days, 10);
  db.prepare("UPDATE users SET access_days = access_days + ?, expires_at = ?, updated_at = datetime('now') WHERE id = ?")
    .run(addedDays, newExpiry.toISOString(), id);
  
  const updatedUser = db.prepare("SELECT * FROM users WHERE id = ?").get(id);
  
  db.prepare("INSERT INTO recent_activity (user_id, action, details) VALUES (?, ?, ?)")
    .run(null, "access_extended", `Acesso de ${user.name} estendido em ${days} dias`);
  
  res.json({ ok: true, user: updatedUser });
});

// Toggle user active status
app.post("/api/users/:id/toggle-active", adminAuth, (req, res) => {
  const { id } = req.params;
  const user = db.prepare("SELECT * FROM users WHERE id = ?").get(id) as any;
  if (!user) {
    return res.status(404).json({ ok: false, error: "Usuário não encontrado" });
  }
  
  const newActive = user.active ? 0 : 1;
  const newStatus = newActive ? "active" : "pending";
  
  db.prepare("UPDATE users SET active = ?, status = ?, updated_at = datetime('now') WHERE id = ?")
    .run(newActive, newStatus, id);
  
  const updatedUser = db.prepare("SELECT * FROM users WHERE id = ?").get(id);
  
  db.prepare("INSERT INTO recent_activity (user_id, action, details) VALUES (?, ?, ?)")
    .run(null, "user_toggled", `Usuário ${user.name} ${newActive ? 'ativado' : 'desativado'}`);
  
  res.json({ ok: true, user: updatedUser });
});

// ==================== SSH Accounts Routes ====================

// List SSH accounts
app.get("/api/tunnels/ssh", adminAuth, (req, res) => {
  const accounts = db.prepare("SELECT * FROM ssh_accounts ORDER BY created_at DESC").all();
  res.json({ ok: true, accounts });
});

// Create SSH account
app.post("/api/tunnels/ssh", adminAuth, (req, res) => {
  const { host, port, username, password, private_key, location, max_speed } = req.body;
  
  if (!host || !username) {
    return res.status(400).json({ ok: false, error: "Host e username obrigatórios" });
  }
  
  const result = db.prepare(
    "INSERT INTO ssh_accounts (host, port, username, password, private_key, location, max_speed) VALUES (?, ?, ?, ?, ?, ?, ?)"
  ).run(host, parseInt(port || "22", 10), username, password || "", private_key || "", location || "", max_speed || "100 Mbps");
  
  const account = db.prepare("SELECT * FROM ssh_accounts WHERE id = ?").get(result.lastInsertRowid);
  res.json({ ok: true, account });
});

// Update SSH account
app.put("/api/tunnels/ssh/:id", adminAuth, (req, res) => {
  const { id } = req.params;
  const existing = db.prepare("SELECT * FROM ssh_accounts WHERE id = ?").get(id) as any;
  if (!existing) {
    return res.status(404).json({ ok: false, error: "Conta SSH não encontrada" });
  }
  
  const { host, port, username, password, private_key, location, max_speed, active } = req.body;
  
  db.prepare(
    "UPDATE ssh_accounts SET host=?, port=?, username=?, password=?, private_key=?, location=?, max_speed=?, active=?, updated_at=datetime('now') WHERE id=?"
  ).run(
    host || existing.host,
    port ? parseInt(port, 10) : existing.port,
    username || existing.username,
    password !== undefined ? password : existing.password,
    private_key !== undefined ? private_key : existing.private_key,
    location !== undefined ? location : existing.location,
    max_speed || existing.max_speed,
    active !== undefined ? (active ? 1 : 0) : existing.active,
    id
  );
  
  const account = db.prepare("SELECT * FROM ssh_accounts WHERE id = ?").get(id);
  res.json({ ok: true, account });
});

// Delete SSH account
app.delete("/api/tunnels/ssh/:id", adminAuth, (req, res) => {
  const { id } = req.params;
  const existing = db.prepare("SELECT * FROM ssh_accounts WHERE id = ?").get(id);
  if (!existing) {
    return res.status(404).json({ ok: false, error: "Conta SSH não encontrada" });
  }
  
  db.prepare("DELETE FROM ssh_accounts WHERE id = ?").run(id);
  res.json({ ok: true, message: "Conta SSH removida com sucesso" });
});

// ==================== Payload Routes ====================

// List payloads
app.get("/api/tunnels/payloads", adminAuth, (req, res) => {
  const sshId = req.query.ssh_id as string;
  let query = `
    SELECT p.*, s.host as ssh_host, s.username as ssh_username, s.location as ssh_location
    FROM payloads p
    LEFT JOIN ssh_accounts s ON p.ssh_account_id = s.id
  `;
  let params: any[] = [];
  
  if (sshId) {
    query += " WHERE p.ssh_account_id = ?";
    params.push(parseInt(sshId, 10));
  }
  
  query += " ORDER BY p.created_at DESC";
  
  const payloads = db.prepare(query).all(...params);
  res.json({ ok: true, payloads });
});

// Create payload
app.post("/api/tunnels/payloads", adminAuth, (req, res) => {
  const { name, type, host, port, payload, sni, ssh_account_id, active } = req.body;
  
  if (!name || !payload) {
    return res.status(400).json({ ok: false, error: "Nome e payload obrigatórios" });
  }
  
  const result = db.prepare(
    "INSERT INTO payloads (name, type, host, port, payload, sni, ssh_account_id, active) VALUES (?, ?, ?, ?, ?, ?, ?, ?)"
  ).run(name, type || "custom", host || "", parseInt(port || "443", 10), payload, sni || "", ssh_account_id || null, active !== undefined ? (active ? 1 : 0) : 1);
  
  const newPayload = db.prepare("SELECT * FROM payloads WHERE id = ?").get(result.lastInsertRowid);
  res.json({ ok: true, payload: newPayload });
});

// Update payload
app.put("/api/tunnels/payloads/:id", adminAuth, (req, res) => {
  const { id } = req.params;
  const existing = db.prepare("SELECT * FROM payloads WHERE id = ?").get(id) as any;
  if (!existing) {
    return res.status(404).json({ ok: false, error: "Payload não encontrado" });
  }
  
  const { name, type, host, port, payload, sni, ssh_account_id, active } = req.body;
  
  db.prepare(
    "UPDATE payloads SET name=?, type=?, host=?, port=?, payload=?, sni=?, ssh_account_id=?, active=?, updated_at=datetime('now') WHERE id=?"
  ).run(
    name || existing.name,
    type || existing.type,
    host !== undefined ? host : existing.host,
    port ? parseInt(port, 10) : existing.port,
    payload || existing.payload,
    sni !== undefined ? sni : existing.sni,
    ssh_account_id !== undefined ? ssh_account_id : existing.ssh_account_id,
    active !== undefined ? (active ? 1 : 0) : existing.active,
    id
  );
  
  const updated = db.prepare("SELECT * FROM payloads WHERE id = ?").get(id);
  res.json({ ok: true, payload: updated });
});

// Delete payload
app.delete("/api/tunnels/payloads/:id", adminAuth, (req, res) => {
  const { id } = req.params;
  const existing = db.prepare("SELECT * FROM payloads WHERE id = ?").get(id);
  if (!existing) {
    return res.status(404).json({ ok: false, error: "Payload não encontrado" });
  }
  
  db.prepare("DELETE FROM payloads WHERE id = ?").run(id);
  res.json({ ok: true, message: "Payload removido com sucesso" });
});

// ==================== Stats Routes ====================

// System status (CPU, RAM, Disk, Uptime)
app.get("/api/stats/status", (_req, res) => {
  try {
    // CPU
    const cpuInfo = execSync("nproc 2>/dev/null || echo 1", { encoding: "utf-8" }).trim();
    const cpuCores = parseInt(cpuInfo, 10) || 1;
    
    // Get CPU usage from /proc/stat
    const cpuLoad = execSync("top -bn1 | grep 'Cpu(s)' | awk '{print $2}' 2>/dev/null || echo 0", { encoding: "utf-8" }).trim();
    const cpuUsage = parseFloat(cpuLoad) || 0;
    
    // RAM
    const memTotal = execSync("free -m | awk '/Mem:/{print $2}' 2>/dev/null || echo 1024", { encoding: "utf-8" }).trim();
    const memUsed = execSync("free -m | awk '/Mem:/{print $3}' 2>/dev/null || echo 512", { encoding: "utf-8" }).trim();
    const memFree = execSync("free -m | awk '/Mem:/{print $4}' 2>/dev/null || echo 512", { encoding: "utf-8" }).trim();
    
    // Disk
    const diskInfo = execSync("df -h / | awk 'NR==2{print $2, $3, $4, $5}' 2>/dev/null || echo '50G 20G 30G 40%'", { encoding: "utf-8" }).trim();
    const diskParts = diskInfo.split(" ");
    
    // Uptime
    const uptimeStr = execSync("uptime -p 2>/dev/null || echo 'up unknown'", { encoding: "utf-8" }).trim();
    const uptimeSecs = execSync("cat /proc/uptime | awk '{print $1}' 2>/dev/null || echo 0", { encoding: "utf-8" }).trim();
    
    // Get number of online users
    const onlineUsers = db.prepare("SELECT COUNT(*) as count FROM online_users WHERE last_heartbeat > datetime('now', '-5 minutes')").get() as any;
    
    // VPN status
    let vpnState = "disconnected";
    try {
      const wgCheck = execSync(`wg show ${vpnStatus.interface} 2>/dev/null || echo "NOT_FOUND"`, { encoding: "utf-8", timeout: 3000 });
      if (!wgCheck.trim().includes("NOT_FOUND")) {
        vpnState = "connected";
      }
    } catch { vpnState = "disconnected"; }
    
    res.json({
      ok: true,
      stats: {
        cpu: {
          usage: cpuUsage,
          cores: cpuCores,
          model: execSync("cat /proc/cpuinfo | grep 'model name' | head -1 | cut -d: -f2 | xargs 2>/dev/null || echo 'Unknown'", { encoding: "utf-8" }).trim(),
        },
        ram: {
          total: parseInt(memTotal, 10) || 0,
          used: parseInt(memUsed, 10) || 0,
          free: parseInt(memFree, 10) || 0,
          percent: parseInt(memTotal, 10) > 0 ? Math.round((parseInt(memUsed, 10) / parseInt(memTotal, 10)) * 100) : 0,
        },
        disk: {
          total: diskParts[0] || "0",
          used: diskParts[1] || "0",
          free: diskParts[2] || "0",
          percent: diskParts[3] || "0%",
        },
        uptime: {
          human: uptimeStr.replace("up ", ""),
          seconds: parseFloat(uptimeSecs) || 0,
        },
        vpn: {
          status: vpnState,
          interface: vpnStatus.interface,
        },
        online_users: (onlineUsers as any).count || 0,
        timestamp: new Date().toISOString(),
      }
    });
  } catch (err: any) {
    res.json({
      ok: true,
      stats: {
        cpu: { usage: 0, cores: 1, model: "Unknown" },
        ram: { total: 0, used: 0, free: 0, percent: 0 },
        disk: { total: "0", used: "0", free: "0", percent: "0%" },
        uptime: { human: "unknown", seconds: 0 },
        vpn: { status: "unknown", interface: vpnStatus.interface },
        online_users: 0,
        timestamp: new Date().toISOString(),
      }
    });
  }
});

// Dashboard stats
app.get("/api/stats/dashboard", adminAuth, (_req, res) => {
  const totalUsers = db.prepare("SELECT COUNT(*) as count FROM users").get() as any;
  const activeUsers = db.prepare("SELECT COUNT(*) as count FROM users WHERE active = 1 AND (expires_at IS NULL OR expires_at > datetime('now'))").get() as any;
  const expiringUsers = db.prepare("SELECT COUNT(*) as count FROM users WHERE active = 1 AND expires_at IS NOT NULL AND expires_at > datetime('now') AND expires_at < datetime('now', '+7 days')").get() as any;
  const expiredUsers = db.prepare("SELECT COUNT(*) as count FROM users WHERE expires_at IS NOT NULL AND expires_at < datetime('now')").get() as any;
  const onlineNow = db.prepare("SELECT COUNT(*) as count FROM online_users WHERE last_heartbeat > datetime('now', '-5 minutes')").get() as any;
  const totalSshAccounts = db.prepare("SELECT COUNT(*) as count FROM ssh_accounts").get() as any;
  const totalPayloads = db.prepare("SELECT COUNT(*) as count FROM payloads").get() as any;
  const recentActivity = db.prepare("SELECT * FROM recent_activity ORDER BY created_at DESC LIMIT 10").all();
  
  res.json({
    ok: true,
    stats: {
      totalUsers: (totalUsers as any).count,
      activeUsers: (activeUsers as any).count,
      expiringUsers: (expiringUsers as any).count,
      expiredUsers: (expiredUsers as any).count,
      onlineNow: (onlineNow as any).count,
      totalSshAccounts: (totalSshAccounts as any).count,
      totalPayloads: (totalPayloads as any).count,
      recentActivity,
    }
  });
});

// ==================== Online Users ====================

// List online users
app.get("/api/online-users", adminAuth, (_req, res) => {
  const online = db.prepare(`
    SELECT ou.*, u.name as user_name, u.email as user_email
    FROM online_users ou
    LEFT JOIN users u ON ou.user_id = u.id
    WHERE ou.last_heartbeat > datetime('now', '-5 minutes')
    ORDER BY ou.last_heartbeat DESC
  `).all();
  res.json({ ok: true, online_users: online });
});

// User heartbeat
app.post("/api/vpn/heartbeat", userAuth, (req, res) => {
  const { device, ip_address, bytes_received, bytes_sent } = req.body;
  const userId = (req.user as any).id;
  const username = (req.user as any).email;
  
  const existing = db.prepare("SELECT * FROM online_users WHERE user_id = ?").get(userId) as any;
  
  if (existing) {
    db.prepare(
      "UPDATE online_users SET last_heartbeat = datetime('now'), device = ?, ip_address = ?, bytes_received = ?, bytes_sent = ? WHERE id = ?"
    ).run(device || existing.device, ip_address || existing.ip_address, bytes_received || 0, bytes_sent || 0, existing.id);
  } else {
    db.prepare(
      "INSERT INTO online_users (user_id, username, device, ip_address, bytes_received, bytes_sent) VALUES (?, ?, ?, ?, ?, ?)"
    ).run(userId, username, device || "", ip_address || "", bytes_received || 0, bytes_sent || 0);
  }
  
  res.json({ ok: true, message: "Heartbeat received" });
});

// ==================== VPN Routes (from original) ====================

// WireGuard helpers
function getWireGuardStatus(): VpnStatus {
  try {
    const output = execSync(`wg show ${vpnStatus.interface} 2>/dev/null || echo "NOT_FOUND"`, {
      encoding: "utf-8",
      timeout: 5000,
    });

    if (output.trim() === "NOT_FOUND") {
      return { ...vpnStatus, running: false };
    }

    const lines = output.split("\n");
    const parsed: VpnStatus = {
      interface: vpnStatus.interface,
      running: true,
      publicKey: "",
      listenPort: 51820,
      clients: 0,
      totalDownload: 0,
      totalUpload: 0,
    };

    let clientCount = 0;
    for (const line of lines) {
      const trimmed = line.trim();
      if (trimmed.startsWith("public key:")) {
        parsed.publicKey = trimmed.split(":")[1].trim();
      } else if (trimmed.startsWith("listening port:")) {
        parsed.listenPort = parseInt(trimmed.split(":")[1].trim(), 10);
      } else if (trimmed.startsWith("peer:")) {
        clientCount++;
      } else if (trimmed.startsWith("transfer:")) {
        const match = trimmed.match(/([\d.]+)\s*(KiB|MiB|GiB)\s+received,\s+([\d.]+)\s*(KiB|MiB|GiB)\s+sent/);
        if (match) {
          const rx = parseBytes(match[1], match[2]);
          const tx = parseBytes(match[3], match[4]);
          parsed.totalDownload += rx;
          parsed.totalUpload += tx;
        }
      }
    }

    parsed.clients = clientCount;
    return parsed;
  } catch {
    return { ...vpnStatus, running: false };
  }
}

function parseBytes(value: string, unit: string): number {
  const num = parseFloat(value);
  switch (unit) {
    case "KiB": return num * 1024;
    case "MiB": return num * 1024 * 1024;
    case "GiB": return num * 1024 * 1024 * 1024;
    default: return num;
  }
}

function generateKeyPair() {
  const privateKey = execSync("wg genkey", { encoding: "utf-8" }).trim();
  const publicKey = execSync(`echo "${privateKey}" | wg pubkey`, { encoding: "utf-8" }).trim();
  const presharedKey = execSync("wg genpsk", { encoding: "utf-8" }).trim();
  return { privateKey, publicKey, presharedKey };
}

function reloadWireGuard() {
  try {
    execSync(`wg addconf ${vpnStatus.interface} <(wg-quick strip ${vpnStatus.interface})`, {
      timeout: 5000,
      shell: "/bin/bash",
    });
    return true;
  } catch {
    return false;
  }
}

// Status da VPN
app.get("/api/vpn/status", (_req, res) => {
  const status = getWireGuardStatus();
  vpnStatus = status;
  res.json({ ok: true, status });
});

// Ativar/Desativar VPN
app.post("/api/vpn/toggle", adminAuth, (req, res) => {
  const { enable } = req.body;

  try {
    if (enable) {
      execSync(`wg-quick up ${vpnStatus.interface}`, { timeout: 10000 });
    } else {
      execSync(`wg-quick down ${vpnStatus.interface}`, { timeout: 10000 });
    }
    vpnStatus.running = enable;
    res.json({ ok: true, running: enable });
  } catch (err: any) {
    res.status(500).json({ ok: false, error: err.message });
  }
});

// Listar clientes
app.get("/api/vpn/clients", (_req, res) => {
  try {
    const wgOutput = execSync(`wg show ${vpnStatus.interface} dump 2>/dev/null || echo ""`, {
      encoding: "utf-8",
      timeout: 5000,
    });

    if (wgOutput.trim()) {
      const lines = wgOutput.trim().split("\n");
      for (let i = 1; i < lines.length; i++) {
        const parts = lines[i].split("\t");
        if (parts.length >= 5) {
          const pubKey = parts[0];
          const existing = clients.find((c) => c.publicKey === pubKey);
          const tx = parseInt(parts[5]) || 0;
          const rx = parseInt(parts[6]) || 0;

          if (existing) {
            existing.downloadBytes = rx;
            existing.uploadBytes = tx;
            existing.lastSeen = new Date().toISOString();
          }
        }
      }
    }
  } catch {}

  res.json({ ok: true, clients });
});

// Adicionar cliente
app.post("/api/vpn/clients", adminAuth, (req, res) => {
  const { name, allowedIPs } = req.body;

  if (!name) {
    return res.status(400).json({ ok: false, error: "Nome do cliente é obrigatório" });
  }

  try {
    const keys = generateKeyPair();
    const id = randomBytes(8).toString("hex");
    const clientIP = allowedIPs || `10.0.0.${clients.length + 2}/32`;

    const newClient: VpnClient = {
      id,
      name,
      publicKey: keys.publicKey,
      privateKey: keys.privateKey,
      presharedKey: keys.presharedKey,
      allowedIPs: clientIP,
      createdAt: new Date().toISOString(),
      enabled: true,
      downloadBytes: 0,
      uploadBytes: 0,
    };

    clients.push(newClient);

    const peerConfig = `
[Peer]
PublicKey = ${keys.publicKey}
PresharedKey = ${keys.presharedKey}
AllowedIPs = ${clientIP}
`;

    const configPath = process.env.WG_CONFIG_PATH || `/etc/wireguard/${vpnStatus.interface}.conf`;
    if (fs.existsSync(configPath)) {
      fs.appendFileSync(configPath, peerConfig);
      reloadWireGuard();
    }

    res.json({ ok: true, client: { ...newClient, privateKey: keys.privateKey, presharedKey: keys.presharedKey } });
  } catch (err: any) {
    res.status(500).json({ ok: false, error: err.message });
  }
});

// Remover cliente
app.delete("/api/vpn/clients/:id", adminAuth, (req, res) => {
  const { id } = req.params;
  const index = clients.findIndex((c) => c.id === id);

  if (index === -1) {
    return res.status(404).json({ ok: false, error: "Cliente não encontrado" });
  }

  const client = clients[index];
  clients.splice(index, 1);

  try {
    const configPath = process.env.WG_CONFIG_PATH || `/etc/wireguard/${vpnStatus.interface}.conf`;

    if (fs.existsSync(configPath)) {
      let config = fs.readFileSync(configPath, "utf-8");
      const peerRegex = new RegExp(`\\[Peer\\][^\\[]*PublicKey\\s*=\\s*${escapeRegex(client.publicKey)}[^\\[]*`, "g");
      config = config.replace(peerRegex, "");
      fs.writeFileSync(configPath, config);
      reloadWireGuard();
    }
  } catch {}

  res.json({ ok: true, message: "Cliente removido" });
});

// Gerar config do cliente (QR code ou arquivo)
app.get("/api/vpn/clients/:id/config", (req, res) => {
  const { id } = req.params;
  const client = clients.find((c) => c.id === id);

  if (!client) {
    return res.status(404).json({ ok: false, error: "Cliente não encontrado" });
  }

  const serverStatus = getWireGuardStatus();
  const serverPubKey = serverStatus.publicKey || process.env.WG_PUBLIC_KEY || "";
  const endpoint = req.headers.host?.split(":")[0] || "localhost";
  const port = serverStatus.listenPort || 51820;

  const config = `[Interface]
PrivateKey = ${client.privateKey}
Address = ${client.allowedIPs}
DNS = 1.1.1.1, 8.8.8.8

[Peer]
PublicKey = ${serverPubKey}
PresharedKey = ${client.presharedKey}
Endpoint = ${endpoint}:${port}
AllowedIPs = 0.0.0.0/0, ::/0
PersistentKeepalive = 25
`;

  res.json({ ok: true, config });
});

// Gerar QR Code (via URL)
app.get("/api/vpn/clients/:id/qrcode", (req, res) => {
  const { id } = req.params;
  const client = clients.find((c) => c.id === id);

  if (!client) {
    return res.status(404).json({ ok: false, error: "Cliente não encontrado" });
  }

  const serverStatus = getWireGuardStatus();
  const serverPubKey = serverStatus.publicKey || process.env.WG_PUBLIC_KEY || "";
  const endpoint = req.headers.host?.split(":")[0] || "localhost";
  const port = serverStatus.listenPort || 51820;

  const config = `[Interface]
PrivateKey = ${client.privateKey}
Address = ${client.allowedIPs}
DNS = 1.1.1.1, 8.8.8.8

[Peer]
PublicKey = ${serverPubKey}
PresharedKey = ${client.presharedKey}
Endpoint = ${endpoint}:${port}
AllowedIPs = 0.0.0.0/0, ::/0
PersistentKeepalive = 25
`;

  res.json({ ok: true, config, qrData: config });
});

// Estatísticas de tráfego
app.get("/api/vpn/stats", (_req, res) => {
  const status = getWireGuardStatus();
  res.json({
    ok: true,
    stats: {
      running: status.running,
      clients: clients.length,
      connectedClients: status.clients,
      totalDownload: status.totalDownload,
      totalUpload: status.totalUpload,
      publicKey: status.publicKey,
      listenPort: status.listenPort,
    },
  });
});

// Helper
function escapeRegex(str: string) {
  return str.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
}

// ==================== Recent Activity ====================
app.get("/api/activity", adminAuth, (req, res) => {
  const limit = parseInt((req.query.limit as string) || "50", 10);
  const activity = db.prepare("SELECT * FROM recent_activity ORDER BY created_at DESC LIMIT ?").all(limit);
  res.json({ ok: true, activity });
});

// ==================== Serve Frontend ====================
const frontendPath = path.join(__dirname, "..", "frontend");

// Serve static files
app.use(express.static(frontendPath));

// SPA fallback for frontend routes
app.use((req, res, next) => {
  // Skip API routes
  if (req.path.startsWith("/api/")) {
    return res.status(404).json({ ok: false, error: "Rota não encontrada" });
  }
  
  const indexPath = path.join(frontendPath, "index.html");
  if (fs.existsSync(indexPath)) {
    res.sendFile(indexPath);
  } else {
    res.status(404).json({ ok: false, error: "Frontend não encontrado. Execute o build primeiro." });
  }
});

// ==================== Start Server ====================
app.listen(PORT, () => {
  console.log(`🛡️ CodViber VPN Admin Server running on http://localhost:${PORT}`);
  console.log(`📡 API: http://localhost:${PORT}/api/stats/status`);
  console.log(`🌐 Frontend: http://localhost:${PORT}`);

  try {
    const status = getWireGuardStatus();
    vpnStatus = status;
    if (status.running) {
      console.log(`✅ WireGuard ${status.interface} is running`);
    } else {
      console.log(`⚠️  WireGuard ${vpnStatus.interface} not active`);
    }
  } catch {
    console.log(`⚠️  WireGuard not available (install with: apt install wireguard)`);
  }
  
  console.log(`📦 SQLite Database: ${DB_PATH}`);
});
