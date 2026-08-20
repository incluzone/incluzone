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
      appBar: AppBar(title: const Text("Redefinir Senha")),
      body: Stack(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                TextField(
                  controller: senha,
                  obscureText: !_senhaVisivel,
                  decoration: InputDecoration(
                    labelText: "Nova senha",
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
                  obscureText: !_confirmarSenhaVisivel,
                  decoration: InputDecoration(
                    labelText: "Confirmar nova senha",
                    suffixIcon: IconButton(
                      icon: Icon(
                        _confirmarSenhaVisivel
                            ? Icons.visibility_off
                            : Icons.visibility,
                      ),
                      onPressed: () {
                        setState(() {
                          _confirmarSenhaVisivel = !_confirmarSenhaVisivel;
                        });
                      },
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                ElevatedButton(
                  onPressed: _carregando ? null : _atualizar,
                  child: _carregando
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text("Salvar"),
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