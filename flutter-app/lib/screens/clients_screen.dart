import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/vpn_provider.dart';

class ClientsScreen extends StatefulWidget {
  const ClientsScreen({super.key});

  @override
  State<ClientsScreen> createState() => _ClientsScreenState();
}

class _ClientsScreenState extends State<ClientsScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<VpnProvider>().fetchClients();
    });
  }

  void _showAddDialog() {
    final nameController = TextEditingController();
    final ipController = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A2E),
        title: const Text(
          'Novo Cliente',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameController,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                labelText: 'Nome do dispositivo',
                filled: true,
                fillColor: const Color(0xFF0F0F1A),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide.none,
                ),
                labelStyle: const TextStyle(color: Colors.grey),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: ipController,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                labelText: 'IP (ex: 10.0.0.3/32)',
                filled: true,
                fillColor: const Color(0xFF0F0F1A),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide.none,
                ),
                labelStyle: const TextStyle(color: Colors.grey),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancelar', style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            onPressed: () {
              if (nameController.text.isNotEmpty) {
                context.read<VpnProvider>().addClient(
                      nameController.text,
                      ipController.text,
                    );
                Navigator.pop(ctx);
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF6C5CE7),
              foregroundColor: Colors.white,
            ),
            child: const Text('Adicionar'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<VpnProvider>();
    final clients = provider.clients;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Clientes VPN'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: _showAddDialog,
          ),
        ],
      ),
      body: clients.isEmpty
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.devices_other_outlined,
                    size: 64,
                    color: Colors.grey[600],
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Nenhum cliente configurado',
                    style: TextStyle(
                      color: Colors.grey[400],
                      fontSize: 16,
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextButton.icon(
                    onPressed: _showAddDialog,
                    icon: const Icon(Icons.add, color: Color(0xFF6C5CE7)),
                    label: const Text(
                      'Adicionar primeiro cliente',
                      style: TextStyle(color: Color(0xFF6C5CE7)),
                    ),
                  ),
                ],
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: clients.length,
              itemBuilder: (context, index) {
                final client = clients[index];
                return Card(
                  margin: const EdgeInsets.only(bottom: 12),
                  child: ListTile(
                    contentPadding: const EdgeInsets.all(16),
                    leading: Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: const Color(0xFF6C5CE7).withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(
                        Icons.devices,
                        color: Color(0xFF6C5CE7),
                      ),
                    ),
                    title: Text(
                      client.name,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SizedBox(height: 4),
                        Text(
                          client.allowedIPs.isNotEmpty
                              ? client.allowedIPs
                              : 'Sem IP configurado',
                          style: TextStyle(color: Colors.grey[400], fontSize: 12),
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Icon(
                              Icons.arrow_downward,
                              size: 12,
                              color: Colors.green[400],
                            ),
                            const SizedBox(width: 2),
                            Text(
                              _formatBytes(client.downloadBytes),
                              style: TextStyle(color: Colors.grey[500], fontSize: 11),
                            ),
                            const SizedBox(width: 12),
                            Icon(
                              Icons.arrow_upward,
                              size: 12,
                              color: Colors.orange[400],
                            ),
                            const SizedBox(width: 2),
                            Text(
                              _formatBytes(client.uploadBytes),
                              style: TextStyle(color: Colors.grey[500], fontSize: 11),
                            ),
                          ],
                        ),
                      ],
                    ),
                    trailing: PopupMenuButton(
                      icon: const Icon(Icons.more_vert, color: Colors.grey),
                      color: const Color(0xFF1A1A2E),
                      itemBuilder: (context) => [
                        PopupMenuItem(
                          child: const ListTile(
                            leading: Icon(Icons.download, color: Color(0xFF6C5CE7)),
                            title: Text('Config', style: TextStyle(color: Colors.white)),
                          ),
                          onTap: () async {
                            Navigator.pop(context);
                            final config = await provider.getClientConfig(client.id);
                            if (config != null && mounted) {
                              _showConfigDialog(config);
                            }
                          },
                        ),
                        PopupMenuItem(
                          child: const ListTile(
                            leading: Icon(Icons.delete_outline, color: Colors.redAccent),
                            title: Text('Remover', style: TextStyle(color: Colors.redAccent)),
                          ),
                          onTap: () {
                            Navigator.pop(context);
                            _confirmRemove(client.id, client.name);
                          },
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
    );
  }

  void _showConfigDialog(String config) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A2E),
        title: const Text(
          'Configuração do Cliente',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
        ),
        content: Container(
          constraints: const BoxConstraints(maxHeight: 400, maxWidth: 400),
          child: SingleChildScrollView(
            child: SelectableText(
              config,
              style: const TextStyle(
                color: Colors.greenAccent,
                fontSize: 11,
                fontFamily: 'monospace',
                height: 1.5,
              ),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Fechar', style: TextStyle(color: Colors.grey)),
          ),
        ],
      ),
    );
  }

  void _confirmRemove(String id, String name) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A2E),
        title: const Text(
          'Remover Cliente',
          style: TextStyle(color: Colors.white),
        ),
        content: Text(
          'Remover $name? Esta ação não pode ser desfeita.',
          style: const TextStyle(color: Colors.grey),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancelar', style: TextStyle(color: Colors.grey)),
          ),
          TextButton(
            onPressed: () {
              // TODO: delete client
              Navigator.pop(ctx);
            },
            child: const Text('Remover', style: TextStyle(color: Colors.redAccent)),
          ),
        ],
      ),
    );
  }

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(0)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}
