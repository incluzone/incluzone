import 'package:flutter/material.dart';
import '../services/supabase_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_map_marker_cluster/flutter_map_marker_cluster.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'dart:io';
import 'dart:convert';
import 'package:path_provider/path_provider.dart';
import 'package:flutter_map_cache/flutter_map_cache.dart';
import 'package:dio_cache_interceptor/dio_cache_interceptor.dart';
import 'package:dio_cache_interceptor_db_store/dio_cache_interceptor_db_store.dart';
import 'dart:async';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_map_animations/flutter_map_animations.dart';
import 'dart:ui';
import 'package:http/http.dart' as http;
import '../main.dart';

class VisualizadorImagem extends StatelessWidget {
  final String url;

  const VisualizadorImagem({super.key, required this.url});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black.withOpacity(0.85),
      body: Stack(
        children: [
          // Efeito de desfoque ao fundo
          Positioned.fill(
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 5, sigmaY: 5),
              child: Container(color: Colors.transparent),
            ),
          ),

          // Área de Zoom expandida para a tela toda
          SizedBox.expand(
            child: InteractiveViewer(
              clipBehavior: Clip.none,
              minScale: 1.0,
              maxScale: 5.0,
              child: Hero(
                tag: url,
                child: Image.network(
                  url,
                  fit: BoxFit.contain,
                  // Este construtor é chamado quando ocorre um erro de carregamento
                  errorBuilder: (context, error, stackTrace) => const Center(
                    child: Icon(
                      Icons.broken_image,
                      color: Colors.grey,
                      size: 40,
                    ),
                  ),
                  // Opcional: Mostra algo enquanto a imagem está baixando
                  loadingBuilder: (context, child, loadingProgress) {
                    if (loadingProgress == null) return child;
                    return const Center(child: CircularProgressIndicator());
                  },
                ),
              ),
            ),
          ),

