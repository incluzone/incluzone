import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'pre_registro_vagas_screen.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:path_provider/path_provider.dart' as path_provider;
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import '../main.dart';
import '../services/gemini_service.dart';

class RegistroVagasScreen extends StatefulWidget {
  const RegistroVagasScreen({super.key});

  @override
  State<RegistroVagasScreen> createState() => _RegistroVagasScreenState();
}

class _VagaSelecionada {
  String tipo;
  int quantidade;
  int quantidadeExistente;
  File? foto;
  String? urlFotoExistente; // Adicionado para fotos vindas do banco
  dynamic idVaga; // Para saber se vamos atualizar ou inserir
  bool validando = false;
  String? erroValidacao;

  _VagaSelecionada({
    required this.tipo,
    this.quantidade = 1,
    this.quantidadeExistente = 1,
    this.urlFotoExistente,
    this.idVaga,
  });
}

class _RegistroVagasScreenState extends State<RegistroVagasScreen> {
  final supabase = Supabase.instance.client;
  late final TextEditingController referenciaController;

  late final TextEditingController logradouroController;
  late final TextEditingController numeroController;
  late final TextEditingController bairroController;
  late final TextEditingController cidadeController;
  late final TextEditingController estadoController;
  bool _editandoEndereco = false;

  RegistroPendente? dados;
  bool carregando = false;
  bool _salvandoEmAndamento = false;
  int _nivelZoom = 0;
  String? idLocalExistente;
  List<String> idsParaDeletar =
      []; // Armazena os IDs das vagas que serão removidas

  // Lista de tipos de vagas disponíveis (Enum do banco)
  final List<String> tiposDisponiveis = ["Idoso", "PcD", "Gestante", "Autista"];

  // Vagas que o usuário está configurando no formulário
  List<_VagaSelecionada> vagasParaRegistro = [];

