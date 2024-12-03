import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_wallpaper_manager/flutter_wallpaper_manager.dart';
import 'package:hive/hive.dart';
import 'package:home_widget/home_widget.dart';
import 'package:home_widget_counter/presentation/custom_quotes.dart';
import 'package:home_widget_counter/provider/quotes_provider.dart';
import 'package:home_widget_counter/widgets/dialogs/widget_config_dialog.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';

import 'helper/settings_helper.dart';
import 'models/quote_model.dart';

// Interactive callback for HomeWidget to handle external requests
@pragma('vm:entry-point')
Future<void> interactiveCallback(Uri? uri) async {
  await HomeWidget.setAppGroupId('group.es.antonborri.homeWidgetCounter');
  if (uri?.host == 'fetchQuote') {
    await _fetchAndDisplayQuote();
  }
}

// Key to store quotes
const _quoteKey = 'quote';

// Fetch a new quote and display it in the widget
Future<void> _fetchAndDisplayQuote() async {
  final provider = QuoteProvider();
  await provider.fetchQuote();
  await HomeWidget.saveWidgetData(_quoteKey, provider.currentQuote);
  await HomeWidget.updateWidget(
    iOSName: 'QuoteWidget',
    androidName: 'QuoteWidgetProvider',
  );
  if (Platform.isAndroid) {
    await HomeWidget.updateWidget(androidName: 'QuoteGlanceWidgetReceiver');
  }
}

// Main Home Page widget
class QuoteHomePage extends StatefulWidget {
  const QuoteHomePage({super.key, required this.title});
  final String title;

  @override
  State<QuoteHomePage> createState() => _QuoteHomePageState();
}

