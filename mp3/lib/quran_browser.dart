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

  bool _isLoading = true;
  String _searchQuery = "";
  List<String> _favoriteReciterIds = [];
  bool _showFavoritesOnly = false;

  @override
  void initState() {
    super.initState();
    _fetchData();
  }

  Future<void> _fetchData() async {
    final prefs = await SharedPreferences.getInstance();
    _favoriteReciterIds = prefs.getStringList('favorite_reciters') ?? [];

    setState(() => _isLoading = true);

    try {
      // Endpoints configured with ar to allow Arabic search data returned,
      final suwarResponse = await http.get(
        Uri.parse('https://mp3quran.net/api/v3/suwar?language=ar'),
      );
      final recitersResponse = await http.get(
        Uri.parse('https://mp3quran.net/api/v3/reciters?language=ar'),
      );

      if (suwarResponse.statusCode == 200 &&
          recitersResponse.statusCode == 200) {
        setState(() {
          _suwar = jsonDecode(suwarResponse.body)['suwar'];
          _reciters = jsonDecode(recitersResponse.body)['reciters'];
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
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
          reciterName: reciter['name'],
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
      final id = r['id'].toString();
      bool matchesSearch = name.contains(_searchQuery.toLowerCase());
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
        color: const Color(0xFF121212),
        child: _isLoading
            ? const Center(
                child: CircularProgressIndicator(color: Color(0xFF1DB954)),
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
                    child: ListView.builder(
                      itemCount: filtered.length,
                      padding: const EdgeInsets.only(bottom: 20),
                      itemBuilder: (context, index) {
                        final r = filtered[index];
                        final id = r['id'].toString();
                        final isFav = _favoriteReciterIds.contains(id);
                        return ListTile(
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 4,
                          ),
                          leading: const CircleAvatar(
                            backgroundColor: Color(0xFF282828),
                            radius: 25,
                            child: Icon(
                              Icons.person_outline,
                              color: Colors.white70,
                            ),
                          ),
                          title: Text(
                            r['name'],
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          subtitle: const Text(
                            "Reciter",
                            style: TextStyle(
                              color: Colors.white54,
                              fontSize: 12,
                            ),
                          ),
                          trailing: IconButton(
                            icon: Icon(
                              isFav ? Icons.favorite : Icons.favorite_border,
                              color: isFav
                                  ? const Color(0xFF1DB954)
                                  : Colors.white54,
                            ),
                            onPressed: () => _toggleFavorite(id),
                          ),
                          onTap: () => _openReciter(r),
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

  @override
  void initState() {
    super.initState();
    _initDir();
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

  Future<void> _previewAudio(String url) async {
    if (_isPlayingPreview) {
      await _player.pause();
      if (mounted) setState(() => _isPlayingPreview = false);
    } else {
      await _player.setUrl(url);
      await _player.play();
      if (mounted) setState(() => _isPlayingPreview = true);
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
      return availableSurahs.contains(s['id'].toString()) &&
          name.contains(_searchQuery.toLowerCase());
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
        color: const Color(0xFF121212),
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
                    hintText: 'Search surah...',
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
                          s['name'],
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
                                _player.pause();
                                _isPlayingPreview = false;
                              }
                            } else {
                              if (_isPlayingPreview) {
                                _player.pause();
                                _isPlayingPreview = false;
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
                          color: const Color(0xFF121212),
                          child: Column(
                            children: [
                              Row(
                                children: [
                                  GestureDetector(
                                    onTap: () => _previewAudio(url),
                                    child: Container(
                                      width: 40,
                                      height: 40,
                                      decoration: const BoxDecoration(
                                        color: Color(0xFF1DB954),
                                        shape: BoxShape.circle,
                                      ),
                                      child: Icon(
                                        _isPlayingPreview
                                            ? Icons.pause
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
