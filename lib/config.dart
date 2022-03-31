import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class PaginaConfiguracao extends StatefulWidget {
  PaginaConfiguracao() : super();

  _PaginaConfiguracaoState createState() => _PaginaConfiguracaoState();
}

class _PaginaConfiguracaoState extends State<PaginaConfiguracao> {
  TextEditingController loginController = TextEditingController();
  TextEditingController passController = TextEditingController();
  TextEditingController codigoController = TextEditingController();
  TimeOfDay tempoAviso = TimeOfDay(hour: 1, minute: 0);
  bool saidaAlmocoSePossivel = true;
  bool avisarSaidaAntes = false;
  var regimeIsSelected = [false, false, false, true];

  late SharedPreferences prefs;

  @override
  void initState() {
    _loadCredentials();
    tempoAviso = TimeOfDay(hour: 1, minute: 0);
  }

  @override
  void dispose() {
    loginController.dispose();
    passController.dispose();
    codigoController.dispose();
    super.dispose();
  }

  _loadCredentials() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    if (prefs.containsKey('login') && prefs.containsKey('pass')) {
      loginController = TextEditingController(text: prefs.get('login').toString());
      passController = TextEditingController(text: prefs.get('pass').toString());
    }

    if (prefs.containsKey('codigo')) {
      codigoController = TextEditingController(text: prefs.get('codigo').toString());
    }

    if (prefs.containsKey('almoco')) {
      setState(() {
        saidaAlmocoSePossivel = prefs.getBool('almoco')!;
      });
    }

    if (prefs.containsKey('avisoHoras') && prefs.containsKey('avisoMinutos')) {
      tempoAviso = TimeOfDay(hour: prefs.getInt('avisoHoras')!, minute: prefs.getInt('avisoMinutos')!);
    } else {
      tempoAviso = TimeOfDay(hour: 1, minute: 0);
    }

    // recupera o regime( int de 0 a 2 representando o botão selecionado)
    if (prefs.containsKey('regime')) {
      int regime = prefs.getInt('regime')!;
      if (regime < regimeIsSelected.length) {
        var isSelectedTemp = [false, false, false, false];
        isSelectedTemp[regime] = true;
        setState(() {
          regimeIsSelected = isSelectedTemp;
        });
      }
    }

    if (prefs.containsKey('avisarSaidaAntes')) {
      avisarSaidaAntes = prefs.getBool('avisarSaidaAntes')!;
    }
  }

  Future<bool> _saveCredentials() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    prefs.setString('login', loginController.text);
    prefs.setString('pass', passController.text);
    prefs.setString('codigo', codigoController.text);
    prefs.setBool('almoco', saidaAlmocoSePossivel);
    for (var i = 0; i < regimeIsSelected.length; i++) {
      if (regimeIsSelected[i]) {
        prefs.setInt('regime', i);
      }
    }
    prefs.setInt('avisoHoras', tempoAviso.hour);
    prefs.setInt('avisoMinutos', tempoAviso.minute);
    prefs.setBool('avisarSaidaAntes', avisarSaidaAntes);
    return Future.value(true);
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: () => _saveCredentials(),
      child: Scaffold(
          appBar: AppBar(
            title: const Text("Configurações"),
          ),
          body: Container(
            padding: const EdgeInsets.all(8.0),
            child: Column(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
              Form(
                child: Column(
                  children: <Widget>[
                    TextFormField(
                      decoration: const InputDecoration(labelText: 'Login'),
                      controller: loginController,
                    ),
                    TextFormField(
                      decoration: const InputDecoration(labelText: 'Senha'),
                      controller: passController,
                      obscureText: true,
                    ),
                    TextFormField(
                      decoration: const InputDecoration(labelText: 'Código da Unidade (OPCIONAL)'),
                      controller: codigoController,
                    ),
                  ],
                ),
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: <Widget>[
                  const Text('Regime: '),
                  ToggleButtons(
                    children: [
                      Text('   4 Horas   '),
                      Text('   5 Horas   '),
                      Text('   6 Horas   '),
                      Text('   8 Horas   '),
                    ],
                    onPressed: (int index) {
                      setState(() {
                        for (int buttonIndex = 0; buttonIndex < regimeIsSelected.length; buttonIndex++) {
                          if (buttonIndex == index) {
                            regimeIsSelected[buttonIndex] = true;
                          } else {
                            regimeIsSelected[buttonIndex] = false;
                          }
                        }
                      });
                    },
                    isSelected: regimeIsSelected,
                  ),
                ],
              ),
              regimeIsSelected[3]
                  ? CheckboxListTile(
                      value: saidaAlmocoSePossivel,
                      onChanged: (bool? valor) {
                        setState(() {
                          saidaAlmocoSePossivel = valor!;
                        });
                      },
                      title: Text('Saída para o almoço se possível?'),
                      secondary: const Icon(Icons.fastfood),
                    )
                  : Container(
                      width: 0,
                      height: 0,
                    ),
              SwitchListTile(
                  title: avisarSaidaAntes
                      ? const Text('Avisar o fim do expediente 5 minutos antes')
                      : const Text('Avisar o fim do expediente na hora'),
                  value: avisarSaidaAntes,
                  onChanged: (bool value) {
                    setState(() {
                      avisarSaidaAntes = value;
                    });
                  },
                  secondary: avisarSaidaAntes ? const Icon(Icons.directions_run) : const Icon(Icons.directions_walk)),
              RaisedButton(
                  child: Text('Avisar o retorno do almoço após ' + tempoAviso.format(context) + ' hora(s)',
                      style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                  textColor: Colors.white,
                  onPressed: () => {
                        showTimePicker(
                          context: context,
                          initialTime: TimeOfDay(hour: tempoAviso.hour, minute: tempoAviso.minute),
                          builder: (BuildContext context, Widget? child) {
                            return MediaQuery(
                              data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: false),
                              child: child!,
                            );
                          },
                        ).then((value) {
                          if (value != null) {
                            setState(() {
                              tempoAviso = value;
                            });
                          }
                        })
                      })
            ]),
          )),
    );
  }
}
