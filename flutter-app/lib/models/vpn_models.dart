class VpnServer {
  final String host;
  final int port;
  final String token;

  VpnServer({
    required this.host,
    this.port = 3006,
    this.token = '',
  });

  String get baseUrl => 'http://$host:$port';

  Map<String, String> get headers => {
        'Content-Type': 'application/json',
        if (token.isNotEmpty) 'Authorization': 'Bearer $token',
      };
}

class VpnStatus {
  final bool running;
  final int clients;
  final int connectedClients;
  final int totalDownload;
  final int totalUpload;
  final String publicKey;
  final int listenPort;

  VpnStatus({
    required this.running,
    required this.clients,
    required this.connectedClients,
    required this.totalDownload,
    required this.totalUpload,
    required this.publicKey,
    required this.listenPort,
  });

  factory VpnStatus.fromJson(Map<String, dynamic> json) {
    final s = json['status'] as Map<String, dynamic>? ?? json;
    return VpnStatus(
      running: s['running'] == true,
      clients: (s['clients'] as num?)?.toInt() ?? 0,
      connectedClients: (s['connectedClients'] as num?)?.toInt() ?? 0,
      totalDownload: (s['totalDownload'] as num?)?.toInt() ?? 0,
      totalUpload: (s['totalUpload'] as num?)?.toInt() ?? 0,
      publicKey: s['publicKey'] as String? ?? '',
      listenPort: (s['listenPort'] as num?)?.toInt() ?? 51820,
    );
  }

  String get formattedDownload {
    return _formatBytes(totalDownload);
  }

  String get formattedUpload {
    return _formatBytes(totalUpload);
  }

  static String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }
}

class VpnClient {
  final String id;
  final String name;
  final String publicKey;
  final String allowedIPs;
  final String createdAt;
  final bool enabled;
  final int downloadBytes;
  final int uploadBytes;
  final String? lastSeen;
  String? privateKey;
  String? presharedKey;

  VpnClient({
    required this.id,
    required this.name,
    required this.publicKey,
    this.allowedIPs = '',
    this.createdAt = '',
    this.enabled = true,
    this.downloadBytes = 0,
    this.uploadBytes = 0,
    this.lastSeen,
    this.privateKey,
    this.presharedKey,
  });

  factory VpnClient.fromJson(Map<String, dynamic> json) {
    return VpnClient(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? '',
      publicKey: json['publicKey'] as String? ?? '',
      allowedIPs: json['allowedIPs'] as String? ?? '',
      createdAt: json['createdAt'] as String? ?? '',
      enabled: json['enabled'] == true,
      downloadBytes: (json['downloadBytes'] as num?)?.toInt() ?? 0,
      uploadBytes: (json['uploadBytes'] as num?)?.toInt() ?? 0,
      lastSeen: json['lastSeen'] as String?,
    );
  }
}
