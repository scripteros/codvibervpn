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

class VpnUser {
  final int id;
  final String name;
  final String email;
  final String? phone;
  final String? deviceName;
  final String? expiresAt;
  final int daysLeft;
  final int maxSpeedMbps;
  final int downloadBytes;
  final int uploadBytes;

  VpnUser({
    required this.id,
    required this.name,
    required this.email,
    this.phone,
    this.deviceName,
    this.expiresAt,
    this.daysLeft = -1,
    this.maxSpeedMbps = 100,
    this.downloadBytes = 0,
    this.uploadBytes = 0,
  });

  factory VpnUser.fromJson(Map<String, dynamic> json) {
    return VpnUser(
      id: json['id'] as int? ?? 0,
      name: json['name'] as String? ?? '',
      email: json['email'] as String? ?? '',
      phone: json['phone'] as String?,
      deviceName: json['deviceName'] as String?,
      expiresAt: json['expiresAt'] as String?,
      daysLeft: json['daysLeft'] as int? ?? -1,
      maxSpeedMbps: json['maxSpeedMbps'] as int? ?? 100,
      downloadBytes: json['downloadBytes'] as int? ?? 0,
      uploadBytes: json['uploadBytes'] as int? ?? 0,
    );
  }

  bool get isExpired => expiresAt != null && DateTime.parse(expiresAt!).isBefore(DateTime.now());
  bool get isUnlimited => daysLeft == -1;
  String get expiryText {
    if (isUnlimited) return 'Ilimitado';
    if (isExpired) return 'Expirado';
    return '$daysLeft dias';
  }
}

class SshAccount {
  final int id;
  final String name;
  final String host;
  final int port;
  final String username;
  final String? password;
  final String? privateKey;
  final String authMethod;
  final String? label;
  final bool isActive;

  SshAccount({
    required this.id,
    required this.name,
    required this.host,
    this.port = 22,
    required this.username,
    this.password,
    this.privateKey,
    this.authMethod = 'password',
    this.label,
    this.isActive = true,
  });

  factory SshAccount.fromJson(Map<String, dynamic> json) {
    return SshAccount(
      id: json['id'] as int? ?? 0,
      name: json['name'] as String? ?? '',
      host: json['host'] as String? ?? '',
      port: json['port'] as int? ?? 22,
      username: json['username'] as String? ?? '',
      password: json['password'] as String?,
      privateKey: json['private_key'] as String?,
      authMethod: json['auth_method'] as String? ?? 'password',
      label: json['label'] as String?,
      isActive: json['is_active'] == true,
    );
  }
}

class Payload {
  final int id;
  final String name;
  final String type;
  final String payload;
  final String? proxyHost;
  final int proxyPort;
  final String? operator;
  final int? sshAccountId;
  final bool isActive;

  Payload({
    required this.id,
    required this.name,
    required this.type,
    required this.payload,
    this.proxyHost,
    this.proxyPort = 80,
    this.operator,
    this.sshAccountId,
    this.isActive = true,
  });

  factory Payload.fromJson(Map<String, dynamic> json) {
    return Payload(
      id: json['id'] as int? ?? 0,
      name: json['name'] as String? ?? '',
      type: json['type'] as String? ?? 'ssh',
      payload: json['payload'] as String? ?? '',
      proxyHost: json['proxy_host'] as String?,
      proxyPort: json['proxy_port'] as int? ?? 80,
      operator: json['operator'] as String?,
      sshAccountId: json['ssh_account_id'] as int?,
      isActive: json['is_active'] == true,
    );
  }
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
