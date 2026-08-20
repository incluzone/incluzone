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
  bool _carregandoGoogle = false;
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
        try {
          await service.garantirPerfilGoogle();
        } catch (e) {
          // Não bloqueia o fluxo, apenas registra o problema
          print("Erro ao garantir perfil do Google: $e");
        }

        // NOVIDADE: Se o usuário selecionou uma foto no formulário de cadastro,
        // fazemos o upload dela agora que ele está autenticado com sucesso.
        if (_imagemSelecionada != null) {
          try {
            await service.uploadFotoPerfil(_imagemSelecionada!);
          } catch (e) {
            // Se falhar o upload da foto, ainda assim deixa o usuário entrar,
            // mas avisamos para que ele saiba que precisa tentar novamente depois.
            print("Erro ao subir foto no pós-cadastro: $e");
            if (mounted) {
              await _mostrarDialogo(
                context,
                "Aviso",
                "Não foi possível enviar sua foto de perfil agora. "
                    "Você poderá adicioná-la depois, no seu perfil.",
              );
            }
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
    _timer?.cancel();
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
      print("Erro ao carregar configurações: $e");
    }
  }

  Future<void> _selecionarImagem() async {
    try {
      final XFile? imagem = await _picker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 70, // Compacta um pouco para não pesar no Supabase
      );

      if (imagem != null) {
        setState(() {
          _imagemSelecionada = File(imagem.path);
        });
        _mostrarSnackBar("Foto selecionada com sucesso.");
      }
    } catch (e) {
      if (mounted) {
        _mostrarDialogo(
          context,
          "Erro",
          "Não foi possível selecionar a imagem. Tente novamente.",
        );
      }
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

  // Agora retorna o Future do showDialog, permitindo que o chamador
  // aguarde o fechamento do diálogo quando necessário (ex: antes de navegar).
  Future<void> _mostrarDialogo(
    BuildContext context,
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
                child: Text("OK"),
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
      _mostrarDialogo(
        context,
        "Sem Conexão",
        "Verifique sua internet e tente novamente.",
      );
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
            _mostrarSnackBar("E-mail reenviado. Confira sua caixa de entrada.");
          }

          setState(() => _carregando = false);
          _iniciarTimer();
        } on AuthException catch (e) {
          setState(() => _carregando = false);
          _tratarErroAuth(e);
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
      _mostrarDialogo(
        context,
        "Erro",
        "Falha na operação. Tente novamente em instantes.",
      );
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
        botoesPersonalizados: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text("Corrigir e-mail"),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              Navigator.pushReplacementNamed(context, '/login');
            },
            child: Text("Ir para login"),
          ),
        ],
      );
    } else {
      _mostrarDialogo(context, "Erro", e.message);
    }
  }

  Future<void> _entrarComGoogle() async {
    if (_carregandoGoogle) return;

    if (!(await _temInternet())) {
      _mostrarDialogo(
        context,
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
      _mostrarDialogo(context, "Erro", e.message);
    } catch (e) {
      _mostrarDialogo(
        context,
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
      appBar: AppBar(title: Text("Cadastro")),
      body: Stack(
        children: [
          Padding(
            padding: EdgeInsets.all(16),
            child: Column(
              children: [
                const SizedBox(height: 10),

                // --- COMPONENTE DO AVATAR COM ÍCONE DE CÂMERA ---
                Center(
                  child: GestureDetector(
                    // Agora o clique em QUALQUER lugar do componente segue a mesma regra
                    onTap: () {
                      if (_imagemSelecionada != null) {
                        // Se já tem imagem, o clique (na foto ou no X) remove e volta ao início
                        setState(() {
                          _imagemSelecionada = null;
                        });
                        _mostrarSnackBar("Foto removida.");
                      } else {
                        // Se não tem imagem, abre o seletor
                        _selecionarImagem();
                      }
                    },
                    child: Stack(
                      children: [
                        // Avatar Principal
                        CircleAvatar(
                          radius: 60, // Tamanho do avatar
                          backgroundImage: _imagemSelecionada != null
                              ? FileImage(_imagemSelecionada!)
                              : null,
                          child: _imagemSelecionada == null
                              ? ClipOval(
                                  child: Image.asset(
                                    'assets/images/avatar.webp',
                                    width: 120,
                                    height: 120,
                                    fit: BoxFit.cover,
                                  ),
                                )
                              : null,
                        ),
                        // Botão indicador no canto (Apenas visual ou clique redundante)
                        Positioned(
                          bottom: 0,
                          right: 0,
                          child: CircleAvatar(
                            backgroundColor: _imagemSelecionada != null
                                ? Colors
                                      .red // Fica vermelho quando tem o "X" para indicar remoção
                                : Theme.of(context).primaryColor,
                            radius: 20,
                            child: Icon(
                              _imagemSelecionada != null
                                  ? Icons
                                        .close // Ícone de "X"
                                  : Icons.add_a_photo, // Ícone de câmera
                              size: 20,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 20),
                TextField(
                  controller: nome,
                  decoration: InputDecoration(labelText: "Nome"),
                ),
                TextField(
                  controller: email,
                  keyboardType: TextInputType.emailAddress,
                  decoration: InputDecoration(labelText: "Email"),
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
                TextField(
                  controller: confirmarSenha,
                  obscureText: true,
                  decoration: InputDecoration(labelText: "Confirmar senha"),
                ),

                SizedBox(height: 20),

                // BOTÃO CADASTRAR
                SizedBox(
                  child: ElevatedButton(
                    onPressed: (_segundosRestantes == 0 && !_carregando)
                        ? _processarAcaoEmail
                        : null, // Desabilita o botão se estiver carregando ou no timer
                    child: _carregando
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Text(
                            _segundosRestantes > 0
                                ? "Aguarde ${_segundosRestantes}s"
                                : (_emailEnviado ? "Reenviar" : "Cadastrar"),
                          ),
                  ),
                ),

                const SizedBox(height: 20),
                GestureDetector(
                  onTap: () {
                    Navigator.pushReplacementNamed(context, '/login');
                  },
                  child: Text.rich(
                    TextSpan(
                      text: "Já tem conta? ",
                      style: const TextStyle(color: Colors.black87),
                      children: [
                        TextSpan(
                          text: "Faça o login",
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

                // TEXTO "OU" CENTRALIZADO
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

                // BOTÃO GOOGLE (AGORA NO TOPO)
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
