import 'package:flutter/material.dart';
import '../services/supabase_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'dart:async';
import 'dart:io';
import '../main.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:image_picker/image_picker.dart';

class CadastroScreen extends StatefulWidget {
  const CadastroScreen({super.key});

  @override
  State<CadastroScreen> createState() => _CadastroScreenState();
}

class _CadastroScreenState extends State<CadastroScreen> {
  final nome = TextEditingController();
  final email = TextEditingController();
  final senha = TextEditingController();
  final confirmarSenha = TextEditingController();
  bool _senhaVisivel = false;
  Timer? _timer;
  int _segundosRestantes = 0;
  bool _emailEnviado = false;
  String _ultimoEmailTentado = ""; // Para comparar se o e-mail mudou
  bool _carregando = false;
  File? _imagemSelecionada;
  final ImagePicker _picker = ImagePicker();

  bool _navegou = false;
  late final StreamSubscription authSub;

  final service = SupabaseService();
  int _nivelZoom = 0;

  @override
  void initState() {
    super.initState();
    _carregarConfiguracoesIniciais();
    authSub = Supabase.instance.client.auth.onAuthStateChange.listen((
      data,
    ) async {
      final session = data.session;

      if (session != null && !_navegou) {
        _navegou = true;

        // Se o usuário veio pelo Google, atualiza o nome padrão do Google
        await service.garantirPerfilGoogle();

        // NOVIDADE: Se o usuário selecionou uma foto no formulário de cadastro,
        // fazemos o upload dela agora que ele está autenticado com sucesso.
        if (_imagemSelecionada != null) {
          try {
            await service.uploadFotoPerfil(_imagemSelecionada!);
          } catch (e) {
            // Se falhar o upload da foto, ainda assim deixa o usuário entrar
            print("Erro ao subir foto no pós-cadastro: $e");
          }
        }

        if (mounted) {
          Navigator.pushReplacementNamed(context, '/');
        }
      }
    });
  }

  @override
  void dispose() {
    authSub.cancel();
    nome.dispose();
    email.dispose();
    senha.dispose();
    confirmarSenha.dispose();
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

  Future<void> _selecionarImagem() async {
    final XFile? imagem = await _picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 70, // Compacta um pouco para não pesar no Supabase
    );

    if (imagem != null) {
      setState(() {
        _imagemSelecionada = File(imagem.path);
      });
    }
  }

  void _iniciarTimer() {
    setState(() {
      _segundosRestantes = 60;
      _emailEnviado = true;
    });

    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_segundosRestantes == 0) {
        timer.cancel();
        if (mounted) setState(() {});
      } else {
        if (mounted) {
          setState(() {
            _segundosRestantes--;
          });
        }
      }
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

