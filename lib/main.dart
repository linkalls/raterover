import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';

void main() {
  runApp(
    const ProviderScope(
      child: MyApp(),
    ),
  );
}

const currencyNames = {
  'USD': 'アメリカドル',
  'EUR': 'ユーロ',
  'JPY': '日本円',
  'GBP': 'イギリスポンド',
  'AUD': 'オーストラリアドル',
  'CAD': 'カナダドル',
  'CHF': 'スイスフラン',
  'CNY': '中国人民元',
  'HKD': '香港ドル',
  'NZD': 'ニュージーランドドル',
  'TWD': '台湾ドル',
  'KRW': '韓国ウォン',
  'SGD': 'シンガポールドル',
};

final themeProvider = StateProvider<ThemeMode>((ref) => ThemeMode.system);
final selectedFromCurrencyProvider = StateProvider<String>((ref) => 'USD');
final selectedToCurrencyProvider = StateProvider<String>((ref) => 'JPY');
final amountProvider = StateProvider<double>((ref) => 0.0);

final exchangeRatesProvider = StateNotifierProvider<ExchangeRatesNotifier, Map<String, double>>((ref) {
  return ExchangeRatesNotifier(ref);
});

class ExchangeRatesNotifier extends StateNotifier<Map<String, double>> {
  final Ref ref;
  static const baseUrl = 'https://cdn.jsdelivr.net/npm/@fawazahmed0/currency-api@latest/v1';
  
  ExchangeRatesNotifier(this.ref) : super({}) {
    loadRates();
  }

  Future<void> loadRates() async {
    final prefs = await SharedPreferences.getInstance();
    final lastUpdate = prefs.getString('lastUpdate');
    final savedRates = prefs.getString('exchangeRates');

    if (lastUpdate != null && savedRates != null) {
      final lastUpdateDate = DateTime.parse(lastUpdate);
      final now = DateTime.now();
      if (now.difference(lastUpdateDate).inDays < 1) {
        state = Map<String, double>.from(
          json.decode(savedRates).map((key, value) => MapEntry(key, value.toDouble()))
        );
        return;
      }
    }

    await fetchLatestRates();
  }

  Future<void> fetchLatestRates() async {
    try {
      debugPrint('Fetching exchange rates from API...');
      final fromCurrency = ref.read(selectedFromCurrencyProvider).toLowerCase();
      final response = await http.get(Uri.parse('$baseUrl/currencies/$fromCurrency.json'));
      debugPrint('API Response status: ${response.statusCode}');
      
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        debugPrint('API Response data: ${json.encode(data)}');
        final rates = data[fromCurrency] as Map<String, dynamic>;
        
        final newRates = <String, double>{};
        newRates[fromCurrency.toUpperCase()] = 1.0;
        
        for (final targetCurrency in currencyNames.keys) {
          final rate = rates[targetCurrency.toLowerCase()];
          if (rate is num) {
            newRates[targetCurrency] = rate.toDouble();
            debugPrint('Rate for $targetCurrency: ${rate.toDouble()}');
          }
        }

        debugPrint('Final rates: $newRates');
        state = newRates;

        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('exchangeRates', json.encode(newRates));
        await prefs.setString('lastUpdate', DateTime.now().toIso8601String());
        debugPrint('Rates saved to local storage');
      }
    } catch (e) {
      debugPrint('Error fetching exchange rates: $e');
      debugPrint('Error stack trace: ${StackTrace.current}');
    }
  }
}

class MyApp extends ConsumerWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(themeProvider);
    
    return MaterialApp(
      title: 'Currency Calculator',
      themeMode: themeMode,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.blue,
          brightness: Brightness.light,
        ),
        useMaterial3: true,
      ),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.blue,
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      home: const CurrencyCalculatorPage(),
    );
  }
}

class CurrencyCalculatorPage extends ConsumerWidget {
  const CurrencyCalculatorPage({super.key});