          // Botão Fechar fixo por cima de tudo
          Positioned(
            top: MediaQuery.of(context).padding.top + 10,
            right: 20,
            child: SafeArea(
              // Garante que o X não fique debaixo do notch/bateria
              child: GestureDetector(
                onTap: () => Navigator.pop(context),
                child: CircleAvatar(
                  backgroundColor: Colors.black.withOpacity(0.4),
                  radius: 20,
                  child: const Icon(Icons.close, color: Colors.white, size: 25),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen>
    with WidgetsBindingObserver, TickerProviderStateMixin {
  final service = SupabaseService();
  // Adicione esta variável para controlar a inscrição
  RealtimeChannel? _realtimeSubscription;

  StreamSubscription<List<ConnectivityResult>>? _connectivitySubscription;
  bool _estaOffline = false;

  String? nomeUsuario;
  bool isGoogle = false;

  late final AnimatedMapController _animatedMapController;
  bool _aguardandoPermissao = false;
  LatLng? _posicaoAtual;
  double _zoomAtual = 13.0; // Valor padrão inicial
  final bool _carregandoLocalizacaoReal = true;
  StreamSubscription<Position>? _positionStream;
  late CacheStore _cacheStore;
  bool _cacheInitialized = false;
  bool _mapReady = false;
  bool _gpsAtivoEPermitido = false; // Nova variável
  final LatLng _fallback = LatLng(-23.5505, -46.6333);
  List<Marker> _markers = [];
  Set<String> _filtrosAtivos = {'Idoso', 'Autista', 'Gestante', 'PcD'};
  List<Map<String, dynamic>> _todosOsLocais = [];
  bool _menuAberto = false;
  int _nivelZoom = 0;
  // Controla o texto do campo de digitação
// Guardam o controle e o texto da pesquisa
final TextEditingController _pesquisaController = TextEditingController();
  // Guarda o texto que a pessoa digitou
String _textoPesquisa = '';

  // ---------------------------------------------------------------------
  // PESQUISA DE LUGARES (LocationIQ)
  // ---------------------------------------------------------------------
  // Crie uma conta gratuita em https://locationiq.com/register e cole sua
  // chave de API abaixo. O plano gratuito já é suficiente para a maioria
  // dos apps pequenos/médios.
  static const String _locationIqApiKey = 'pk.56580cf5d359c74bbe21d5140a2bac7f';

  bool _pesquisaAberta = false;
  final TextEditingController _controladorPesquisa = TextEditingController();
  final FocusNode _focusPesquisa = FocusNode();
  List<Map<String, dynamic>> _resultadosPesquisa = [];
  bool _carregandoPesquisa = false;
  String? _erroPesquisa;
  Timer? _debouncePesquisa;
  String? _municipioUsuario;

  @override
  void initState() {
    super.initState();
    _carregarConfiguracoesIniciais();
    WidgetsBinding.instance.addObserver(this);
    _initCache(); // Inicializa o banco de dados do mapa
    carregar();
    _configurarEscutaRealtime();
    _ouvirConexao();
    _animatedMapController = AnimatedMapController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
      curve: Curves.easeInOut,
    );
    Geolocator.getServiceStatusStream().listen((ServiceStatus status) {
      setState(() {
        _gpsAtivoEPermitido = (status == ServiceStatus.enabled);
      });

      if (_gpsAtivoEPermitido) {
        _atualizarLocalizacao(); // Tenta pegar a posição se ele ligou agora
      }
    });
  }

@override
void dispose() {
  WidgetsBinding.instance.removeObserver(this);
  _positionStream?.cancel();
  _cacheStore.close();
  
  _pesquisaController.dispose(); // Limpa o controller da barra de pesquisa

  if (_realtimeSubscription != null) {
    Supabase.instance.client.removeChannel(_realtimeSubscription!);
  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _positionStream?.cancel(); // Para de seguir o usuário ao sair da tela
    _cacheStore.close();
    if (_realtimeSubscription != null) {
      Supabase.instance.client.removeChannel(_realtimeSubscription!);
    }
    _debouncePesquisa?.cancel();
    _controladorPesquisa.dispose();
    _focusPesquisa.dispose();
    super.dispose();
  }
  super.dispose();
}

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      if (_aguardandoPermissao) {
        _atualizarLocalizacao(); // Centraliza
        _aguardandoPermissao = false; // Reseta
      }
    }
  }

  Future<void> _descobrirMunicipioUsuario(LatLng posicao) async {
    try {
      final uri = Uri.parse(
        'https://us1.locationiq.com/v1/reverse'
        '?key=$_locationIqApiKey'
        '&lat=${posicao.latitude}'
        '&lon=${posicao.longitude}'
        '&format=json'
        '&accept-language=pt-BR',
      );
      final resposta = await http.get(uri).timeout(const Duration(seconds: 6));
      if (resposta.statusCode == 200) {
        final dados = jsonDecode(resposta.body);
        final endereco = dados['address'] ?? {};
        final municipio =
            endereco['city'] ??
            endereco['town'] ??
            endereco['municipality'] ??
            endereco['county'];
        if (mounted && municipio != null) {
          setState(() => _municipioUsuario = municipio.toString());
        }
      }
    } catch (e) {
      debugPrint("Erro ao descobrir município: $e");
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

    // ESTA É A PARTE QUE FALTA:
    // Acessa o estado do MyApp através da chave global e chama o método de atualização
    myAppKey.currentState?.atualizarEscala(_nivelZoom);

    try {
      // Salva no disco
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt('nivel_zoom', _nivelZoom);
    } catch (e) {
      // Se não conseguir salvar, desfaz a alteração visual e avisa o usuário
      debugPrint("Erro ao salvar preferência de zoom: $e");
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

  Future<void> _carregarConfiguracoesIniciais() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (!mounted) return;
      setState(() {
        _nivelZoom = prefs.getInt('nivel_zoom') ?? 0;
      });
    } catch (e) {
      // Se não der pra ler as preferências, seguimos com o padrão e
      // avisamos discretamente (sem bloquear a tela com um diálogo)
      debugPrint("Erro ao carregar preferências de zoom: $e");
      if (!mounted) return;
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

  Future<bool> _temInternet() async {
    final connectivityResult = await Connectivity().checkConnectivity();
    if (connectivityResult.contains(ConnectivityResult.none)) {
      return false;
    }
    // Opcional: Checagem real de DNS
    try {
      final result = await InternetAddress.lookup(
        'google.com',
      ).timeout(const Duration(seconds: 3));
      return result.isNotEmpty && result[0].rawAddress.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  void _ouvirConexao() {
    _connectivitySubscription = Connectivity().onConnectivityChanged.listen((
      results,
    ) async {
      bool temConexaoLayer = !results.contains(ConnectivityResult.none);
      bool temInternetReal = false;

      if (temConexaoLayer) {
        try {
          final result = await InternetAddress.lookup(
            'google.com',
          ).timeout(const Duration(seconds: 3));
          temInternetReal =
              result.isNotEmpty && result[0].rawAddress.isNotEmpty;
        } catch (_) {
          temInternetReal = false;
        }
      }

      if (_estaOffline != !temInternetReal) {
        setState(() {
          _estaOffline = !temInternetReal;
        });

        if (_estaOffline) {
          if (_realtimeSubscription != null) {
            Supabase.instance.client.removeChannel(_realtimeSubscription!);
            _realtimeSubscription = null;
            debugPrint("Realtime pausado: Sem internet.");
          }

          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Row(
                children: [
                  Icon(Icons.cloud_off, color: Colors.white),
                  SizedBox(width: 10),
                  Text("Você está offline. Exibindo dados salvos."),
                ],
              ),
              backgroundColor: Color.fromARGB(255, 65, 65, 65),
              duration: Duration(days: 1), // Fica visível até voltar a rede
            ),
          );
        } else {
          ScaffoldMessenger.of(context).hideCurrentSnackBar();
          _configurarEscutaRealtime();
          _carregarMarcadores();
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text("Conexão restabelecida!"),
              backgroundColor: Colors.green,
              duration: Duration(seconds: 2),
            ),
          );

          debugPrint("Realtime reativado: Internet voltou.");
        }
      }
    });
  }

  // Função para inicializar o local de salvamento do mapa
  Future<void> _initCache() async {
    try {
      final dir = await getTemporaryDirectory();
      _cacheStore = DbCacheStore(
        databasePath: dir.path,
        databaseName: "map_cache_pcd",
      );
      if (!mounted) return;
      setState(() {
        _cacheInitialized = true;
      });
    } catch (e) {
      // O cache de tiles é apenas uma otimização para uso offline do mapa;
      // se falhar, o app segue funcionando normalmente enquanto houver internet
      debugPrint("Erro ao inicializar cache do mapa: $e");
    }
  }

  // Salva a última localização conhecida
  Future<void> _salvarUltimaLocalizacao(LatLng posicao) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setDouble('ultima_lat', posicao.latitude);
      await prefs.setDouble('ultima_lng', posicao.longitude);
    } catch (e) {
      debugPrint("Erro ao salvar última localização: $e");
    }
  }

  // Recupera a localização salva ou retorna o fallback se não houver nada
  Future<LatLng> _recuperarUltimaLocalizacao() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final lat = prefs.getDouble('ultima_lat');
      final lng = prefs.getDouble('ultima_lng');

      if (lat != null && lng != null) {
        return LatLng(lat, lng);
      }
    } catch (e) {
      debugPrint("Erro ao recuperar última localização: $e");
    }
    return _fallback; // Retorna São Paulo se não houver nada salvo ou der erro
  }

  void carregar() async {
    await _recuperarFiltrosDoCache();

    // 1. Verificação de Internet
    if (!(await _temInternet())) {
      if (mounted) {
        // Verifica se esta tela é a que o usuário está vendo no momento
        _mostrarDialogo(
          "Sem Conexão",
          "Parece que você está offline. Exibindo dados salvos localmente.",
        );
      }
    }

    // 2. Carregar dados do usuário (Supabase)
    // Isolado em try/catch para que uma falha aqui não impeça o mapa de carregar
    try {
      final nome = await service.getNomeUsuario();
      final user = Supabase.instance.client.auth.currentUser;

      if (mounted) {
        setState(() {
          nomeUsuario = nome;
          isGoogle =
              user?.identities?.any((i) => i.provider == 'google') ?? false;
        });
      }
    } catch (e) {
      debugPrint("Erro ao carregar dados do usuário: $e");
    }

    // --- LÓGICA DE LOCALIZAÇÃO OTIMIZADA ---

    // 3. Tenta recuperar do cache local (SharedPreferences)
    final localizacaoSalva = await _recuperarUltimaLocalizacao();

    // Definimos a posição inicial (ou cache ou fallback de SP),
    // mas ainda não mostramos o mapa (_mapReady continua false)
    _posicaoAtual = localizacaoSalva;

    // 4. PASSO DE ATUALIZAÇÃO: Tentar obter a posição real via GPS
    try {
      await _verificarPermissoes();

      // Tenta pegar a posição atual com um timeout de 4 segundos
      Position atual = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: const Duration(seconds: 4),
      );

      final novaPosicao = LatLng(atual.latitude, atual.longitude);
      _posicaoAtual = novaPosicao;

      // Salva essa nova posição no cache para a próxima vez
      await _salvarUltimaLocalizacao(novaPosicao);

      // Inicia a escuta para seguir o usuário se ele se mover
      _iniciarEscutaLocalizacao();

      setState(() {
        _gpsAtivoEPermitido = true;
      });
    } catch (e) {
      // Se o GPS falhar (permissão negada ou timeout), mantemos o _posicaoAtual
      // como o cache (ou SP se o cache retornou SP).
      debugPrint("GPS não disponível, usando fallback/cache: $e");

      setState(() {
        _gpsAtivoEPermitido = false;
      });

      // Se o usuário negou a permissão permanentemente, mostramos o diálogo
      _tratarErroLocalizacao(e.toString());
    } finally {
      // 5. LIBERAÇÃO FINAL: Agora que temos o melhor local possível,
      // renderizamos o mapa de uma vez.

      // Descobre o município do usuário para filtrar as buscas depois
      if (_posicaoAtual != null) {
        await _descobrirMunicipioUsuario(_posicaoAtual!);
      }

      if (mounted) {
        setState(() {
          // Se a posição for igual ao fallback (SP), zoom 13. Caso contrário, zoom 17.
          if (_posicaoAtual != null &&
              _posicaoAtual!.latitude == _fallback.latitude &&
              _posicaoAtual!.longitude == _fallback.longitude) {
            _zoomAtual = 13.0;
          } else {
            _zoomAtual = 17.0;
          }
          _mapReady = true;
        });
      }
    }

    // 6. Carregar os marcadores (Vagas)
    try {
      await _carregarMarcadores();
    } catch (e) {
      debugPrint("Erro ao carregar marcadores: $e");
    }
  }

  Future<void> _atualizarLocalizacao({bool mostrarFeedback = false}) async {
    try {
      LocationPermission permission = await Geolocator.checkPermission();
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();

      if (!serviceEnabled) {
        if (mostrarFeedback && mounted) _mostrarDialogoGpsDesativado();
        return; // 🚫 evita spam
      }

      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        if (mostrarFeedback && mounted) _mostrarDialogoExplicacao();
        return; // 🚫 evita spam
      }

      Position atual = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );

      if (!mounted) return;

      final novaPosicao = LatLng(atual.latitude, atual.longitude);

      setState(() {
        _posicaoAtual = novaPosicao;
        _gpsAtivoEPermitido = true;
      });

      _animatedMapController.animateTo(dest: novaPosicao, zoom: 17);
    } catch (e) {
      debugPrint("Erro ao atualizar localização: $e");
      // Só incomoda o usuário com um retorno se ele pediu explicitamente
      // (ex: tocou no botão de centralizar); atualizações automáticas ficam silenciosas
      if (mostrarFeedback && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Não foi possível obter sua localização agora. Tente novamente.',
            ),
          ),
        );
      }
    }
  }

  void _iniciarEscutaLocalizacao() {
    // Define as configurações do Stream
    const LocationSettings locationSettings = LocationSettings(
      accuracy: LocationAccuracy.high,
      distanceFilter: 15, // <--- Aqui definimos a atualização a cada 15m
    );

    _positionStream =
        Geolocator.getPositionStream(locationSettings: locationSettings).listen(
          (Position position) {
            final novaPosicao = LatLng(position.latitude, position.longitude);
            _salvarUltimaLocalizacao(novaPosicao);
            setState(() {
              _posicaoAtual = novaPosicao;
              _gpsAtivoEPermitido = true; // Se recebeu posição, está ativo
            });
          },
          onError: (error) {
            // Se o usuário desativar o GPS ou permissão, entra aqui
            debugPrint("Erro no stream de localização: $error");
            setState(() {
              _gpsAtivoEPermitido = false;
            });
          },
        );
  }

  void _centralizarNoUsuario() {
    if (_posicaoAtual != null && _gpsAtivoEPermitido) {
      _animatedMapController.animateTo(dest: _posicaoAtual!, zoom: 17);
    } else {
      // Caso o GPS esteja desligado/sem permissão, tenta reativar e
      // avisa o usuário (diálogo ou snackbar) se não conseguir centralizar
      _atualizarLocalizacao(mostrarFeedback: true);
    }
  }

  Future<void> _verificarPermissoes() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      setState(() => _gpsAtivoEPermitido = false);
      throw Exception('GPS_DESATIVADO');
    }

    LocationPermission permission = await Geolocator.checkPermission();

    if (permission == LocationPermission.denied) {
      setState(() => _gpsAtivoEPermitido = false);
      permission = await Geolocator.requestPermission();
    }

    if (permission == LocationPermission.denied) {
      setState(() => _gpsAtivoEPermitido = false);
      throw Exception('PERMISSAO_NEGADA');
    }

    if (permission == LocationPermission.deniedForever) {
      setState(() => _gpsAtivoEPermitido = false);
      throw Exception('PERMISSAO_PERMANENTE');
    }

    setState(() => _gpsAtivoEPermitido = true);
  }

  // Função para tratar os erros e mostrar os diálogos
  void _tratarErroLocalizacao(String erro) {
    if (erro.contains('GPS_DESATIVADO')) {
      _mostrarDialogoGpsDesativado();
    } else if (erro.contains('PERMISSAO_PERMANENTE') ||
        erro.contains('PERMISSAO_NEGADA')) {
      // Só mostramos o diálogo de "Abrir Configurações" se estiver bloqueado no sistema
      _mostrarDialogoExplicacao();
    } else {
      // Caso seja apenas um erro genérico ou o usuário negou uma vez,
      // talvez apenas um log ou uma mensagem discreta (SnackBar) seja melhor.
      debugPrint("Erro de localização: $erro");
    }
  }

  void _mostrarDialogoExplicacao() {
    if (ModalRoute.of(context)?.isCurrent ?? false) {
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Localização necessária'),
          content: const Text(
            'Precisamos da sua localização para mostrar vagas especiais perto de você.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancelar'),
            ),
            TextButton(
              onPressed: () async {
                _aguardandoPermissao = true;
                Navigator.pop(context);
                await Geolocator.openAppSettings();
              },
              child: const Text('Abrir configurações'),
            ),
          ],
        ),
      );
    }
  }

  void _mostrarDialogoGpsDesativado() {
    if (ModalRoute.of(context)?.isCurrent ?? false) {
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: const Row(children: [Text('GPS Desativado')]),
          content: const Text(
            'O serviço de localização do seu aparelho parece estar desligado. Por favor, ative-o para continuar.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancelar'),
            ),
            TextButton(
              onPressed: () async {
                Navigator.pop(context);
                // Abre a tela de configurações de localização do Android/iOS
                await Geolocator.openLocationSettings();
              },
              child: const Text('Abrir Configurações'),
            ),
          ],
        ),
      );
    }
  }

  void _mostrarDialogo(String titulo, String mensagem) {
    if (ModalRoute.of(context)?.isCurrent ?? false) {
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
  }

  void _mostrarDialogoEditarVaga(String titulo, String mensagem) {
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

  final GoogleSignIn _googleSignIn = GoogleSignIn();

  Future<void> _excluirConta() async {
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

    try {
      final user = Supabase.instance.client.auth.currentUser;

      // 🔥 1. Revoga acesso do Google no app
      try {
        await _googleSignIn.disconnect(); // remove permissão do Google
      } catch (_) {
        // pode falhar se não estiver logado via Google, então ignoramos
      }

      // 🔥 2. Deleta usuário no backend (Supabase Edge Function)
      await Supabase.instance.client.functions.invoke(
        'delete-user',
        body: {'userId': user?.id},
      );

      // 🔥 3. Faz logout do Supabase
      await Supabase.instance.client.auth.signOut();

      if (!mounted) return;

      Navigator.of(context).pushNamedAndRemoveUntil('/', (route) => false);
    } catch (e) {
      // Não expomos o erro técnico bruto ao usuário, apenas registramos
      debugPrint("Erro ao excluir conta: $e");
      if (!mounted) return;
      _mostrarDialogo(
        "Erro",
        "Não foi possível excluir sua conta agora. Verifique sua conexão e tente novamente, ou entre em contato com o suporte.",
      );
    }
  }

  Widget _buildUserLocationMarker() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.blueAccent,
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 3),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.2),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
    );
  }

  Future<void> _configurarEscutaRealtime() async {
    if (!(await _temInternet())) {
      debugPrint("Sem internet: pulando configuração de Realtime.");
      return;
    }
    if (_realtimeSubscription != null) {
      await Supabase.instance.client.removeChannel(_realtimeSubscription!);
    }
    _realtimeSubscription = Supabase.instance.client
        .channel('alteracoes_mapa')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'vagas',
          callback: (payload) async {
            debugPrint('Mudança detectada via Realtime: ${payload.eventType}');
            await _carregarMarcadores();
          },
        );
    _realtimeSubscription!.subscribe((status, [error]) {
      if (status == RealtimeSubscribeStatus.subscribed) {
        debugPrint('Conectado ao Realtime com sucesso!');
      }
      if (status == RealtimeSubscribeStatus.channelError) {
        debugPrint('Erro no canal Realtime: $error');
        // Opcional: tentar novamente após alguns segundos
      }
    });
  }

  Future<File> _getMarkersCacheFile() async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/markers_cache.json');
  }

  Future<List<Map<String, dynamic>>> _buscarMarcadores() async {
    try {
      // Tenta buscar do Supabase
      final response = await Supabase.instance.client
          .from('locais_com_vagas')
          .select()
          .timeout(const Duration(seconds: 5));

      final lista = List<Map<String, dynamic>>.from(response);

      // Salva o resultado no cache local para uso offline futuro
      final file = await _getMarkersCacheFile();
      await file.writeAsString(jsonEncode(lista));

      return lista;
    } catch (e) {
      debugPrint("Erro ao buscar do Supabase, tentando cache local: $e");

      // Se falhar (offline ou erro no servidor), tenta ler do arquivo local
      try {
        final file = await _getMarkersCacheFile();
        if (await file.exists()) {
          final jsonString = await file.readAsString();
          final List<dynamic> dadosLocal = jsonDecode(jsonString);

          // Se já existe o aviso persistente de "offline" (via _ouvirConexao),
          // não precisamos duplicar a mensagem aqui
          if (!_estaOffline) {
            _avisarUsoDeCacheDeVagas();
          }
          return List<Map<String, dynamic>>.from(dadosLocal);
        }
      } catch (erroCache) {
        debugPrint("Erro ao ler cache local de vagas: $erroCache");
      }

      // Se não houver cache nem internet, retorna vazio e avisa o usuário
      if (!_estaOffline) {
        _avisarFalhaAoCarregarVagas();
      }
      return [];
    }
  }

  // Avisa que os dados exibidos são do cache (não os mais recentes)
  void _avisarUsoDeCacheDeVagas() {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          "Não foi possível atualizar as vagas agora. Exibindo dados salvos.",
        ),
      ),
    );
  }

  // Avisa que não foi possível obter nenhuma vaga (nem do servidor, nem do cache)
  void _avisarFalhaAoCarregarVagas() {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text("Não foi possível carregar as vagas no momento."),
      ),
    );
  }

  List<Marker> gerarMarcadores(List<Map<String, dynamic>> locais) {
    final List<Marker> markers = [];

    for (final local in locais) {
      final lat = (local['latitude'] as num).toDouble();
      final lng = (local['longitude'] as num).toDouble();
      final vagas = local['vagas'] as List<dynamic>;
      final tiposUnicos = vagas.map((v) => v['tipo_vaga']).toSet();

      for (final tipo in tiposUnicos) {
        markers.add(
          Marker(
            key: ValueKey<String>("$lat|$lng|$tipo"),
            point: LatLng(lat, lng),
            width: 50,
            height: 50,
            rotate: true,
            alignment: const Alignment(0.0, -1.0),
            child: GestureDetector(
              onTap: () =>
                  _mostrarDetalhesLocal(local, tipo), // <--- CHAMA A ABA AQUI
              child: _iconePorTipo(tipo),
            ),
          ),
        );
      }
    }
    return markers;
  }

  Future<void> _carregarMarcadores() async {
    final locais = await _buscarMarcadores();
    _todosOsLocais = locais; // Salva a lista bruta
    _aplicarFiltro();
  }

