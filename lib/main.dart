import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

final GlobalKey<ScaffoldMessengerState> scaffoldMessengerKey =
    GlobalKey<ScaffoldMessengerState>();

Future<Pokemon> fetchPokemon(int id) async {
  final uri = Uri.parse('https://pokeapi.co/api/v2/pokemon/$id');
  try {
    final res = await http.get(uri).timeout(const Duration(seconds: 10));
    if (res.statusCode == 200) {
      return Pokemon.fromJson(jsonDecode(res.body) as Map<String, dynamic>);
    }
    if (res.statusCode == 404) {
      throw PokemonNotFound(id);
    }
    throw Exception('Failed to load Pokémon (HTTP ${res.statusCode})');
  } on TimeoutException {
    throw Exception('Request timed out');
  }
}

class PokemonNotFound implements Exception {
  final int id;
  PokemonNotFound(this.id);
  @override
  String toString() => 'No Pokémon with id=$id';
}

class Pokemon {
  final int id;
  final String name;
  final int height;
  final int weight;
  final String? sprite;

  const Pokemon({
    required this.id,
    required this.name,
    required this.height,
    required this.weight,
    this.sprite,
  });

  factory Pokemon.fromJson(Map<String, dynamic> json) {
    return switch (json) {
      {
        'id': int id,
        'name': String name,
        'height': int height,
        'weight': int weight,
        'sprites': Map<String, dynamic> sprites,
      } =>
        Pokemon(
          id: id,
          name: name,
          height: height,
          weight: weight,
          sprite: sprites['front_default'] as String?,
        ),
      _ => throw const FormatException('Unexpected JSON shape for Pokemon'),
    };
  }
}

void main() => runApp(const MyApp());

class MyApp extends StatefulWidget {
  const MyApp({super.key});
  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  static const int minId = 1;
  static const int maxId = 151;

  int _currentId = minId;
  late Future<Pokemon> _futurePokemon;
  bool _loading = false;

  late final TextEditingController _idCtrl = TextEditingController(
    text: '$minId',
  );

  @override
  void initState() {
    super.initState();
    _futurePokemon = fetchPokemon(_currentId);
  }

  void _showSnack(String msg) {
    final m = scaffoldMessengerKey.currentState;
    m?.hideCurrentSnackBar();
    m?.showSnackBar(SnackBar(content: Text(msg)));
  }

  void _syncIdField() {
    _idCtrl.text = '$_currentId';
  }

  Future<void> _startFetch(int id) async {
    setState(() {
      _currentId = id;
      _loading = true;
      _syncIdField();
      _futurePokemon = fetchPokemon(_currentId);
    });
    try {
      await _futurePokemon;
    } catch (e) {
      if (mounted) _showSnack('Failed to load id=$id\n$e');
      rethrow;
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _next() {
    final base = _currentId.clamp(minId, maxId);
    final nextId = (base + 1) > maxId ? minId : base + 1;
    _startFetch(nextId);
  }

  void _prev() {
    final base = _currentId.clamp(minId, maxId);
    final prevId = (base - 1) < minId ? maxId : base - 1;
    _startFetch(prevId);
  }

  void _jumpToTypedId() {
    FocusScope.of(context).unfocus();
    final raw = _idCtrl.text.trim();
    final parsed = int.tryParse(raw);
    if (parsed == null) {
      _showSnack('Enter a valid number');
      return;
    }
    if (parsed > maxId) {
      _showSnack('Pokémon IDs go up to $maxId. Try 1–$maxId.');
      return;
    }
    _startFetch(parsed);
  }

  Future<void> _pullToRefresh() async => _startFetch(_currentId);

  @override
  void dispose() {
    _idCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Pokémon Prev/Next Demo',
      theme: ThemeData(useMaterial3: true, colorSchemeSeed: Colors.redAccent),
      scaffoldMessengerKey: scaffoldMessengerKey,
      home: Scaffold(
        appBar: AppBar(
          title: const Text('Pokémon Demo'),
          actions: [
            IconButton(
              onPressed: _loading ? null : _prev,
              tooltip: 'Previous Pokémon',
              icon: const Icon(Icons.navigate_before),
            ),
            IconButton(
              onPressed: _loading ? null : _next,
              tooltip: 'Next Pokémon',
              icon: const Icon(Icons.navigate_next),
            ),
            IconButton(
              onPressed: _loading ? null : () => _startFetch(_currentId),
              tooltip: 'Refresh',
              icon: const Icon(Icons.refresh),
            ),
          ],
        ),
        body: RefreshIndicator(
          onRefresh: _pullToRefresh,
          child: FutureBuilder<Pokemon>(
            future: _futurePokemon,
            builder: (context, snapshot) {
              Widget child;

              if (snapshot.connectionState == ConnectionState.waiting ||
                  _loading) {
                child = const Center(child: CircularProgressIndicator());
              } else if (snapshot.hasError) {
                final err = snapshot.error;
                final msg = (err is PokemonNotFound)
                    ? err.toString()
                    : 'Error: $err';
                child = Center(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(msg, textAlign: TextAlign.center),
                        const SizedBox(height: 12),
                        FilledButton.icon(
                          onPressed: () => _startFetch(_currentId),
                          icon: const Icon(Icons.refresh),
                          label: const Text('Retry'),
                        ),
                      ],
                    ),
                  ),
                );
              } else {
                final p = snapshot.data!;
                final displayName = p.name.isEmpty
                    ? 'Unknown'
                    : '${p.name[0].toUpperCase()}${p.name.substring(1)}';
                child = Padding(
                  padding: const EdgeInsets.all(16),
                  child: Card(
                    child: ListTile(
                      leading: (p.sprite != null)
                          ? Image.network(p.sprite!, width: 56, height: 56)
                          : CircleAvatar(child: Text('${p.id}')),
                      title: Text(displayName),
                      subtitle: Text(
                        'height: ${p.height} • weight: ${p.weight}',
                      ),
                      trailing: FilledButton(
                        onPressed: _loading ? null : _next,
                        child: const Text('Next'),
                      ),
                    ),
                  ),
                );
              }

              return SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    minHeight: MediaQuery.of(context).size.height * 0.6,
                  ),
                  child: child,
                ),
              );
            },
          ),
        ),
        bottomNavigationBar: Padding(
          padding: const EdgeInsets.all(8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              FilledButton(
                onPressed: _loading ? null : _prev,
                child: const Text('Prev'),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  controller: _idCtrl,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: InputDecoration(
                    labelText:
                        'Jump to ID ($minId–$maxId shown; any id allowed)',
                    border: const OutlineInputBorder(),
                    isDense: true,
                  ),
                  onSubmitted: (_) => _jumpToTypedId(),
                ),
              ),
              const SizedBox(width: 8),
              FilledButton.tonal(
                onPressed: _loading ? null : _jumpToTypedId,
                child: const Text('Go'),
              ),
              const SizedBox(width: 12),
              FilledButton(
                onPressed: _loading ? null : _next,
                child: const Text('Next'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