  double convertCurrency(double amount, String from, String to, Map<String, double> rates, WidgetRef ref) {
    if (rates.isEmpty) {
      debugPrint('No rates available, returning original amount');
      return amount;
    }
    
    debugPrint('Converting $amount $from to $to');
    debugPrint('Available rates: $rates');
    
    if (from != rates.keys.first) {
      ref.read(exchangeRatesProvider.notifier).fetchLatestRates();
      return amount;
    }

    final double rate = rates[to] ?? 1.0;
    debugPrint('Rate for $to: $rate');
    final result = amount * rate;
    debugPrint('Final result: $result');
    return result;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final fromCurrency = ref.watch(selectedFromCurrencyProvider);
    final toCurrency = ref.watch(selectedToCurrencyProvider);
    final amount = ref.watch(amountProvider);
    final themeMode = ref.watch(themeProvider);
    final rates = ref.watch(exchangeRatesProvider);

    final convertedAmount = convertCurrency(amount, fromCurrency, toCurrency, rates, ref);
    final numberFormat = NumberFormat('#,##0.00');

    return Scaffold(
      appBar: AppBar(
        title: const Text('通貨計算機'),
        actions: [
          IconButton(
            icon: Icon(
              themeMode == ThemeMode.dark ? Icons.light_mode : Icons.dark_mode,
            ),
            onPressed: () {
              ref.read(themeProvider.notifier).state = 
                themeMode == ThemeMode.dark ? ThemeMode.light : ThemeMode.dark;
            },
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  children: [
                    TextField(
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(
                        labelText: '金額を入力',
                        border: const OutlineInputBorder(),
                        suffixText: fromCurrency,
                      ),
                      onChanged: (value) {
                        ref.read(amountProvider.notifier).state = 
                          double.tryParse(value) ?? 0.0;
                      },
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: DropdownButtonFormField<String>(
                            value: fromCurrency,
                            decoration: const InputDecoration(
                              labelText: '変換元の通貨',
                              border: OutlineInputBorder(),
                            ),
                            items: currencyNames.keys.map((currency) {
                              return DropdownMenuItem(
                                value: currency,
                                child: Text('$currency (${currencyNames[currency]})'),
                              );
                            }).toList(),
                            onChanged: (value) {
                              if (value != null) {
                                ref.read(selectedFromCurrencyProvider.notifier).state = value;
                                ref.read(exchangeRatesProvider.notifier).fetchLatestRates();
                              }
                            },
                          ),
                        ),
                        const SizedBox(width: 16),
                        IconButton(
                          icon: const Icon(Icons.swap_horiz),
                          onPressed: () {
                            final temp = ref.read(selectedFromCurrencyProvider);
                            ref.read(selectedFromCurrencyProvider.notifier).state = 
                              ref.read(selectedToCurrencyProvider);
                            ref.read(selectedToCurrencyProvider.notifier).state = temp;
                            ref.read(exchangeRatesProvider.notifier).fetchLatestRates();
                          },
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: DropdownButtonFormField<String>(
                            value: toCurrency,
                            decoration: const InputDecoration(
                              labelText: '変換先の通貨',
                              border: OutlineInputBorder(),
                            ),
                            items: currencyNames.keys.map((currency) {
                              return DropdownMenuItem(
                                value: currency,
                                child: Text('$currency (${currencyNames[currency]})'),
                              );
                            }).toList(),
                            onChanged: (value) {
                              if (value != null) {
                                ref.read(selectedToCurrencyProvider.notifier).state = value;
                              }
                            },
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  children: [
                    const Text(
                      '変換結果',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '${numberFormat.format(convertedAmount)} $toCurrency',
                      style: const TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '1 $fromCurrency = ${numberFormat.format(convertCurrency(1, fromCurrency, toCurrency, rates, ref))} $toCurrency',
                      style: const TextStyle(
                        fontSize: 14,
                        color: Colors.grey,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
