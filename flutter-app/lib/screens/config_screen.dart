import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/vpn_provider.dart';

class ConfigScreen extends StatefulWidget {
  const ConfigScreen({super.key});

  @override
  State<ConfigScreen> createState() => _ConfigScreenState();
}

class _ConfigScreenState extends State<ConfigScreen> {
  String? _selectedConfig;
  String? _selectedClientId;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<VpnProvider>().fetchClients();
    });
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<VpnProvider>();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Configuração'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const Text(
            'Selecione um cliente',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 16),

          // Client Selector
          ...provider.clients.map((client) => Card(
                margin: const EdgeInsets.only(bottom: 8),
                child: RadioListTile<String>(
                  title: Text(
                    client.name,
                    style: const TextStyle(color: Colors.white),
                  ),
                  subtitle: Text(
                    client.allowedIPs,
                    style: TextStyle(color: Colors.grey[400], fontSize: 12),
                  ),
                  value: client.id,
                  groupValue: _selectedClientId,
                  activeColor: const Color(0xFF6C5CE7),
                  onChanged: (value) async {
                    setState(() => _selectedClientId = value);
                    final config = await provider.getClientConfig(value!);
                    if (config != null) {
                      setState(() => _selectedConfig = config);
                    }
                  },
                ),
              )),

          if (provider.clients.isEmpty)
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: const Color(0xFF1A1A2E),
                borderRadius: BorderRadius.circular(16),
              ),
              child: const Column(
                children: [
                  Icon(Icons.info_outline, color: Colors.grey, size: 32),
                  SizedBox(height: 12),
                  Text(
                    'Nenhum cliente disponível. Crie um cliente primeiro.',
                    style: TextStyle(color: Colors.grey),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),

          if (_selectedConfig != null) ...[
            const SizedBox(height: 24),
            const Text(
              'Configuração WireGuard',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: Colors.white70,
              ),
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFF0D1117),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
              ),
              child: SelectableText(
                _selectedConfig!,
                style: const TextStyle(
                  color: Colors.greenAccent,
                  fontSize: 12,
                  fontFamily: 'monospace',
                  height: 1.6,
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Instructions
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFF6C5CE7).withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: const Color(0xFF6C5CE7).withValues(alpha: 0.2),
                ),
              ),
              child: const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Como usar:',
                    style: TextStyle(
                      color: Color(0xFF6C5CE7),
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                  SizedBox(height: 8),
                  Text(
                    '1. Instale o WireGuard no seu dispositivo\n'
                    '2. Copie a configuração acima\n'
                    '3. Cole no app WireGuard\n'
                    '4. Ative a conexão',
                    style: TextStyle(color: Colors.white70, fontSize: 13, height: 1.5),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}
