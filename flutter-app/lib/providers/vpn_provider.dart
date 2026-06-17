import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../models/vpn_models.dart';

class VpnProvider extends ChangeNotifier {
  String _baseUrl = 'https://servico.mobap.com.br:3007';
  String? _token;
  VpnUser? _user;
  VpnStatus? _status;
  List<VpnClient> _clients = [];
  List<SshAccount> _sshAccounts = [];
  List<Payload> _payloads = [];
  bool _isLoading = false;
  String? _error;
  bool _authenticated = false;

  String get baseUrl => _baseUrl;
  String? get token => _token;
  VpnUser? get user => _user;
  VpnStatus? get status => _status;
  List<VpnClient> get clients => _clients;
  List<SshAccount> get sshAccounts => _sshAccounts;
  List<Payload> get payloads => _payloads;
  bool get isLoading => _isLoading;
  String? get error => _error;
  bool get authenticated => _authenticated;

  Map<String, String> get _headers => {
        'Content-Type': 'application/json',
        if (_token != null) 'Authorization': 'Bearer $_token',
      };

  void setBaseUrl(String url) {
    _baseUrl = url;
    notifyListeners();
  }

  Future<bool> login(String email, String password) async {
    _isLoading = true;
    _error = null;
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
        // Fetch configs in background
        fetchUserConfigs();
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
      // Fetch SSH accounts for this user
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

      // Fetch payloads for this user
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

  Future<void> checkExpiry() async {
    if (_token == null) return;
    try {
      final response = await http.get(
        Uri.parse('$_baseUrl/api/auth/user-verify'),
        headers: _headers,
      );
      if (response.statusCode != 200) {
        _authenticated = false;
        _error = 'Sessão expirada. Faça login novamente.';
        notifyListeners();
      }
    } catch (e) {
      debugPrint('Error checking expiry: $e');
    }
  }

  void logout() {
    _token = null;
    _user = null;
    _authenticated = false;
    _status = null;
    _clients = [];
    _sshAccounts = [];
    _payloads = [];
    notifyListeners();
  }
}