class _QuoteHomePageState extends State<QuoteHomePage>
    with WidgetsBindingObserver {
  late Box<QuoteModel> quoteBox;
  Timer? _wallpaperChangeTimer;
  bool isApiEnabled = true; // Track API quotes switch

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    quoteBox = Hive.box<QuoteModel>('quotesBox');
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Provider.of<QuoteProvider>(context, listen: false).fetchQuote();
    });
    _initializeApiSettings();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (state == AppLifecycleState.resumed) {
      Provider.of<QuoteProvider>(context, listen: false).fetchQuote();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _wallpaperChangeTimer?.cancel();
    super.dispose();
  }

  Future<void> _initializeApiSettings() async {
    isApiEnabled = await SettingsHelper.isApiQuotesEnabled();
    if (isApiEnabled) {
      _startWallpaperChangeTimer();
    }
    setState(() {});
  }

  // Periodically fetch and update the wallpaper
  void _startWallpaperChangeTimer() {
    _wallpaperChangeTimer =
        Timer.periodic(const Duration(minutes: 1), (_) async {
      if (isApiEnabled) {
        final quoteProvider =
            Provider.of<QuoteProvider>(context, listen: false);
        await quoteProvider.fetchQuote();
        final newQuote = quoteProvider.currentQuote;
        await _setLiveWallpaper(newQuote);
      }
    });
  }

  Future<void> _fetchNewQuote() async {
    final quoteProvider = Provider.of<QuoteProvider>(context, listen: false);
    await quoteProvider.fetchQuote();
  }

  // Set live wallpaper for home screen, static for lock screen
  Future<void> _setLiveWallpaper(String quote) async {
    try {
      List<String> words = quote.split(' ');
      String animatedText = '';
      int index = 0;

      Timer.periodic(const Duration(milliseconds: 500), (timer) async {
        if (index < words.length) {
          animatedText += '${words[index]} ';
          index++;
          final imageFile = await _generateQuoteImage(animatedText.trim());
          await WallpaperManager.setWallpaperFromFile(
            imageFile.path,
            WallpaperManager.HOME_SCREEN,
          );
        } else {
          timer.cancel();
        }
      });

      final imageFile = await _generateQuoteImage(quote);
      await WallpaperManager.setWallpaperFromFile(
        imageFile.path,
        WallpaperManager.LOCK_SCREEN,
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to set wallpaper: $e'),
        ),
      );
    }
  }

  // Generate a PNG image of the quote
  Future<File> _generateQuoteImage(String quote) async {
    final screenWidth = MediaQuery.of(context).size.width;
    final screenHeight = MediaQuery.of(context).size.height;

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(
      recorder,
      Rect.fromPoints(Offset.zero, Offset(screenWidth, screenHeight)),
    );

    canvas.drawRect(
      Rect.fromLTWH(0, 0, screenWidth, screenHeight),
      Paint()..color = Colors.white,
    );

    double fontSize = 40.0;
    final textStyle = TextStyle(
      fontSize: fontSize,
      fontStyle: FontStyle.italic,
      color: Colors.black,
    );

    final textSpan = TextSpan(text: quote, style: textStyle);
    final textPainter = TextPainter(
      text: textSpan,
      textDirection: TextDirection.ltr,
    );

    textPainter.layout(maxWidth: screenWidth * 0.8);
    final offset = Offset(
      (screenWidth - textPainter.width) / 2,
      (screenHeight - textPainter.height) / 2,
    );
    textPainter.paint(canvas, offset);

    final picture = recorder.endRecording();
    final img =
        await picture.toImage(screenWidth.toInt(), screenHeight.toInt());
    final byteData = await img.toByteData(format: ui.ImageByteFormat.png);
    final buffer = byteData!.buffer.asUint8List();

    final directory = await getApplicationDocumentsDirectory();
    final file = File('${directory.path}/quote_image.png');
    await file.writeAsBytes(buffer);
    return file;
  }

  @override
  Widget build(BuildContext context) {
    final quoteProvider = Provider.of<QuoteProvider>(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        actions: [
          FutureBuilder<bool>(
            future: SettingsHelper.isApiQuotesEnabled(),
            builder: (context, snapshot) {
              final isApiEnabled = snapshot.data ?? true;
              return Switch(
                value: isApiEnabled,
                onChanged: (value) async {
                  await SettingsHelper.setApiQuotesEnabled(value);
                  setState(() {}); // Refresh UI
                },
                activeColor: Colors.green,
                inactiveThumbColor: Colors.red,
              );
            },
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 15.0, vertical: 10),
        child: SizedBox(
          child: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                const Text(
                  'Current Quote:',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 10),
                FutureBuilder<bool>(
                  future: SettingsHelper.isApiQuotesEnabled(),
                  builder: (context, snapshot) {
                    if (!snapshot.hasData) {
                      return const CircularProgressIndicator(); // Show progress while loading settings
                    }

                    final isApiEnabled = snapshot.data ?? true;

                    if (isApiEnabled) {
                      if (quoteProvider.isFetching) {
                        return const CircularProgressIndicator(); // Show progress while fetching from API
                      } else {
                        return Text(
                          quoteProvider.currentQuote,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 20,
                            fontStyle: FontStyle.italic,
                          ),
                        );
                      }
                    } else {
                      // Simulate loading state for Hive quotes
                      final localQuoteFuture = Future.delayed(
                        const Duration(milliseconds: 700),
                        _getRandomQuote,
                      );

                      return FutureBuilder<String?>(
                        future: localQuoteFuture,
                        builder: (context, localSnapshot) {
                          if (localSnapshot.connectionState ==
                              ConnectionState.waiting) {
                            return const CircularProgressIndicator(); // Show progress while loading local quote
                          }

                          if (localSnapshot.hasError) {
                            return const Text(
                              'Error fetching local quote',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 20,
                                fontStyle: FontStyle.italic,
                              ),
                            );
                          }

                          final randomQuote = localSnapshot.data;
                          return Text(
                            randomQuote ?? 'No quotes available locally',
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              fontSize: 20,
                              fontStyle: FontStyle.italic,
                            ),
                          );
                        },
                      );
                    }
                  },
                ),
                const SizedBox(
                  height: 30,
                ),
                ElevatedButton(
                  onPressed: _fetchNewQuote,
                  child: const Text('Fetch New Quote'),
                ),
                GestureDetector(
                  onTap: () async {
                    await showForm(context, 'Widget Configuration');
                  },
                  child: const Text('Pin Widget to Home Screen'),
                ),
                const SizedBox(height: 15),
                GestureDetector(
                  onTap: () async {
                    if (isApiEnabled && quoteProvider.currentQuote.isNotEmpty) {
                      await _setLiveWallpaper(quoteProvider.currentQuote);
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          backgroundColor: Colors.green,
                          content: Text('Wallpaper set successfully!'),
                        ),
                      );
                    } else {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          backgroundColor: Colors.red,
                          content:
                              Text('Failed: Enable API or no quotes available'),
                        ),
                      );
                    }
                  },
                  child: const Text('Set Quote to Wallpaper'),
                ),
                const SizedBox(height: 15),
                const Expanded(child: CustomQuotes()),
              ],
            ),
          ),
        ),
      ),
    );
  }

//Helper method to get a random quote from Hive
  String? _getRandomQuote() {
    final quoteBox = Hive.box<QuoteModel>('quotesBox');
    if (quoteBox.isEmpty) return null;
    final randomIndex = Random().nextInt(quoteBox.length);
    return quoteBox.getAt(randomIndex)?.quote;
  }
}
