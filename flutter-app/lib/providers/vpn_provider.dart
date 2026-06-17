import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../models/vpn_models.dart';

class VpnProvider extends ChangeNotifier {
  String _baseUrl = 'https://codvibervpn.mobap.com.br';
  String? _token;
  VpnUser? _user;
  VpnStatus? _status;
  List<SshAccount> _sshAccounts = [];
  List<Payload> _payloads = [];
  List<SshAccount> _publicServers = [];
  bool _isLoading = false;
  String? _error;
  bool _authenticated = false;
  SshAccount? _activeServer;
  bool _vpnConnected = false;
  int _downloadSpeed = 0;
  int _uploadSpeed = 0;

  String get baseUrl => _baseUrl;
  String? get token => _token;
  VpnUser? get user => _user;
  VpnStatus? get status => _status;
  List<SshAccount> get sshAccounts => _sshAccounts;
  List<Payload> get payloads => _payloads;
  List<SshAccount> get publicServers => _publicServers;
  bool get isLoading => _isLoading;
  String? get error => _error;
  bool get authenticated => _authenticated;
  SshAccount? get activeServer => _activeServer;
  bool get vpnConnected => _vpnConnected;
  int get downloadSpeed => _downloadSpeed;
  int get uploadSpeed => _uploadSpeed;

  Map<String, String> get _headers => {
        'Content-Type': 'application/json',
        if (_token != null) 'Authorization': 'Bearer $_token',
      };

  void setBaseUrl(String url) {
    _baseUrl = url;
    notifyListeners();
  }

  /// Fetch list of public SSH servers available for users
  Future<void> fetchPublicServers() async {
    try {
      final response = await http.get(
        Uri.parse('$_baseUrl/api/tunnels/ssh'),
        headers: {'Content-Type': 'application/json'},
      );
      if (response.statusCode == 200) {
        final d = jsonDecode(response.body);
        _publicServers = (d['accounts'] as List?)
                ?.map((a) => SshAccount.fromJson(a))
                .where((s) => s.isActive)
                .toList() ??
            [];
        notifyListeners();
      }
    } catch (e) {
      debugPrint('Error fetching servers: $e');
    }
  }

  /// User registration (creates pending account)
  Future<bool> register(String name, String email, String password, SshAccount selectedServer) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final response = await http.post(
        Uri.parse('$_baseUrl/api/auth/register'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'name': name,
          'email': email,
          'password': password,
          'selectedServerId': selectedServer.id,
        }),
      );

      final data = jsonDecode(response.body);

      if (response.statusCode == 201 || response.statusCode == 200) {
        _isLoading = false;
        notifyListeners();
        return true;
      } else {
        _error = data['error'] ?? 'Erro ao cadastrar';
        _isLoading = false;
        notifyListeners();
        return false;
      }
    } catch (e) {
      _error = 'Erro de conexão: ${e.toString()}';
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  /// Login with email + password + selected server
  Future<bool> login(String email, String password, SshAccount selectedServer) async {
    _isLoading = true;
    _error = null;
    _activeServer = selectedServer;
    notifyListeners();

    try {
      final response = await http.post(
        Uri.parse('$_baseUrl/api/auth/user-login'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'email': email, 'password': password}),
      );

      final data = jsonDecode(response.body);

      if (response.statusCode == 200) {
        _token = data['token'] as String;
        _user = VpnUser.fromJson(data['user']);
        _authenticated = true;
        _isLoading = false;
        notifyListeners();
        // Fetch configs + start speed monitor
        fetchUserConfigs();
        _startSpeedMonitor();
        return true;
      } else {
        _error = data['error'] ?? 'Erro ao autenticar';
        _isLoading = false;
        notifyListeners();
        return false;
      }
    } catch (e) {
      _error = 'Erro de conexão: ${e.toString()}';
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  Future<void> fetchUserConfigs() async {
    try {
      final sshResp = await http.get(
        Uri.parse('$_baseUrl/api/tunnels/ssh'),
        headers: _headers,
      );
      if (sshResp.statusCode == 200) {
        final d = jsonDecode(sshResp.body);
        _sshAccounts = (d['accounts'] as List?)
                ?.map((a) => SshAccount.fromJson(a))
                .toList() ??
            [];
      }

      final payloadResp = await http.get(
        Uri.parse('$_baseUrl/api/tunnels/payloads'),
        headers: _headers,
      );
      if (payloadResp.statusCode == 200) {
        final d = jsonDecode(payloadResp.body);
        _payloads = (d['payloads'] as List?)
                ?.map((p) => Payload.fromJson(p))
                .toList() ??
            [];
      }

      notifyListeners();
    } catch (e) {
      debugPrint('Error fetching configs: $e');
    }
  }

  void _startSpeedMonitor() {
    Future.doWhile(() async {
      await Future.delayed(const Duration(seconds: 2));
      if (!_authenticated) return false;
      await fetchStatus();
      return _authenticated;
    });
  }

  Future<void> connectVpn() async {
    if (_token == null || _activeServer == null) return;
    _isLoading = true;
    notifyListeners();

    try {
      final response = await http.post(
        Uri.parse('$_baseUrl/api/vpn/connect'),
        headers: _headers,
        body: jsonEncode({
          'serverId': _activeServer!.id,
          'userId': _user?.id,
        }),
      );

      if (response.statusCode == 200) {
        _vpnConnected = true;
        _startSpeedMonitor();
      } else {
        _error = 'Erro ao conectar VPN';
      }
    } catch (e) {
      _error = 'Erro: ${e.toString()}';
    }
    _isLoading = false;
    notifyListeners();
  }

  Future<void> disconnectVpn() async {
    if (_token == null) return;
    try {
      await http.post(
        Uri.parse('$_baseUrl/api/vpn/disconnect'),
        headers: _headers,
      );
    } catch (_) {}
    _vpnConnected = false;
    _downloadSpeed = 0;
    _uploadSpeed = 0;
    notifyListeners();
  }

  Future<void> fetchStatus() async {
    if (_token == null) return;
    try {
      final response = await http.get(
        Uri.parse('$_baseUrl/api/vpn/status'),
        headers: _headers,
      );
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        _status = VpnStatus.fromJson(data);
        _downloadSpeed = data['downloadSpeed'] as int? ?? 0;
        _uploadSpeed = data['uploadSpeed'] as int? ?? 0;
        notifyListeners();
      }
    } catch (e) {
      debugPrint('Error fetching status: $e');
    }
  }

  Future<void> sendHeartbeat() async {
    if (_token == null) return;
    try {
      await http.post(
        Uri.parse('$_baseUrl/api/vpn/heartbeat'),
        headers: _headers,
        body: jsonEncode({
          'downloadSpeed': _downloadSpeed,
          'uploadSpeed': _uploadSpeed,
        }),
      );
    } catch (_) {}
  }

  void logout() {
    disconnectVpn();
    _token = null;
    _user = null;
    _authenticated = false;
    _status = null;
    _sshAccounts = [];
    _payloads = [];
    _activeServer = null;
    _publicServers = [];
    notifyListeners();
  }
}
