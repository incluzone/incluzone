import 'package:flutter/material.dart';
import '../services/supabase_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'dart:io';
import '../main.dart';
import 'package:shared_preferences/shared_preferences.dart';

class RedefinirSenhaScreen extends StatefulWidget {
  const RedefinirSenhaScreen({super.key});

  @override
  State<RedefinirSenhaScreen> createState() => _RedefinirSenhaScreenState();
}

class _RedefinirSenhaScreenState extends State<RedefinirSenhaScreen> {
  final user = Supabase.instance.client.auth.currentUser;
  final senha = TextEditingController();
  final confirmarSenha = TextEditingController();
  int _nivelZoom = 0;
  bool _carregando = false;

  bool _senhaVisivel = false;
  bool _confirmarSenhaVisivel = false;
  final service = SupabaseService();

  @override
  void initState() {
    super.initState();

    _carregarConfiguracoesIniciais();
    Supabase.instance.client.auth.onAuthStateChange.listen((data) {
      final event = data.event;

      if (event == AuthChangeEvent.passwordRecovery) {
        // usuário entrou via link de recuperação
        debugPrint("Modo recuperação ativado");
        if (mounted) {
          _mostrarSnackBar("Defina sua nova senha abaixo.");
        }
      }
    });
  }

  @override
  void dispose() {
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
      debugPrint("Erro ao carregar configurações: $e");
    }
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
    // A senha é obrigatória nesta tela: ela existe justamente para defini-la.
    if (senha.text.trim().isEmpty) {
      _mostrarDialogo("Campo obrigatório", "Digite a nova senha.");
      return false;
    }

    final temMaiuscula = RegExp(r'[A-Z]').hasMatch(senha.text);
    final temNumero = RegExp(r'[0-9]').hasMatch(senha.text);
    final temEspecial = RegExp(
      r'[!@#\$&*~%^()_\-+=<>?/\\|{}[\]:;.,]',
    ).hasMatch(senha.text);

    if (senha.text.length < 8 || !temMaiuscula || !temNumero || !temEspecial) {
      _mostrarDialogo(
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
      _mostrarDialogo("Erro", "As senhas não coincidem.");
      return false;
    }

    return true;
  }

  Future<void> _atualizar() async {
    if (_carregando) return;
    if (!_validarCampos()) return;

    if (!(await _temInternet())) {
      if (mounted) {
        _mostrarDialogo(
          "Sem Conexão",
          "Parece que você está offline. Verifique sua conexão com a internet e tente novamente.",
        );
      }
      return; // Interrompe a execução aqui
    }

    setState(() => _carregando = true);

    try {
      final session = Supabase.instance.client.auth.currentSession;
      if (session == null) {
        setState(() => _carregando = false);
        _mostrarDialogo(
          "Sessão inválida",
          "O link de recuperação expirou ou já foi usado. Solicite um novo link e abra-o novamente.",
          botoesPersonalizados: [
            TextButton(
              onPressed: () {
                Navigator.pop(context);
                Navigator.pushReplacementNamed(context, '/login');
              },
              child: const Text("Ir para login"),
            ),
          ],
        );
        return;
      }

      await Supabase.instance.client.auth.updateUser(
        UserAttributes(password: senha.text.trim()),
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Senha atualizada com sucesso! Faça login."),
          ),
        );
        await Supabase.instance.client.auth.signOut();
        Navigator.pushReplacementNamed(context, '/login');
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
      debugPrint("Erro ao atualizar senha: $e");
      _mostrarDialogo(
        "Erro",
        "Não foi possível atualizar sua senha agora. Tente novamente.",
      );
    } finally {
      if (mounted) setState(() => _carregando = false);
    }
  }

