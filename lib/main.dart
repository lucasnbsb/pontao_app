import 'dart:ffi';
import 'dart:io';
import 'dart:math';

import 'package:cookie_jar/cookie_jar.dart';
import 'package:dio/adapter.dart';
import 'package:dio/dio.dart';
import 'package:dio_cookie_manager/dio_cookie_manager.dart';
import 'package:flutter/src/widgets/text.dart' as tx;
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:pontao_unb/config.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:html/dom.dart';
import 'package:html/parser.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({Key? key}) : super(key: key);

  // This widget is the root of your application.
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Pontão UnB',
      theme: ThemeData(
          brightness: Brightness.light,
          primaryColor: const Color.fromRGBO(0, 58, 122, 1),
          buttonTheme: const ButtonThemeData(buttonColor: Color.fromRGBO(0, 166, 235, 1))),
      home: const PaginaPonto(title: 'Pontao UnB'),
    );
  }
}

class PaginaPonto extends StatefulWidget {
  const PaginaPonto({Key? key, required this.title}) : super(key: key);
  final String title;
  @override
  State<PaginaPonto> createState() => _PaginaPontoState();
}

// basicamente um mnemonico pra dizer saida_almoco = 0 e saida_dia=1
// enums em dart sao declaradas assim, os nomes nao sao variaveis e sim chaves da enum
enum Notificacoes { saida_almoco, saida_dia }

class _PaginaPontoState extends State<PaginaPonto> {
  final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin = FlutterLocalNotificationsPlugin();

  /* -------------------------------------------------------------------------- */
  /*                             Switch de Ambiente                             */
  /* -------------------------------------------------------------------------- */
  bool desenvolvimento = true;
  bool verbose = false;
  bool sso = true;

  // Valores para as credenciais, vem do shared prefs
  static String login = '';
  static String pass = '';
  static String codigoUnidade = '';

  // Controlador de indicadores de progresso
  bool isLoading = false;
  bool confirmacao = false;
  bool saidaAlmocoSePossivel = true;
  bool avisarSaidaAntes = false;
  TimeOfDay tempoAviso = const TimeOfDay(hour: 1, minute: 0);

  // Texto de status, constantemente renderizado, atualizado via append
  String textoAviso = '';

  // Controladores dos campos de texto necessários para a tela de configuracao
  // relendo esse codigo percebi que eles sao completamente desnecessários agora que a tela
  // de configuração esta em outro lugar, mas sao usados para passar os dados do shared prefs para
  // as variáveis acima, pode só deletar eles e passar o valor direto
  TextEditingController loginController = TextEditingController();
  TextEditingController passController = TextEditingController();
  TextEditingController codigoController = TextEditingController();

  // botoes de multiplas selecoes tem o seu estado guardado em arrays cujo tamanho é igual
  // ao numero de botoes, esse array é usado para marcar qual dos botoes recebe a classe selected
  var regimeIsSelected = [false, false, false, true];

  // Sufixos das telas correspondentes, o dio usa uma url base para fazer todas as requisicoes
  final loginSuffix = '/sigrh/login.jsf';
  final entradaSaidaSuffix = '/sigrh/frequencia/ponto_eletronico/cadastro_ponto_eletronico.jsf';
  final servidorSuffix = '/sigrh/servidor/portal/servidor.jsf';
  final unidadeSuffix = '/sigrh/frequencia/ponto_eletronico/form_selecao_unidade.jsf';

  // metodo de ciclo de vida do flutter para limpar os componentes,
  // nao vai ser necessário quando retirar os controladores que nao estao sendo usados
  @override
  void dispose() {
    loginController.dispose();
    passController.dispose();
    codigoController.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _loadCredentials();
    _loadTimetable();
  }

