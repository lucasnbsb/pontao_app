import 'dart:ffi';
import 'dart:html';
import 'dart:math';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
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
          buttonTheme: const ButtonThemeData(
              buttonColor: Color.fromRGBO(0, 166, 235, 1))),
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

class _PaginaPontoState extends State<PaginaPonto> {
  final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
      FlutterLocalNotificationsPlugin();
  bool desenvolvimento = true;

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
  final entradaSaidaSuffix =
      '/sigrh/frequencia/ponto_eletronico/cadastro_ponto_eletronico.jsf';
  final servidorSuffix = '/sigrh/servidor/portal/servidor.jsf';
  final unidadeSuffix =
      '/sigrh/frequencia/ponto_eletronico/form_selecao_unidade.jsf';

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
      codigoController =
          TextEditingController(text: prefs.get('codigo').toString());
    }

    if (prefs.containsKey('almoco')) {
      setState(() {
        saidaAlmocoSePossivel = prefs.getBool('almoco') ?? true;
      });
    }

    if (prefs.containsKey('avisoHoras') && prefs.containsKey('avisoMinutos')) {
      setState(() {
        tempoAviso = TimeOfDay(
            hour: prefs.getInt('avisoHoras') ?? 1,
            minute: prefs.getInt('avisoMinutos') ?? 0);
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


    // verifica onde o login foi parar, tipicamente na página de ponto, mas pode ser outro lugar
  // determina o que fazer a partir daí, navegar para a página de ponto ou bater o ponto.
  // é aqui que o aplicativo descobre se ele ta batendo o ponto de entrada ou saída
  void realizarNavegacao(String postLoginData, String viewStateValue, Dio dio, String entradaSaidaRadix, Options optionsPost) async {
    var domPostLogin = parse(postLoginData);
    var viewStateNavegacao = buscarViewState(domPostLogin);

    if (postLoginData.contains('autenticar-se novamente')) {
      avisoErro('⛔ Sessão expirada, tente novamente');
      return;
    } else {
      var msgErro = domPostLogin.querySelectorAll('ul.erros > li');
      if (msgErro.length > 0) {
        avisoErro('⛔ ERRO: ' + msgErro[0].text);
        return;
      }
    }

    /* --- basicamente o switch pra saber onde está e o que fazer a partir dai -- */
    // tirei o logoff por algum motivo, nao lembro por que
    if (domPostLogin.querySelectorAll('input[name="idFormDadosEntradaSaida:idBtnRegistrarEntrada"]').length > 0) {
      aviso('⛵ Realizando Navegação');
      realizarEntrada(viewStateNavegacao, dio, entradaSaidaRadix, optionsPost);
      // realizarLogoff(dio, optionsPost);
    } else if (domPostLogin.querySelectorAll('input[name="idFormDadosEntradaSaida:idBtnRegistrarSaida"]').length > 0) {
      aviso('⛵ Realizando Navegação');
      realizarSaida(viewStateNavegacao, dio, entradaSaidaRadix, optionsPost);
      // realizarLogoff(dio, optionsPost);
    } else if (domPostLogin.querySelectorAll('form[name="painelAcessoDadosServidor"]').length > 0) {
      navegarParaPonto(viewStateNavegacao, dio, servidorSuffix, optionsPost);
    } else if (domPostLogin.querySelectorAll('select[name="selecionarUnidadeForm:unidade"]').length > 0) {
      selecionarUnidade(viewStateNavegacao, dio, servidorSuffix, optionsPost, domPostLogin);
    } else {
      var voltaParaInicio = await dio.get(servidorSuffix);
      var domVoltaParaInicio = parse(voltaParaInicio.data);
      var viewStateVolta = buscarViewState(domVoltaParaInicio);
      realizarNavegacao(voltaParaInicio.data, viewStateVolta, dio, entradaSaidaRadix, optionsPost);
    }
  }

    // bate o pojnto para a entrada, mmetade do método é o post e a outra
  // é buscar os horários registgrados e calcular o horario de saida
  Future realizarEntrada(String viewState, Dio dio, String entradaSaidaRadix, Options optionsPost) async {
    FormData formDataEntrada = FormData.from({
      'idFormDadosEntradaSaida': 'idFormDadosEntradaSaida',
      'idFormDadosEntradaSaida:observacoes': '',
      'idFormDadosEntradaSaida:idBtnRegistrarEntrada': 'Registrar Entrada',
      'javax.faces.ViewState': viewState,
    });
    aviso('🚪 Realizando Entrada');
    var postEntrada = await dio.post(entradaSaidaRadix, data: formDataEntrada, options: optionsPost);
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
  Future realizarSaida(String viewState, Dio dio, String entradaSaidaRadix, Options optionsPost) async {
    var almoco = false;
    if (regimeIsSelected[3]) {
      almoco = saidaAlmocoSePossivel && isHoraAlmoco();
    }

    FormData formDataEntrada = FormData.from({
      'idFormDadosEntradaSaida': 'idFormDadosEntradaSaida',
      'idFormDadosEntradaSaida:observacoes': '',
      'idFormDadosEntradaSaida:saidaAlmoco': almoco.toString(),
      'idFormDadosEntradaSaida:idBtnRegistrarSaida': 'Registrar Saída',
      'javax.faces.ViewState': viewState,
    });

    if (desenvolvimento || almoco) {
      aviso(textoSaidaParaAlmoco());
    } else {
      aviso('🎉 Realizando Saída');
    }

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
  Future navegarParaPonto(String viewStateAnterior, Dio dio, String servidorRadix, Options optionsPost) async {
    FormData formDataPonto = FormData.from({
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
    var domPaginaPonto = parse(paginaPonto.data);
    var viewState = buscarViewState(domPaginaPonto);
    realizarNavegacao(paginaPonto.data, viewState, dio, entradaSaidaSuffix, optionsPost);
  }

  // nao é preciso interagir com o dropdown, apenas colocar o valor correto nos dados do form
  Future selecionarUnidade(String viewStateAnterior, Dio dio, String servidorRadix, Options optionsPost, html.Document dom) async {
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
      FormData formDataUnidade = FormData.from({
        'selecionarUnidadeForm': 'selecionarUnidadeForm',
        'selecionarUnidadeForm:unidade': int.parse(codigoUnidade),
        'selecionarUnidadeForm:continuar': 'Continuar >>',
        'javax.faces.ViewState': viewStateAnterior,
      });
      // Código preenchido realizar a navegação daí.
      var paginaPonto = await dio.post(unidadeSuffix, data: formDataUnidade, options: optionsPost);
      var domPaginaPonto = parse(paginaPonto.data);
      var viewStateUnidade = buscarViewState(domPaginaPonto);
      realizarNavegacao(paginaPonto.data, viewStateUnidade, dio, entradaSaidaSuffix, optionsPost);
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

  // extrai do dom o valor do view state
  String buscarViewState(Document pagina) {
    var inputViewState = pagina.getElementsByTagName('input');
    var viewStateValue = '';
    inputViewState.forEach((input) => {
          if (input.parent!.id == 'javax.faces.ViewState')
            {
              viewStateValue = input.parent!.attributes['value'].toString() ,
            }
        });
    return viewStateValue;
  }

  /* -------------------------------------------------------------------------- */
  /*                      Métodos para agendar notificações                     */
  /* -------------------------------------------------------------------------- */
  void inicializarPluginNotificacoes() {
    const initializationSettingsAndroid =
        AndroidInitializationSettings('app_icon24');
    const initializationSettings =
        InitializationSettings(android: initializationSettingsAndroid);
    flutterLocalNotificationsPlugin.initialize(initializationSettings,
        onSelectNotification: null);
  }

  Future marcarNotificacao(int id, int hora, int minuto, String texto, String titulo) async {
    var scheduledNotificationDateTime =
        DateTime.now().add(Duration(hours: hora, minutes: minuto));
    var androidPlatformChannelSpecifics = const AndroidNotificationDetails(
        'ponto_unb', 'Ponto',
        channelDescription: 'Notificações para o ponto eletrônico');
    NotificationDetails platformChannelSpecifics =
        NotificationDetails(android: androidPlatformChannelSpecifics);
    await flutterLocalNotificationsPlugin.cancelAll();
    await flutterLocalNotificationsPlugin.schedule(id, titulo, texto,
        scheduledNotificationDateTime, platformChannelSpecifics);
  }

  /* -------------------------------------------------------------------------- */
  /*                            Métodos para horários                           */
  /* -------------------------------------------------------------------------- */
  // consistem apenas de calculo de data e hora e manipulação de string.
  DateTime getTempoMinimoAteSaida(
      List<String> horasRegistradas, int horasRegime, String ultimaEntrada) {
    var dateRegime = DateTime.utc(2000, 1, 1, horasRegime);
    var horasReg = int.parse(horasRegistradas[0].split(':')[0]);
    var minutosReg = int.parse(horasRegistradas[0].split(':')[1]);
    return dateRegime
        .subtract(Duration(hours: horasReg))
        .subtract(Duration(minutes: minutosReg));
  }

  String getTextoHorarioMinimoSaida(
      List<String> horasRegistradas, int horasRegime, String ultimaEntrada) {
    var dateSub =
        getTempoMinimoAteSaida(horasRegistradas, horasRegime, ultimaEntrada);
    var timeUltimaEntrada = DateTime.utc(
        2000,
        1,
        1,
        int.parse(ultimaEntrada.split(':')[0]),
        int.parse(ultimaEntrada.split(':')[1]));
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
    var arrayDomHorarios = dom.querySelectorAll(
        'form[name="formHorariosSemana"] > table > tbody > tr > td > span');
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
    var arrayDomHorarios = dom.querySelectorAll(
        'form[name="formHorariosSemana"] > table > tbody > tr > td > span');
    var arrayHorarios = arrayDomHorarios.map((h) => h.innerHtml);
    return arrayHorarios.elementAt(arrayHorarios.length - 1);
  }

  List<String> buscarHorasRegistradas(Document dom) {
    // retorna um array com [horas registradas, horas contabilizadas] formato HH:mm
    var horas =
        dom.querySelectorAll('tfoot > tr >td[style="font-weight: bold;"]');
    var retorno = List.empty();
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

  @override
  Widget build(BuildContext context) {
    // This method is rerun every time setState is called, for instance as done
    // by the _incrementCounter method above.
    //
    // The Flutter framework has been optimized to make rerunning build methods
    // fast, so that you can just rebuild anything that needs updating rather
    // than having to individually change instances of widgets.
    return Scaffold(
      appBar: AppBar(
        // Here we take the value from the MyHomePage object that was created by
        // the App.build method, and use it to set our appbar title.
        title: Text(widget.title),
      ),
      body: Center(
        // Center is a layout widget. It takes a single child and positions it
        // in the middle of the parent.
        child: Column(
          // Column is also a layout widget. It takes a list of children and
          // arranges them vertically. By default, it sizes itself to fit its
          // children horizontally, and tries to be as tall as its parent.
          //
          // Invoke "debug painting" (press "p" in the console, choose the
          // "Toggle Debug Paint" action from the Flutter Inspector in Android
          // Studio, or the "Toggle Debug Paint" command in Visual Studio Code)
          // to see the wireframe for each widget.
          //
          // Column has various properties to control how it sizes itself and
          // how it positions its children. Here we use mainAxisAlignment to
          // center the children vertically; the main axis here is the vertical
          // axis because Columns are vertical (the cross axis would be
          // horizontal).
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            const Text(
              'You have pushed the button this many times:',
            ),
            Text(
              'AAA',
              style: Theme.of(context).textTheme.headline4,
            ),
          ],
        ),
      ),
      floatingActionButton: const FloatingActionButton(
        onPressed: null,
        tooltip: 'Increment',
        child: Icon(Icons.add),
      ), // This trailing comma makes auto-formatting nicer for build methods.
    );
  }
}
