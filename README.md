# 🛡️ Hermes VPN

Aplicação de VPN para acesso seguro ao servidor Hermes via **WireGuard**.

## Estrutura

```
vpn-app/
├── server/          # Backend Node.js (API REST)
│   ├── server.ts    # Servidor principal
│   ├── package.json
│   └── .env.example
└── flutter-app/     # App mobile Flutter
    ├── lib/
    │   ├── main.dart
    │   ├── models/
    │   ├── providers/
    │   ├── screens/
    │   └── widgets/
    └── pubspec.yaml
```

## Backend

```bash
cd server
cp .env.example .env
npm install
npm run dev    # Desenvolvimento
npm start      # Produção (porta 3006)
```

### API

| Método | Rota | Descrição |
|--------|------|-----------|
| GET | `/api/vpn/status` | Status da VPN |
| POST | `/api/vpn/toggle` | Ativar/desativar |
| GET | `/api/vpn/clients` | Listar clientes |
| POST | `/api/vpn/clients` | Adicionar cliente |
| DELETE | `/api/vpn/clients/:id` | Remover cliente |
| GET | `/api/vpn/clients/:id/config` | Config do cliente |
| GET | `/api/vpn/clients/:id/qrcode` | QR code do cliente |
| GET | `/api/vpn/stats` | Estatísticas |

## Flutter App

```bash
cd flutter-app
flutter pub get
flutter run
```

## Requisitos

- Servidor Linux com WireGuard (`apt install wireguard`)
- Porta 3006 liberada no firewall
- Node.js 20+
- Flutter SDK 3.16+ (para desenvolvimento mobile)
