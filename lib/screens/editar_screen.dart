import 'package:flutter/material.dart';
import '../services/supabase_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'dart:io';
import 'dart:async';
import '../main.dart';
import 'package:image_picker/image_picker.dart';

class EditarScreen extends StatefulWidget {
  const EditarScreen({super.key});

  @override
  State<EditarScreen> createState() => _EditarScreenState();
}

class _EditarScreenState extends State<EditarScreen> {
  final nome = TextEditingController();
  final email = TextEditingController();
  final senha = TextEditingController();
  final confirmarSenha = TextEditingController();
  final SupabaseService _supabaseService = SupabaseService();
  Timer? _timer;
  int _segundosRestantes = 0;
  bool _emailAlteradoPendente = false;
  String _ultimoEmailTentaAlterar = "";
  bool _carregando = false;
  bool _excluindo = false;
  File? _imagemSelecionada;
  String? _urlImagemExistente;
  final ImagePicker _picker = ImagePicker();
  late final StreamSubscription<AuthState> _authSubscription;

  bool _senhaVisivel = false;
  int _nivelZoom = 0;

  @override
  void initState() {
    super.initState();
    _carregarConfiguracoesIniciais();
    _carregarDadosUsuario();
    _authSubscription = Supabase.instance.client.auth.onAuthStateChange.listen((
      data,
    ) {
      final user = data.session?.user;
      if (user != null &&
          user.email == _ultimoEmailTentaAlterar &&
          user.newEmail == null &&
          _emailAlteradoPendente) {
        if (mounted) {
          _timer?.cancel();
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("E-mail confirmado com sucesso!")),
          );
          Navigator.pushReplacementNamed(context, '/');
        }
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    nome.dispose();
    email.dispose();
    senha.dispose();
    confirmarSenha.dispose();
    _authSubscription.cancel();
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

    await prefs.setInt('nivel_zoom', _nivelZoom);
    myAppKey.currentState?.atualizarEscala(_nivelZoom);
  }

  Future<void> _selecionarImagem() async {
    try {
      final XFile? imagem = await _picker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 70,
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
          "Erro",
          "Não foi possível selecionar a imagem. Tente novamente.",
        );
      }
    }
  }

  Future<void> _carregarConfiguracoesIniciais() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      setState(() {
        _nivelZoom = prefs.getInt('nivel_zoom') ?? 0;
      });
    } catch (e) {
      debugPrint("Erro ao carregar configurações: $e");
    }
  }

  Future<void> _carregarDadosUsuario() async {
    setState(() => _carregando = true);
    bool carregouAlgumDado = false;

    try {
      final response = await Supabase.instance.client.auth.getUser();
      final user = response.user;

      if (user != null) {
        setState(() {
          nome.text = user.userMetadata?['name'] ?? '';
          email.text = user.email ?? '';
          _urlImagemExistente = user.userMetadata?['avatar_url'];

          if (_emailAlteradoPendente &&
              user.email == _ultimoEmailTentaAlterar) {
            _emailAlteradoPendente = false;
          }
        });
        carregouAlgumDado = true;
      }
    } catch (e) {
      final user = Supabase.instance.client.auth.currentUser;
      if (user != null) {
        setState(() {
          nome.text = user.userMetadata?['name'] ?? '';
          email.text = user.email ?? '';
          _urlImagemExistente = user.userMetadata?['avatar_url'];
        });
        carregouAlgumDado = true;
      }
    } finally {
      if (mounted) setState(() => _carregando = false);
    }

    if (!carregouAlgumDado && mounted) {
      _mostrarDialogo(
        "Erro",
        "Não foi possível carregar os dados do seu perfil. "
            "Verifique sua conexão e tente novamente mais tarde.",
      );
    }
  }

  void _iniciarTimer() {
    setState(() {
      _segundosRestantes = 60;
    });
    _timer?.cancel();

    _timer = Timer.periodic(const Duration(seconds: 1), (timer) async {
      if (_segundosRestantes == 0) {
        timer.cancel();
        if (_emailAlteradoPendente && mounted) {
          _mostrarSnackBar(
            "O tempo para confirmar o novo e-mail expirou. "
            "Você pode tentar novamente quando quiser.",
          );
        }
      } else {
        if (mounted) {
          setState(() => _segundosRestantes--);

          if (_segundosRestantes % 3 == 0 && _emailAlteradoPendente) {
            try {
              final response = await Supabase.instance.client.auth.getUser();
              final user = response.user;

              if (user != null &&
                  user.email == _ultimoEmailTentaAlterar &&
                  user.newEmail == null) {
                timer.cancel();

                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text("E-mail confirmado com sucesso!"),
                    ),
                  );
                  Navigator.pushReplacementNamed(context, '/');
                }
              }
            } catch (e) {
              debugPrint("Erro na verificação automática: $e");
            }
          }
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
      final result = await InternetAddress.lookup('google.com');
      return result.isNotEmpty && result[0].rawAddress.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

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

  bool _validarCampos() {
    if (nome.text.trim().isEmpty || email.text.trim().isEmpty) {
      _mostrarDialogo("Erro", "Nome e email são obrigatórios.");
      return false;
    }

    if (!email.text.contains("@") || !email.text.contains(".")) {
      _mostrarDialogo("Erro", "Digite um e-mail válido.");
      return false;
    }

    if (senha.text.isNotEmpty) {
      final temMaiuscula = RegExp(r'[A-Z]').hasMatch(senha.text);
      final temNumero = RegExp(r'[0-9]').hasMatch(senha.text);
      final temEspecial = RegExp(
        r'[!@#\$&*~%^()_\-+=<>?/\\|{}[\]:;.,]',
      ).hasMatch(senha.text);

      if (senha.text.length < 8 ||
          !temMaiuscula ||
          !temNumero ||
          !temEspecial) {
        _mostrarDialogo(
          "Senha fraca",
          "Senha deve ter 8+ caracteres, maiúscula, número e especial.",
        );
        return false;
      }

      if (senha.text != confirmarSenha.text) {
        _mostrarDialogo("Erro", "As senhas não coincidem.");
        return false;
      }
    }

    return true;
  }

  Future<void> _atualizar() async {
    if (_carregando || _segundosRestantes > 0) return;
    if (!_validarCampos()) return;

    if (!(await _temInternet())) {
      _mostrarDialogo("Sem Conexão", "Verifique sua internet.");
      return;
    }

    setState(() => _carregando = true);

    try {
      String? novaUrlAvatar = _urlImagemExistente;

      if (_imagemSelecionada != null) {
        try {
          novaUrlAvatar = await _supabaseService.atualizarFotoPerfil(
            _imagemSelecionada!,
          );
        } catch (e) {
          setState(() => _carregando = false);
          await _mostrarDialogo(
            "Aviso",
            "Não foi possível atualizar sua foto de perfil agora. "
                "Os demais dados serão salvos normalmente.",
          );
          setState(() => _carregando = true);
          novaUrlAvatar = _urlImagemExistente;
        }
      }

      final auth = Supabase.instance.client.auth;
      final emailNovo = email.text.trim();

      final Map<String, dynamic> userMetadata = {'name': nome.text.trim()};
      if (novaUrlAvatar != null) {
        userMetadata['avatar_url'] = novaUrlAvatar;
      }

      await auth.updateUser(
        UserAttributes(
          email: emailNovo,
          password: senha.text.isNotEmpty ? senha.text : null,
          data: userMetadata,
        ),
        emailRedirectTo: 'io.supabase.flutter://login-callback',
      );

      final response = await auth.getUser();
      final userDepois = response.user;

      bool trocaDeEmailPendente = userDepois?.newEmail != null;

      if (trocaDeEmailPendente) {
        setState(() {
          _emailAlteradoPendente = true;
          _ultimoEmailTentaAlterar = emailNovo;
        });
        _iniciarTimer();

        await _mostrarDialogo(
          "Confirme seu e-mail",
          "Para concluir a alteração para $emailNovo, você deve clicar no link enviado para o seu e-mail.",
        );
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("Perfil atualizado com sucesso!")),
          );
          Navigator.pushReplacementNamed(context, '/');
        }
      }
    } on AuthException catch (e) {
      String mensagemErro = e.message;
      if (e.message.contains(
        "New password should be different from the old password",
      )) {
        mensagemErro = "A nova senha deve ser diferente da senha atual.";
      }
      _mostrarDialogo("Erro de autenticação", mensagemErro);
    } catch (e) {
      _mostrarDialogo("Erro", "Falha ao atualizar. Tente novamente.");
    } finally {
      if (mounted) setState(() => _carregando = false);
    }
  }

  Future<void> _excluirConta() async {
    if (_excluindo) return;

    if (!(await _temInternet())) {
      if (mounted) {
        _mostrarDialogo(
          "Sem Conexão",
          "Parece que você está offline. Verifique sua conexão com a internet e tente novamente.",
        );
      }
      return;
    }

    final confirmar = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text("Excluir conta"),
        content: const Text(
          "Tem certeza que deseja excluir sua conta? Essa ação não pode ser desfeita.",
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text("Cancelar"),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text("Excluir", style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirmar != true) return;

    setState(() => _excluindo = true);

    try {
      final user = Supabase.instance.client.auth.currentUser;

      await Supabase.instance.client.functions.invoke(
        'delete-user',
        body: {'userId': user?.id},
      );

      await Supabase.instance.client.auth.signOut();

      if (!mounted) return;

      await _mostrarDialogo(
        "Conta excluída",
        "Sua conta foi excluída com sucesso.",
      );

      if (!mounted) return;
      Navigator.of(context).pushNamedAndRemoveUntil('/', (route) => false);
    } catch (e) {
      debugPrint("Erro ao excluir conta: $e");
      _mostrarDialogo(
        "Erro",
        "Não foi possível excluir a conta agora. Tente novamente mais tarde.",
      );
    } finally {
      if (mounted) setState(() => _excluindo = false);
    }
  }

  Widget _buildFieldLabel(String label) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 6),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Text(
          label,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 16,
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
    );
  }

  InputDecoration _buildInputDecoration({Widget? suffixIcon}) {
    return InputDecoration(
      filled: true,
      fillColor: Colors.white,
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      suffixIcon: suffixIcon,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(25),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(25),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(25),
        borderSide: BorderSide.none,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF0F4C81), Color(0xFF286E95), Color(0xFF438BA8)],
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
                    const SizedBox(height: 10),
                    const Text(
                      "Editar conta",
                      style: TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 20),

                    GestureDetector(
                      onTap: () {
                        final temImagemLocal = _imagemSelecionada != null;
                        final temImagemRemota =
                            _urlImagemExistente != null &&
                            _urlImagemExistente!.isNotEmpty;

                        if (temImagemLocal || temImagemRemota) {
                          setState(() {
                            _imagemSelecionada = null;
                            _urlImagemExistente = null;
                          });
                          _mostrarSnackBar("Foto removida.");
                        } else {
                          _selecionarImagem();
                        }
                      },
                      child: Stack(
                        children: [
                          CircleAvatar(
                            radius: 55,
                            backgroundColor: const Color(0xFF0073E6),
                            backgroundImage: _imagemSelecionada != null
                                ? FileImage(_imagemSelecionada!)
                                : (_urlImagemExistente != null &&
                                      _urlImagemExistente!.isNotEmpty)
                                ? NetworkImage(_urlImagemExistente!)
                                : null,
                            child:
                                (_imagemSelecionada == null &&
                                    (_urlImagemExistente == null ||
                                        _urlImagemExistente!.isEmpty))
                                ? const Icon(
                                    Icons.person,
                                    size: 75,
                                    color: Colors.white,
                                  )
                                : null,
                          ),
                          Positioned(
                            bottom: 0,
                            right: 0,
                            child: CircleAvatar(
                              radius: 18,
                              backgroundColor:
                                  (_imagemSelecionada != null ||
                                      (_urlImagemExistente != null &&
                                          _urlImagemExistente!.isNotEmpty))
                                  ? Colors.red
                                  : const Color(0xFF6B4C9A),
                              child: Icon(
                                (_imagemSelecionada != null ||
                                        (_urlImagemExistente != null &&
                                            _urlImagemExistente!.isNotEmpty))
                                    ? Icons.close
                                    : Icons.add_a_photo,
                                size: 18,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 25),

                    _buildFieldLabel("Nome:"),
                    TextField(
                      controller: nome,
                      style: const TextStyle(color: Colors.black87),
                      decoration: _buildInputDecoration(),
                    ),

                    const SizedBox(height: 16),

                    _buildFieldLabel("E-mail:"),
                    TextField(
                      controller: email,
                      keyboardType: TextInputType.emailAddress,
                      style: const TextStyle(color: Colors.black87),
                      decoration: _buildInputDecoration(),
                    ),

                    const SizedBox(height: 16),

                    _buildFieldLabel("Nova Senha (opcional)"),
                    TextField(
                      controller: senha,
                      obscureText: !_senhaVisivel,
                      style: const TextStyle(color: Colors.black87),
                      decoration: _buildInputDecoration(
                        suffixIcon: IconButton(
                          icon: Icon(
                            _senhaVisivel
                                ? Icons.visibility_off
                                : Icons.visibility,
                            color: const Color(0xFF0F4C81),
                          ),
                          onPressed: () {
                            setState(() {
                              _senhaVisivel = !_senhaVisivel;
                            });
                          },
                        ),
                      ),
                    ),

                    const SizedBox(height: 16),

                    _buildFieldLabel("Confirmar nova senha"),
                    TextField(
                      controller: confirmarSenha,
                      obscureText: true,
                      style: const TextStyle(color: Colors.black87),
                      decoration: _buildInputDecoration(),
                    ),

                    const SizedBox(height: 25),

                    SizedBox(
                      width: double.infinity,
                      height: 50,
                      child: ElevatedButton(
                        onPressed: (_segundosRestantes == 0 && !_carregando)
                            ? _atualizar
                            : null,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF018ABE),
                          elevation: 3,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(25),
                          ),
                        ),
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
                                    : (_emailAlteradoPendente
                                          ? "Reenviar confirmação"
                                          : "Salvar alterações"),
                                style: const TextStyle(
                                  fontSize: 18,
                                  color: Colors.white,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                      ),
                    ),

                    const SizedBox(height: 20),

                    Row(
                      children: [
                        Expanded(
                          child: Container(
                            height: 1,
                            color: Colors.white.withOpacity(0.4),
                          ),
                        ),
                        const Padding(
                          padding: EdgeInsets.symmetric(horizontal: 12),
                          child: Text(
                            "ou",
                            style: TextStyle(
                              color: Colors.white70,
                              fontSize: 14,
                            ),
                          ),
                        ),
                        Expanded(
                          child: Container(
                            height: 1,
                            color: Colors.white.withOpacity(0.4),
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 20),

                    SizedBox(
                      width: double.infinity,
                      height: 50,
                      child: ElevatedButton(
                        onPressed: _excluindo ? null : _excluirConta,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.white,
                          elevation: 2,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(25),
                          ),
                        ),
                        child: _excluindo
                            ? const SizedBox(
                                height: 18,
                                width: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  valueColor: AlwaysStoppedAnimation(
                                    Colors.red,
                                  ),
                                ),
                              )
                            : const Text(
                                "Excluir Conta",
                                style: TextStyle(
                                  fontSize: 18,
                                  color: Color(0xFFFF5252),
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                      ),
                    ),

                    const SizedBox(height: 80),

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
