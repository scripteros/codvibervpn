import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/vpn_provider.dart';
import '../models/vpn_models.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _serverController = TextEditingController(text: 'http://servico.mobap.com.br:3007');
  SshAccount? _selectedServer;
  List<SshAccount> _servers = [];
  bool _loadingServers = false;
  bool _registering = false;
  final _nameController = TextEditingController();
  final _confirmPasswordController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadServers();
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _serverController.dispose();
    _nameController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  Future<void> _loadServers() async {
    setState(() => _loadingServers = true);
    try {
      final provider = context.read<VpnProvider>();
      await provider.fetchPublicServers();
      setState(() {
        _servers = provider.publicServers;
        _loadingServers = false;
        if (_servers.isNotEmpty) {
          _selectedServer = _servers.first;
        }
      });
    } catch (e) {
      setState(() => _loadingServers = false);
    }
  }

  Future<void> _login() async {
    if (_selectedServer == null) {
      _showError('Selecione um servidor');
      return;
    }
    final provider = context.read<VpnProvider>();
    provider.setBaseUrl(_serverController.text.trim());

    final success = await provider.login(
      _emailController.text.trim(),
      _passwordController.text,
      _selectedServer!,
    );

    if (success && mounted) {
      Navigator.pushReplacementNamed(context, '/home');
    }
  }

  Future<void> _register() async {
    if (_selectedServer == null) {
      _showError('Selecione um servidor');
      return;
    }
    if (_passwordController.text != _confirmPasswordController.text) {
      _showError('Senhas não conferem');
      return;
    }
    final provider = context.read<VpnProvider>();
    provider.setBaseUrl(_serverController.text.trim());

    final success = await provider.register(
      _nameController.text.trim(),
      _emailController.text.trim(),
      _passwordController.text,
      _selectedServer!,
    );

    if (success && mounted) {
      setState(() => _registering = false);
      _showSuccess('Cadastro realizado! Aguarde liberação do administrador.');
    }
  }

  void _showError(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: Colors.red),
    );
  }

  void _showSuccess(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: Colors.green),
    );
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<VpnProvider>();

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Logo
                Container(
                  width: 100,
                  height: 100,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: const LinearGradient(
                      colors: [Color(0xFF6C5CE7), Color(0xFF00D2FF)],
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF6C5CE7).withValues(alpha: 0.3),
                        blurRadius: 30,
                        spreadRadius: 5,
                      ),
                    ],
                  ),
                  child: const Icon(
                    Icons.shield_outlined,
                    size: 50,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 32),

                const Text(
                  'CodVibe VPN',
                  style: TextStyle(
                    fontSize: 32,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  _registering ? 'Crie sua conta' : 'Selecione o servidor e faça login',
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.grey[400],
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 32),

                // Server Picker
                _loadingServers
                    ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
                    : _servers.isEmpty
                        ? TextField(
                            controller: _serverController,
                            style: const TextStyle(color: Colors.white),
                            decoration: InputDecoration(
                              labelText: 'URL do Servidor',
                              prefixIcon: const Icon(Icons.dns_outlined, color: Color(0xFF6C5CE7)),
                              filled: true,
                              fillColor: const Color(0xFF1A1A2E),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: BorderSide.none,
                              ),
                              labelStyle: const TextStyle(color: Colors.grey),
                            ),
                          )
                        : DropdownButtonFormField<SshAccount>(
                            value: _selectedServer,
                            dropdownColor: const Color(0xFF1A1A2E),
                            style: const TextStyle(color: Colors.white),
                            decoration: InputDecoration(
                              labelText: 'Servidor',
                              prefixIcon: const Icon(Icons.dns_outlined, color: Color(0xFF6C5CE7)),
                              filled: true,
                              fillColor: const Color(0xFF1A1A2E),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: BorderSide.none,
                              ),
                              labelStyle: const TextStyle(color: Colors.grey),
                            ),
                            items: _servers.map((s) {
                              return DropdownMenuItem<SshAccount>(
                                value: s,
                                child: Row(
                                  children: [
                                    Icon(
                                      _getOperatorIcon(s.label ?? ''),
                                      size: 18,
                                      color: _getOperatorColor(s.label ?? ''),
                                    ),
                                    const SizedBox(width: 8),
                                    Text(s.label ?? s.name),
                                  ],
                                ),
                              );
                            }).toList(),
                            onChanged: (v) => setState(() => _selectedServer = v),
                          ),
                const SizedBox(height: 16),

                if (_registering) ...[
                  TextField(
                    controller: _nameController,
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      labelText: 'Nome',
                      prefixIcon: const Icon(Icons.person_outline, color: Color(0xFF6C5CE7)),
                      filled: true,
                      fillColor: const Color(0xFF1A1A2E),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                      labelStyle: const TextStyle(color: Colors.grey),
                    ),
                  ),
                  const SizedBox(height: 16),
                ],

                // Email
                TextField(
                  controller: _emailController,
                  keyboardType: TextInputType.emailAddress,
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    labelText: 'Email',
                    prefixIcon: const Icon(Icons.email_outlined, color: Color(0xFF6C5CE7)),
                    filled: true,
                    fillColor: const Color(0xFF1A1A2E),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                    labelStyle: const TextStyle(color: Colors.grey),
                  ),
                ),
                const SizedBox(height: 16),

                // Password
                TextField(
                  controller: _passwordController,
                  obscureText: true,
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    labelText: 'Senha',
                    prefixIcon: const Icon(Icons.lock_outline, color: Color(0xFF6C5CE7)),
                    filled: true,
                    fillColor: const Color(0xFF1A1A2E),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                    labelStyle: const TextStyle(color: Colors.grey),
                  ),
                ),
                const SizedBox(height: 16),

                if (_registering)
                  TextField(
                    controller: _confirmPasswordController,
                    obscureText: true,
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      labelText: 'Confirmar Senha',
                      prefixIcon: const Icon(Icons.lock_outline, color: Color(0xFF6C5CE7)),
                      filled: true,
                      fillColor: const Color(0xFF1A1A2E),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                      labelStyle: const TextStyle(color: Colors.grey),
                    ),
                  ),

                const SizedBox(height: 16),

                // Error
                if (provider.error != null)
                  Container(
                    padding: const EdgeInsets.all(12),
                    margin: const EdgeInsets.only(bottom: 16),
                    decoration: BoxDecoration(
                      color: Colors.red.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.red.withValues(alpha: 0.3)),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.error_outline, color: Colors.red, size: 20),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            provider.error!,
                            style: const TextStyle(color: Colors.red, fontSize: 13),
                          ),
                        ),
                      ],
                    ),
                  ),

                // Login button
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: ElevatedButton(
                    onPressed: provider.isLoading ? null : (_registering ? _register : _login),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF6C5CE7),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      elevation: 0,
                    ),
                    child: provider.isLoading
                        ? const SizedBox(
                            width: 24,
                            height: 24,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : Text(
                            _registering ? 'Cadastrar' : 'Entrar',
                            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                          ),
                  ),
                ),
                const SizedBox(height: 16),

                // Toggle register/login
                TextButton(
                  onPressed: () {
                    setState(() => _registering = !_registering);
                  },
                  child: Text(
                    _registering
                        ? 'Já tem conta? Faça login'
                        : 'Não tem conta? Cadastre-se',
                    style: const TextStyle(color: Color(0xFF6C5CE7)),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Color _getOperatorColor(String label) {
    final l = label.toLowerCase();
    if (l.contains('tim')) return const Color(0xFF003A70);
    if (l.contains('vivo')) return const Color(0xFF660099);
    if (l.contains('claro')) return const Color(0xFFFF0000);
    return const Color(0xFF6C5CE7);
  }

  IconData _getOperatorIcon(String label) {
    final l = label.toLowerCase();
    if (l.contains('tim') || l.contains('vivo') || l.contains('claro')) {
      return Icons.sim_card;
    }
    return Icons.dns;
  }
}