  @override
  void initState() {
    super.initState();
    _carregarConfiguracoesIniciais();
    referenciaController = TextEditingController();

    logradouroController = TextEditingController();
    numeroController = TextEditingController();
    bairroController = TextEditingController();
    cidadeController = TextEditingController();
    estadoController = TextEditingController();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (dados == null) {
      final args = ModalRoute.of(context)!.settings.arguments;

      if (args is RegistroPendente) {
        // Fluxo normal: vindo da captura de endereço
        dados = args;
        _preencherControllersDeEndereco();
        _verificarPontoExistente();
      } else if (args is Map<String, dynamic>) {
        // Fluxo Histórico: vindo da lista de registros já salvos
        _preencherComDadosDoHistorico(args);
      } else {
        // Nenhum dado válido foi passado para a tela; avisa o usuário
        // assim que a UI estiver pronta, em vez de deixar a tela em branco.
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            _mostrarDialogo(
              "Erro",
              "Não foi possível carregar os dados deste registro. Volte e tente novamente.",
            );
          }
        });
      }
    }
  }

  void _preencherControllersDeEndereco() {
    if (dados == null) return;
    logradouroController.text = dados!.logradouro ?? '';
    numeroController.text = dados!.numero ?? '';
    bairroController.text = dados!.bairro ?? '';
    cidadeController.text = dados!.cidade ?? '';
    estadoController.text = dados!.estado ?? '';
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

  void _preencherComDadosDoHistorico(Map<String, dynamic> item) {
    setState(() {
      dados = RegistroPendente(
        id: item['id'].toString(),
        endereco:
            item['endereco'] ??
            "${item['logradouro'] ?? 'Rua desconhecida'} - ${item['bairro'] ?? ''}",
        logradouro: item['logradouro'] ?? '',
        numero: item['numero'] ?? '',
        bairro: item['bairro'] ?? '',
        cidade: item['cidade'] ?? '',
        estado: item['estado'] ?? '',
        lat: (item['latitude'] as num).toDouble(),
        lng: (item['longitude'] as num).toDouble(),
      );

      _preencherControllersDeEndereco();

      idLocalExistente = item['id'].toString();
      referenciaController.text = item['referencia'] ?? '';

      if (item['vagas'] != null) {
        vagasParaRegistro = (item['vagas'] as List).map((v) {
          // Captura a quantidade vinda do histórico/banco
          final qte = v['quantidade'] is int
              ? v['quantidade']
              : int.tryParse(v['quantidade'].toString()) ?? 1;

          return _VagaSelecionada(
            tipo: v['tipo_vaga']?.toString() ?? '',
            quantidade: qte,
            quantidadeExistente:
                qte, // Agora a comparação no salvar vai funcionar!
            idVaga: v['id_vaga'] ?? v['id'],
            urlFotoExistente: v['foto_url']?.toString(),
          );
        }).toList();
      }
    });
  }

  @override
  void dispose() {
    referenciaController.dispose();
    logradouroController.dispose();
    numeroController.dispose();
    bairroController.dispose();
    cidadeController.dispose();
    estadoController.dispose();
    super.dispose();
  }

  Widget _construirPreviewFoto(_VagaSelecionada vaga) {
    if (vaga.foto != null) {
      return Image.file(vaga.foto!, width: 50, height: 50, fit: BoxFit.cover);
    } else if (vaga.urlFotoExistente != null) {
      return Image.network(
        vaga.urlFotoExistente!,
        width: 50,
        height: 50,
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) =>
            const Icon(Icons.broken_image, size: 30),
      );
    }
    return const Icon(Icons.photo_library, color: Color.fromARGB(0, 0, 0, 0));
  }

  Future<void> _verificarPontoExistente() async {
    if (dados == null) return;
    setState(() => carregando = true);

    try {
      final double margemErro = 0.0003; // ~33 metros

      final localExistente = await supabase
          .from('locais_com_vagas')
          .select()
          .gte('latitude', dados!.lat - margemErro)
          .lte('latitude', dados!.lat + margemErro)
          .gte('longitude', dados!.lng - margemErro)
          .lte('longitude', dados!.lng + margemErro)
          .maybeSingle();

      if (localExistente != null) {
        idLocalExistente = localExistente['id'].toString();
        referenciaController.text = localExistente['referencia'] ?? '';

        logradouroController.text =
            localExistente['logradouro'] ?? dados!.logradouro ?? '';
        numeroController.text =
            (localExistente['numero'] ?? dados!.numero ?? '').toString();
        bairroController.text = localExistente['bairro'] ?? dados!.bairro ?? '';
        cidadeController.text = localExistente['cidade'] ?? dados!.cidade ?? '';
        estadoController.text = localExistente['estado'] ?? dados!.estado ?? '';

        if (localExistente['vagas'] != null) {
          setState(() {
            vagasParaRegistro = (localExistente['vagas'] as List).map((v) {
              final qte = v['quantidade'] is int
                  ? v['quantidade']
                  : int.tryParse(v['quantidade'].toString()) ?? 1;
              return _VagaSelecionada(
                tipo: v['tipo_vaga']?.toString() ?? '',
                quantidade: qte,
                quantidadeExistente: qte, // <--- Salvamos o valor original aqui
                idVaga: v['id_vaga'],
                urlFotoExistente: v['foto_url']?.toString(),
              );
            }).toList();
          });

          if (mounted) {
            _mostrarSnackBar(
              "Já existe um registro para este local. Os dados foram carregados para edição.",
            );
          }
        }
      }
    } catch (e) {
      debugPrint("Erro ao verificar ponto: $e");
      if (mounted) {
        _mostrarSnackBar(
          "Não foi possível verificar se já existe um registro para este local.",
          erro: true,
        );
      }
    } finally {
      if (mounted) setState(() => carregando = false);
    }
  }

  Future<void> _limparRegistroPendente(String id) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final String? dadosString = prefs.getString('meus_registros');

      if (dadosString != null) {
        // 1. Pega a lista atual do celular
        List<dynamic> dadosDecodificados = jsonDecode(dadosString);

        // 2. Remove o item que acabou de ser salvo no banco de dados
        dadosDecodificados.removeWhere((item) => item['id'] == id);

        // 3. Salva a lista atualizada (sem o item) de volta no celular
        await prefs.setString('meus_registros', jsonEncode(dadosDecodificados));
        debugPrint("Registro removido dos pendentes com sucesso.");
      }
    } catch (e) {
      // Não é crítico: o pior caso é o registro pendente reaparecer na lista.
      debugPrint("Erro ao limpar registro pendente: $e");
    }
  }

  Future<File?> _comprimirParaWebp(File arquivoOriginal) async {
    // Pega o diretório temporário do sistema (iOS/Android)
    final dir = await path_provider.getTemporaryDirectory();

    // Cria um caminho único para o arquivo de saída
    final outPath =
        "${dir.absolute.path}/temp_${DateTime.now().millisecondsSinceEpoch}.webp";

    var resultado = await FlutterImageCompress.compressAndGetFile(
      arquivoOriginal.absolute.path,
      outPath,
      format: CompressFormat.webp,
      quality: 10,
    );

    // No FlutterImageCompress >= 2.0.0, o retorno é do tipo XFile
    return resultado != null ? File(resultado.path) : null;
  }

  Future<void> _selecionarFoto(_VagaSelecionada vaga) async {
    final picker = ImagePicker();

    final XFile? pickedFile;
    try {
      pickedFile = await picker.pickImage(source: ImageSource.gallery);
    } catch (e) {
      if (mounted) {
        _mostrarDialogo(
          "Erro",
          "Não foi possível abrir a galeria de fotos. Tente novamente.",
        );
      }
      return;
    }

    if (pickedFile != null) {
      setState(() {
        vaga.validando = true; // Começa o carregamento específico deste card
        vaga.erroValidacao = null; // Limpa erros anteriores
      });

      if (!(await _temInternet())) {
        setState(() {
          vaga.validando = false;
          vaga.erroValidacao = "Sem conexão para validar a foto.";
        });
        _mostrarSnackBar(
          "Verifique sua internet para validar a foto com IA.",
          erro: true,
        );
        return;
      }

      try {
        File arquivoOriginal = File(pickedFile.path);
        File? arquivoWebp = await _comprimirParaWebp(arquivoOriginal);

        if (arquivoWebp != null) {
          // 1. Atualiza a foto na tela para o usuário ver
          setState(() => vaga.foto = arquivoWebp);

          // 2. Chama o Gemini para validar em tempo real
          final resultado = await GeminiService.validarVaga(
            arquivoWebp,
            vaga.tipo,
          );

          setState(() {
            if (resultado['status'] == true) {
              vaga.erroValidacao = null; // Tudo certo!
            } else {
              // Mapeia o erro
              vaga.erroValidacao = _traduzirErroGemini(resultado['message']);
              vaga.foto = null; // Opcional: remove a foto se for inválida
            }
          });
        } else {
          setState(
            () => vaga.erroValidacao = "Não foi possível processar a imagem.",
          );
        }
      } catch (e) {
        debugPrint("Erro ao processar/validar foto: $e");
        setState(() => vaga.erroValidacao = "Erro ao processar imagem");
      } finally {
        if (mounted) {
          setState(() => vaga.validando = false); // Para o carregamento do card
        }
      }
    }
  }

  // Função auxiliar para traduzir os códigos que definimos no prompt
  String _traduzirErroGemini(String message) {
    switch (message) {
      case "NOT_A_PARKING_SPOT":
        return "Não parece uma vaga.";
      case "WRONG_TYPE":
        return "Tipo de vaga incorreto.";
      case "NO_SIGNALIZATION":
        return "Sinalização não encontrada.";
      case "POOR_QUALITY":
        return "Imagem com qualidade baixa.";
      default:
        return "Imagem inválida.";
    }
  }

  Future<void> _salvarTudo() async {
    // LOCK: primeira linha executada, de forma 100% síncrona, antes de qualquer outra coisa.
    if (_salvandoEmAndamento) {
      debugPrint("Salvamento já em andamento, ignorando clique duplicado.");
      return;
    }
    _salvandoEmAndamento = true;

    try {
      if (dados == null) {
        _mostrarDialogo(
          "Erro",
          "Dados do local não encontrados. Volte e tente novamente.",
        );
        return;
      }

      if (vagasParaRegistro.isEmpty) {
        _mostrarSnackBar("Selecione ao menos um tipo de vaga");
        return;
      }

      if (logradouroController.text.trim().isEmpty ||
          bairroController.text.trim().isEmpty ||
          cidadeController.text.trim().isEmpty ||
          estadoController.text.trim().isEmpty) {
        _mostrarSnackBar("Endereço incompleto. Confira os campos.", erro: true);
        return;
      }

      // Validações ANTES de qualquer escrita no banco
      for (var v in vagasParaRegistro) {
        if (v.validando) {
          _mostrarSnackBar("Aguarde a validação das imagens...");
          return;
        }
        if (v.erroValidacao != null) {
          _mostrarSnackBar("Corrija a foto de ${v.tipo} antes de salvar.");
          return;
        }
        if (v.foto == null && v.urlFotoExistente == null) {
          _mostrarSnackBar("A foto para ${v.tipo} é obrigatória");
          return;
        }
      }

      if (!(await _temInternet())) {
        if (mounted) {
          _mostrarDialogo(
            "Sem Conexão",
            "Parece que você está offline. Verifique sua conexão com a internet e tente novamente.",
          );
        }
        return;
      }

      setState(() => carregando = true);

      final userId = supabase.auth.currentUser?.id;

      // 1. Salvar ou Atualizar o Local
      final localResponse = await supabase
          .from('locais')
          .upsert({
            if (idLocalExistente != null) 'id': idLocalExistente,
            'latitude': dados!.lat,
            'longitude': dados!.lng,
            'referencia': referenciaController.text,
            'logradouro': logradouroController.text.trim(), // alterado
            'numero': numeroController.text.trim(), // alterado
            'bairro': bairroController.text.trim(), // alterado
            'cidade': cidadeController.text.trim(), // alterado
            'estado': estadoController.text.trim(), // alterado
            if (idLocalExistente == null) 'id_usuario_criador': userId,
          })
          .select()
          .single();

      final localId = localResponse['id'];
      idLocalExistente = localId
          .toString(); // Trava re-inserção em chamadas futuras

      // 2. Deletar vagas removidas
      if (idsParaDeletar.isNotEmpty) {
        await supabase.from('vagas').delete().inFilter('id', idsParaDeletar);
      }

      // 3. Salvar cada vaga individualmente
      for (var vaga in vagasParaRegistro) {
        String? urlParaSalvar = vaga.urlFotoExistente;

        bool fotoMudou = vaga.foto != null;
        bool quantidadeMudou =
            vaga.idVaga != null &&
            (vaga.quantidade != vaga.quantidadeExistente);
        bool ehNovaVaga = vaga.idVaga == null;

        if (fotoMudou) {
          if (vaga.urlFotoExistente != null) {
            try {
              final String nomeArquivoAntigo = vaga.urlFotoExistente!
                  .split('/')
                  .last;
              await supabase.storage.from('vagas_images').remove([
                nomeArquivoAntigo,
              ]);
            } catch (e) {
              debugPrint("Erro ao limpar arquivo antigo: $e");
            }
          }

          final fileName = 'vaga_${DateTime.now().millisecondsSinceEpoch}.webp';
          await supabase.storage
              .from('vagas_images')
              .upload(fileName, vaga.foto!);
          urlParaSalvar = supabase.storage
              .from('vagas_images')
              .getPublicUrl(fileName);
        }

        final dadosVaga = {
          if (vaga.idVaga != null) 'id': vaga.idVaga,
          'id_local': localId,
          'tipo_vaga': vaga.tipo,
          'quantidade': vaga.quantidade,
          'foto_url': urlParaSalvar,
        };

        if (fotoMudou || quantidadeMudou || ehNovaVaga) {
          dadosVaga['id_usuario_ultima_alteracao'] = userId;
          dadosVaga['data_ultima_alteracao'] = DateTime.now()
              .toUtc()
              .toIso8601String();
        }

        await supabase.from('vagas').upsert(dadosVaga);
      }

      // 4. Registrar contribuição
      await supabase.from('contribuicoes').upsert({
        'id_usuario': userId,
        'id_local': localId,
        'data_contribuicao': DateTime.now().toUtc().toIso8601String(),
      }, onConflict: 'id_usuario,id_local');

      if (dados != null) await _limparRegistroPendente(dados!.id);

      if (mounted) {
        Navigator.pushNamedAndRemoveUntil(context, '/', (route) => false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Dados atualizados com sucesso!")),
        );
      }
    } catch (e) {
      debugPrint("Erro ao salvar registro de vagas: $e");
      if (mounted) {
        _mostrarDialogo(
          "Erro",
          "Não foi possível salvar os dados agora. Tente novamente em instantes.",
        );
      }
    } finally {
      _salvandoEmAndamento =
          false; // libera o lock em TODOS os caminhos de saída
      if (mounted) setState(() => carregando = false);
    }
  }

  Widget _criarLinhaDeChips(List<String> tipos) {
    return Row(
      children: tipos.map((tipo) {
        bool selecionado = vagasParaRegistro.any((v) => v.tipo == tipo);
        return Expanded(
          // Expanded faz com que ocupem o mesmo espaço na linha
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: FilterChip(
              label: Center(child: Text(tipo)),
              selected: selecionado,
              onSelected: (bool value) {
                setState(() {
                  if (value) {
                    vagasParaRegistro.add(_VagaSelecionada(tipo: tipo));
                  } else {
                    final vagaRemovida = vagasParaRegistro.firstWhere(
                      (v) => v.tipo == tipo,
                    );
                    if (vagaRemovida.idVaga != null) {
                      idsParaDeletar.add(vagaRemovida.idVaga);
                    }
                    vagasParaRegistro.removeWhere((v) => v.tipo == tipo);
                  }
                });
              },
            ),
          ),
        );
      }).toList(),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      resizeToAvoidBottomInset: false,
      appBar: AppBar(title: const Text("Registrar Vagas")),
      body: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        "Endereço Identificado:",
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      IconButton(
                        icon: Icon(
                          _editandoEndereco ? Icons.check_circle : Icons.edit,
                          color: _editandoEndereco ? Colors.green : null,
                        ),
                        tooltip: _editandoEndereco
                            ? "Confirmar alterações"
                            : "Editar endereço",
                        onPressed: () {
                          if (_editandoEndereco) {
                            // Saindo do modo edição: valida campos obrigatórios
                            if (logradouroController.text.trim().isEmpty ||
                                bairroController.text.trim().isEmpty ||
                                cidadeController.text.trim().isEmpty ||
                                estadoController.text.trim().isEmpty) {
                              _mostrarSnackBar(
                                "Preencha logradouro, bairro, cidade e estado.",
                                erro: true,
                              );
                              return;
                            }
                          }
                          setState(
                            () => _editandoEndereco = !_editandoEndereco,
                          );
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),

                  if (!_editandoEndereco)
                    Text(
                      "${logradouroController.text}, ${numeroController.text}\n"
                      "${bairroController.text}\n"
                      "${cidadeController.text} - ${estadoController.text}",
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                      ),
                    )
                  else
                    Column(
                      children: [
                        Row(
                          children: [
                            Expanded(
                              flex: 3,
                              child: TextField(
                                controller: logradouroController,
                                decoration: const InputDecoration(
                                  labelText: "Logradouro",
                                  border: OutlineInputBorder(),
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              flex: 1,
                              child: TextField(
                                controller: numeroController,
                                decoration: const InputDecoration(
                                  labelText: "Número",
                                  border: OutlineInputBorder(),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        TextField(
                          controller: bairroController,
                          decoration: const InputDecoration(
                            labelText: "Bairro",
                            border: OutlineInputBorder(),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Expanded(
                              flex: 3,
                              child: TextField(
                                controller: cidadeController,
                                decoration: const InputDecoration(
                                  labelText: "Cidade",
                                  border: OutlineInputBorder(),
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              flex: 1,
                              child: TextField(
                                controller: estadoController,
                                decoration: const InputDecoration(
                                  labelText: "UF",
                                  border: OutlineInputBorder(),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  const SizedBox(height: 20),

                  TextField(
                    controller: referenciaController,
                    decoration: const InputDecoration(
                      labelText: "Ponto de Referência",
                      border: OutlineInputBorder(),
                    ),
                  ),

                  const SizedBox(height: 24),
                  const Text(
                    "Tipos de Vagas no Local:",
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 12),

                  // Chips para selecionar tipos
                  Column(
                    children: [
                      _criarLinhaDeChips(["Idoso", "PcD"]),
                      const SizedBox(height: 8),
                      _criarLinhaDeChips(["Gestante", "Autista"]),
                    ],
                  ),

                  const SizedBox(height: 20),

                  // Lista dinâmica de detalhes das vagas
                  ...vagasParaRegistro.reversed.map(
                    (vaga) => Card(
                      margin: const EdgeInsets.only(bottom: 16),
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  vaga.tipo,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 16,
                                  ),
                                ),
                                Row(
                                  children: [
                                    IconButton(
                                      onPressed: () => setState(
                                        () => vaga.quantidade > 1
                                            ? vaga.quantidade--
                                            : null,
                                      ),
                                      icon: const Icon(
                                        Icons.remove_circle_outline,
                                      ),
                                    ),
                                    Text(
                                      vaga.quantidade.toString(),
                                      style: const TextStyle(fontSize: 18),
                                    ),
                                    IconButton(
                                      onPressed: () =>
                                          setState(() => vaga.quantidade++),
                                      icon: const Icon(
                                        Icons.add_circle_outline,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                            const Divider(),
                            ListTile(
                              leading: vaga.validando
                                  ? const CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ) // Mostra progresso no lugar do ícone
                                  : Icon(
                                      vaga.foto == null
                                          ? Icons.photo_library
                                          : (vaga.erroValidacao != null
                                                ? Icons.error
                                                : Icons.check_circle),
                                      color: vaga.foto == null
                                          ? Colors.grey
                                          : (vaga.erroValidacao != null
                                                ? Colors.red
                                                : Colors.green),
                                    ),
                              title: Text(
                                vaga.validando
                                    ? "Validando com IA..."
                                    : (vaga.erroValidacao ??
                                          (vaga.foto == null
                                              ? "Selecionar foto"
                                              : "Foto validada")),
                                style: TextStyle(
                                  color: vaga.erroValidacao != null
                                      ? Colors.red
                                      : Colors.black,
                                ),
                              ),
                              onTap: vaga.validando
                                  ? null
                                  : () => _selecionarFoto(vaga),
                              trailing: _construirPreviewFoto(vaga),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(height: 20),

                  Center(
                    child: AbsorbPointer(
                      absorbing:
                          carregando ||
                          vagasParaRegistro.any((v) => v.validando),
                      child: ElevatedButton(
                        onPressed:
                            (carregando ||
                                vagasParaRegistro.any((v) => v.validando))
                            ? null
                            : _salvarTudo,
                        child: carregando
                            ? const CircularProgressIndicator()
                            : const Text("Confirmar e Salvar"),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          Container(
            width: double.infinity, // Largura 100%
            padding: const EdgeInsets.all(25),
            alignment: Alignment
                .centerLeft, // Alinha a logo à esquerda (como estava no Positioned)
            child: Image.asset(
              'assets/images/titulo.webp',
              width: 150,
              fit: BoxFit.contain,
            ),
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