  _loadTimetable() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    if (prefs.containsKey('horarios')) {
      setState(() {
        textoAviso = 'Últimos Registros\n' + prefs.get('horarios').toString();
      });
    }
  }

  _saveTimetable(String horarios) async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    prefs.setString('horarios', horarios);
  }

  _loadCredentials() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    if (prefs.containsKey('login') && prefs.containsKey('pass')) {
      setState(() {
        login = prefs.get('login').toString();
        pass = prefs.get('pass').toString();
      });

      loginController = TextEditingController(text: login);
      passController = TextEditingController(text: pass);
    }

    if (prefs.containsKey('codigo')) {
      codigoController = TextEditingController(text: prefs.get('codigo').toString());
    }

    if (prefs.containsKey('almoco')) {
      setState(() {
        saidaAlmocoSePossivel = prefs.getBool('almoco') ?? true;
      });
    }

    if (prefs.containsKey('avisoHoras') && prefs.containsKey('avisoMinutos')) {
      setState(() {
        tempoAviso = TimeOfDay(hour: prefs.getInt('avisoHoras') ?? 1, minute: prefs.getInt('avisoMinutos') ?? 0);
      });
    } else {
      setState(() {
        tempoAviso = const TimeOfDay(hour: 1, minute: 0);
      });
    }

    // recupera o regime( int de 0 a 3 representando o botão selecionado)
    if (prefs.containsKey('regime')) {
      int regime = prefs.getInt('regime') ?? 0;
      if (regime < regimeIsSelected.length) {
        var isSelectedTemp = [false, false, false, false];
        isSelectedTemp[regime] = true;
        setState(() {
          regimeIsSelected = isSelectedTemp;
        });
      }
    }

    if (prefs.containsKey('avisarSaidaAntes')) {
      avisarSaidaAntes = prefs.getBool('avisarSaidaAntes') ?? true;
    }
  }

  /* -------------------------------------------------------------------------- */
  /*                                 Bater Ponto                                */
  /* -------------------------------------------------------------------------- */
  Future baterPonto() async {
    var loginUrl = desenvolvimento
        ? 'https://autenticacao.homologa.unb.br/sso-server/login?service=https%3A%2F%2Fsig.homologa.unb.br%2Fsigrh%2Flogin%2Fcas'
        : 'https://autenticacao.unb.br/sso-server/login?service=https%3A%2F%2Fsig.unb.br%2Fsigrh%2Flogin%2Fcas';

    var baseUrl = '';
    if (desenvolvimento) {
      baseUrl = 'https://sig.homologa.unb.br';
    } else {
      baseUrl = 'https://sig.unb.br';
    }

    // host é um header obrigatório para o post
    final urlHost = baseUrl.replaceAll('https://', '');
    final urlHostLogin = desenvolvimento ? 'autenticacao.homologa.unb.br' : 'TODO';

    // aqui ele busca os dados que vieram do shared prefs
    // mudar para colocar direto do shared prefs e deletar
    // os controladores inuteis
    setState(() {
      confirmacao = false;
      login = loginController.text;
      pass = passController.text;
      codigoUnidade = codigoController.text;
    });

    // Configurar a instância do Dio.
    BaseOptions optionsDio = BaseOptions(baseUrl: baseUrl);
    Dio dio = Dio(optionsDio);

    /* ------------ adiciona o gerenciador de cookies no cliente http ----------- */
    var cookieJar = CookieJar();
    dio.interceptors.add(CookieManager(cookieJar));
    /* -------- LIGAR ESSA VERSÃO PARA VER OS CHAMADOS DO DIO NO CONSOLE -------- */
    // dio.interceptors..add(CookieManager(cookieJar))..add(LogInterceptor());

    // Esse codigo ignora avisos de bad certificate.
    (dio.httpClientAdapter as DefaultHttpClientAdapter).onHttpClientCreate = (client) {
      client.badCertificateCallback = (X509Certificate cert, String host, int port) {
        return true;
      };
    };

    setState(() {
      isLoading = true;
      textoAviso = '📡 Buscando a página de login\n';
    });
    if (sso) {
      realizarLoginSSO(loginUrl, urlHostLogin, baseUrl, urlHost, dio, cookieJar);
    } else {
      realizarLoginAntigo(loginUrl, baseUrl, urlHost, dio);
    }
  }

  realizarLoginSSO(String loginUrl, String urlHostLogin, String baseUrl, String urlHost, Dio dio, CookieJar cookieJar) async {
    // Usa o referer da pagina expirada para evitar o popup, nao deve ser necessário depois do SSO
    var optionsGet = Options(headers: {'Referer': baseUrl + '/sigrh/expirada.jsp'});

    // Busca a Página de Login
    var getLogin;
    try {
      getLogin = await dio.get(loginUrl, options: optionsGet);
      avisoVerboso("navegando para a página de login");
    } on DioError catch (e) {
      avisoErro('⛔ Erro ao recuperar a página de login, verifique a sua conexão de internet');
      return;
    }

    var domGetLogin = parse(getLogin.data);
    avisoVerboso("Realizando o parse da página de login");

    //buscar lt e execution
    var lt = '';
    var execution = '';
    var viewStateValue = '';

    var domLt = domGetLogin.querySelectorAll('input[name="lt"]');
    var domExecution = domGetLogin.querySelectorAll('input[name="execution"]');

    if (domLt.length > 0) {
      lt = domLt[0].attributes['value'].toString();
    } else {
      // Erro de login
      avisoErro('⛔ Erro ao recuperar informações da página de login');
      avisoVerboso('Erro ao recuperar lt da página do sigle sign on');
      return;
    }

    if (domExecution.length > 0) {
      execution = domExecution[0].attributes['value'].toString();
    } else {
      // Erro de login
      avisoErro('⛔ Erro ao recuperar informações da página de login');
      avisoVerboso('Erro ao recuperar lt da página do sigle sign on');
      return;
    }

    var formDataLogin = {
      'username': login,
      'password': pass,
      'lt': lt,
      'execution': execution,
      '_eventId': 'submit',
      'submit': 'Submit',
    };

    var headersPostLogin = {
      'Host': urlHostLogin,
      'Connection': 'keep-alive',
      'Pragma': 'no-cache',
      'Cache-Control': 'no-cache',
      'Origin': 'https://' + urlHostLogin,
      'Upgrade-Insecure-Requests': 1,
      'User-Agent': 'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/99.0.4844.84 Safari/537.36',
      'Accept':
          'text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,image/apng,*/*;q=0.8,application/signed-exchange;v=b3;q=0.9',
      'Referer': loginUrl,
      'Accept-Encoding': 'gzip, deflate, br',
      'Accept-Language': 'pt-BR,pt;q=0.9,en-US;q=0.8,en;q=0.7',
    };

    //continuar daqui
    var optionsPostLogin = Options(
      headers: headersPostLogin,
      contentType: Headers.formUrlEncodedContentType,
      followRedirects: false,
      //validateStatus: (status) {return status! < 500;}
    );

    // Post para realizar o login, o processo é o mesmo mas com post agora, usa o follow redirects
    // que é uma funcao recursiva que faz as chamadas para o endereco colocado no header location da resposta
    aviso('🖥️ Realizando login'); // Realizar o Login
    Response postLogin;
    try {
      // Post para realizar o login, deve retornar 302, ir pro catch e ser tartado como redirect
      // feito assim pq o comportamento é anomalo, 302 não deve ser retornado de um post.
      avisoVerboso("Enviando o POST de login");
      postLogin = await dio.post(loginUrl, data: formDataLogin, options: optionsPostLogin);
    } on DioError catch (e) {
      avisoVerboso("Catch no post de login");
      var redirectResult = await followLoginRedirect(e, dio, cookieJar);

      // Verficiar o status após a tentativa de login e navegar de acordo
      avisoVerboso("Post de login bem sucedido, realizando navegação");

      // antes de realizar a navegação, montar o mapa de opções para a operação do sistema daqui pra frente,
      // o login é completamente diferente das outras operações

      var headers = {
        'Host': urlHost,
        'Origin': baseUrl,
        'Referer': baseUrl + '/',
        'Connection': 'keep-alive',
        'Pragma': 'no-cache',
        'Cache-Control': 'no-cache',
        'Accept-Encoding': 'gzip, deflate, br',
        'Accept-Language': 'pt-BR,pt;q=0.9,en-US;q=0.8,en;q=0.7',
        'Upgrade-Insecure-Requests': 1,
        'User-Agent': 'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/99.0.4844.84 Safari/537.36',
        'Accept':
            'text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,image/apng,*/*;q=0.8,application/signed-exchange;v=b3;q=0.9',
      };

      var options = Options(
        headers: headers,
        contentType: Headers.formUrlEncodedContentType,
        followRedirects: true,
        //validateStatus: (status) {return status! < 500;}
      );

      realizarNavegacao(redirectResult, dio, entradaSaidaSuffix, options, cookieJar);
    }
  }

  // NÂO HA GARANTIAS AQUI, EM ESTADO DE TODO
  realizarLoginAntigo(String loginUrl, String baseUrl, String urlHost, Dio dio) async {
    // Usa o referer da pagina expirada para evitar o popup, nao deve ser necessário depois do SSO
    var optionsGet = Options(headers: {'Referer': baseUrl + '/sigrh/expirada.jsp'});

    // Busca a Página de Login
    var getLogin;
    try {
      getLogin = await dio.get(loginSuffix, options: optionsGet);
      avisoVerboso("navegando para a página de login");
    } on DioError catch (e) {
      avisoErro('⛔ Erro ao recuperar a página de login, verifique a sua conexão de internet');
      return;
    }

    // em cada requisicao em faço o parse do html recebido e trabalho ele no formato DOM
    var domGetLogin = parse(getLogin.data);
    avisoVerboso("Realizando o parse da página de login");

    // O view state é um valor que o jsf mantem para rastrear as navegações, é preciso obte-lo para
    // fazer as chamadas subsequentes
    var viewStateValue = buscarViewState(domGetLogin);

    // Configurar o POST para o login
    // manda dimensões para evitar a página mobile, que nao tem a pagina de ponto
    FormData formDataLogin = FormData.fromMap({
      'formLogin': 'formLogin',
      'width': '1920',
      'height': '1080',
      // 'urlRedirect': '',
      'login': login,
      'senha': pass,
      'logar': 'Entrar',
      'javax.faces.ViewState': viewStateValue,
    });

    // basicamente imita os headers utilizados no chrome
    var headersPost = {
      'Host': urlHost,
      'Connection': 'close',
      'Pragma': 'no-cache',
      'Cache-Control': 'no-cache',
      'Origin': baseUrl,
      'Upgrade-Insecure-Requests': 1,
      'Content-Type': 'application/x-www-form-urlencoded',
      'User-Agent': 'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/74.0.3729.108 Safari/537.36',
      'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,image/webp,image/apng,*/*;q=0.8,application/signed-exchange;v=b3',
      'Referer': baseUrl + '/sigrh/expirada.jsp',
      'Accept-Encoding': 'gzip, deflate, br',
      'Accept-Language': 'en-US,en;q=0.9,pt;q=0.8',
    };

    var optionsPost = Options(headers: headersPost, followRedirects: false);

    // Post para realizar o login, o processo é o mesmo mas com post agora, usa o follow redirects
    // que é uma funcao recursiva que faz as chamadas para o endereco colocado no header location da resposta
    aviso('🖥️ Realizando login'); // Realizar o Login
    var postLogin;
    try {
      //postLogin = await dio.post(loginSuffix,data: formDataLogin, options: optionsPost);
      postLogin = await dio.post(loginSuffix, data: formDataLogin, options: optionsPost);
      avisoVerboso("Enviando o POST de login");
    } on DioError catch (e) {
      avisoVerboso("Catch no post de login");
      postLogin = await followRedirect(e, dio);
    }

    avisoVerboso("Post de login bem sucedido, realizando navegação");
    // Verficiar o status após a tentativa de login e navegar de acordo
    // realizarNavegacao(postLogin, dio, entradaSaidaSuffix, optionsPost);
  }

  // verifica onde o login foi parar, tipicamente na página de ponto, mas pode ser outro lugar
  // determina o que fazer a partir daí, navegar para a página de ponto ou bater o ponto.
  // é aqui que o aplicativo descobre se ele ta batendo o ponto de entrada ou saída
  void realizarNavegacao(Response postLoginData, Dio dio, String entradaSaidaRadix, Options optionsPost, CookieJar cookieJar) async {
    var domPostLogin = parse(postLoginData.data);
    var viewStateNavegacao = buscarViewState(domPostLogin);

    if (postLoginData.data.contains('autenticar-se novamente')) {
      avisoErro('⛔ Sessão expirada, tente novamente');
      return;
    } else {
      var msgErro = domPostLogin.querySelectorAll('ul.erros > li');
      if (msgErro.length > 0) {
        avisoErro('⛔ ERRO: ' + msgErro[0].text);
        return;
      }
    }

    avisoVerboso("Descobrindo onde entrou e indo pra pagina de ponto");
    /* --- basicamente o switch pra saber onde está e o que fazer a partir dai -- */
    // tirei o logoff por algum motivo, nao lembro por que
    if (domPostLogin.querySelectorAll('input[name="idFormDadosEntradaSaida:idBtnRegistrarEntrada"]').length > 0) {
      aviso('⛵ Realizando Navegação');
      realizarEntrada(viewStateNavegacao, dio, entradaSaidaRadix, optionsPost, cookieJar);
      // realizarLogoff(dio, optionsPost);
    } else if (domPostLogin.querySelectorAll('input[name="idFormDadosEntradaSaida:idBtnRegistrarSaida"]').length > 0) {
      aviso('⛵ Realizando Navegação');
      realizarSaida(viewStateNavegacao, dio, entradaSaidaRadix, optionsPost, cookieJar);
      // realizarLogoff(dio, optionsPost);
    } else if (domPostLogin.querySelectorAll('form[name="painelAcessoDadosServidor"]').length > 0) {
      navegarParaPonto(viewStateNavegacao, dio, servidorSuffix, optionsPost, cookieJar);
    } else if (domPostLogin.querySelectorAll('select[name="selecionarUnidadeForm:unidade"]').length > 0) {
      selecionarUnidade(viewStateNavegacao, dio, servidorSuffix, optionsPost, domPostLogin, cookieJar);
    } else {
      var voltaParaInicio = await dio.get(servidorSuffix);
      realizarNavegacao(voltaParaInicio, dio, entradaSaidaRadix, optionsPost, cookieJar);
    }
  }

  // bate o pojnto para a entrada, mmetade do método é o post e a outra
  // é buscar os horários registgrados e calcular o horario de saida
  Future realizarEntrada(String viewState, Dio dio, String entradaSaidaRadix, Options optionsPost, CookieJar cookieJar) async {
    var formDataEntrada = {
      'idFormDadosEntradaSaida': 'idFormDadosEntradaSaida',
      'idFormDadosEntradaSaida:observacoes': '',
      'idFormDadosEntradaSaida:idBtnRegistrarEntrada': 'Registrar Entrada',
      'javax.faces.ViewState': viewState,
    };
    aviso('🚪 Realizando Entrada');
    avisoVerboso("Mandando o post de entrada");
    var postEntrada;
    try {
      postEntrada = await dio.post(entradaSaidaRadix, data: formDataEntrada, options: optionsPost);
    } on DioError catch (e) {
      avisoVerboso('catch no post de entrada');
      //postEntrada = await followLoginRedirect(e, dio, cookieJar);
    }
    var domPostEntrada = parse(postEntrada.data);

    var msgErro = domPostEntrada.querySelectorAll('ul.erros > li');
    if (msgErro.length > 0) {
      avisoErro('⛔ ERRO: ' + msgErro[0].text);
    }

    var horarios = buscarHorariosEntradaSaida(domPostEntrada);
    aviso(horarios.toString());

    var ultimaEntrada = buscarUltimoHorarioEntrada(domPostEntrada);

    var horasRegistradas = buscarHorasRegistradas(domPostEntrada);
    if (horasRegistradas.length > 0) {
      if (horasRegistradas[0] != '00:00') {
        DateTime tempoMinimoSaida = getTempoMinimoAteSaida(horasRegistradas, getHorasRegime(), ultimaEntrada).subtract(Duration(minutes: 15));
        var textoAvisoExpediente = 'Horário mínimo de saída atingido';
        if (avisarSaidaAntes) {
          tempoMinimoSaida = tempoMinimoSaida.subtract(Duration(minutes: 5));
          textoAvisoExpediente = 'Fim do expediente em 5 minutos';
        }
        marcarNotificacao(Notificacoes.saida_dia.index, tempoMinimoSaida.hour, tempoMinimoSaida.minute, textoAvisoExpediente, 'Lembrete');
      }
      var textoHorasRegistradas = '\n\n\n⏱️ Horas Registradas: ' + horasRegistradas[0] + '\n⏰ Horas Contabilizadas: ' + horasRegistradas[1];
      aviso(textoHorasRegistradas);
      var textoHorarioMinimoSaida = '⌚ Horario Mínimo de Saída: ' + getTextoHorarioMinimoSaida(horasRegistradas, getHorasRegime(), ultimaEntrada);

      aviso(textoHorarioMinimoSaida);
      _saveTimetable(horarios.toString() + textoHorasRegistradas + '\n' + textoHorarioMinimoSaida);
    }

    setState(() {
      isLoading = false;
    });
  }

  //  só faz saida para almoço se o regime for 8 horas e o check estiver marcado e for hora de almoço
  //  funcionamento analogo ao metodo de realizar entradas
  Future realizarSaida(String viewState, Dio dio, String entradaSaidaRadix, Options optionsPost, CookieJar cookieJar) async {
    var almoco = false;
    if (regimeIsSelected[3]) {
      almoco = saidaAlmocoSePossivel && isHoraAlmoco();
    }

    var formDataEntrada = {
      'idFormDadosEntradaSaida': 'idFormDadosEntradaSaida',
      'idFormDadosEntradaSaida:observacoes': '',
      'idFormDadosEntradaSaida:saidaAlmoco': almoco.toString(),
      'idFormDadosEntradaSaida:idBtnRegistrarSaida': 'Registrar Saída',
      'javax.faces.ViewState': viewState,
    };

    if (desenvolvimento || almoco) {
      aviso(textoSaidaParaAlmoco());
    } else {
      aviso('🎉 Realizando Saída');
    }

    avisoVerboso("Descobrindo onde entrou e indo pra pagina de ponto");
    var postSaida = await dio.post(entradaSaidaRadix, data: formDataEntrada, options: optionsPost);
    var domPostSaida = parse(postSaida.data);

    var msgErro = domPostSaida.querySelectorAll('ul.erros > li');
    if (msgErro.length > 0) {
      avisoErro('⛔ ERRO: ' + msgErro[0].text);
    }

    var horarios = buscarHorariosEntradaSaida(domPostSaida);
    aviso(horarios.toString());

    var horasRegistradas = buscarHorasRegistradas(domPostSaida);
    if (horasRegistradas.length > 0) {
      var textoHorasRegistradas = '\n\n\n⏱️ Horas Registradas: ' + horasRegistradas[0] + '\n⏰ Horas Contabilizadas: ' + horasRegistradas[1];
      aviso(textoHorasRegistradas);
      _saveTimetable(horarios.toString() + textoHorasRegistradas);
    }

    // Marcar o push notification, roda sempre em desenv
    if (desenvolvimento || almoco) {
      marcarNotificacao(
          Notificacoes.saida_almoco.index, tempoAviso.hour, tempoAviso.minute, 'Horário mínimo de saída de almoço atingido', 'Lembrete');
    }

    setState(() {
      isLoading = false;
    });
  }

  // Move a navegacao para a pagina de registro de ponto
  Future navegarParaPonto(String viewStateAnterior, Dio dio, String servidorRadix, Options optionsPost, CookieJar cookieJar) async {
    FormData formDataPonto = FormData.fromMap({
      'painelAcessoDadosServidor': 'painelAcessoDadosServidor',
      'painelAcessoDadosServidor:linkPontoEletronicoAntigo': 'painelAcessoDadosServidor:linkPontoEletronicoAntigo',
      'javax.faces.ViewState': viewStateAnterior,
    });
    var paginaPonto;
    try {
      paginaPonto = await dio.post(servidorRadix, data: formDataPonto, options: optionsPost);
    } on DioError catch (e) {
      paginaPonto = await followRedirect(e, dio);
    }
    realizarNavegacao(paginaPonto, dio, entradaSaidaSuffix, optionsPost, cookieJar);
  }

  // nao é preciso interagir com o dropdown, apenas colocar o valor correto nos dados do form
  Future selecionarUnidade(String viewStateAnterior, Dio dio, String servidorRadix, Options optionsPost, Document dom, CookieJar cookieJar) async {
    if (codigoUnidade.isEmpty) {
      var opcoes = dom.querySelectorAll('select[name="selecionarUnidadeForm:unidade"]>option:not([disabled])');
      if (opcoes.length > 0) {
        aviso('👁️‍🗨️ Para selecionar a unidade permanentemente preencha o código da unidade escolhida no formulário de login\n');
        opcoes.forEach((o) => {
              if (o.text.indexOf('SELECIONE') == -1) {aviso('codigo: ' + o.attributes['value'].toString() + ' ' + o.text)}
            });
        setState(() {
          isLoading = false;
        });
      }
    } else {
      aviso('🏢 Selecionando a unidade');
      FormData formDataUnidade = FormData.fromMap({
        'selecionarUnidadeForm': 'selecionarUnidadeForm',
        'selecionarUnidadeForm:unidade': int.parse(codigoUnidade),
        'selecionarUnidadeForm:continuar': 'Continuar >>',
        'javax.faces.ViewState': viewStateAnterior,
      });
      // Código preenchido realizar a navegação daí.
      var paginaPonto = await dio.post(unidadeSuffix, data: formDataUnidade, options: optionsPost);
      realizarNavegacao(paginaPonto, dio, entradaSaidaSuffix, optionsPost, cookieJar);
    }
  }

  // acho que nao está sendo utilizado ainda
  Future realizarLogoff(Dio dio, Options optionsPost) async {
    const urlLogoff = '/sigrh/LogOff';
    var retornoLogoff;
    try {
      retornoLogoff = await dio.get(urlLogoff, options: optionsPost);
    } on DioError catch (e) {
      retornoLogoff = await followRedirect(e, dio);
    }
    return true;
  }

  // Segue os redirects de posts em 302, gets ele ja segue automatico
  Future followRedirect(DioError e, Dio dio) async {
    if (e.response != null && e.response!.statusCode == 302) {
      var locationRedirect = e.response!.headers.value('location');
      try {
        var redirect = await dio.get(locationRedirect ?? '');
        return redirect;
      } on DioError catch (e) {
        return followRedirect(e, dio);
      }
    }
  }

  // Segue os redirects de posts em 302, gets ele ja segue automatico
  Future followLoginRedirect(DioError e, Dio dio, CookieJar cookieJar) async {
    if (e.response != null && e.response!.statusCode == 302) {
      var locationRedirect = e.response!.headers.value('location');
      cookieJar.loadForRequest(Uri.parse(locationRedirect!));
      try {
        var redirect = await dio.get(locationRedirect, options: Options(followRedirects: false));
        return redirect;
      } on DioError catch (e) {
        return followLoginRedirect(e, dio, cookieJar);
      }
    }
  }

  // extrai do dom o valor do view state
  String buscarViewState(Document pagina) {
    var inputViewState = pagina.getElementsByTagName('input');
    var viewStateValue = '';
    inputViewState.forEach((input) => {
          if (input.attributes['id'] == 'javax.faces.ViewState')
            {
              viewStateValue = input.attributes['value'].toString(),
            }
        });
    return viewStateValue;
  }

  /* -------------------------------------------------------------------------- */
  /*                      Métodos para agendar notificações                     */
  /* -------------------------------------------------------------------------- */
  void inicializarPluginNotificacoes() {
    const initializationSettingsAndroid = AndroidInitializationSettings('app_icon24');
    const initializationSettings = InitializationSettings(android: initializationSettingsAndroid);
    flutterLocalNotificationsPlugin.initialize(initializationSettings, onSelectNotification: null);
  }

  Future marcarNotificacao(int id, int hora, int minuto, String texto, String titulo) async {
    var scheduledNotificationDateTime = DateTime.now().add(Duration(hours: hora, minutes: minuto));
    var androidPlatformChannelSpecifics =
        const AndroidNotificationDetails('ponto_unb', 'Ponto', channelDescription: 'Notificações para o ponto eletrônico');
    NotificationDetails platformChannelSpecifics = NotificationDetails(android: androidPlatformChannelSpecifics);
    await flutterLocalNotificationsPlugin.cancelAll();
    await flutterLocalNotificationsPlugin.schedule(id, titulo, texto, scheduledNotificationDateTime, platformChannelSpecifics);
  }

  /* -------------------------------------------------------------------------- */
  /*                            Métodos para horários                           */
  /* -------------------------------------------------------------------------- */
  // consistem apenas de calculo de data e hora e manipulação de string.
  DateTime getTempoMinimoAteSaida(List<String> horasRegistradas, int horasRegime, String ultimaEntrada) {
    var dateRegime = DateTime.utc(2000, 1, 1, horasRegime);
    var horasReg = int.parse(horasRegistradas[0].split(':')[0]);
    var minutosReg = int.parse(horasRegistradas[0].split(':')[1]);
    return dateRegime.subtract(Duration(hours: horasReg)).subtract(Duration(minutes: minutosReg));
  }

  String getTextoHorarioMinimoSaida(List<String> horasRegistradas, int horasRegime, String ultimaEntrada) {
    var dateSub = getTempoMinimoAteSaida(horasRegistradas, horasRegime, ultimaEntrada);
    var timeUltimaEntrada = DateTime.utc(2000, 1, 1, int.parse(ultimaEntrada.split(':')[0]), int.parse(ultimaEntrada.split(':')[1]));
    var dateReturn = timeUltimaEntrada.add(Duration(hours: dateSub.hour));
    dateReturn = dateReturn.add(Duration(minutes: dateSub.minute));
    dateReturn = dateReturn.subtract(const Duration(minutes: 15));
    var horasString = dateReturn.hour.toString();
    var minutosString = dateReturn.minute.toString();

    if (horasString.length == 1) {
      horasString = '0' + horasString;
    }
    if (minutosString.length == 1) {
      minutosString = '0' + minutosString;
    }

    return horasString + ':' + minutosString;
  }

  dynamic buscarHorariosEntradaSaida(Document dom) {
    // var horariosSemana = domPostLogin.querySelectorAll('form[name="formHorariosSemana"]');
    var textoTabela = 'Data                Entrada  Saída\n';
    var arrayDomHorarios = dom.querySelectorAll('form[name="formHorariosSemana"] > table > tbody > tr > td > span');
    var arrayHorarios = arrayDomHorarios.map((h) => h.innerHtml);
    var contadorLinha = 0;
    for (var h in arrayHorarios) {
      if (contadorLinha == 0) {
        textoTabela += (h + '    ');
      } else if (contadorLinha == 1) {
        textoTabela += (h + '    ');
      } else if (contadorLinha == 2) {
        textoTabela += (h + '\n');
        contadorLinha = -1;
      }
      contadorLinha += 1;
    }
    return textoTabela;
  }

  dynamic buscarUltimoHorarioEntrada(Document dom) {
    var arrayDomHorarios = dom.querySelectorAll('form[name="formHorariosSemana"] > table > tbody > tr > td > span');
    var arrayHorarios = arrayDomHorarios.map((h) => h.innerHtml);
    return arrayHorarios.elementAt(arrayHorarios.length - 1);
  }

  List<String> buscarHorasRegistradas(Document dom) {
    // retorna um array com [horas registradas, horas contabilizadas] formato HH:mm
    var horas = dom.querySelectorAll('tfoot > tr >td[style="font-weight: bold;"]');
    var retorno = List.empty(growable: true);
    if (horas.length >= 2) {
      retorno.add(horas[0].innerHtml);
      retorno.add(horas[1].innerHtml);
      return List.from(retorno);
    } else {
      return [];
    }
  }

  int getHorasRegime() {
    const horas = [4, 5, 6, 8];
    for (var i = 0; i < regimeIsSelected.length; i++) {
      if (regimeIsSelected[i]) {
        return horas[i];
      }
    }
    return 6;
  }

  /* -------------------------------------------------------------------------- */
  /*                            Metodos para o almoco                           */
  /* -------------------------------------------------------------------------- */
  // retorna um emoji de comida aleatorio para servir como sugestao de almoco
  String textoSaidaParaAlmoco() {
    var emojis = ['🌭', '🍔', '🍕', '🥪', '🥙', '🌮', '🌯', '🍝', '🍜', '🥗', '🍣', '🍤', '🥠', '🥘', '🍱', '🍲', '🍗'];
    return emojis[Random().nextInt(emojis.length)] + ' Realizando Saída para almoço';
  }

  // determina se estamos entre as 11 e as 15 horas
  bool isHoraAlmoco() {
    var now = TimeOfDay.now();
    return (now.hour >= 11 && now.hour < 15);
  }

  /* -------------------------------------------------------------------------- */
  /*                              Metodos de aviso                              */
  /* -------------------------------------------------------------------------- */
  // toda manipulacao de estado no flutter deve ser feita por meio de setState
  void aviso(String texto) {
    print(texto);
    setState(() {
      textoAviso += texto + '\n';
    });
  }

  //  marcar o isLoading como false corta a animacao de espera
  void avisoErro(String texto) {
    aviso(texto);
    setState(() {
      isLoading = false;
    });
  }

  void avisoVerboso(String texto) {
    if (verbose) {
      aviso(texto);
    }
  }

  /* -------------------------------------------------------------------------- */
  /*                         FRONT END DAQUI PRA FRENTE                         */
  /* -------------------------------------------------------------------------- */
  @override
  Widget build(BuildContext context) {
    final title = 'Pontão UnB';
    return Scaffold(
      appBar: AppBar(
        title: tx.Text(title),
      ),
      body: Column(
        mainAxisAlignment: MainAxisAlignment.start,
        children: [
          desenvolvimento
              ? tx.Text('Ambiente: Desenvolvimento')
              : Container(
                  height: 0,
                  width: 0,
                ),
          Expanded(
            flex: 1,
            child: Card(
                child: Container(
              padding: const EdgeInsets.all(8.0),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  login.length > 0
                      ? tx.Text(
                          'Usuário: ' + login + '\nRegime: ' + getHorasRegime().toString() + ' horas',
                          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                        )
                      : Center(
                          child: tx.Text('Primeiro uso, configure as credenciais no botão verde.',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w800,
                              )),
                        ),
                  Row(
                    children: [
                      Expanded(
                          child: isLoading
                              ? Center(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.stretch,
                                    children: <Widget>[
                                      LinearProgressIndicator(),
                                    ],
                                  ),
                                )
                              : confirmacao
                                  ? RaisedButton.icon(
                                      icon: Icon(Icons.done_all),
                                      textColor: Colors.white,
                                      color: Color.fromRGBO(0, 130, 46, 1),
                                      label: tx.Text('Certeza?', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 20)),
                                      onPressed: baterPonto,
                                      elevation: 15,
                                    )
                                  : RaisedButton.icon(
                                      icon: Icon(Icons.done),
                                      textColor: Colors.white,
                                      label: tx.Text('Bater Ponto', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 20)),
                                      onPressed: () => setState(() {
                                        confirmacao = true;
                                      }),
                                      elevation: 15,
                                    ))
                    ],
                  ),
                ],
              ),
            )),
          ),
          Expanded(
            flex: 2,
            child: SingleChildScrollView(
              padding: EdgeInsets.all(10),
              child: tx.Text(
                textoAviso,
                style: TextStyle(fontSize: 18),
              ),
            ),
          )
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: isLoading
            ? null
            : () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => PaginaConfiguracao()),
                ).whenComplete(() => {_loadCredentials(), setState(() {})});
              },
        disabledElevation: 0,
        elevation: 11,
        child: Icon(Icons.assignment_ind),
        backgroundColor: Colors.green,
      ),
    );
  }
}
