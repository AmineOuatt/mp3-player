import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:just_audio/just_audio.dart';

class QuranBrowserMode extends StatefulWidget {
  const QuranBrowserMode({super.key});

  @override
  State<QuranBrowserMode> createState() => _QuranBrowserModeState();
}

class _QuranBrowserModeState extends State<QuranBrowserMode> {
  // English UI items, Arabic search capable endpoints
  List<dynamic> _reciters = [];
  List<dynamic> _suwar = [];
  Map<String, String> _endpointStatus = {};

  bool _isLoading = true;
  String? _errorMessage;
  String _searchQuery = "";
  List<String> _favoriteReciterIds = [];
  bool _showFavoritesOnly = false;

  String _displayArabicName(dynamic item) {
    final ar = (item['name_ar'] ?? '').toString().trim();
    if (ar.isNotEmpty) return ar;
    return (item['name'] ?? '').toString();
  }

  @override
  void initState() {
    super.initState();
    _fetchData();
  }

  Future<void> _fetchData() async {
    final prefs = await SharedPreferences.getInstance();
    _favoriteReciterIds = prefs.getStringList('favorite_reciters') ?? [];

    setState(() {
      _isLoading = true;
      _errorMessage = null;
      _endpointStatus = {};
    });

    try {
      final suwarEngResult = await _fetchWithFallback(
        'https://www.mp3quran.net/api/v3/suwar?language=eng',
        'https://mp3quran.net/api/v3/suwar?language=eng',
      );
      final suwarArResult = await _fetchWithFallback(
        'https://www.mp3quran.net/api/v3/suwar?language=ar',
        'https://mp3quran.net/api/v3/suwar?language=ar',
      );
      final recitersEngResult = await _fetchWithFallback(
        'https://www.mp3quran.net/api/v3/reciters?language=eng',
        'https://mp3quran.net/api/v3/reciters?language=eng',
      );
      final recitersArResult = await _fetchWithFallback(
        'https://www.mp3quran.net/api/v3/reciters?language=ar',
        'https://mp3quran.net/api/v3/reciters?language=ar',
      );

      final suwarEng = _decodeListResponse(suwarEngResult.key, 'suwar');
      final suwarAr = _decodeListResponse(suwarArResult.key, 'suwar');
      final recitersEng = _decodeListResponse(
        recitersEngResult.key,
        'reciters',
      );
      final recitersAr = _decodeListResponse(recitersArResult.key, 'reciters');

      final baseSuwar = suwarEng.isNotEmpty ? suwarEng : suwarAr;
      final baseReciters = recitersEng.isNotEmpty ? recitersEng : recitersAr;

      final arSuwarById = {
        for (final s in suwarAr)
          s['id'].toString(): (s['name'] ?? '').toString(),
      };
      final arRecitersById = {
        for (final r in recitersAr)
          r['id'].toString(): (r['name'] ?? '').toString(),
      };

      final mergedSuwar = baseSuwar.map((raw) {
        final item = Map<String, dynamic>.from(raw as Map);
        item['name_ar'] = arSuwarById[item['id'].toString()] ?? item['name'];
        return item;
      }).toList();

      final mergedReciters = baseReciters.map((raw) {
        final item = Map<String, dynamic>.from(raw as Map);
        item['name_ar'] = arRecitersById[item['id'].toString()] ?? item['name'];
        return item;
      }).toList();

      if (!mounted) return;
      setState(() {
        _endpointStatus = {
          'suwar_eng': suwarEngResult.value,
          'suwar_ar': suwarArResult.value,
          'reciters_eng': recitersEngResult.value,
          'reciters_ar': recitersArResult.value,
        };
        _suwar = mergedSuwar;
        _reciters = mergedReciters;
        _isLoading = false;
        if (_reciters.isEmpty) {
          _errorMessage =
              'Could not load imams. Check internet connection and try again.';
        }
      });
    } catch (e) {
      debugPrint("Exception fetching data: $e");
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage =
              'Could not load imams. Check internet connection and try again.';
          _endpointStatus['exception'] = e.toString();
        });
      }
    }
  }

  Future<MapEntry<http.Response?, String>> _fetchWithFallback(
    String primaryUrl,
    String secondaryUrl,
  ) async {
    final attempts = <String>[];

    try {
      final response = await http
          .get(Uri.parse(primaryUrl))
          .timeout(const Duration(seconds: 12));
      if (response.statusCode == 200) {
        return MapEntry(response, 'ok 200 via www');
      }
      attempts.add('www:${response.statusCode}');
    } catch (e) {
      attempts.add('www:err ${e.runtimeType}');
    }

    try {
      final response = await http
          .get(Uri.parse(secondaryUrl))
          .timeout(const Duration(seconds: 12));
      if (response.statusCode == 200) {
        return MapEntry(response, 'ok 200 via root');
      }
      attempts.add('root:${response.statusCode}');
    } catch (e) {
      attempts.add('root:err ${e.runtimeType}');
    }

    return MapEntry(null, attempts.join(' | '));
  }

  List<dynamic> _decodeListResponse(http.Response? response, String key) {
    if (response == null) return [];
    try {
      final decoded = jsonDecode(utf8.decode(response.bodyBytes));
      if (decoded is Map<String, dynamic> && decoded[key] is List) {
        return decoded[key] as List<dynamic>;
      }
    } catch (_) {}
    return [];
  }

  Future<void> _toggleFavorite(String id) async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      if (_favoriteReciterIds.contains(id)) {
        _favoriteReciterIds.remove(id);
      } else {
        _favoriteReciterIds.add(id);
      }
    });
    await prefs.setStringList('favorite_reciters', _favoriteReciterIds);
  }

  void _openReciter(dynamic reciter) async {
    if (reciter['moshaf'] == null || (reciter['moshaf'] as List).isEmpty)
      return;

    // Automatically select the first moshaf
    final moshaf = reciter['moshaf'][0];

    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => SurahSelectionScreen(
          reciterName: _displayArabicName(reciter),
          moshaf: moshaf,
          suwarList: _suwar,
        ),
      ),
    );

    if (result != null && mounted) {
      Navigator.pop(context, result);
    }
  }

  @override
  Widget build(BuildContext context) {
    List<dynamic> filtered = _reciters.where((r) {
      final name = r['name'].toString().toLowerCase();
      final nameAr = (r['name_ar'] ?? '').toString().toLowerCase();
      final id = r['id'].toString();
      final q = _searchQuery.toLowerCase();

      bool matchesSearch = name.contains(q) || nameAr.contains(q);
      bool matchesFav = !_showFavoritesOnly || _favoriteReciterIds.contains(id);
      return matchesSearch && matchesFav;
    }).toList();

    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text(
          "Audio Library",
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 22,
            color: Colors.white,
          ),
        ),
      ),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF1F1F1F), Color(0xFF121212)],
            stops: [0.0, 0.45],
          ),
        ),
        child: _isLoading
            ? const Center(
                child: CircularProgressIndicator(color: Color(0xFF1DB954)),
              )
            : _errorMessage != null
            ? Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        _errorMessage!,
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: Colors.white70),
                      ),
                      const SizedBox(height: 12),
                      ElevatedButton(
                        onPressed: _fetchData,
                        child: const Text('Retry'),
                      ),
                    ],
                  ),
                ),
              )
            : Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16.0,
                      vertical: 12.0,
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Container(
                            height: 40,
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: TextField(
                              style: const TextStyle(
                                color: Colors.black,
                                fontSize: 14,
                              ),
                              decoration: const InputDecoration(
                                prefixIcon: Icon(
                                  Icons.search,
                                  color: Colors.black54,
                                ),
                                hintText: 'Search reciters...',
                                hintStyle: TextStyle(color: Colors.black54),
                                border: InputBorder.none,
                                contentPadding: EdgeInsets.symmetric(
                                  vertical: 10,
                                ),
                              ),
                              onChanged: (val) {
                                setState(() {
                                  _searchQuery = val;
                                });
                              },
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Container(
                          decoration: BoxDecoration(
                            color: _showFavoritesOnly
                                ? const Color(0xFF1DB954)
                                : Colors.transparent,
                            shape: BoxShape.circle,
                          ),
                          child: IconButton(
                            icon: Icon(
                              _showFavoritesOnly
                                  ? Icons.favorite
                                  : Icons.favorite_border,
                              color: _showFavoritesOnly
                                  ? Colors.white
                                  : Colors.white70,
                            ),
                            onPressed: () {
                              setState(() {
                                _showFavoritesOnly = !_showFavoritesOnly;
                              });
                            },
                          ),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: filtered.isEmpty
                        ? Center(
                            child: Text(
                              _searchQuery.isEmpty
                                  ? 'No imams found.'
                                  : 'No matching imams found.',
                              style: const TextStyle(color: Colors.white54),
                            ),
                          )
                        : ListView.builder(
                            itemCount: filtered.length,
                            padding: const EdgeInsets.only(bottom: 20),
                            itemBuilder: (context, index) {
                              final r = filtered[index];
                              final id = r['id'].toString();
                              final isFav = _favoriteReciterIds.contains(id);
                              return Container(
                                margin: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF181818),
                                  borderRadius: BorderRadius.circular(14),
                                ),
                                child: ListTile(
                                  contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 16,
                                    vertical: 6,
                                  ),
                                  leading: const CircleAvatar(
                                    backgroundColor: Color(0xFF282828),
                                    radius: 24,
                                    child: Icon(
                                      Icons.graphic_eq,
                                      color: Color(0xFF1DB954),
                                    ),
                                  ),
                                  title: Text(
                                    _displayArabicName(r),
                                    textDirection: TextDirection.rtl,
                                    textAlign: TextAlign.right,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  subtitle: const Text(
                                    "إمام",
                                    textDirection: TextDirection.rtl,
                                    textAlign: TextAlign.right,
                                    style: TextStyle(
                                      color: Colors.white54,
                                      fontSize: 12,
                                    ),
                                  ),
                                  trailing: IconButton(
                                    icon: Icon(
                                      isFav
                                          ? Icons.favorite
                                          : Icons.favorite_border,
                                      color: isFav
                                          ? const Color(0xFF1DB954)
                                          : Colors.white54,
                                    ),
                                    onPressed: () => _toggleFavorite(id),
                                  ),
                                  onTap: () => _openReciter(r),
                                ),
                              );
                            },
                          ),
                  ),
                ],
              ),
      ),
    );
  }
}

