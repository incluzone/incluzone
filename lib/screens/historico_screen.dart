import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'dart:convert';
import 'dart:io';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../main.dart';

class HistoricoScreen extends StatefulWidget {
  const HistoricoScreen({super.key});

  @override
  State<HistoricoScreen> createState() => _HistoricoScreenState();
}

class _HistoricoScreenState extends State<HistoricoScreen> {
  final supabase = Supabase.instance.client;
  bool _carregando = true;
  List<dynamic> _historico = [];
  final String _cacheKey = 'historico_cache';
  int _nivelZoom = 0;

  @override
  void initState() {
    super.initState();
    _carregarConfiguracoesIniciais();
    _buscarHistorico();
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

  Future<void> _buscarHistorico({bool mostrarFeedbackSucesso = false}) async {
    final prefs = await SharedPreferences.getInstance();
    bool tinhaCache = false;

    // 1. Tentar carregar do cache primeiro para dar agilidade visual
    final cacheJson = prefs.getString(_cacheKey);
    if (cacheJson != null) {
      tinhaCache = true;
      if (_historico.isEmpty) {
        try {
          setState(() {
            _historico = jsonDecode(cacheJson);
            _carregando = false;
          });
        } catch (e) {
          // Cache corrompido: ignora e segue para buscar do servidor
          debugPrint("Erro ao ler cache do histórico: $e");
        }
      }
    }

    // 2. Se tiver internet, busca do banco e atualiza o cache
    if (await _temInternet()) {
      try {
        final user = supabase.auth.currentUser;
        if (user == null) {
          if (mounted) setState(() => _carregando = false);
          return;
        }

        final response = await supabase
            .from('contribuicoes')
            .select(
              'id_local, locais_com_vagas (*)',
            ) // Simplificado para o exemplo
            .eq('id_usuario', user.id);

        final novosDados = response
            .map((item) => item['locais_com_vagas'])
            .toList();

        setState(() {
          _historico = novosDados;
          _carregando = false;
        });

        // Salva no SharedPreferences para a próxima vez
        await prefs.setString(_cacheKey, jsonEncode(novosDados));

        if (mostrarFeedbackSucesso && mounted) {
          _mostrarSnackBar("Histórico atualizado.");
        }
      } catch (e) {
        debugPrint("Erro ao buscar histórico: $e");
        if (mounted) setState(() => _carregando = false);

        if (mounted) {
          if (tinhaCache) {
            // Já existe algo na tela; um aviso discreto basta
            _mostrarSnackBar(
              "Não foi possível atualizar o histórico. Exibindo dados salvos.",
              erro: true,
            );
          } else {
            // Tela ficaria vazia sem explicação nenhuma; nesse caso um diálogo é melhor
            _mostrarDialogo(
              "Erro",
              "Não foi possível carregar seu histórico agora. Tente novamente mais tarde.",
            );
          }
        }
      }
    } else {
      // Caso esteja totalmente offline
      if (mounted) setState(() => _carregando = false);

      if (mounted) {
        if (tinhaCache) {
          _mostrarSnackBar("Você está offline. Exibindo dados salvos.");
        } else {
          _mostrarDialogo(
            "Sem Conexão",
            "Você está offline e ainda não há dados salvos para exibir.",
          );
        }
      }
    }
  }

  // Sua lógica de verificação de internet
  Future<bool> _temInternet() async {
    final connectivityResult = await Connectivity().checkConnectivity();
    if (connectivityResult.contains(ConnectivityResult.none)) return false;
    try {
      final result = await InternetAddress.lookup('google.com');
      return result.isNotEmpty && result[0].rawAddress.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  // Função para mostrar o diálogo. Retorna o Future do showDialog para
  // permitir aguardar o fechamento quando necessário, e aceita botões
  // personalizados.
  Future<void> _mostrarDialogo(
    String titulo,
    String mensagem, {
    List<Widget>? botoesPersonalizados,
  }) {
    return showDialog(
      context: context,
      builder: (context) => AlertDialog(
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

  Future<void> _confirmarExclusao(Map<String, dynamic> local) async {
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Excluir registro"),
        content: Text(
          "Tem certeza que deseja excluir o registro de \"${local['logradouro']}, ${local['numero']}\"?\n\n"
          "Essa ação é irreversível e vai remover o local, as vagas e as contribuições associadas para TODOS os usuários do app.",
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

    if (!(await _temInternet())) {
      if (mounted) {
        _mostrarDialogo(
          "Sem Conexão",
          "Parece que você está offline. Verifique sua conexão com a internet para excluir este registro.",
        );
      }
      return;
    }

    try {
      final deletados = await supabase
          .from('locais')
          .delete()
          .eq('id', local['id'])
          .select();

      if (deletados.isEmpty) {
        // 0 linhas afetadas = RLS bloqueou ou o registro não existe mais
        throw Exception(
          "Nenhuma linha foi excluída. Verifique as permissões (RLS) ou se você é o criador do registro.",
        );
      }

      if (!mounted) return;

      setState(() {
        _historico.removeWhere((item) => item['id'] == local['id']);
      });

      // Atualiza o cache local para refletir a exclusão
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_cacheKey, jsonEncode(_historico));

      _mostrarSnackBar("Registro excluído com sucesso.");
    } catch (e) {
      debugPrint("Erro ao excluir registro: $e");
      if (mounted) {
        _mostrarDialogo(
          "Erro",
          "Não foi possível excluir o registro. Tente novamente.",
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Histórico"),
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
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: "Atualizar",
            onPressed: _carregando
                ? null
                : () => _buscarHistorico(mostrarFeedbackSucesso: true),
          ),
        ],
      ),
      body: _carregando
          ? const Center(child: CircularProgressIndicator())
          : _historico.isEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.only(
                  bottom: 100,
                ), // Ajuste este valor para subir ou descer
                child: Column(
                  mainAxisSize: MainAxisSize
                      .min, // Faz a coluna ocupar apenas o espaço dos filhos
                  children: [
                    Icon(
                      Icons.history_outlined,
                      size: 80,
                      color: Colors.grey[400],
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      "Nenhum registro encontrado.",
                      style: TextStyle(fontSize: 18, color: Colors.grey),
                    ),
                    const SizedBox(height: 12),
                    TextButton.icon(
                      onPressed: () =>
                          _buscarHistorico(mostrarFeedbackSucesso: true),
                      icon: const Icon(Icons.refresh),
                      label: const Text("Tentar novamente"),
                    ),
                  ],
                ),
              ),
            )
          : RefreshIndicator(
              onRefresh: () => _buscarHistorico(mostrarFeedbackSucesso: true),
              child: Column(
                // Adicionado Column para empilhar o texto e a lista
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Padding(
                    padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
                    child: Text(
                      "Histórico das suas vagas registradas:",
                      style: TextStyle(fontSize: 16),
                    ),
                  ),
                  Expanded(
                    // Ocupa o restante do espaço da tela
                    child: ListView.builder(
                      padding: const EdgeInsets.all(16),
                      itemCount: _historico.length,
                      itemBuilder: (context, index) {
                        final item = _historico[index];

                        // Sua View retorna 'vagas' como uma lista de objetos JSON
                        final List<dynamic> vagas = item['vagas'] is List
                            ? item['vagas']
                            : [];

                        return Card(
                          margin: const EdgeInsets.only(bottom: 16),
                          child: ExpansionTile(
                            collapsedShape: const Border(),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            title: Text(
                              "${item['logradouro']}, ${item['numero']}",
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            subtitle: Text(
                              "${item['bairro']} - ${item['cidade']}",
                            ),
                            children: [
                              Padding(
                                padding: const EdgeInsets.all(16.0),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      "Referência: ${item['referencia'] != null && item['referencia'].isNotEmpty ? item['referencia'] : 'Não registrada'}",
                                    ),
                                    const Divider(),
                                    ...vagas.map((v) {
                                      // Se a vaga for nula (LEFT JOIN sem dados), ignoramos
                                      if (v['tipo_vaga'] == null) {
                                        return const SizedBox();
                                      }

                                      return ListTile(
                                        contentPadding: EdgeInsets.zero,
                                        // Leading: Mostra o ícone do tipo de vaga
                                        leading: SizedBox(
                                          width: 32,
                                          height: 32,
                                          child: _getCustomImage(
                                            v['tipo_vaga'],
                                          ),
                                        ),
                                        title: Text(v['tipo_vaga']),
                                        // Trailing: Mostra a foto da vaga vinda do banco e a quantidade
                                        trailing: Wrap(
                                          crossAxisAlignment:
                                              WrapCrossAlignment.center,
                                          spacing: 12,
                                          children: [
                                            Text(
                                              "${v['quantidade']} vagas",
                                              style: const TextStyle(
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                            // Widget de imagem da vaga
                                            if (v['foto_url'] != null)
                                              ClipRRect(
                                                borderRadius:
                                                    BorderRadius.circular(4),
                                                child: Image.network(
                                                  v['foto_url'],
                                                  width: 45,
                                                  height: 45,
                                                  fit: BoxFit.cover,
                                                  // Tratamento de erro caso o link expire ou falhe
                                                  errorBuilder:
                                                      (
                                                        context,
                                                        error,
                                                        stackTrace,
                                                      ) => const Icon(
                                                        Icons.broken_image,
                                                        size: 20,
                                                      ),
                                                  loadingBuilder:
                                                      (
                                                        context,
                                                        child,
                                                        loadingProgress,
                                                      ) {
                                                        if (loadingProgress ==
                                                            null) {
                                                          return child;
                                                        }
                                                        return const SizedBox(
                                                          width: 20,
                                                          height: 20,
                                                          child:
                                                              CircularProgressIndicator(
                                                                strokeWidth: 2,
                                                              ),
                                                        );
                                                      },
                                                ),
                                              ),
                                          ],
                                        ),
                                      );
                                    }).toList(),
                                    const SizedBox(height: 8),
                                    Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      children: [
                                        TextButton.icon(
                                          onPressed: () async {
                                            if (!(await _temInternet())) {
                                              if (mounted) {
                                                _mostrarDialogo(
                                                  "Sem Conexão",
                                                  "Parece que você está offline. Verifique sua conexão com a internet para editar este registro.",
                                                );
                                              }
                                              return;
                                            }
                                            await Navigator.pushNamed(
                                              context,
                                              '/registro_vagas',
                                              arguments: item,
                                            );
                                            _buscarHistorico();
                                          },
                                          icon: const Icon(
                                            Icons.edit,
                                            size: 20,
                                          ),
                                          label: const Text("Editar registro"),
                                          style: TextButton.styleFrom(
                                            foregroundColor: Colors.blue[700],
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 16,
                                              vertical: 8,
                                            ),
                                          ),
                                        ),
                                        TextButton.icon(
                                          onPressed: () =>
                                              _confirmarExclusao(item),
                                          icon: const Icon(
                                            Icons.delete_outline,
                                            size: 20,
                                          ),
                                          label: const Text("Excluir registro"),
                                          style: TextButton.styleFrom(
                                            foregroundColor: Colors.red[700],
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 16,
                                              vertical: 8,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                  Container(
                    width: double.infinity, // Largura 100%
                    padding: const EdgeInsets.all(10),
                    alignment: Alignment
                        .centerLeft, // Alinha a logo à esquerda (como estava no Positioned)
                    child: Image.asset(
                      'assets/images/titulo.webp',
                      width: 135,
                      fit: BoxFit.contain,
                    ),
                  ),
                ],
              ),
            ),
      floatingActionButton: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          // Botão A-
          FloatingActionButton(
            heroTag: "btn_diminuir",
            // Desabilita visualmente se chegar no limite 0
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

          // Botão A+
          FloatingActionButton(
            heroTag: "btn_aumentar",
            // Desabilita visualmente se chegar no limite 2
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

  Widget _getCustomImage(String tipo) {
    String path;

    switch (tipo) {
      case 'PcD':
        path = 'assets/images/vaga_icons/pcd.webp';
        break;
      case 'Autista':
        path = 'assets/images/vaga_icons/autista.webp';
        break;
      case 'Gestante':
        path = 'assets/images/vaga_icons/gestante.webp';
        break;
      case 'Idoso':
        path = 'assets/images/vaga_icons/idoso.webp';
        break;
      default:
        // Caso não encontre, retorna um ícone padrão ou imagem genérica
        return const Icon(Icons.location_on, color: Colors.grey);
    }

    return Image.asset(
      path,
      fit: BoxFit.contain,
      // Caso a imagem falhe ao carregar (caminho errado, etc)
      errorBuilder: (context, error, stackTrace) =>
          const Icon(Icons.broken_image),
    );
  }
}