@override
Widget build(BuildContext context) {
  return Scaffold(
    resizeToAvoidBottomInset: false,
    appBar: AppBar(
      backgroundColor: const Color(0xFF4589A4),
      elevation: 0,
      iconTheme: const IconThemeData(color: Colors.white),
    ),
    body: Container(
      width: double.infinity,
      height: double.infinity,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Color(0xFF4589A4), // #4589a4 em cima
            Color(0xFF013E69), // #013e69 em baixo
          ],
        ),
      ),
      child: Stack(
        children: [
          // Conteúdo subido para a parte superior (~20% da tela acima)
          Align(
            alignment: const Alignment(0, -0.6),
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 28),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Título da Tela
                  const Text(
                    "Redefinir Senha",
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 32),

                  // Rótulo: Nova senha
                  const Text(
                    "Nova senha:",
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                  const SizedBox(height: 8),
                  // Campo: Nova senha
                  Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(25),
                    ),
                    child: TextField(
                      controller: senha,
                      obscureText: !_senhaVisivel,
                      style: const TextStyle(color: Colors.black),
                      decoration: InputDecoration(
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 14,
                        ),
                        border: InputBorder.none,
                        suffixIcon: IconButton(
                          icon: Icon(
                            _senhaVisivel
                                ? Icons.visibility_off
                                : Icons.visibility,
                            color: const Color(0xFF4589A4),
                          ),
                          onPressed: () {
                            setState(() {
                              _senhaVisivel = !_senhaVisivel;
                            });
                          },
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),

                  // Rótulo: Confirmar nova senha
                  const Text(
                    "Confirmar nova senha:",
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                  const SizedBox(height: 8),
                  // Campo: Confirmar nova senha
                  Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(25),
                    ),
                    child: TextField(
                      controller: confirmarSenha,
                      obscureText: !_confirmarSenhaVisivel,
                      style: const TextStyle(color: Colors.black),
                      decoration: InputDecoration(
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 14,
                        ),
                        border: InputBorder.none,
                        suffixIcon: IconButton(
                          icon: Icon(
                            _confirmarSenhaVisivel
                                ? Icons.visibility_off
                                : Icons.visibility,
                            color: const Color(0xFF4589A4),
                          ),
                          onPressed: () {
                            setState(() {
                              _confirmarSenhaVisivel = !_confirmarSenhaVisivel;
                            });
                          },
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 32),

                  // Botão Salvar
                  SizedBox(
                    height: 50,
                    child: ElevatedButton(
                      onPressed: _carregando ? null : _atualizar,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF0088CC),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(25),
                        ),
                        elevation: 3,
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
                          : const Text(
                              "Salvar",
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Texto IncluZone estilizado no canto inferior esquerdo
          Positioned(
            bottom: 25,
            left: 25,
            child: RichText(
              text: const TextSpan(
                children: [
                  TextSpan(
                    text: "Inclu",
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 26,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  TextSpan(
                    text: "Zone",
                    style: TextStyle(
                      color: Color(0xFF79BFE1),
                      fontSize: 26,
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

    // Botões de Zoom no padrão dos 3 estados
    floatingActionButton: Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        // Botão A-
        SizedBox(
          width: 56,
          height: 56,
          child: FloatingActionButton(
            heroTag: "btn_diminuir",
            onPressed: _nivelZoom > 0 ? () => _atualizarZoom(false) : null,
            backgroundColor: _nivelZoom == 0
                ? const Color(0xFFE0E0E0)
                : const Color(0xFF9BCDE0),
            disabledElevation: 0,
            elevation: 2,
            shape: const CircleBorder(),
            child: Text(
              "A-",
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: _nivelZoom == 0
                    ? const Color(0xFF9E9E9E)
                    : const Color(0xFF005670),
              ),
            ),
          ),
        ),
        const SizedBox(width: 12),
        // Botão A+
        SizedBox(
          width: 56,
          height: 56,
          child: FloatingActionButton(
            heroTag: "btn_aumentar",
            onPressed: _nivelZoom < 2 ? () => _atualizarZoom(true) : null,
            backgroundColor: _nivelZoom == 2
                ? const Color(0xFFE0E0E0)
                : const Color(0xFF2B82B5),
            disabledElevation: 0,
            elevation: 2,
            shape: const CircleBorder(),
            child: Text(
              "A+",
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: _nivelZoom == 2
                    ? const Color(0xFF9E9E9E)
                    : Colors.white,
              ),
            ),
          ),
        ),
      ],
    ),
  );
}
}