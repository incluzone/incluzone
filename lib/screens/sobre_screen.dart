import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../main.dart';
import 'package:url_launcher/url_launcher.dart';

class SobreScreen extends StatefulWidget {
  const SobreScreen({super.key});

  @override
  State<SobreScreen> createState() => _SobreScreenState();
}

class _SobreScreenState extends State<SobreScreen> {
  int _nivelZoom = 0;

  @override
  void initState() {
    super.initState();
    _carregarConfiguracoesIniciais();
  }

  Future<void> _enviarEmail() async {
    final Uri emailLaunchUri = Uri(
      scheme: 'mailto',
      path: 'incluzoneapp+suporte@gmail.com',
    );

    try {
      final bool podeAbrir = await canLaunchUrl(emailLaunchUri);

      if (podeAbrir) {
        final bool abriu = await launchUrl(emailLaunchUri);
        if (!abriu && mounted) {
          _mostrarDialogoEmailIndisponivel();
        }
      } else {
        // Caso não haja app de email instalado
        if (mounted) {
          _mostrarDialogoEmailIndisponivel();
        }
      }
    } catch (e) {
      // Caso ocorra algum erro inesperado ao tentar abrir o app de email
      if (mounted) {
        _mostrarDialogoEmailIndisponivel();
      }
    }
  }

  // Diálogo com opção de copiar o e-mail, já que o app de email
  // pode não estar instalado/configurado no dispositivo do usuário
  void _mostrarDialogoEmailIndisponivel() {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text("Não foi possível abrir o e-mail"),
        content: const Text(
          "Não encontramos um aplicativo de e-mail configurado neste "
          "dispositivo. Você pode copiar o endereço abaixo e nos enviar "
          "sua mensagem manualmente:\n\nincluzoneapp+suporte@gmail.com",
        ),
        actions: [
          TextButton(
            onPressed: () async {
              await Clipboard.setData(
                const ClipboardData(text: 'incluzoneapp+suporte@gmail.com'),
              );
              if (!mounted) return;
              Navigator.of(dialogContext).pop();
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('E-mail copiado para a área de transferência'),
                ),
              );
            },
            child: const Text("Copiar e-mail"),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text("OK"),
          ),
        ],
      ),
    );
  }

  Future<void> _carregarConfiguracoesIniciais() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (!mounted) return;
      setState(() {
        _nivelZoom = prefs.getInt('nivel_zoom') ?? 0;
      });
    } catch (e) {
      // Caso as preferências não possam ser lidas, seguimos com o padrão
      // e avisamos o usuário de forma discreta (snackbar), sem bloquear a tela
      if (!mounted) return;
      setState(() {
        _nivelZoom = 0;
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Não foi possível carregar suas preferências de zoom. Usando o padrão.',
            ),
          ),
        );
      });
    }
  }

  Future<void> _atualizarZoom(bool aumentar) async {
    final int nivelAnterior = _nivelZoom;
    int novoNivel = nivelAnterior;

    if (aumentar && nivelAnterior < 2) {
      novoNivel++;
    } else if (!aumentar && nivelAnterior > 0) {
      novoNivel--;
    } else {
      return;
    }

    // Atualiza a UI imediatamente para dar resposta rápida ao usuário
    setState(() {
      _nivelZoom = novoNivel;
    });
    myAppKey.currentState?.atualizarEscala(_nivelZoom);

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt('nivel_zoom', _nivelZoom);
    } catch (e) {
      // Se não conseguir salvar, desfaz a alteração visual e avisa o usuário
      if (!mounted) return;
      setState(() {
        _nivelZoom = nivelAnterior;
      });
      myAppKey.currentState?.atualizarEscala(_nivelZoom);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Não foi possível salvar a preferência de zoom. Tente novamente.',
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Sobre o IncluZone"),
        scrolledUnderElevation: 0,
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,

        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 24),
            height: 1,
            color: const Color(0xFFD0D0D0),
          ),
        ),
      ),

      body: SizedBox.expand(
        // <-- ISSO FAZ O STACK OCUPAR A TELA TODA
        child: Stack(
          children: [
            SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 4),
                  const Text(
                    "Este aplicativo foi desenvolvido para oferecer uma experiência acessível e segura.",
                    style: TextStyle(fontSize: 16),
                  ),
                  const SizedBox(height: 10),
                  const Text(
                    "Aqui você pode encontrar informações sobre nossa missão e os termos de uso.",
                    style: TextStyle(fontSize: 16),
                  ),
                  const SizedBox(height: 20),
                  const Divider(),
                  const ListTile(
                    leading: Icon(Icons.code),
                    title: Text("Desenvolvido por"),
                    subtitle: Text("Equipe IncluZone"),
                  ),
                  const ListTile(
                    leading: Icon(Icons.info_outline),
                    title: Text("Versão"),
                    subtitle: Text("1.0.0"),
                  ),
                  const Divider(),
                  ListTile(
                    leading: const Icon(Icons.email_outlined),
                    title: const Text("Suporte via E-mail"),
                    subtitle: const Text(
                      "incluzoneapp+suporte@gmail.com",
                      style: TextStyle(
                        color: Color(0xFF02457A), // Define a cor azul
                        decoration:
                            TextDecoration.underline, // Adiciona o sublinhado
                      ),
                    ),
                    onTap: _enviarEmail,
                  ),
                ],
              ),
            ),
            Positioned(
              bottom: 25,
              left: 25,
              child: Image.asset('assets/images/titulo.webp', width: 150),
            ),
          ],
        ),
      ),
      // Botões de acessibilidade mantidos identicos
      floatingActionButton: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          FloatingActionButton(
            heroTag: "btn_diminuir_sobre",
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
            heroTag: "btn_aumentar_sobre",
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
