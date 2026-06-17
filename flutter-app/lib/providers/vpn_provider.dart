import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../models/vpn_models.dart';

class VpnProvider extends ChangeNotifier {
  VpnServer _server = VpnServer(host: 'servico.mobap.com.br', port: 3006);
  VpnStatus? _status;
  List<VpnClient> _clients = [];
  bool _isLoading = false;
  String? _error;
  bool _authenticated = false;

  VpnServer get server => _server;
  VpnStatus? get status => _status;
  List<VpnClient> get clients => _clients;
  bool get isLoading => _isLoading;
  String? get error => _error;
  bool get authenticated => _authenticated;

  void setServer(String host, int port) {
    _server = VpnServer(host: host, port: port);
    notifyListeners();
  }

  void setToken(String token) {
    _server = VpnServer(host: _server.host, port: _server.port, token: token);
    notifyListeners();
  }

  Future<bool> login(String password) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final response = await http.post(
        Uri.parse('${_server.baseUrl}/api/auth/login'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'password': password}),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        setToken(data['token'] as String);
        _authenticated = true;
        _isLoading = false;
        notifyListeners();
        return true;
      } else {
        _error = 'Senha incorreta';
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

  Future<void> fetchStatus() async {
    try {
      final response = await http.get(
        Uri.parse('${_server.baseUrl}/api/vpn/status'),
        headers: _server.headers,
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        _status = VpnStatus.fromJson(data);
        notifyListeners();
      }
    } catch (e) {
      debugPrint('Erro ao buscar status: $e');
    }
  }

  Future<bool> toggleVpn(bool enable) async {
    _isLoading = true;
    notifyListeners();

    try {
      final response = await http.post(
        Uri.parse('${_server.baseUrl}/api/vpn/toggle'),
        headers: _server.headers,
        body: jsonEncode({'enable': enable}),
      );

      if (response.statusCode == 200) {
        _isLoading = false;
        await fetchStatus();
        return true;
      }
    } catch (e) {
      _error = 'Erro ao alternar VPN: $e';
    }

    _isLoading = false;
    notifyListeners();
    return false;
  }

  Future<void> fetchClients() async {
    try {
      final response = await http.get(
        Uri.parse('${_server.baseUrl}/api/vpn/clients'),
        headers: _server.headers,
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        _clients = (data['clients'] as List)
            .map((c) => VpnClient.fromJson(c))
            .toList();
        notifyListeners();
      }
    } catch (e) {
      debugPrint('Erro ao buscar clientes: $e');
    }
  }

  Future<bool> addClient(String name, String allowedIPs) async {
    _isLoading = true;
    notifyListeners();

    try {
      final response = await http.post(
        Uri.parse('${_server.baseUrl}/api/vpn/clients'),
        headers: _server.headers,
        body: jsonEncode({'name': name, 'allowedIPs': allowedIPs}),
      );

      if (response.statusCode == 200) {
        _isLoading = false;
        await fetchClients();
        return true;
      }
    } catch (e) {
      _error = 'Erro ao adicionar cliente: $e';
    }

    _isLoading = false;
    notifyListeners();
    return false;
  }

  Future<String?> getClientConfig(String clientId) async {
    try {
      final response = await http.get(
        Uri.parse('${_server.baseUrl}/api/vpn/clients/$clientId/config'),
        headers: _server.headers,
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data['config'] as String?;
      }
    } catch (e) {
      debugPrint('Erro ao buscar config: $e');
    }
    return null;
  }

  void logout() {
    _authenticated = false;
    _status = null;
    _clients = [];
    _server = VpnServer(host: _server.host, port: _server.port);
    notifyListeners();
  }
}
