import 'package:flutter/material.dart';
import '../services/supabase_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'dart:io';
import '../main.dart';
import 'package:shared_preferences/shared_preferences.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final email = TextEditingController();
  final senha = TextEditingController();
  bool _senhaVisivel = false;
  bool _navegou = false;
  Timer? _timer;
  int _segundosRestantes = 0;
  bool _emailEnviado = false; // Para saber se trocamos o texto do botão
  bool _carregandoRecuperacao = false;
  bool _carregandoLogin = false;
  bool _carregandoGoogle = false;
  late final StreamSubscription authSub;
  int _nivelZoom = 0;

  final service = SupabaseService();

  @override
  void initState() {
    super.initState();
    _carregarConfiguracoesIniciais();
    authSub = Supabase.instance.client.auth.onAuthStateChange.listen((
      data,
    ) async {
      final session = data.session;
      final event = data.event;

      if (event == AuthChangeEvent.passwordRecovery && !_navegou) {
        _navegou = true;

        if (mounted) {
          Navigator.pushReplacementNamed(context, '/redefinir_senha');
        }
        return;
      }

      if (session != null && !_navegou) {
        _navegou = true;

        try {
          await service.garantirPerfilGoogle();
        } catch (e) {
          // Não bloqueia o fluxo, apenas registra o problema
          debugPrint("Erro ao garantir perfil do Google: $e");
        }

        if (mounted) {
          Navigator.pushReplacementNamed(context, '/');
        }
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    authSub.cancel();
    email.dispose();
    senha.dispose();
    super.dispose();
  }

  Future<void> _atualizarZoom(bool aumentar) async {
    final prefs = await SharedPreferences.getInstance();

    setState(() {
      if (aumentar && _nivelZoom < 2) {
        _nivelZoom++;
      } else if (!aumentar && _nivelZoom > 0) {
        _nivelZoom--;
      }
    });

    // Salva no disco
    await prefs.setInt('nivel_zoom', _nivelZoom);

    // Acessa o estado do MyApp através da chave global e chama o método de atualização
    myAppKey.currentState?.atualizarEscala(_nivelZoom);
  }

  Future<void> _carregarConfiguracoesIniciais() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      setState(() {
        _nivelZoom = prefs.getInt('nivel_zoom') ?? 0;
      });
    } catch (e) {
      // Falha ao carregar preferências não é crítica; a tela segue com o padrão.
      debugPrint("Erro ao carregar configurações: $e");
    }
  }

  Future<bool> _temInternet() async {
    try {
      final connectivityResult = await Connectivity().checkConnectivity();
      if (connectivityResult.contains(ConnectivityResult.none)) {
        return false;
      }
      // Opcional: Checagem real de DNS
      final result = await InternetAddress.lookup('google.com');
      return result.isNotEmpty && result[0].rawAddress.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  // Retorna o Future do showDialog, permitindo aguardar o fechamento quando
  // necessário, e aceita botões personalizados.
  Future<void> _mostrarDialogo(
    String titulo,
    String mensagem, {
    List<Widget>? botoesPersonalizados,
  }) {
    return showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(titulo),
        content: Text(mensagem),
        actions:
            botoesPersonalizados ??
            [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text("OK"),
              ),
            ],
      ),
    );
  }

  void _mostrarSnackBar(String mensagem, {bool erro = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(mensagem),
        backgroundColor: erro ? Colors.red.shade600 : null,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  Future<void> _fazerLogin() async {
    if (_carregandoLogin) return;

    final emailText = email.text.trim();
    final senhaText = senha.text.trim();

    if (emailText.isEmpty || senhaText.isEmpty) {
      _mostrarDialogo("Campos obrigatórios", "Preencha o email e a senha.");
      return;
    }

    if (!(await _temInternet())) {
      if (mounted) {
        _mostrarDialogo(
          "Sem Conexão",
          "Parece que você está offline. Verifique sua conexão com a internet e tente novamente.",
        );
      }
      return; // Interrompe a execução aqui
    }

    setState(() => _carregandoLogin = true);

    try {
      await service.login(emailText, senhaText);
      // Se o login for bem-sucedido, o listener de auth cuida da navegação.
    } on AuthException catch (e) {
      final msg = e.message.toLowerCase();
      if (msg.contains('invalid') || msg.contains('credentials')) {
        _mostrarDialogo("Erro no login", "Email ou senha inválidos.");
      } else if (msg.contains('confirm')) {
        _mostrarDialogo(
          "E-mail não confirmado",
          "Confirme seu e-mail antes de fazer login. Verifique sua caixa de entrada.",
        );
      } else {
        _mostrarDialogo("Erro no login", e.message);
      }
    } catch (e) {
      _mostrarDialogo(
        "Erro",
        "Não foi possível fazer login agora. Tente novamente.",
      );
    } finally {
      if (mounted) setState(() => _carregandoLogin = false);
    }
  }

  void _iniciarTimer() {
    setState(() {
      _segundosRestantes = 60;
      _emailEnviado = true;
    });

    _timer?.cancel(); // Cancela timer anterior se existir
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_segundosRestantes == 0) {
        timer.cancel();
      } else {
        setState(() {
          _segundosRestantes--;
        });
      }
    });
  }

  Future<void> _recuperarSenha() async {
    final emailText = email.text.trim();

    if (emailText.isEmpty) {
      _mostrarDialogo(
        "Email obrigatório",
        "Digite seu email para recuperar a senha.",
      );
      return;
    }

    if (!email.text.contains("@") || !email.text.contains(".")) {
      _mostrarDialogo("Erro", "Digite um e-mail válido.");
      return;
    }

    if (!(await _temInternet())) {
      _mostrarDialogo(
        "Sem Conexão",
        "Verifique sua internet e tente novamente.",
      );
      return;
    }

    // Inicia o carregamento
    setState(() => _carregandoRecuperacao = true);

    try {
      final bool existe = await Supabase.instance.client.rpc(
        'verificar_email_existe',
        params: {'email_input': emailText},
      );

      if (!existe) {
        setState(() => _carregandoRecuperacao = false); // Para o loader
        _mostrarDialogo("Erro", "E-mail não cadastrado.");
        return;
      }

      await Supabase.instance.client.auth.resetPasswordForEmail(
        emailText,
        redirectTo: 'io.supabase.flutter://login-callback',
      );

      _iniciarTimer();

      if (mounted) {
        _mostrarDialogo(
          "Verifique seu email",
          "Enviamos um link para redefinir sua senha.",
        );
      }
    } on AuthException catch (e) {
      if (mounted) {
        _mostrarDialogo("Erro", e.message);
      }
    } catch (e) {
      if (mounted) {
        _mostrarDialogo(
          "Erro",
          "Não foi possível enviar o email de recuperação.",
        );
      }
    } finally {
      // Finaliza o carregamento independente de sucesso ou erro
      if (mounted) {
        setState(() => _carregandoRecuperacao = false);
      }
    }
  }

  Future<void> _entrarComGoogle() async {
    if (_carregandoGoogle) return;

    if (!(await _temInternet())) {
      _mostrarDialogo(
        "Sem Conexão",
        "Verifique sua internet e tente novamente.",
      );
      return;
    }

    setState(() => _carregandoGoogle = true);
    try {
      await Supabase.instance.client.auth.signInWithOAuth(
        OAuthProvider.google,
        redirectTo: 'io.supabase.flutter://login-callback',
      );
    } on AuthException catch (e) {
      _mostrarDialogo("Erro", e.message);
    } catch (e) {
      _mostrarDialogo(
        "Erro",
        "Não foi possível continuar com o Google. Tente novamente.",
      );
    } finally {
      if (mounted) setState(() => _carregandoGoogle = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      resizeToAvoidBottomInset: false,
      appBar: AppBar(title: const Text("Login")),
      body: Stack(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                TextField(
                  controller: email,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(labelText: "Email"),
                ),

                TextField(
                  controller: senha,
                  obscureText: !_senhaVisivel,
                  decoration: InputDecoration(
                    labelText: "Senha",
                    suffixIcon: IconButton(
                      icon: Icon(
                        _senhaVisivel ? Icons.visibility_off : Icons.visibility,
                      ),
                      onPressed: () {
                        setState(() {
                          _senhaVisivel = !_senhaVisivel;
                        });
                      },
                    ),
                  ),
                ),

                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    // Desabilita se estiver carregando ou se o timer estiver rodando
                    onPressed:
                        (_segundosRestantes == 0 && !_carregandoRecuperacao)
                        ? _recuperarSenha
                        : null,
                    child: _carregandoRecuperacao
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.blue,
                            ),
                          )
                        : Text(
                            _segundosRestantes > 0
                                ? "Reenviar email em ${_segundosRestantes}s"
                                : (_emailEnviado
                                      ? "Reenviar email"
                                      : "Esqueci a senha"),
                            style: TextStyle(
                              color: _segundosRestantes > 0
                                  ? Colors.grey
                                  : Colors.blue,
                            ),
                          ),
                  ),
                ),

                ElevatedButton(
                  onPressed: _carregandoLogin ? null : _fazerLogin,
                  child: _carregandoLogin
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text("Entrar"),
                ),

                const SizedBox(height: 20),
                GestureDetector(
                  onTap: () {
                    Navigator.pushReplacementNamed(context, '/cadastro');
                  },
                  child: Text.rich(
                    TextSpan(
                      text: "Ainda não tem conta? ",
                      style: const TextStyle(color: Colors.black87),
                      children: [
                        TextSpan(
                          text: "Cadastre-se",
                          style: TextStyle(
                            color: Colors.blue,
                            fontWeight: FontWeight.bold,
                            decoration: TextDecoration.underline,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Row(
                    children: const [
                      Expanded(child: Divider()),
                      Padding(
                        padding: EdgeInsets.symmetric(horizontal: 8),
                        child: Text("ou", style: TextStyle(color: Colors.grey)),
                      ),
                      Expanded(child: Divider()),
                    ],
                  ),
                ),

                ElevatedButton.icon(
                  icon: _carregandoGoogle
                      ? const SizedBox(
                          height: 18,
                          width: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Image.asset(
                          'assets/images/google_logo.webp',
                          width: 24,
                          height: 24,
                        ),
                  label: Text(
                    _carregandoGoogle
                        ? "Conectando..."
                        : "Continuar com Google",
                  ),
                  onPressed: _carregandoGoogle ? null : _entrarComGoogle,
                ),
              ],
            ),
          ),
          Positioned(
            bottom: 25, // Margem do fundo
            left: 25, // Margem da esquerda
            child: Image.asset('assets/images/titulo.webp', width: 150),
          ),
        ],
      ),
      floatingActionButton: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          // Botão A-
          FloatingActionButton(
            heroTag: "btn_diminuir",
            // Desabilita visualmente se chegar no limite 0
            onPressed: _nivelZoom > 0 ? () => _atualizarZoom(false) : null,
            backgroundColor: _nivelZoom > 0 ? null : Colors.grey.shade300,
            shape: const CircleBorder(),
            child: Text(
              "A-",
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: _nivelZoom > 0 ? null : Colors.grey.shade600,
              ),
            ),
          ),

          const SizedBox(width: 12),

          // Botão A+
          FloatingActionButton(
            heroTag: "btn_aumentar",
            // Desabilita visualmente se chegar no limite 2
            onPressed: _nivelZoom < 2 ? () => _atualizarZoom(true) : null,
            backgroundColor: _nivelZoom < 2 ? null : Colors.grey.shade300,
            shape: const CircleBorder(),
            child: Text(
              "A+",
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: _nivelZoom < 2 ? null : Colors.grey.shade600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}