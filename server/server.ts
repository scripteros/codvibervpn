import express from "express";
import cors from "cors";
import { randomBytes } from "crypto";
import { execSync, exec } from "child_process";
import fs from "fs";
import path from "path";
import dotenv from "dotenv";

dotenv.config();

const app = express();
const PORT = parseInt(process.env.PORT || "3006", 10);

app.use(cors());
app.use(express.json({ limit: "5mb" }));

// ==================== In-Memory Store ====================
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

// ==================== WireGuard Helpers ====================

function getWireGuardStatus(): VpnStatus {
  try {
    const output = execSync(`wg show ${vpnStatus.interface} 2>/dev/null || echo "NOT_FOUND"`, {
      encoding: "utf-8",
      timeout: 5000,
    });

    if (output.trim() === "NOT_FOUND") {
      return { ...vpnStatus, running: false };
    }

    // Parse WireGuard output for status
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

// ==================== API Routes ====================

// Status da VPN
app.get("/api/vpn/status", (_req, res) => {
  const status = getWireGuardStatus();
  vpnStatus = status;
  res.json({ ok: true, status });
});

// Ativar/Desativar VPN
app.post("/api/vpn/toggle", (req, res) => {
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
  // Refresh from wg show
  try {
    const wgOutput = execSync(`wg show ${vpnStatus.interface} dump 2>/dev/null || echo ""`, {
      encoding: "utf-8",
      timeout: 5000,
    });

    if (wgOutput.trim()) {
      const lines = wgOutput.trim().split("\n");
      // First line is the interface itself
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
app.post("/api/vpn/clients", (req, res) => {
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

    // Add peer to WireGuard config
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
app.delete("/api/vpn/clients/:id", (req, res) => {
  const { id } = req.params;
  const index = clients.findIndex((c) => c.id === id);

  if (index === -1) {
    return res.status(404).json({ ok: false, error: "Cliente não encontrado" });
  }

  const client = clients[index];
  clients.splice(index, 1);

  // Remove from WireGuard config
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

  // Return as plain text that the Flutter app can convert to QR
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

// ==================== Start Server ====================

app.listen(PORT, () => {
  console.log(`🛡️ Hermes VPN Server running on http://localhost:${PORT}`);
  console.log(`📡 API: http://localhost:${PORT}/api/vpn/status`);

  // Check initial WireGuard status
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
});