void _aplicarFiltro() {
  if (!mounted) return;

  final locaisFiltrados = _todosOsLocais.map((local) {
    // 1. Filtra as vagas pelo tipo selecionado
    final novasVagas = (local['vagas'] as List)
        .where((v) => _filtrosAtivos.contains(v['tipo_vaga']))
        .toList();
    return {...local, 'vagas': novasVagas};
  }).where((local) {
    bool temVagas = (local['vagas'] as List).isNotEmpty;

    // 2. Compara o texto digitado com a referência e o endereço
    String referencia = (local['referencia'] ?? '').toString().toLowerCase();
    String endereco = (local['endereco'] ?? '').toString().toLowerCase();
    String busca = _textoPesquisa.trim().toLowerCase();

    bool combinaComPesquisa = busca.isEmpty ||
        referencia.contains(busca) ||
        endereco.contains(busca);

    return temVagas && combinaComPesquisa;
  }).toList();

  setState(() {
    _markers = gerarMarcadores(locaisFiltrados);
  });
  // Se a pesquisa encontrou exatamente 1 lugar, anima o mapa até ele!
if (_textoPesquisa.isNotEmpty && locaisFiltrados.length == 1) {
  final umLocal = locaisFiltrados.first;
  final lat = (umLocal['latitude'] as num).toDouble();
  final lng = (umLocal['longitude'] as num).toDouble();
  _animatedMapController.animateTo(
    dest: LatLng(lat, lng),
    zoom: 17.0,
  );
}
}

  // Salva os filtros ativos no disco
  Future<void> _salvarFiltrosNoCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      // Convertemos o Set em List para o SharedPreferences aceitar
      await prefs.setStringList('filtros_usuarios', _filtrosAtivos.toList());
    } catch (e) {
      debugPrint("Erro ao salvar filtros: $e");
    }
  }

  // Recupera os filtros salvos
  Future<void> _recuperarFiltrosDoCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final List<String>? filtrosSalvos = prefs.getStringList(
        'filtros_usuarios',
      );

      if (filtrosSalvos != null && filtrosSalvos.isNotEmpty) {
        if (!mounted) return;
        setState(() {
          _filtrosAtivos = filtrosSalvos.toSet();
        });
      }
    } catch (e) {
      debugPrint("Erro ao recuperar filtros: $e");
    }
  }

  // ---------------------------------------------------------------------
  // LÓGICA DE PESQUISA DE LUGARES (LocationIQ)
  // ---------------------------------------------------------------------

  void _alternarPesquisa() {
    if (_pesquisaAberta) {
      _fecharPesquisa();
      return;
    }

    setState(() {
      _pesquisaAberta = true;
      _menuAberto = false; // fecha o menu de filtro, se estiver aberto
    });

    // Espera o frame renderizar o campo antes de focar/abrir o teclado
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focusPesquisa.requestFocus();
    });
  }

  void _fecharPesquisa() {
    _debouncePesquisa?.cancel();
    _focusPesquisa.unfocus();
    if (!mounted) return;
    setState(() {
      _pesquisaAberta = false;
      _controladorPesquisa.clear();
      _resultadosPesquisa = [];
      _erroPesquisa = null;
      _carregandoPesquisa = false;
    });
  }

  // Chamado a cada tecla digitada; usa debounce para não estourar a API
  void _aoDigitarPesquisa(String texto) {
    _debouncePesquisa?.cancel();

    if (texto.trim().isEmpty) {
      setState(() {
        _resultadosPesquisa = [];
        _carregandoPesquisa = false;
        _erroPesquisa = null;
      });
      return;
    }

    setState(() {
      _carregandoPesquisa = true;
      _erroPesquisa = null;
    });

    _debouncePesquisa = Timer(const Duration(milliseconds: 500), () {
      _buscarNoLocationIQ(texto.trim());
    });
  }

  // Faz a chamada real à API de autocomplete do LocationIQ
  Future<void> _buscarNoLocationIQ(String query) async {
    if (_locationIqApiKey.isEmpty ||
        _locationIqApiKey == 'COLOQUE_SUA_CHAVE_LOCATIONIQ_AQUI') {
      if (!mounted) return;
      setState(() {
        _carregandoPesquisa = false;
        _erroPesquisa =
            'Configure sua chave da API do LocationIQ no código (constante _locationIqApiKey).';
      });
      return;
    }

    if (!(await _temInternet())) {
      if (!mounted) return;
      setState(() {
        _carregandoPesquisa = false;
        _erroPesquisa = 'Sem conexão com a internet.';
      });
      return;
    }

    try {
      final lat = _posicaoAtual?.latitude ?? _fallback.latitude;
      final lng = _posicaoAtual?.longitude ?? _fallback.longitude;

      // Cria uma caixa delimitadora (viewbox) em torno da posição atual do
      // usuário, usada apenas para PRIORIZAR resultados próximos
      // (bounded=0 permite que resultados fora dela também apareçam).
      const double delta = 0.35; // ~ raio de busca em graus
      final viewbox =
          '${lng - delta},${lat + delta},${lng + delta},${lat - delta}';

      final uri = Uri.parse(
        'https://api.locationiq.com/v1/search'
        '?key=$_locationIqApiKey'
        '&q=${Uri.encodeQueryComponent(query)}'
        '&viewbox=$viewbox'
        '&bounded=0'
        '&limit=10'
        '&dedupe=1'
        '&accept-language=pt-BR'
        '&addressdetails=1'
        '&format=json',
      );

      final resposta = await http.get(uri).timeout(const Duration(seconds: 6));

      if (!mounted) return;

      if (resposta.statusCode == 200) {
        final List<dynamic> dados = jsonDecode(resposta.body);

        final filtrados = _municipioUsuario == null
            ? dados
            : dados.where((item) {
                final endereco = item['address'] ?? {};
                final cidadeItem =
                    (endereco['city'] ??
                            endereco['town'] ??
                            endereco['municipality'] ??
                            endereco['county'] ??
                            '')
                        .toString()
                        .toLowerCase();
                return cidadeItem == _municipioUsuario!.toLowerCase();
              }).toList();

        setState(() {
          _resultadosPesquisa = filtrados.map<Map<String, dynamic>>((item) {
            return {
              'display_name': (item['display_name'] ?? '').toString(),
              'lat': double.tryParse(item['lat'].toString()) ?? 0.0,
              'lon': double.tryParse(item['lon'].toString()) ?? 0.0,
              'tipo': (item['type'] ?? '').toString(),
            };
          }).toList();
          _carregandoPesquisa = false;
          _erroPesquisa = _resultadosPesquisa.isEmpty
              ? 'Nenhum resultado encontrado.'
              : null;
        });
      } else if (resposta.statusCode == 404) {
        // O LocationIQ retorna 404 quando a busca não encontra nada
        setState(() {
          _resultadosPesquisa = [];
          _carregandoPesquisa = false;
          _erroPesquisa = 'Nenhum resultado encontrado.';
        });
      } else {
        debugPrint(
          'Erro LocationIQ: ${resposta.statusCode} - ${resposta.body}',
        );
        setState(() {
          _resultadosPesquisa = [];
          _carregandoPesquisa = false;
          _erroPesquisa = 'Não foi possível buscar agora. Tente novamente.';
        });
      }
    } catch (e) {
      debugPrint("Erro ao buscar lugares no LocationIQ: $e");
      if (!mounted) return;
      setState(() {
        _resultadosPesquisa = [];
        _carregandoPesquisa = false;
        _erroPesquisa = 'Não foi possível buscar agora. Tente novamente.';
      });
    }
  }

  // Leva o mapa até o ponto escolhido pelo usuário
  Future<void> _selecionarResultadoPesquisa(
    Map<String, dynamic> resultado,
  ) async {
    final destino = LatLng(
      resultado['lat'] as double,
      resultado['lon'] as double,
    );
    final nomeLocal = resultado['display_name'] as String;

    _fecharPesquisa();

    await _animatedMapController.animateTo(dest: destino, zoom: 17.0);

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(nomeLocal, maxLines: 1, overflow: TextOverflow.ellipsis),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  Widget _buildFiltroCustom() {
    final tipos = ['Idoso', 'Autista', 'Gestante', 'PcD'];
    const double larguraBase = 120.0;

    return TapRegion(
      // Esta função dispara quando você clica em qualquer lugar FORA deste widget
      onTapOutside: (event) {
        if (_menuAberto) {
          setState(() {
            _menuAberto = false;
          });
        }
      },
      child: Container(
        margin: const EdgeInsets.only(top: 16, left: 16),
        constraints: const BoxConstraints(
          minWidth: larguraBase,
          maxWidth: 160, // Limite máximo para não cobrir a tela toda
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            GestureDetector(
              onTap: () => setState(() => _menuAberto = !_menuAberto),
              child: Container(
                height: 56,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: _menuAberto
                      ? const BorderRadius.vertical(top: Radius.circular(15))
                      : BorderRadius.circular(15),
                  boxShadow: const [
                    BoxShadow(color: Colors.black12, blurRadius: 4),
                  ],
                ),
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Icon(
                      Icons.filter_list,
                      size: 18,
                      color: Colors.blueAccent,
                    ),
                    const Flexible(
                      // <--- Adicione isso para o texto não empurrar os ícones
                      child: Text(
                        "Filtrar",
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                        ),
                      ),
                    ),
                    Icon(
                      _menuAberto ? Icons.arrow_drop_up : Icons.arrow_drop_down,
                      color: Colors.grey,
                    ),
                  ],
                ),
              ),
            ),

            AnimatedCrossFade(
              firstChild: const SizedBox.shrink(),
              secondChild: Container(
                decoration: const BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.vertical(
                    bottom: Radius.circular(20),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black12,
                      blurRadius: 4,
                      offset: Offset(0, 2),
                    ),
                  ],
                ),
                child: Column(
                  children: tipos.map((tipo) {
                    final ativo = _filtrosAtivos.contains(tipo);
                    return InkWell(
                      onTap: () {
                        setState(() {
                          if (ativo) {
                            _filtrosAtivos.remove(tipo);
                          } else {
                            _filtrosAtivos.add(tipo);
                          }
                        });
                        _salvarFiltrosNoCache();
                        _aplicarFiltro();
                      },

                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(
                          vertical: 12,
                          horizontal: 16,
                        ),
                        decoration: BoxDecoration(
                          border: Border(
                            top: BorderSide(color: Colors.grey.shade100),
                          ),
                          color: ativo
                              ? Colors.blueAccent.withOpacity(0.05)
                              : Colors.transparent,
                        ),
                        child: Row(
                          children: [
                            Icon(
                              ativo ? Icons.check : Icons.close,
                              size: 18,
                              color: ativo
                                  ? Colors.blueAccent
                                  : Colors.grey.shade300,
                            ),
                            const SizedBox(width: 10),
                            Text(
                              tipo,
                              style: TextStyle(
                                fontSize: 13,
                                color: ativo
                                    ? Colors.blueAccent
                                    : Colors.black87,
                                fontWeight: ativo
                                    ? FontWeight.bold
                                    : FontWeight.normal,
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ),
              crossFadeState: _menuAberto
                  ? CrossFadeState.showSecond
                  : CrossFadeState.showFirst,
              duration: const Duration(milliseconds: 250),
            ),
          ],
        ),
      ),
    );
  }

  // Barra de pesquisa que ocupa toda a largura, sobrepondo o botão de filtro
  Widget _buildBotaoPesquisaAnimado(BuildContext context) {
    final larguraTela = MediaQuery.of(context).size.width;
    const double tamanhoFechado = 56.0;
    final double larguraAberta =
        larguraTela - 32; // 16px de margem de cada lado

    return AnimatedPositioned(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOutCubic,
      top: 16,
      right: 16,
      left: _pesquisaAberta ? 16 : larguraTela - 16 - tamanhoFechado,
      child: GestureDetector(
        onTap: _pesquisaAberta ? null : _alternarPesquisa,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeInOutCubic,
          height: 56,
          width: _pesquisaAberta ? larguraAberta : tamanhoFechado,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(15),
            boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 4)],
          ),
          padding: const EdgeInsets.symmetric(horizontal: 16),
          alignment: Alignment.center,
          child: _pesquisaAberta
              ? Row(
                  children: [
                    const Icon(
                      Icons.search,
                      size: 20,
                      color: Colors.blueAccent,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        controller: _controladorPesquisa,
                        focusNode: _focusPesquisa,
                        onChanged: _aoDigitarPesquisa,
                        textInputAction: TextInputAction.search,
                        decoration: const InputDecoration(
                          hintText: 'Pesquisar um lugar...',
                          border: InputBorder.none,
                          isDense: true,
                        ),
                        style: const TextStyle(fontSize: 14),
                      ),
                    ),
                    if (_carregandoPesquisa) ...[
                      const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                      const SizedBox(width: 12),
                    ],
                    GestureDetector(
                      onTap: _fecharPesquisa,
                      child: Padding(
                        padding: const EdgeInsets.all(4),
                        child: Icon(
                          Icons.close,
                          color: Colors.grey.shade600,
                          size: 22,
                        ),
                      ),
                    ),
                  ],
                )
              : const Icon(Icons.search, color: Colors.blueAccent),
        ),
      ),
    );
  }

  Widget _buildResultadosPesquisaAnimados(BuildContext context) {
    final temConteudo = _resultadosPesquisa.isNotEmpty || _erroPesquisa != null;

    return Positioned(
      top: 72,
      left: 16,
      right: 16,
      child: IgnorePointer(
        ignoring: !temConteudo,
        child: AnimatedOpacity(
          duration: const Duration(milliseconds: 200),
          opacity: temConteudo ? 1 : 0,
          child: _resultadosPesquisa.isNotEmpty
              ? Container(
                  constraints: BoxConstraints(
                    maxHeight: MediaQuery.of(context).size.height * 0.45,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(15),
                    boxShadow: const [
                      BoxShadow(
                        color: Colors.black12,
                        blurRadius: 4,
                        offset: Offset(0, 2),
                      ),
                    ],
                  ),
                  child: ListView.separated(
                    shrinkWrap: true,
                    padding: EdgeInsets.zero,
                    itemCount: _resultadosPesquisa.length,
                    separatorBuilder: (context, index) =>
                        Divider(height: 1, color: Colors.grey.shade100),
                    itemBuilder: (context, index) {
                      final resultado = _resultadosPesquisa[index];
                      return InkWell(
                        onTap: () => _selecionarResultadoPesquisa(resultado),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            vertical: 12,
                            horizontal: 16,
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Icon(
                                Icons.location_on_outlined,
                                color: Colors.blueAccent,
                                size: 20,
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  resultado['display_name'] as String,
                                  style: const TextStyle(
                                    fontSize: 13,
                                    color: Colors.black87,
                                  ),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                )
              : (_erroPesquisa != null
                    ? Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(
                          vertical: 14,
                          horizontal: 16,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(15),
                        ),
                        child: Text(
                          _erroPesquisa!,
                          style: TextStyle(
                            fontSize: 13,
                            color: Colors.grey.shade600,
                            fontStyle: FontStyle.italic,
                          ),
                        ),
                      )
                    : const SizedBox.shrink()),
        ),
      ),
    );
  }

  Widget _iconePorTipo(String tipo) {
    switch (tipo) {
      case 'Idoso':
        return Image.asset(
          'assets/images/vaga_icons/idoso.webp',
          width: 50,
          height: 50,
        );

      case 'Autista':
        return Image.asset(
          'assets/images/vaga_icons/autista.webp',
          width: 50,
          height: 50,
        );

      case 'Gestante':
        return Image.asset(
          'assets/images/vaga_icons/gestante.webp',
          width: 50,
          height: 50,
        );

      case 'PcD':
        return Image.asset(
          'assets/images/vaga_icons/pcd.webp',
          width: 50,
          height: 50,
        );
      default:
        return Image.asset(
          'assets/images/vaga_icons/pcd_autista_idoso_gestante.webp',
          width: 50,
          height: 50,
        );
    }
  }

  String _obterImagemDoCluster(List<Marker> clusterMarkers) {
    // 1. Extrai os tipos únicos
    final tiposSet = clusterMarkers.map((m) {
      final keyString = (m.key as ValueKey).value.toString();
      return keyString.split('|').last;
    }).toSet();

    // 2. Transforma em lista e ordena alfabeticamente
    // Isso garante que 'PcD' e 'Idoso' sempre resultem em 'idoso_pcd'
    final listaOrdenada = tiposSet.toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));

    // 3. Caso especial: Se vazio ou se tiver todos (4 tipos), retorna o ícone completo
    if (listaOrdenada.isEmpty || listaOrdenada.length == 4) {
      return 'assets/images/vaga_icons/autista_gestante_idoso_pcd.webp';
    }

    // 4. Gera o nome do arquivo juntando os itens da lista ordenada
    // Ex: ['Autista', 'Idoso'] -> 'autista_idoso'
    final nomeArquivo = listaOrdenada.map((s) => s.toLowerCase()).join('_');

    return 'assets/images/vaga_icons/$nomeArquivo.webp';
  }

  void _mostrarDetalhesLocal(Map<String, dynamic> local, String tipoClicado) {
    final dadosVaga = (local['vagas'] as List).firstWhere(
      (v) => v['tipo_vaga'] == tipoClicado,
      orElse: () => null,
    );

    if (dadosVaga == null) return;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return DraggableScrollableSheet(
          initialChildSize: 0.5,
          minChildSize: 0.3,
          maxChildSize: 0.95,
          expand: false,
          builder: (context, scrollController) {
            return Container(
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
              ),
              child: ListView(
                controller: scrollController,
                padding: const EdgeInsets.only(bottom: 24),
                children: [
                  // Barra visual de arraste
                  Center(
                    child: Container(
                      margin: const EdgeInsets.symmetric(vertical: 12),
                      width: 40,
                      height: 5,
                      decoration: BoxDecoration(
                        color: Colors.grey[300],
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  ),

                  Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Cabeçalho com Ícone e Tipo
                        Row(
                          children: [
                            _iconePorTipo(tipoClicado),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                "Vaga para $tipoClicado",
                                style: const TextStyle(
                                  fontSize: 22,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.blueAccent,
                                ),
                              ),
                            ),
                            IconButton(
                              icon: const Icon(
                                Icons.edit_outlined,
                                color: Colors.blueAccent,
                              ),
                              onPressed: () async {
                                if (!(await _temInternet())) {
                                  if (mounted) {
                                    _mostrarDialogoEditarVaga(
                                      "Sem Conexão",
                                      "Parece que você está offline. Verifique sua conexão com a internet e tente novamente.",
                                    );
                                  }
                                  return; // Interrompe a execução aqui
                                }

                                if (service.estaLogado) {
                                  // Aguarda o usuário terminar o registro na outra tela
                                  await Navigator.pushNamed(
                                    context,
                                    '/registro_vagas',
                                    arguments: local,
                                  );
                                } else {
                                  Navigator.pushNamed(context, '/login');
                                }
                              },
                            ),
                          ],
                        ),

                        const SizedBox(height: 12),

                        // --- SEÇÃO DE CONTRIBUINTES ---
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              "Contribuintes deste local",
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: Colors.black54,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Builder(
                              builder: (context) {
                                final List<dynamic> contribuintes =
                                    local['contribuintes'] ?? [];

                                if (contribuintes.isEmpty) {
                                  return Container(
                                    width: double.infinity,
                                    padding: const EdgeInsets.all(12),
                                    decoration: BoxDecoration(
                                      color: Colors.grey.shade100,
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: Text(
                                      "Nenhuma contribuição registrada ainda.",
                                      style: TextStyle(
                                        fontSize: 13,
                                        color: Colors.grey.shade600,
                                        fontStyle: FontStyle.italic,
                                      ),
                                    ),
                                  );
                                }

                                // Gera a lista vertical de usuários usando uma Column
                                return Column(
                                  children: contribuintes.map<Widget>((
                                    contrib,
                                  ) {
                                    final String? avatarUrl = contrib['avatar'];
                                    final String nome =
                                        contrib['nome'] ?? "Usuário Anônimo";

                                    return Container(
                                      margin: const EdgeInsets.only(
                                        bottom: 8,
                                      ), // Espaçamento entre usuários
                                      padding: const EdgeInsets.symmetric(
                                        vertical: 8,
                                        horizontal: 12,
                                      ),
                                      decoration: BoxDecoration(
                                        color: Colors.grey.shade100,
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      child: Row(
                                        children: [
                                          CircleAvatar(
                                            radius: 18,
                                            backgroundColor:
                                                Colors.grey.shade300,
                                            backgroundImage:
                                                (avatarUrl != null &&
                                                    avatarUrl.isNotEmpty)
                                                ? NetworkImage(avatarUrl)
                                                : null,
                                            child:
                                                (avatarUrl == null ||
                                                    avatarUrl.isEmpty)
                                                ? ClipRRect(
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                          18,
                                                        ),
                                                    child: Image.asset(
                                                      'assets/images/avatar.webp',
                                                      fit: BoxFit.cover,
                                                      width: double.infinity,
                                                      height: double.infinity,
                                                    ),
                                                  )
                                                : null,
                                          ),
                                          const SizedBox(width: 12),
                                          Expanded(
                                            child: Text(
                                              nome,
                                              style: const TextStyle(
                                                fontSize: 14,
                                                fontWeight: FontWeight.w600,
                                                color: Colors.black87,
                                              ),
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                        ],
                                      ),
                                    );
                                  }).toList(),
                                );
                              },
                            ),
                          ],
                        ),

                        const SizedBox(height: 20),

                        // Endereço
                        const Text(
                          "Endereço",
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                        Text("${local['logradouro']}, ${local['numero']}"),
                        Text(
                          "${local['bairro']} - ${local['cidade']}/${local['estado']}",
                        ),
                        Text(
                          "Referência: ${local['referencia'] != null && local['referencia'].isNotEmpty ? local['referencia'] : 'Não registrada'}",
                          style: const TextStyle(fontSize: 12),
                        ),

                        const Divider(height: 32),

                        // Info de Quantidade
                        const Text(
                          "Vagas Disponíveis",
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text("Quantidade no local: ${dadosVaga['quantidade']}"),

                        const Divider(height: 32),

                        // 📸 SEÇÃO DE IMAGEM (Simplificada)
                        if (dadosVaga['foto_url'] != null &&
                            dadosVaga['foto_url'].toString().isNotEmpty) ...[
                          const Text(
                            "Foto da Vaga",
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
                          const SizedBox(height: 12),
                          GestureDetector(
                            onTap: () {
                              Navigator.push(
                                context,
                                PageRouteBuilder(
                                  opaque: false,
                                  barrierDismissible: true,
                                  pageBuilder: (context, _, _) =>
                                      VisualizadorImagem(
                                        url: dadosVaga['foto_url'],
                                      ),
                                ),
                              );
                            },
                            child: Container(
                              width: double.infinity,
                              height: 300,
                              decoration: BoxDecoration(
                                color: const Color(0xFFE7E7E7),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(12),
                                child: Stack(
                                  children: [
                                    Hero(
                                      tag: dadosVaga['foto_url'],
                                      child: Image.network(
                                        dadosVaga['foto_url'],
                                        width: double.infinity,
                                        height: double.infinity,
                                        fit: BoxFit.contain,
                                        loadingBuilder:
                                            (context, child, loadingProgress) {
                                              if (loadingProgress == null)
                                                return child;
                                              return const Center(
                                                child:
                                                    CircularProgressIndicator(),
                                              );
                                            },
                                        errorBuilder:
                                            (context, error, stackTrace) =>
                                                const Center(
                                                  child: Icon(
                                                    Icons.broken_image,
                                                    color: Colors.grey,
                                                    size: 40,
                                                  ),
                                                ),
                                      ),
                                    ),
                                    // Indicador visual de que a imagem é expansível
                                    Positioned(
                                      right: 8,
                                      bottom: 8,
                                      child: Container(
                                        padding: const EdgeInsets.all(4),
                                        decoration: BoxDecoration(
                                          color: Colors.black45,
                                          borderRadius: BorderRadius.circular(
                                            8,
                                          ),
                                        ),
                                        child: const Icon(
                                          Icons.fullscreen,
                                          color: Colors.white,
                                          size: 30,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ] else ...[
                          // Opcional: Feedback visual se não houver foto
                          const Text(
                            "Nenhuma foto cadastrada para esta vaga.",
                            style: TextStyle(
                              color: Colors.grey,
                              fontStyle: FontStyle.italic,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      resizeToAvoidBottomInset: false,
      appBar: AppBar(title: const Text("Home")),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Stack(
              children: [
                if (_mapReady && _posicaoAtual != null)
                  FlutterMap(
                    mapController: _animatedMapController.mapController,
                    options: MapOptions(
                      initialCenter: _posicaoAtual ?? _fallback,
                      initialZoom: _zoomAtual,
                      maxZoom: 19.0,
                      minZoom: 12.0,
                      onTap: (_, _) {
                        // Fecha a pesquisa ao tocar no mapa
                        if (_pesquisaAberta) _fecharPesquisa();
                      },
                    ),
                    children: [
                      TileLayer(
                        urlTemplate:
                            'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                        userAgentPackageName: 'br.com.incluzone.backend',
                        tileDisplay: const TileDisplay.fadeIn(
                          duration: Duration(milliseconds: 500),
                        ),
                        tileProvider: CachedTileProvider(store: _cacheStore),
                      ),

                      // 🔵 CLUSTER DOS MARKERS DO SUPABASE
                      MarkerClusterLayerWidget(
                        options: MarkerClusterLayerOptions(
                          maxClusterRadius: 100,
                          size: const Size(70, 70),
                          markers: _markers,
                          rotate: true,
                          alignment: const Alignment(0.0, -1.0),
                          spiderfyCluster: true,
                          zoomToBoundsOnClick: false,
                          maxZoom: 19,
                          spiderfyCircleRadius: 70,

                          builder: (context, clusterMarkers) {
                            final caminhoImagem = _obterImagemDoCluster(
                              clusterMarkers,
                            );

                            return Transform.translate(
                              offset: const Offset(0, 10),
                              child: Image.asset(
                                caminhoImagem,
                                width: 80,
                                height: 80,
                              ),
                            );
                          },

                          onClusterTap: (cluster) async {
                            final camera =
                                _animatedMapController.mapController.camera;

                            // 1. Verificar se todos os marcadores estão na mesma coordenada
                            final primeiraCoordenada =
                                cluster.markers.first.point;
                            final todosNaMesmaCoordenada = cluster.markers
                                .every(
                                  (m) =>
                                      m.point.latitude ==
                                          primeiraCoordenada.latitude &&
                                      m.point.longitude ==
                                          primeiraCoordenada.longitude,
                                );

                            if (todosNaMesmaCoordenada) {
                              // Para pontos sobrepostos, mantemos o zoom alto para o spiderfy
                              await _animatedMapController.animateTo(
                                dest: primeiraCoordenada,
                                zoom: 18.0,
                              );
                            } else {
                              // 2. Calculamos o enquadramento ideal
                              final cameraFit = CameraFit.bounds(
                                bounds: cluster.bounds,
                                padding: const EdgeInsets.all(
                                  50,
                                ), // Margem interna em pixels
                              );

                              final fitOutput = cameraFit.fit(camera);

                              // 3. A MÁGICA: Subtraímos 0.5 do zoom calculado para dar o "respiro" extra
                              double zoomComMargem = fitOutput.zoom - 0.5;

                              // 4. Aplicamos a trava de segurança (ex: não passar de 17)
                              if (zoomComMargem > 17.0) {
                                zoomComMargem = 17.0;
                              }

                              await _animatedMapController.animateTo(
                                dest: fitOutput.center,
                                zoom: zoomComMargem,
                              );
                            }
                          },
                        ),
                      ),

                      // 🟢 USUÁRIO FORA DO CLUSTER (SEPARADO)
                      MarkerLayer(
                        markers: [
                          if (_mapReady &&
                              _posicaoAtual != null &&
                              _gpsAtivoEPermitido)
                            Marker(
                              point: _posicaoAtual!,
                              width: 22,
                              height: 22,
                              child: _buildUserLocationMarker(),
                            ),
                        ],
                      ),
                    ],
                  ),

// 1. BARRA DE PESQUISA (Fica no topo, na posição top: 16)
Positioned(
  top: 16,
  left: 16,
  right: 16,
  child: Card(
    elevation: 6,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(25),
    ),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: TextField(
        controller: _pesquisaController,
        onChanged: (texto) {
          setState(() {
            _textoPesquisa = texto;
          });
          _aplicarFiltro();
        },
        decoration: InputDecoration(
          hintText: 'Pesquisar referência (ex: Farmácia, Loja X)...',
          hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: 14),
          prefixIcon: const Icon(Icons.search, color: Colors.blueAccent),
          suffixIcon: _textoPesquisa.isNotEmpty
              ? IconButton(
                  icon: const Icon(Icons.clear, color: Colors.grey),
                  onPressed: () {
                    _pesquisaController.clear();
                    setState(() {
                      _textoPesquisa = '';
                    });
                    _aplicarFiltro();
                  },
                )
              : null,
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(vertical: 14),
        ),
      ),
    ),
  ),
),

// 2. FILTRO DE VAGAS (Mudou para top: 80 para ficar ABAIXO da barra)
Positioned(
  top: 80,
  left: 0,
  child: _buildFiltroCustom(),
),

// 3. BOTÃO DE GPS (Mudou para top: 80 para alinhar com o filtro)
if (_mapReady)
  Positioned(
    top: 80,
    right: 16,
    child: FloatingActionButton(
      backgroundColor: Colors.white,
      foregroundColor: Colors.blueAccent,
      elevation: 4,
      onPressed: _centralizarNoUsuario,
      child: const Icon(Icons.my_location),
    ),
  ),
              ],
            ),
          ),
        ],
      ),

      drawer: Drawer(
        child: Column(
          children: [
            // O Expanded faz o ListView ocupar todo o espaço disponível no topo e meio
            Expanded(
              child: SafeArea(
                child: ListView(
                  // Remova o padding padrão do ListView para não dar conflito com o topo
                  padding: EdgeInsets.zero,
                  children: [
                    ListTile(
                      title: const Text("Sobre o IncluZone"),
                      leading: const Icon(Icons.info_outline),
                      onTap: () {
                        Navigator.pop(context);
                        Navigator.pushNamed(context, '/sobre');
                      },
                    ),
                    if (nomeUsuario == null) ...[
                      ListTile(
                        title: const Text("Login"),
                        leading: const Icon(Icons.login),
                        onTap: () {
                          Navigator.pop(context);
                          Navigator.pushNamed(context, '/login');
                        },
                      ),
                      ListTile(
                        title: const Text("Cadastrar"),
                        leading: const Icon(Icons.person_add_outlined),
                        onTap: () {
                          Navigator.pop(context);
                          Navigator.pushNamed(context, '/cadastro');
                        },
                      ),
                    ],
                    ListTile(
                      title: const Text("Pré-registrar Vagas"),
                      leading: const Icon(Icons.location_on_outlined),
                      onTap: () {
                        Navigator.pop(context);
                        Navigator.pushNamed(context, '/pre_registro_vagas');
                      },
                    ),
                    if (nomeUsuario != null) ...[
                      if (!isGoogle) ...[
                        ListTile(
                          title: const Text("Editar conta"),
                          leading: const Icon(Icons.edit_outlined),
                          onTap: () {
                            Navigator.pop(context);
                            Navigator.pushNamed(context, '/editar');
                          },
                        ),
                      ],
                      ListTile(
                        title: const Text("Histórico"),
                        leading: const Icon(Icons.history),
                        onTap: () async {
                          Navigator.pop(context);
                          Navigator.pushNamed(context, '/historico');
                        },
                      ),
                      ListTile(
                        title: const Text("Sair"),
                        leading: const Icon(Icons.logout),
                        onTap: () async {
                          Navigator.pop(context);
                          try {
                            await service.client.auth.signOut();
                          } catch (e) {
                            // Mesmo se falhar remotamente, seguimos limpando o
                            // estado local para não travar o usuário logado
                            debugPrint("Erro ao sair: $e");
                          }
                          if (!mounted) return;
                          setState(() => nomeUsuario = null);
                          Navigator.pushReplacementNamed(context, '/');
                        },
                      ),
                      if (isGoogle) ...[
                        ListTile(
                          title: const Text(
                            "Excluir conta",
                            style: TextStyle(color: Colors.red),
                          ),
                          leading: const Icon(Icons.delete, color: Colors.red),
                          onTap: _excluirConta,
                        ),
                      ],
                    ],
                  ],
                ),
              ),
            ),

            // Rodapé centralizado
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 20),
                child: Image.asset('assets/images/titulo.webp', width: 150),
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
