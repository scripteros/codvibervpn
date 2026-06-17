import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/vpn_provider.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  Timer? _speedTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final p = context.read<VpnProvider>();
      p.fetchStatus();
      p.sendHeartbeat();
    });
    _speedTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      final p = context.read<VpnProvider>();
      if (p.authenticated) {
        p.fetchStatus();
        p.sendHeartbeat();
      }
    });
  }

  @override
  void dispose() {
    _speedTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<VpnProvider>();
    final user = provider.user;
    final server = provider.activeServer;

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('CodVibe VPN', style: TextStyle(fontSize: 18)),
            if (server != null)
              Text(
                server.label ?? server.name,
                style: const TextStyle(fontSize: 11, color: Colors.grey),
              ),
          ],
        ),
        actions: [
          if (provider.authenticated)
            IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: () => provider.fetchStatus(),
            ),
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () {
              provider.logout();
              Navigator.pushReplacementNamed(context, '/login');
            },
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          // Connection Card
          _buildConnectionCard(provider),
          const SizedBox(height: 20),

          // Speed Card
          if (provider.vpnConnected) _buildSpeedCard(provider),
          if (provider.vpnConnected) const SizedBox(height: 20),

          // User Info
          if (user != null) _buildUserCard(user, provider),

          const SizedBox(height: 20),

          // Active server info
          if (server != null)
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFF1A1A2E),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.dns_outlined,
                    color: _getOperatorColor(server.label ?? ''),
                    size: 28,
                  ),
                  const SizedBox(width: 12),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        server.label ?? server.name,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                        ),
                      ),
                      Text(
                        '${server.host}:${server.port}',
                        style: const TextStyle(color: Colors.grey, fontSize: 12),
                      ),
                    ],
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildConnectionCard(VpnProvider provider) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: provider.vpnConnected
              ? [const Color(0xFF00D2FF), const Color(0xFF6C5CE7)]
              : [const Color(0xFF2D2D3A), const Color(0xFF1A1A2E)],
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: (provider.vpnConnected ? const Color(0xFF00D2FF) : Colors.black)
                .withValues(alpha: 0.2),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Status da VPN',
                    style: TextStyle(fontSize: 14, color: Colors.white70),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Container(
                        width: 12,
                        height: 12,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: provider.vpnConnected
                              ? Colors.greenAccent
                              : Colors.redAccent,
                          boxShadow: [
                            BoxShadow(
                              color: (provider.vpnConnected
                                      ? Colors.greenAccent
                                      : Colors.redAccent)
                                  .withValues(alpha: 0.5),
                              blurRadius: 8,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        provider.vpnConnected ? 'Conectado' : 'Desconectado',
                        style: const TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              // Connect/Disconnect button
              GestureDetector(
                onTap: () {
                  if (provider.vpnConnected) {
                    provider.disconnectVpn();
                  } else {
                    provider.connectVpn();
                  }
                },
                child: Container(
                  width: 60,
                  height: 32,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(16),
                    color: provider.vpnConnected
                        ? Colors.greenAccent.withValues(alpha: 0.3)
                        : Colors.grey.withValues(alpha: 0.3),
                  ),
                  child: AnimatedAlign(
                    duration: const Duration(milliseconds: 300),
                    alignment: provider.vpnConnected
                        ? Alignment.centerRight
                        : Alignment.centerLeft,
                    child: Container(
                      width: 28,
                      height: 28,
                      margin: const EdgeInsets.all(2),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color:
                            provider.vpnConnected ? Colors.greenAccent : Colors.grey,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _buildStatItem(
                Icons.arrow_downward,
                provider.downloadSpeed > 0
                    ? _formatSpeed(provider.downloadSpeed)
                    : '0 B/s',
                'Download',
                provider.vpnConnected,
              ),
              _buildStatItem(
                Icons.arrow_upward,
                provider.uploadSpeed > 0
                    ? _formatSpeed(provider.uploadSpeed)
                    : '0 B/s',
                'Upload',
                provider.vpnConnected,
              ),
              _buildStatItem(
                Icons.devices,
                '${provider.status?.connectedClients ?? 0}',
                'Conectados',
                provider.vpnConnected,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSpeedCard(VpnProvider provider) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A2E),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Velocidade em Tempo Real',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: Column(
                  children: [
                    const Icon(Icons.arrow_downward, color: Color(0xFF00D2FF), size: 24),
                    const SizedBox(height: 4),
                    Text(
                      _formatSpeed(provider.downloadSpeed),
                      style: const TextStyle(
                        color: Color(0xFF00D2FF),
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const Text(
                      'Download',
                      style: TextStyle(color: Colors.grey, fontSize: 12),
                    ),
                  ],
                ),
              ),
              Container(
                height: 60,
                width: 1,
                color: Colors.white.withValues(alpha: 0.1),
              ),
              Expanded(
                child: Column(
                  children: [
                    const Icon(Icons.arrow_upward, color: Color(0xFF6C5CE7), size: 24),
                    const SizedBox(height: 4),
                    Text(
                      _formatSpeed(provider.uploadSpeed),
                      style: const TextStyle(
                        color: Color(0xFF6C5CE7),
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const Text(
                      'Upload',
                      style: TextStyle(color: Colors.grey, fontSize: 12),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: provider.downloadSpeed / 1000000),
            duration: const Duration(milliseconds: 800),
            builder: (context, value, _) {
              return ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: value.clamp(0, 1),
                  backgroundColor: Colors.white.withValues(alpha: 0.1),
                  color: const Color(0xFF00D2FF),
                  minHeight: 4,
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildUserCard(VpnUser user, VpnProvider provider) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A2E),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                backgroundColor: const Color(0xFF6C5CE7),
                radius: 20,
                child: Text(
                  (user.name.isNotEmpty ? user.name[0] : '?').toUpperCase(),
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      user.name,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                    Text(
                      user.email,
                      style: const TextStyle(color: Colors.grey, fontSize: 12),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _buildUserStat('Acesso', user.expiryText),
              _buildUserStat('Limite', '${user.maxSpeedMbps} Mbps'),
              _buildUserStat('Status', user.isExpired ? 'Expirado' : 'Ativo'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildUserStat(String label, String value) {
    return Column(
      children: [
        Text(
          value,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: 14,
          ),
        ),
        Text(
          label,
          style: const TextStyle(color: Colors.grey, fontSize: 11),
        ),
      ],
    );
  }

  Widget _buildStatItem(IconData icon, String value, String label, bool active) {
    return Column(
      children: [
        Icon(icon, color: Colors.white70, size: 20),
        const SizedBox(height: 4),
        Text(
          value,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: 16,
          ),
        ),
        Text(
          label,
          style: const TextStyle(color: Colors.white60, fontSize: 12),
        ),
      ],
    );
  }

  String _formatSpeed(int bytesPerSecond) {
    if (bytesPerSecond < 1024) return '$bytesPerSecond B/s';
    if (bytesPerSecond < 1024 * 1024) {
      return '${(bytesPerSecond / 1024).toStringAsFixed(1)} KB/s';
    }
    return '${(bytesPerSecond / (1024 * 1024)).toStringAsFixed(1)} MB/s';
  }

  Color _getOperatorColor(String label) {
    final l = label.toLowerCase();
    if (l.contains('tim')) return const Color(0xFF003A70);
    if (l.contains('vivo')) return const Color(0xFF660099);
    if (l.contains('claro')) return const Color(0xFFFF0000);
    return const Color(0xFF6C5CE7);
  }
}
