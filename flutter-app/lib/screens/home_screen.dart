import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/vpn_provider.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<VpnProvider>().fetchStatus();
    });
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<VpnProvider>();
    final status = provider.status;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Hermes VPN'),
        actions: [
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
      body: RefreshIndicator(
        onRefresh: () => provider.fetchStatus(),
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            // Status Card
            _buildStatusCard(status, provider),
            const SizedBox(height: 24),

            // Quick Actions
            const Text(
              'Ações Rápidas',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 16),

            Row(
              children: [
                Expanded(
                  child: _buildActionCard(
                    icon: Icons.people_outline,
                    label: 'Clientes',
                    subtitle: '${provider.clients.length} dispositivos',
                    onTap: () => Navigator.pushNamed(context, '/clients'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _buildActionCard(
                    icon: Icons.download_outlined,
                    label: 'Config',
                    subtitle: 'Baixar config',
                    onTap: () => Navigator.pushNamed(context, '/config'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 32),

            // QR Code Info
            if (status != null)
              Container(
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
                      'Informações do Servidor',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 16),
                    _buildInfoRow('Porta', '${status.listenPort}'),
                    _buildInfoRow('Chave Pública', status.publicKey.length > 20
                        ? '${status.publicKey.substring(0, 20)}...'
                        : status.publicKey),
                    _buildInfoRow('Clientes Conectados', '${status.connectedClients}'),
                    _buildInfoRow('Download', status.formattedDownload),
                    _buildInfoRow('Upload', status.formattedUpload),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusCard(VpnStatus? status, VpnProvider provider) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: status?.running == true
              ? [const Color(0xFF00D2FF), const Color(0xFF6C5CE7)]
              : [const Color(0xFF2D2D3A), const Color(0xFF1A1A2E)],
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: (status?.running == true ? const Color(0xFF00D2FF) : Colors.black)
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
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.white70,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Container(
                        width: 12,
                        height: 12,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: status?.running == true ? Colors.greenAccent : Colors.redAccent,
                          boxShadow: [
                            BoxShadow(
                              color: (status?.running == true ? Colors.greenAccent : Colors.redAccent)
                                  .withValues(alpha: 0.5),
                              blurRadius: 8,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        status?.running == true ? 'Ativo' : 'Inativo',
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
              // Toggle button
              GestureDetector(
                onTap: () => provider.toggleVpn(status?.running != true),
                child: Container(
                  width: 60,
                  height: 32,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(16),
                    color: status?.running == true
                        ? Colors.greenAccent.withValues(alpha: 0.3)
                        : Colors.grey.withValues(alpha: 0.3),
                  ),
                  child: AnimatedAlign(
                    duration: const Duration(milliseconds: 300),
                    alignment: status?.running == true
                        ? Alignment.centerRight
                        : Alignment.centerLeft,
                    child: Container(
                      width: 28,
                      height: 28,
                      margin: const EdgeInsets.all(2),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: status?.running == true ? Colors.greenAccent : Colors.grey,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          // Stats row
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _buildStatItem(
                Icons.arrow_downward,
                status?.formattedDownload ?? '0 B',
                'Download',
              ),
              _buildStatItem(
                Icons.arrow_upward,
                status?.formattedUpload ?? '0 B',
                'Upload',
              ),
              _buildStatItem(
                Icons.devices,
                '${status?.connectedClients ?? 0}',
                'Conectados',
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStatItem(IconData icon, String value, String label) {
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

  Widget _buildActionCard({
    required IconData icon,
    required String label,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: const Color(0xFF1A1A2E),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
        ),
        child: Column(
          children: [
            Icon(icon, color: const Color(0xFF6C5CE7), size: 32),
            const SizedBox(height: 8),
            Text(
              label,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 14,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              subtitle,
              style: const TextStyle(color: Colors.grey, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: const TextStyle(color: Colors.grey, fontSize: 13),
          ),
          Flexible(
            child: Text(
              value,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
              textAlign: TextAlign.end,
            ),
          ),
        ],
      ),
    );
  }
}