class SurahSelectionScreen extends StatefulWidget {
  final String reciterName;
  final dynamic moshaf;
  final List<dynamic> suwarList;

  const SurahSelectionScreen({
    super.key,
    required this.reciterName,
    required this.moshaf,
    required this.suwarList,
  });

  @override
  State<SurahSelectionScreen> createState() => _SurahSelectionScreenState();
}

class _SurahSelectionScreenState extends State<SurahSelectionScreen> {
  String _searchQuery = "";
  bool _isDownloading = false;
  double _downloadProgress = 0.0;
  String? _downloadingSurahId;
  String? _expandedSurahId;
  String? _localDirPath;

  final AudioPlayer _player = AudioPlayer();
  bool _isPlayingPreview = false;
  String? _previewingSurahId;

  @override
  void initState() {
    super.initState();
    _initDir();
    _player.playerStateStream.listen((state) {
      if (!mounted) return;
      final playing = state.playing;
      if (!playing && _isPlayingPreview) {
        setState(() {
          _isPlayingPreview = false;
          _previewingSurahId = null;
        });
      }
    });
  }

  Future<void> _initDir() async {
    final dir = await getApplicationDocumentsDirectory();
    if (mounted) {
      setState(() {
        _localDirPath = dir.path;
      });
    }
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  Future<void> _previewAudio(String surahId, String url) async {
    final isSameSurah = _previewingSurahId == surahId;
    if (_isPlayingPreview && isSameSurah) {
      await _player.stop();
      if (mounted) {
        setState(() {
          _isPlayingPreview = false;
          _previewingSurahId = null;
        });
      }
    } else {
      await _player.setUrl(url);
      await _player.play();
      if (mounted) {
        setState(() {
          _isPlayingPreview = true;
          _previewingSurahId = surahId;
        });
      }
    }
  }

  void _useAudioDirectly(dynamic surah, String audioPath) {
    String name = "${widget.reciterName} - ${surah['name']}";
    Navigator.pop(context, {'path': audioPath, 'name': name});
  }

  Future<void> _deleteSurah(dynamic surah) async {
    if (_localDirPath == null) return;
    final filename = "${widget.reciterName}_${surah['name']}.mp3".replaceAll(
      RegExp(r'[\\/:*?"<>|]'),
      '',
    );
    final file = File('$_localDirPath/$filename');
    if (file.existsSync()) {
      try {
        file.deleteSync();
        if (mounted) setState(() {});
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Deleted Successfully"),
            backgroundColor: Colors.redAccent,
          ),
        );
      } catch (e) {}
    }
  }

  Future<void> _downloadSurah(dynamic surah, String finalUrl) async {
    setState(() {
      _isDownloading = true;
      _downloadingSurahId = surah['id'].toString();
    });

    try {
      final request = http.Request('GET', Uri.parse(finalUrl));
      final response = await http.Client().send(request);
      final total = response.contentLength ?? 0;

      int downloadedBytes = 0;
      List<int> bytes = [];

      response.stream.listen(
        (chunk) {
          bytes.addAll(chunk);
          downloadedBytes += chunk.length;
          if (total != 0) {
            setState(() {
              _downloadProgress = downloadedBytes / total;
            });
          }
        },
        onDone: () async {
          final dir = await getApplicationDocumentsDirectory();
          final filename = "${widget.reciterName}_${surah['name']}.mp3"
              .replaceAll(RegExp(r'[\\/:*?"<>|]'), '');
          final file = File('${dir.path}/$filename');
          await file.writeAsBytes(bytes);

          if (mounted) {
            setState(() {
              _isDownloading = false;
              _downloadingSurahId = null;
            });
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text("Download Complete"),
                backgroundColor: Color(0xFF1DB954),
              ),
            );
          }
        },
        onError: (e) {
          setState(() {
            _isDownloading = false;
            _downloadingSurahId = null;
          });
        },
      );
    } catch (e) {
      if (mounted) {
        setState(() {
          _isDownloading = false;
          _downloadingSurahId = null;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final availableSurahs = widget.moshaf['surah_list'].toString().split(',');
    final filteredSuwar = widget.suwarList.where((s) {
      final name = s['name'].toString().toLowerCase();
      final nameAr = (s['name_ar'] ?? '').toString().toLowerCase();
      final q = _searchQuery.toLowerCase();

      bool matchesSearch = name.contains(q) || nameAr.contains(q);
      return availableSurahs.contains(s['id'].toString()) && matchesSearch;
    }).toList();

    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text(
          widget.reciterName,
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
        ),
      ),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF282828), Color(0xFF121212)],
            stops: [0.0, 0.4],
          ),
        ),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: 16.0,
                vertical: 12.0,
              ),
              child: Container(
                height: 40,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: TextField(
                  style: const TextStyle(color: Colors.black, fontSize: 14),
                  decoration: const InputDecoration(
                    prefixIcon: Icon(Icons.search, color: Colors.black54),
                    hintText: 'ابحث عن السورة...',
                    hintStyle: TextStyle(color: Colors.black54),
                    border: InputBorder.none,
                    contentPadding: EdgeInsets.symmetric(vertical: 10),
                  ),
                  onChanged: (val) {
                    setState(() {
                      _searchQuery = val;
                    });
                  },
                ),
              ),
            ),
            Expanded(
              child: ListView.builder(
                itemCount: filteredSuwar.length,
                padding: const EdgeInsets.only(bottom: 20),
                itemBuilder: (context, index) {
                  final s = filteredSuwar[index];
                  final surahIdStr = s['id'].toString().padLeft(3, '0');
                  final url = "${widget.moshaf['server']}$surahIdStr.mp3";

                  final filename = "${widget.reciterName}_${s['name']}.mp3"
                      .replaceAll(RegExp(r'[\\/:*?"<>|]'), '');
                  final bool fileExists =
                      _localDirPath != null &&
                      File('$_localDirPath/$filename').existsSync();

                  final isThisDownloading =
                      _isDownloading &&
                      _downloadingSurahId == s['id'].toString();
                  final isExpanded = _expandedSurahId == s['id'].toString();
                  final isPreviewingThis =
                      _isPlayingPreview &&
                      _previewingSurahId == s['id'].toString();

                  return Column(
                    children: [
                      ListTile(
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 4,
                        ),
                        leading: CircleAvatar(
                          backgroundColor: Colors.transparent,
                          child: Text(
                            s['id'].toString(),
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 16,
                            ),
                          ),
                        ),
                        title: Text(
                          (s['name_ar'] ?? s['name']).toString(),
                          textDirection: TextDirection.rtl,
                          textAlign: TextAlign.right,
                          style: TextStyle(
                            color: isExpanded
                                ? const Color(0xFF1DB954)
                                : Colors.white,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        trailing: Icon(
                          isExpanded
                              ? Icons.keyboard_arrow_up
                              : Icons.more_horiz,
                          color: Colors.white54,
                        ),
                        onTap: () async {
                          setState(() {
                            if (isExpanded) {
                              _expandedSurahId = null;
                              if (_isPlayingPreview) {
                                _player.stop();
                                _isPlayingPreview = false;
                                _previewingSurahId = null;
                              }
                            } else {
                              if (_isPlayingPreview) {
                                _player.stop();
                                _isPlayingPreview = false;
                                _previewingSurahId = null;
                              }
                              _expandedSurahId = s['id'].toString();
                            }
                          });
                        },
                      ),
                      if (isExpanded)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 12,
                          ),
                          color: Colors.black26,
                          child: Column(
                            children: [
                              Row(
                                children: [
                                  GestureDetector(
                                    onTap: () =>
                                        _previewAudio(s['id'].toString(), url),
                                    child: Container(
                                      width: 40,
                                      height: 40,
                                      decoration: const BoxDecoration(
                                        color: Color(0xFF1DB954),
                                        shape: BoxShape.circle,
                                      ),
                                      child: Icon(
                                        isPreviewingThis
                                            ? Icons.stop
                                            : Icons.play_arrow,
                                        color: Colors.black,
                                        size: 28,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: StreamBuilder<Duration?>(
                                      stream: _player.positionStream,
                                      builder: (context, posSnap) {
                                        return StreamBuilder<Duration?>(
                                          stream: _player.durationStream,
                                          builder: (context, durSnap) {
                                            final pos =
                                                posSnap.data ?? Duration.zero;
                                            final dur =
                                                durSnap.data ?? Duration.zero;
                                            double max = dur.inMilliseconds
                                                .toDouble();
                                            double val = pos.inMilliseconds
                                                .toDouble();
                                            if (val > max) val = max;
                                            if (max == 0) max = 1;
                                            return SliderTheme(
                                              data: SliderTheme.of(context).copyWith(
                                                trackHeight: 4.0,
                                                thumbShape:
                                                    const RoundSliderThumbShape(
                                                      enabledThumbRadius: 6.0,
                                                    ),
                                                overlayShape:
                                                    const RoundSliderOverlayShape(
                                                      overlayRadius: 12.0,
                                                    ),
                                              ),
                                              child: Slider(
                                                value: val,
                                                max: max,
                                                activeColor: const Color(
                                                  0xFF1DB954,
                                                ),
                                                inactiveColor: Colors.white24,
                                                onChanged: (v) {
                                                  _player.seek(
                                                    Duration(
                                                      milliseconds: v.toInt(),
                                                    ),
                                                  );
                                                },
                                              ),
                                            );
                                          },
                                        );
                                      },
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 12),
                              Row(
                                children: [
                                  Expanded(
                                    child: ElevatedButton(
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: Colors.transparent,
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(
                                            20,
                                          ),
                                          side: const BorderSide(
                                            color: Color(0xFF1DB954),
                                          ),
                                        ),
                                        foregroundColor: const Color(
                                          0xFF1DB954,
                                        ),
                                      ),
                                      onPressed: () => _useAudioDirectly(
                                        s,
                                        fileExists
                                            ? '$_localDirPath/$filename'
                                            : url,
                                      ),
                                      child: const Text("Use Audio"),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  if (isThisDownloading)
                                    Padding(
                                      padding: const EdgeInsets.all(8.0),
                                      child: SizedBox(
                                        width: 24,
                                        height: 24,
                                        child: CircularProgressIndicator(
                                          value: _downloadProgress,
                                          color: const Color(0xFF1DB954),
                                          strokeWidth: 3,
                                        ),
                                      ),
                                    )
                                  else if (fileExists)
                                    IconButton(
                                      icon: const Icon(
                                        Icons.delete_outline,
                                        color: Colors.redAccent,
                                      ),
                                      tooltip: "Delete",
                                      onPressed: () => _deleteSurah(s),
                                    )
                                  else
                                    IconButton(
                                      icon: const Icon(
                                        Icons.download_for_offline,
                                        color: Colors.white70,
                                      ),
                                      onPressed: () => _downloadSurah(s, url),
                                      tooltip: "Download",
                                    ),
                                ],
                              ),
                            ],
                          ),
                        ),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
