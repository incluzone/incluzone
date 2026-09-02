
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
  bool _carregandoRecuperacao = false; // Nova variável
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


        await service.garantirPerfilGoogle();


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


    // ESTA É A PARTE QUE FALTA:
    // Acessa o estado do MyApp através da chave global e chama o método de atualização
    myAppKey.currentState?.atualizarEscala(_nivelZoom);
  }


  Future<void> _carregarConfiguracoesIniciais() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _nivelZoom = prefs.getInt('nivel_zoom') ?? 0;
    });
  }


  Future<bool> _temInternet() async {
    final connectivityResult = await Connectivity().checkConnectivity();
    if (connectivityResult.contains(ConnectivityResult.none)) {
      return false;
    }
    // Opcional: Checagem real de DNS
    try {
      final result = await InternetAddress.lookup('google.com');
      return result.isNotEmpty && result[0].rawAddress.isNotEmpty;
    } catch (_) {
      return false;
    }
  }


  void _mostrarDialogo(String titulo, String mensagem) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(titulo),
        content: Text(mensagem),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("OK"),
          ),
        ],
      ),
    );
  }


  Future<void> _fazerLogin() async {
    final emailText = email.text.trim();
    final senhaText = senha.text.trim();


    if (!(await _temInternet())) {
      if (mounted) {
        _mostrarDialogo(
          "Sem Conexão",
          "Parece que você está offline. Verifique sua conexão com a internet e tente novamente.",
        );
      }
      return; // Interrompe a execução aqui
    }


    if (emailText.isEmpty || senhaText.isEmpty) {
      _mostrarDialogo("Campos obrigatórios", "Preencha o email e a senha.");
      return;
    }


    try {
      await service.login(emailText, senhaText);
    } catch (e) {
      _mostrarDialogo("Erro no login", "Email ou senha inválidos.");
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
        setState(() {
          // Opcional: manter _emailEnviado como true para o texto ser "Reenviar"
          // em vez de "Esqueci a senha"
        });
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


  @override
  Widget build(BuildContext context) {
    return Scaffold(
      resizeToAvoidBottomInset: false,
      backgroundColor: Colors.transparent,
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color(0xFF4A8CA9), // Azul claro do topo
              Color(0xFF003D6A), // Azul escuro da base
            ],
          ),
        ),
        child: SafeArea(
          child: Stack(
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 16,
                ),
                child: Column(
                  children: [
                    const SizedBox(height: 60),
                    const Center(
                      // 1. Título Login
                      child: Text(
                        "Login",
                        style: TextStyle(
                          fontSize: 32,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),


                    // 3. Campo E-mail
                    const Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        "E-mail:",
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                    const SizedBox(height: 6),
                    TextField(
                      controller: email,
                      keyboardType: TextInputType.emailAddress,
                      style: const TextStyle(color: Colors.black87),
                      decoration: InputDecoration(
                        filled: true,
                        fillColor: Colors.white,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(15),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),


                    const SizedBox(height: 16),


                    // 4. Campo Senha
                    const Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        "Senha:",
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                    const SizedBox(height: 6),
                    TextField(
                      controller: senha,
                      obscureText: !_senhaVisivel,
                      style: const TextStyle(color: Colors.black87),
                      decoration: InputDecoration(
                        filled: true,
                        fillColor: Colors.white,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(15),
                          borderSide: BorderSide.none,
                        ),
                        suffixIcon: IconButton(
                          icon: Icon(
                            _senhaVisivel
                                ? Icons.visibility_off
                                : Icons.visibility,
                            color: const Color(0xFF003D6A),
                          ),
                          onPressed: () {
                            setState(() {
                              _senhaVisivel = !_senhaVisivel;
                            });
                          },
                        ),
                      ),
                    ),


                    // 5. Esqueci a Senha
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton(
                        style: TextButton.styleFrom(
                          padding: EdgeInsets.zero,
                          alignment: Alignment.centerLeft,
                        ),
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
                                  color: Colors.white,
                                ),
                              )
                            : Text(
                                _segundosRestantes > 0
                                    ? "Reenviar email em ${_segundosRestantes}s"
                                    : (_emailEnviado
                                          ? "Reenviar email"
                                          : "Esqueceu a senha?"),
                                style: TextStyle(
                                  color: _segundosRestantes > 0
                                      ? Colors.white54
                                      : Colors.white,
                                  decoration: TextDecoration.underline,
                                  decorationColor: Colors.white,
                                ),
                              ),
                      ),
                    ),


                    const SizedBox(height: 10),


                    // 6. Botão Entrar
                    SizedBox(
                      width: double.infinity,
                      height: 45,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF018ABE),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(20),
                          ),
                        ),
                        onPressed: _fazerLogin,
                        child: const Text(
                          "Entrar",
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),


                    const SizedBox(height: 16),


                    // 7. Divisor "OU"
                    Row(
                      children: const [
                        Expanded(
                          child: Divider(color: Colors.white54, thickness: 1),
                        ),
                        Padding(
                          padding: EdgeInsets.symmetric(horizontal: 12),
                          child: Text(
                            "OU",
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        Expanded(
                          child: Divider(color: Colors.white54, thickness: 1),
                        ),
                      ],
                    ),


                    const SizedBox(height: 16),


                    // 8. Botão Google
                    SizedBox(
                      width: double.infinity,
                      height: 48,
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(25),
                          ),
                        ),
                        icon: Image.asset(
                          'assets/images/google_logo.webp',
                          width: 22,
                          height: 22,
                        ),
                        label: const Text(
                          "Continuar com Google",
                          style: TextStyle(
                            color: Colors.black87,
                            fontSize: 16,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        onPressed: () async {
                          await Supabase.instance.client.auth.signInWithOAuth(
                            OAuthProvider.google,
                            redirectTo: 'io.supabase.flutter://login-callback',
                          );
                        },
                      ),
                    ),


                    const SizedBox(height: 20),


                    // 9. Link de Cadastro
                    GestureDetector(
                      onTap: () {
                        Navigator.pushReplacementNamed(context, '/cadastro');
                      },
                      child: const Text(
                        "Não tem conta? Cadastre-se",
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 15,
                          decoration: TextDecoration.underline,
                          decorationColor: Colors.white,
                        ),
                      ),
                    ),
                  ],
                ),
              ),


              // Imagem no rodapé
              Positioned(
                bottom: 25,
                left: 25,
                child: RichText(
                  text: const TextSpan(
                    children: [
                      TextSpan(
                        text: "Inclu",
                        style: TextStyle(
                          color: Color(0xFFF5F5F5),
                          fontSize: 30,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      TextSpan(
                        text: "Zone",
                        style: TextStyle(
                          color: Color(0xFF78BDD8),
                          fontSize: 30,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
      floatingActionButton: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          FloatingActionButton(
            heroTag: "btn_diminuir",
            onPressed: _nivelZoom > 0 ? () => _atualizarZoom(false) : null,
            backgroundColor: _nivelZoom > 0
                ? const Color(0xFF97CADB)
                : Colors.grey.shade300,
            foregroundColor: _nivelZoom > 0
                ? const Color(0xFF005E7D)
                : Colors.grey.shade600,


            shape: const CircleBorder(),
            child: Text(
              "A-",
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: _nivelZoom > 0
                    ? const Color(0xFF005E7D)
                    : Colors.grey.shade600,
              ),
            ),
          ),


          const SizedBox(width: 12),
          FloatingActionButton(
            heroTag: "btn_aumentar",
            onPressed: _nivelZoom < 2 ? () => _atualizarZoom(true) : null,
            backgroundColor: _nivelZoom < 2
                ? const Color(0xFF2F8BAF)
                : Colors.grey.shade300,
            foregroundColor: _nivelZoom < 2
                ? const Color(0xFFF5F5F5)
                : Colors.grey.shade600,


            shape: const CircleBorder(),
            child: Text(
              "A+",
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: _nivelZoom < 2
                    ? const Color(0xFFF5F5F5)
                    : Colors.grey.shade600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