  void _mostrarDialogo(BuildContext context, String titulo, String mensagem) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(titulo),
        content: Text(mensagem),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text("OK"),
          ),
        ],
      ),
    );
  }

  bool _validarCampos(BuildContext context) {
    if (nome.text.trim().isEmpty ||
        email.text.trim().isEmpty ||
        senha.text.trim().isEmpty) {
      _mostrarDialogo(context, "Erro", "Todos os campos são obrigatórios.");
      return false;
    }

    if (!email.text.contains("@") || !email.text.contains(".")) {
      _mostrarDialogo(context, "Erro", "Digite um e-mail válido.");
      return false;
    }

    final senhaValue = senha.text;

    final temMaiuscula = RegExp(r'[A-Z]').hasMatch(senhaValue);
    final temNumero = RegExp(r'[0-9]').hasMatch(senhaValue);
    final temEspecial = RegExp(
      r'[!@#\$&*~%^()_\-+=<>?/\\|{}[\]:;.,]',
    ).hasMatch(senhaValue);

    if (senha.text.length < 8 || !temMaiuscula || !temNumero || !temEspecial) {
      _mostrarDialogo(
        context,
        "Senha fraca",
        "A senha deve ter:\n"
            "- Pelo menos 8 caracteres\n"
            "- Pelo menos 1 letra maiúscula\n"
            "- Pelo menos 1 número\n"
            "- Pelo menos 1 caractere especial",
      );
      return false;
    }

    if (senha.text != confirmarSenha.text) {
      _mostrarDialogo(context, "Erro", "As senhas não coincidem.");
      return false;
    }

    return true;
  }

  Future<void> _processarAcaoEmail() async {
    if (_carregando) return;

    final emailAtual = email.text.trim();

    // Validação básica de campo antes de tentar qualquer coisa
    if (emailAtual.isEmpty) {
      _mostrarDialogo(context, "Erro", "Digite o e-mail.");
      return;
    }

    if (!(await _temInternet())) {
      _mostrarDialogo(context, "Sem Conexão", "Verifique sua internet.");
      return;
    }

    setState(() => _carregando = true);

    try {
      if (!_emailEnviado) {
        // --- LOGICA DE CADASTRO INICIAL ---
        if (!_validarCampos(context)) {
          setState(() => _carregando = false);
          return;
        }
        await service.cadastrarUsuario(nome.text, emailAtual, senha.text);
        _ultimoEmailTentado = emailAtual;

        // Primeiro paramos o loading, depois iniciamos o timer
        setState(() => _carregando = false);
        _iniciarTimer();

        _mostrarDialogo(
          context,
          "Verifique seu e-mail",
          "Link enviado para $emailAtual",
        );
      } else {
        try {
          if (emailAtual != _ultimoEmailTentado) {
            // Se o e-mail mudou, não tentamos atualizar o usuário "fantasma"
            // Fazemos um novo cadastro com os dados corretos
            await service.cadastrarUsuario(nome.text, emailAtual, senha.text);
            _ultimoEmailTentado = emailAtual;
            _mostrarDialogo(
              context,
              "E-mail Corrigido",
              "Novo link enviado para $emailAtual",
            );
          } else {
            // Se for o mesmo e-mail, usamos o resend (que não exige sessão)
            await Supabase.instance.client.auth.resend(
              type: OtpType.signup,
              email: emailAtual,
            );
            _mostrarDialogo(
              context,
              "E-mail Reenviado",
              "Confira sua caixa de entrada.",
            );
          }

          setState(() => _carregando = false);
          _iniciarTimer();
        } catch (e) {
          setState(() => _carregando = false);
          // Trate o erro de "User already registered" aqui se o usuário
          // tentar corrigir para um e-mail que já existe de verdade
          _mostrarDialogo(
            context,
            "Erro",
            "Não foi possível reenviar. Verifique os dados.",
          );
        }
      }
    } on AuthException catch (e) {
      setState(() => _carregando = false);
      _tratarErroAuth(e);
    } catch (e) {
      setState(() => _carregando = false);
      _mostrarDialogo(context, "Erro", "Falha na operação.");
    } finally {
      // Garantia final de que o load sairá da tela
      if (mounted && _carregando) setState(() => _carregando = false);
    }
  }

  void _tratarErroAuth(AuthException e) {
    final msg = e.message.toLowerCase();
    if (msg.contains('already') || msg.contains('registered')) {
      _mostrarDialogo(
        context,
        "Conta já existe",
        "Este e-mail já está cadastrado.",
      );
    } else {
      _mostrarDialogo(context, "Erro", e.message);
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
              Color(0xFF003D6A), // Azul escuro no topo
              Color(0xFF4A8CA9), // Azul claro na base
            ],
          ),
        ),
        child: SafeArea(
          child: Stack(
            children: [
              SingleChildScrollView(
                padding: const EdgeInsets.symmetric(
                  horizontal: 28,
                  vertical: 20,
                ),
                child: Column(
                  children: [
                    const Text(
                      "Crie sua conta",
                      style: TextStyle(
                        fontSize: 30,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 20),

                    // --- AVATAR COM CÂMERA ---
                    Center(
                      child: GestureDetector(
                        onTap: () {
                          if (_imagemSelecionada != null) {
                            setState(() {
                              _imagemSelecionada = null;
                            });
                          } else {
                            _selecionarImagem();
                          }
                        },
                        child: Stack(
                          children: [
                            CircleAvatar(
                              radius: 55,
                              backgroundColor: const Color(0xFF007ACC),
                              backgroundImage: _imagemSelecionada != null
                                  ? FileImage(_imagemSelecionada!)
                                  : null,
                              child: _imagemSelecionada == null
                                  ? const Icon(
                                      Icons.person,
                                      size: 80,
                                      color: Colors.white,
                                    )
                                  : null,
                            ),
                            Positioned(
                              bottom: 0,
                              right: 0,
                              child: Icon(
                                _imagemSelecionada != null
                                    ? Icons.close
                                    : Icons.camera_alt,
                                size: 32,
                                color: Colors.white,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),

                    // --- CAMPO NOME ---
                    const Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        "Nome:",
                        style: TextStyle(color: Colors.white, fontSize: 16),
                      ),
                    ),
                    const SizedBox(height: 6),
                    TextField(
                      controller: nome,
                      style: const TextStyle(color: Colors.black87),
                      decoration: InputDecoration(
                        filled: true,
                        fillColor: Colors.white,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(20),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),

                    // --- CAMPO EMAIL ---
                    const Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        "E-mail:",
                        style: TextStyle(color: Colors.white, fontSize: 16),
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
                          borderRadius: BorderRadius.circular(20),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),

                    // --- CAMPO SENHA ---
                    const Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        "Senha:",
                        style: TextStyle(color: Colors.white, fontSize: 16),
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
                          borderRadius: BorderRadius.circular(20),
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
                    const SizedBox(height: 14),

                    // --- CAMPO CONFIRMAR SENHA ---
                    const Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        "Confirmar Senha:",
                        style: TextStyle(color: Colors.white, fontSize: 16),
                      ),
                    ),
                    const SizedBox(height: 6),
                    TextField(
                      controller: confirmarSenha,
                      obscureText: true,
                      style: const TextStyle(color: Colors.black87),
                      decoration: InputDecoration(
                        filled: true,
                        fillColor: Colors.white,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(20),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                    const SizedBox(height: 28),

                    // --- BOTÃO CADASTRAR-SE ---
                    SizedBox(
                      width: double.infinity,
                      height: 50,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF0088CC),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(25),
                          ),
                          elevation: 3,
                        ),
                        onPressed: (_segundosRestantes == 0 && !_carregando)
                            ? _processarAcaoEmail
                            : null,
                        child: _carregando
                            ? const SizedBox(
                                height: 20,
                                width: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : Text(
                                _segundosRestantes > 0
                                    ? "Aguarde ${_segundosRestantes}s"
                                    : (_emailEnviado
                                          ? "Reenviar"
                                          : "Cadastrar-se"),
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                      ),
                    ),
                    const SizedBox(height: 20),

                    // --- DIVISOR "OU" ---
                    Row(
                      children: const [
                        Expanded(
                          child: Divider(color: Colors.white38, thickness: 1),
                        ),
                        Padding(
                          padding: EdgeInsets.symmetric(horizontal: 12),
                          child: Text(
                            "OU",
                            style: TextStyle(
                              color: Colors.white70,
                              fontSize: 13,
                            ),
                          ),
                        ),
                        Expanded(
                          child: Divider(color: Colors.white38, thickness: 1),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),

                    // --- BOTÃO GOOGLE ---
                    SizedBox(
                      width: double.infinity,
                      height: 48,
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(25),
                          ),
                          elevation: 2,
                        ),
                        icon: Image.asset(
                          'assets/images/google_logo.webp',
                          width: 22,
                          height: 22,
                        ),
                        label: const Text(
                          "Continuar com o Google",
                          style: TextStyle(
                            color: Color(0xFF003D6A),
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
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
                    const SizedBox(height: 24),

                    // --- LINK PARA LOGIN ---
                    GestureDetector(
                      onTap: () {
                        Navigator.pushReplacementNamed(context, '/login');
                      },
                      child: const Text(
                        "Já possui login? Entre aqui",
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          decoration: TextDecoration.underline,
                          decorationColor: Colors.white,
                        ),
                      ),

                    
                    ),

                    const SizedBox(height: 80),

                    // --- MARCA INCLUZONE NO RODAPÉ ---
                    Align(
                      alignment: Alignment.centerLeft,
                      child: RichText(
                        text: const TextSpan(
                          children: [
                            TextSpan(
                              text: "Inclu",
                              style: TextStyle(
                                color: Color(0xFFF5F5F5),
                                fontSize: 24,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            TextSpan(
                              text: "Zone",
                              style: TextStyle(
                                color: Color(0xFF78BDD8),
                                fontSize: 24,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),

                    const SizedBox(height: 25),
                  ],
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
