import 'dart:io';

import 'package:flutter/material.dart';
import 'package:hive_flutter/adapters.dart';
import 'package:home_widget/home_widget.dart';
import 'package:home_widget_counter/dash_with_sign.dart';
import 'package:home_widget_counter/models/tag_model.dart';
import 'package:home_widget_counter/provider/quotes_provider.dart';
import 'package:home_widget_counter/provider/tag_provider.dart';
import 'package:home_widget_counter/quote_home_page.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'helper/native_bridge.dart';
import 'models/quote_model.dart';

Future<void> main() async {

  // Hive Database
  await Hive.initFlutter();
  Hive.registerAdapter(QuoteModelAdapter());
  Hive.registerAdapter(TagModelAdapter());
  await Hive.openBox<QuoteModel>('quotesBox');
  await Hive.openBox<TagModel>('tagsBox');

  await SharedPreferences.getInstance();
  NativeBridge.registerMethods();

  WidgetsFlutterBinding.ensureInitialized();
  // Set AppGroup Id. This is needed for iOS Apps to talk to their WidgetExtensions
  await HomeWidget.setAppGroupId('group.es.antonborri.homeWidgetCounter');
  await HomeWidget.setAppGroupId('group.es.antonborri.homeWidgetCounter');
  // Register an Interactivity Callback. It is necessary that this method is static and public
  await HomeWidget.registerInteractivityCallback(interactiveCallback);
  runApp(const MyApp());
}

/// Callback invoked by HomeWidget Plugin when performing interactive actions
/// The @pragma('vm:entry-point') Notification is required so that the Plugin can find it
@pragma('vm:entry-point')
Future<void> interactiveCallback(Uri? uri) async {
  // Set AppGroup Id. This is needed for iOS Apps to talk to their WidgetExtensions
  await HomeWidget.setAppGroupId('group.es.antonborri.homeWidgetCounter');

  // We check the host of the uri to determine which action should be triggered.
  if (uri?.host == 'increment') {
    await _increment();
  } else if (uri?.host == 'clear') {
    await _clear();
  }
}

const _countKey = 'counter';

/// Gets the currently stored Value
Future<int> get _value async {
  final value = await HomeWidget.getWidgetData<int>(_countKey, defaultValue: 0);
  return value!;
}

/// Retrieves the current stored value
/// Increments it by one
/// Saves that new value
/// @returns the new saved value
Future<int> _increment() async {
  final oldValue = await _value;
  final newValue = oldValue + 1;
  await _sendAndUpdate(newValue);
  return newValue;
}

/// Clears the saved Counter Value
Future<void> _clear() async {
  await _sendAndUpdate(null);
}

/// Stores [value] in the Widget Configuration
Future<void> _sendAndUpdate([int? value]) async {
  await HomeWidget.saveWidgetData(_countKey, value);
  await HomeWidget.renderFlutterWidget(
    DashWithSign(count: value ?? 0),
    key: 'dash_counter',
    logicalSize: const Size(100, 100),
  );
  await HomeWidget.updateWidget(
    iOSName: 'CounterWidget',
    androidName: 'CounterWidgetProvider',
  );

  if (Platform.isAndroid) {
    // Update Glance Provider
    await HomeWidget.updateWidget(androidName: 'CounterGlanceWidgetReceiver');
  }
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => QuoteProvider()),
        ChangeNotifierProvider(create: (_) => TagProvider())
      ],
      child: MaterialApp(
        title: 'Flutter Demo',
        theme: ThemeData.light(
          useMaterial3: false,
        ),
        // home: const MyHomePage(title: 'Flutter Demo Home Page'),
        home: const QuoteHomePage(title: 'Quotes'),
      ),
    );
  }
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key, required this.title});

  final String title;

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  Future<void> _incrementCounter() async {
    await _increment();
    setState(() {});
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (state == AppLifecycleState.resumed) {
      setState(() {});
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Future<void> _requestToPinWidget() async {
    final isRequestPinSupported =
    await HomeWidget.isRequestPinWidgetSupported();
    if (isRequestPinSupported == true) {
      await HomeWidget.requestPinWidget(
        androidName: 'CounterGlanceWidgetReceiver',
      );
    }
  }

  Future<void> _checkInstalledWidgets() async {
    final installedWidgets = await HomeWidget.getInstalledWidgets();

    debugPrint(installedWidgets.toString());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            const Text(
              'You have pushed the button this many times:',
            ),
            FutureBuilder<int>(
              future: _value,
              builder: (_, snapshot) => Column(
                children: [
                  Text(
                    (snapshot.data ?? 0).toString(),
                    style: Theme.of(context).textTheme.headlineMedium,
                  ),
                  GestureDetector(
                    onTap: _requestToPinWidget,
                    onLongPress: _checkInstalledWidgets,
                    child: DashWithSign(count: snapshot.data ?? 0),
                  ),
                ],
              ),
            ),
            TextButton(
              onPressed: () async {
                await _clear();
                setState(() {});
              },
              child: const Text('Clear'),
            ),
            InkWell(
              onTap: () {
                Navigator.push(context, MaterialPageRoute(builder: (_) => QuoteHomePage(title: "Quotes")));
              },
              child: const Text(
                  "Goto Next Page"
              ),
            )
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _incrementCounter,
        tooltip: 'Increment',
        child: const Icon(Icons.add),
      ),
    );
  }
}