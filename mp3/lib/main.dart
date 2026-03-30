import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:just_audio/just_audio.dart';
import 'package:file_picker/file_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'quran_browser.dart';

// --- DATA MODELS ---

class LoopBookmark {
  final String id;
  String name;
  Duration start;
  Duration end;

  LoopBookmark({
    required this.id,
    required this.name,
    required this.start,
    required this.end,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'start': start.inMilliseconds,
    'end': end.inMilliseconds,
  };

  factory LoopBookmark.fromJson(Map<String, dynamic> json) => LoopBookmark(
    id: json['id'],
    name: json['name'],
    start: Duration(milliseconds: json['start']),
    end: Duration(milliseconds: json['end']),
  );
}

class SavedAudioEntry {
  final String path;
  String name;
  List<LoopBookmark> segments;

  SavedAudioEntry({
    required this.path,
    required this.name,
    List<LoopBookmark>? segments,
  }) : segments = segments ?? [];

  Map<String, dynamic> toJson() => {
    'path': path,
    'name': name,
    'segments': segments.map((s) => s.toJson()).toList(),
  };

  factory SavedAudioEntry.fromJson(Map<String, dynamic> json) =>
      SavedAudioEntry(
        path: json['path'],
        name: json['name'],
        segments: (json['segments'] as List)
            .map((s) => LoopBookmark.fromJson(s as Map<String, dynamic>))
            .toList(),
      );
}

// --- MAIN APP ---

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const AudioRepeaterApp());
}

class AudioRepeaterApp extends StatelessWidget {
  const AudioRepeaterApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Spotify Loop Studio',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF121212),
        primaryColor: const Color(0xFF1DB954),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF1DB954),
          secondary: Color(0xFF1ED760),
          surface: Color(0xFF181818),
        ),
        textTheme: GoogleFonts.plusJakartaSansTextTheme(
          ThemeData.dark().textTheme,
        ),
        useMaterial3: true,
      ),
      home: const AudioLooperScreen(),
    );
  }
}

// --- SCREENS ---

class AudioLooperScreen extends StatefulWidget {
  const AudioLooperScreen({super.key});

  @override
  State<AudioLooperScreen> createState() => _AudioLooperScreenState();
}

class _AudioLooperScreenState extends State<AudioLooperScreen> {
  final AudioPlayer _player = AudioPlayer();
  SharedPreferences? _prefs;

  List<SavedAudioEntry> _library = [];
  SavedAudioEntry? _currentEntry;

  bool _isPlaying = false;
  bool _isLooping = true;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;

  Duration _loopStart = Duration.zero;
  Duration _loopEnd = Duration.zero;

  List<double> _waveformSamples = [];
  String _segmentSearchQuery = "";

  @override
  void initState() {
    super.initState();
    _initApp();
  }

  Future<void> _initApp() async {
    _prefs = await SharedPreferences.getInstance();
    _loadLibrary();

    _player.positionStream.listen((pos) {
      if (!mounted) return;
      setState(() => _position = pos);

      // Auto-looping logic
      if (_isLooping && _loopEnd > Duration.zero && pos >= _loopEnd) {
        _player.seek(_loopStart);
      }
    });

    _player.durationStream.listen((dur) {
      if (!mounted) return;
      setState(() {
        _duration = dur ?? Duration.zero;
        if (_loopEnd == Duration.zero || _loopEnd > _duration) {
          _loopEnd = _duration;
        }
      });
    });

    _player.playerStateStream.listen((state) {
      if (!mounted) return;
      setState(() {
        _isPlaying = state.playing;
      });
      if (state.processingState == ProcessingState.completed) {
        if (_isLooping) {
          _player.seek(_loopStart);
          _player.play();
        } else {
          _player.seek(Duration.zero);
          _player.pause();
        }
      }
    });
  }

  void _loadLibrary() {
    final libraryJson = _prefs?.getString('library');
    if (libraryJson != null) {
      final List decoded = jsonDecode(libraryJson);
      setState(() {
        _library = decoded.map((e) => SavedAudioEntry.fromJson(e)).toList();
      });
    }
  }

  Future<void> _saveLibrary() async {
    final libraryJson = jsonEncode(_library.map((e) => e.toJson()).toList());
    await _prefs?.setString('library', libraryJson);
  }

  void _openOnlineQuranBrowser() async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => const QuranBrowserMode(),
        fullscreenDialog: true,
      ),
    );

    // If an audio was selected and downloaded or used online
    if (result != null && result is Map) {
      String path = result['path'].toString();
      String filename = result['name'].toString();

      // Auto-load it into the library
      bool exists = _library.any((entry) => entry.path == path);
      if (!exists) {
        setState(() {
          _library.add(
            SavedAudioEntry(path: path, name: filename, segments: []),
          );
        });
        _saveLibrary();
      }
      _loadFile(path, filename);
    }
  }

  Future<void> _importAudio() async {
    FilePickerResult? result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['mp3', 'wav', 'm4a', 'aac', 'ogg', 'flac'],
    );

    if (result != null && result.files.single.path != null) {
      final path = result.files.single.path!;
      final name = result.files.single.name;

      _loadFile(path, name);
    }
  }

  Future<void> _loadFile(String path, String name) async {
    try {
      if (path.startsWith('http://') || path.startsWith('https://')) {
        await _player.setUrl(path);
      } else {
        await _player.setFilePath(path);
      }

      // Update library
      int index = _library.indexWhere((e) => e.path == path);
      SavedAudioEntry entry;
      if (index == -1) {
        entry = SavedAudioEntry(path: path, name: name);
        _library.add(entry);
      } else {
        entry = _library[index];
      }

      setState(() {
        _currentEntry = entry;
        _loopStart = Duration.zero;
        _loopEnd = _duration;
      });

      _saveLibrary();
      _generateWaveform(path);
      _player.play();
    } catch (e) {
      debugPrint("Error loading file: $e");
    }
  }

  Future<void> _generateWaveform(String path) async {
    // A VERY simplified mock waveform generation for local files.
    // In a real app with just_audio, you might need a platform channel or a heavier dart package to decode PCM bytes.
    // Here we generate 96 mock values for demonstration purposes, mimicking a downsampled byte array.
    final rand = Random();
    List<double> samples = List.generate(
      96,
      (index) => rand.nextDouble() * 0.8 + 0.2,
    );

    setState(() {
      _waveformSamples = samples;
    });
  }

  void _upsertAudioEntry() {
    if (_currentEntry != null) {
      int index = _library.indexWhere((e) => e.path == _currentEntry!.path);
      if (index != -1) {
        _library[index] = _currentEntry!;
        _saveLibrary();
      }
    }
  }

  void _seekBy(Duration offset) {
    final target = _position + offset;
    final clamped = target < Duration.zero
        ? Duration.zero
        : (target > _duration ? _duration : target);
    _player.seek(clamped);
  }

  void _saveSegment() {
    if (_currentEntry == null) return;

    HapticFeedback.mediumImpact();
    TextEditingController controller = TextEditingController(
      text: "Segment ${_currentEntry!.segments.length + 1}",
    );

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF181818),
        title: const Text(
          'Save Loop Segment',
          style: TextStyle(color: Colors.white),
        ),
        content: TextField(
          controller: controller,
          style: const TextStyle(color: Colors.white),
          decoration: const InputDecoration(
            hintText: "Enter segment name",
            hintStyle: TextStyle(color: Colors.grey),
            enabledBorder: UnderlineInputBorder(
              borderSide: BorderSide(color: Colors.grey),
            ),
            focusedBorder: UnderlineInputBorder(
              borderSide: BorderSide(color: Color(0xFF1DB954)),
            ),
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(
            child: const Text('CANCEL', style: TextStyle(color: Colors.grey)),
            onPressed: () => Navigator.pop(context),
          ),
          TextButton(
            child: const Text(
              'SAVE',
              style: TextStyle(color: Color(0xFF1DB954)),
            ),
            onPressed: () {
              final newBookmark = LoopBookmark(
                id: DateTime.now().millisecondsSinceEpoch.toString(),
                name: controller.text.trim(),
                start: _loopStart,
                end: _loopEnd,
              );
              setState(() {
                _currentEntry!.segments.add(newBookmark);
              });
              _upsertAudioEntry();
              Navigator.pop(context);
            },
          ),
        ],
      ),
    );
  }

  void _deleteSegment(LoopBookmark segment) {
    setState(() {
      _currentEntry?.segments.removeWhere((s) => s.id == segment.id);
    });
    _upsertAudioEntry();
  }

  void _editSegmentName(LoopBookmark segment) {
    TextEditingController controller = TextEditingController(
      text: segment.name,
    );
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF181818),
        title: const Text(
          'Edit Segment Name',
          style: TextStyle(color: Colors.white),
        ),
        content: TextField(
          controller: controller,
          style: const TextStyle(color: Colors.white),
          decoration: const InputDecoration(
            hintText: "Enter new name",
            hintStyle: TextStyle(color: Colors.grey),
            enabledBorder: UnderlineInputBorder(
              borderSide: BorderSide(color: Colors.grey),
            ),
            focusedBorder: UnderlineInputBorder(
              borderSide: BorderSide(color: Color(0xFF1DB954)),
            ),
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(
            child: const Text('CANCEL', style: TextStyle(color: Colors.grey)),
            onPressed: () => Navigator.pop(context),
          ),
          TextButton(
            child: const Text(
              'SAVE',
              style: TextStyle(color: Color(0xFF1DB954)),
            ),
            onPressed: () {
              if (controller.text.trim().isNotEmpty) {
                setState(() {
                  segment.name = controller.text.trim();
                });
                _upsertAudioEntry();
              }
              Navigator.pop(context);
            },
          ),
        ],
      ),
    );
  }

  void _editLibraryAudioName(SavedAudioEntry entry) {
    TextEditingController controller = TextEditingController(text: entry.name);
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF181818),
        title: const Text(
          'Edit Audio Name',
          style: TextStyle(color: Colors.white),
        ),
        content: TextField(
          controller: controller,
          style: const TextStyle(color: Colors.white),
          decoration: const InputDecoration(
            hintText: "Enter new name",
            hintStyle: TextStyle(color: Colors.grey),
            enabledBorder: UnderlineInputBorder(
              borderSide: BorderSide(color: Colors.grey),
            ),
            focusedBorder: UnderlineInputBorder(
              borderSide: BorderSide(color: Color(0xFF1DB954)),
            ),
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(
            child: const Text('CANCEL', style: TextStyle(color: Colors.grey)),
            onPressed: () => Navigator.pop(context),
          ),
          TextButton(
            child: const Text(
              'SAVE',
              style: TextStyle(color: Color(0xFF1DB954)),
            ),
            onPressed: () {
              if (controller.text.trim().isNotEmpty) {
                setState(() {
                  entry.name = controller.text.trim();
                });
                _saveLibrary(); // Save changes to library right away
              }
              Navigator.pop(context);
            },
          ),
        ],
      ),
    );
  }

  void _editAudioName() {
    if (_currentEntry == null) return;

    TextEditingController controller = TextEditingController(
      text: _currentEntry!.name,
    );

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF181818),
        title: const Text(
          'Edit Audio Name',
          style: TextStyle(color: Colors.white),
        ),
        content: TextField(
          controller: controller,
          style: const TextStyle(color: Colors.white),
          decoration: const InputDecoration(
            hintText: "Enter new name",
            hintStyle: TextStyle(color: Colors.grey),
            enabledBorder: UnderlineInputBorder(
              borderSide: BorderSide(color: Colors.grey),
            ),
            focusedBorder: UnderlineInputBorder(
              borderSide: BorderSide(color: Color(0xFF1DB954)),
            ),
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(
            child: const Text('CANCEL', style: TextStyle(color: Colors.grey)),
            onPressed: () => Navigator.pop(context),
          ),
          TextButton(
            child: const Text(
              'SAVE',
              style: TextStyle(color: Color(0xFF1DB954)),
            ),
            onPressed: () {
              if (controller.text.trim().isNotEmpty) {
                setState(() {
                  _currentEntry!.name = controller.text.trim();
                });
                _upsertAudioEntry();
              }
              Navigator.pop(context);
            },
          ),
        ],
      ),
    );
  }

  void _openLibraryPanel() {
    String librarySearchQuery = "";
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            final filteredLibrary = _library
                .where(
                  (e) => e.name.toLowerCase().contains(
                    librarySearchQuery.toLowerCase(),
                  ),
                )
                .toList();

            return FractionallySizedBox(
              heightFactor: 0.72,
              child: Container(
                decoration: const BoxDecoration(
                  color: Color(0xFF121212),
                  borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
                ),
                child: Column(
                  children: [
                    Container(
                      margin: const EdgeInsets.only(top: 12, bottom: 8),
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: Colors.grey[700],
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            "Audio Library",
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          SizedBox(
                            width: 150,
                            child: TextField(
                              decoration: InputDecoration(
                                hintText: "Search...",
                                hintStyle: const TextStyle(
                                  color: Colors.grey,
                                  fontSize: 13,
                                ),
                                isDense: true,
                                prefixIcon: const Icon(
                                  Icons.search,
                                  size: 16,
                                  color: Colors.grey,
                                ),
                                contentPadding: EdgeInsets.zero,
                                filled: true,
                                fillColor: const Color(0xFF282828),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(20),
                                  borderSide: BorderSide.none,
                                ),
                              ),
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 14,
                              ),
                              onChanged: (val) {
                                setModalState(() => librarySearchQuery = val);
                              },
                            ),
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: filteredLibrary.isEmpty
                          ? const Center(
                              child: Text(
                                "No items found.",
                                style: TextStyle(color: Colors.grey),
                              ),
                            )
                          : ListView.builder(
                              itemCount: filteredLibrary.length,
                              itemBuilder: (context, index) {
                                final item = filteredLibrary[index];
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
                                    leading: const Icon(
                                      Icons.album,
                                      color: Color(0xFF1DB954),
                                    ),
                                    title: Text(
                                      item.name,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    subtitle: Text(
                                      "${item.segments.length} segments saved",
                                      style: const TextStyle(
                                        color: Colors.grey,
                                      ),
                                    ),
                                    trailing: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        IconButton(
                                          icon: const Icon(
                                            Icons.edit,
                                            color: Colors.grey,
                                            size: 20,
                                          ),
                                          onPressed: () {
                                            _editLibraryAudioName(item);
                                          },
                                        ),
                                        IconButton(
                                          icon: const Icon(
                                            Icons.delete,
                                            color: Colors.redAccent,
                                            size: 20,
                                          ),
                                          onPressed: () {
                                            setState(() {
                                              _library.remove(item);
                                              if (_currentEntry == item) {
                                                _currentEntry = null;
                                                _player.stop();
                                              }
                                            });
                                            _saveLibrary();
                                            setModalState(() {});
                                          },
                                        ),
                                      ],
                                    ),
                                    onTap: () {
                                      Navigator.pop(context);
                                      _loadFile(item.path, item.name);
                                    },
                                  ),
                                );
                              },
                            ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  void _openSegmentPlayer(int initialIndex) {
    if (_currentEntry == null) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => SegmentPlayerScreen(
          player: _player,
          segments: _currentEntry!.segments,
          initialIndex: initialIndex,
          trackName: _currentEntry?.name ?? 'Unknown Track',
        ),
      ),
    );
  }

  String _formatDuration(Duration d) {
    final minutes = d.inMinutes;
    final seconds = d.inSeconds % 60;
    final ms = (d.inMilliseconds % 1000) ~/ 100;
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}.$ms';
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFF121212),
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          title: GestureDetector(
            onTap: _editAudioName,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(
                  child: Text(
                    _currentEntry?.name ?? "No Audio Loaded",
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (_currentEntry != null) ...[
                  const SizedBox(width: 8),
                  const Icon(Icons.edit, size: 16, color: Colors.grey),
                ],
              ],
            ),
          ),
          leading: IconButton(
            icon: const Icon(Icons.menu),
            onPressed: _openLibraryPanel,
          ),
          actions: [
            IconButton(
              tooltip: "Browse Quran API",
              icon: const Icon(Icons.cloud_outlined, color: Colors.white),
              onPressed: _openOnlineQuranBrowser,
            ),
            IconButton(
              icon: const Icon(Icons.file_upload, color: Color(0xFF1DB954)),
              onPressed: _importAudio,
            ),
          ],
        ),
        body: SafeArea(
          child: Column(
            children: [
              // Upper Workspace: Waveform & Playback Controls
              Expanded(
                flex: 4,
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    children: [
                      // Waveform Container
                      GestureDetector(
                        onTapDown: (details) {
                          if (_duration == Duration.zero) return;
                          final percent =
                              details.localPosition.dx /
                              MediaQuery.of(context).size.width;
                          final newPos = Duration(
                            milliseconds: (_duration.inMilliseconds * percent)
                                .toInt(),
                          );
                          _player.seek(newPos);
                        },
                        child: Container(
                          height: 120,
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          decoration: BoxDecoration(
                            color: const Color(0xFF181818).withAlpha(230),
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: CustomPaint(
                            painter: _WaveformPainter(
                              samples: _waveformSamples,
                              positionPercent: _duration.inMilliseconds > 0
                                  ? _position.inMilliseconds /
                                        _duration.inMilliseconds
                                  : 0,
                              loopStartPercent: _duration.inMilliseconds > 0
                                  ? _loopStart.inMilliseconds /
                                        _duration.inMilliseconds
                                  : 0,
                              loopEndPercent: _duration.inMilliseconds > 0
                                  ? _loopEnd.inMilliseconds /
                                        _duration.inMilliseconds
                                  : 1.0,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),

                      // Range Slider
                      Expanded(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            RangeSlider(
                              values: RangeValues(
                                _duration.inMilliseconds > 0
                                    ? _loopStart.inMilliseconds /
                                          _duration.inMilliseconds
                                    : 0,
                                _duration.inMilliseconds > 0
                                    ? _loopEnd.inMilliseconds /
                                          _duration.inMilliseconds
                                    : 1.0,
                              ),
                              min: 0.0,
                              max: 1.0,
                              activeColor: const Color(0xFF1DB954),
                              inactiveColor: Colors.grey[800],
                              onChanged: (values) {
                                setState(() {
                                  _loopStart = Duration(
                                    milliseconds:
                                        (_duration.inMilliseconds *
                                                values.start)
                                            .toInt(),
                                  );
                                  _loopEnd = Duration(
                                    milliseconds:
                                        (_duration.inMilliseconds * values.end)
                                            .toInt(),
                                  );
                                });
                                if (_position < _loopStart ||
                                    _position > _loopEnd) {
                                  _player.seek(_loopStart);
                                }
                              },
                            ),

                            // Timestamps
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16.0,
                              ),
                              child: Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    _formatDuration(_loopStart),
                                    style: const TextStyle(color: Colors.grey),
                                  ),
                                  Text(
                                    _formatDuration(_loopEnd),
                                    style: const TextStyle(color: Colors.grey),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 8),

                      // Set Bounds Controls
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                          _buildControlBtn("Set Start", () {
                            HapticFeedback.mediumImpact();
                            setState(() {
                              _loopStart = _position;
                              if (_loopStart > _loopEnd) _loopEnd = _duration;
                            });
                          }),
                          _buildControlBtn("Set End", () {
                            HapticFeedback.mediumImpact();
                            setState(() {
                              _loopEnd = _position;
                              if (_loopEnd < _loopStart)
                                _loopStart = Duration.zero;
                            });
                          }),
                        ],
                      ),
                      const SizedBox(height: 16),

                      // Main Controls (+-5s seek around play button)
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          IconButton(
                            icon: Icon(
                              _isLooping ? Icons.repeat_on : Icons.repeat,
                              color: _isLooping
                                  ? const Color(0xFF1DB954)
                                  : Colors.grey,
                              size: 28,
                            ),
                            onPressed: () {
                              HapticFeedback.selectionClick();
                              setState(() => _isLooping = !_isLooping);
                            },
                          ),
                          const SizedBox(width: 16),

                          IconButton(
                            iconSize: 32,
                            icon: const Icon(
                              Icons.fast_rewind,
                              color: Colors.white,
                            ),
                            onPressed: () {
                              HapticFeedback.selectionClick();
                              _seekBy(const Duration(seconds: -5));
                            },
                          ),

                          Container(
                            margin: const EdgeInsets.symmetric(horizontal: 8),
                            decoration: const BoxDecoration(
                              color: Color(0xFF1DB954),
                              shape: BoxShape.circle,
                            ),
                            child: IconButton(
                              iconSize: 48,
                              padding: const EdgeInsets.all(12),
                              icon: Icon(
                                _isPlaying ? Icons.pause : Icons.play_arrow,
                                color: Colors.black,
                              ),
                              onPressed: () {
                                HapticFeedback.mediumImpact();
                                _isPlaying ? _player.pause() : _player.play();
                              },
                            ),
                          ),

                          IconButton(
                            iconSize: 32,
                            icon: const Icon(
                              Icons.fast_forward,
                              color: Colors.white,
                            ),
                            onPressed: () {
                              HapticFeedback.selectionClick();
                              _seekBy(const Duration(seconds: 5));
                            },
                          ),

                          const SizedBox(width: 16),
                          IconButton(
                            icon: const Icon(
                              Icons.bookmark_add,
                              color: Colors.white,
                              size: 28,
                            ),
                            onPressed: _currentEntry != null
                                ? _saveSegment
                                : null,
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      // Overall Progress Slider (Voice Tracer)
                      SliderTheme(
                        data: SliderTheme.of(context).copyWith(
                          activeTrackColor: const Color(0xFF1DB954),
                          inactiveTrackColor: Colors.grey[800],
                          thumbColor: Colors.white,
                          trackHeight: 4.0,
                          thumbShape: const RoundSliderThumbShape(
                            enabledThumbRadius: 6.0,
                          ),
                          overlayShape: const RoundSliderOverlayShape(
                            overlayRadius: 14.0,
                          ),
                        ),
                        child: Slider(
                          value: _duration.inMilliseconds > 0
                              ? _position.inMilliseconds /
                                    _duration.inMilliseconds
                              : 0.0,
                          onChanged: (value) {
                            final newPos = Duration(
                              milliseconds: (_duration.inMilliseconds * value)
                                  .toInt(),
                            );
                            _player.seek(newPos);
                          },
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16.0),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              _formatDuration(_position),
                              style: const TextStyle(
                                color: Colors.grey,
                                fontSize: 12,
                              ),
                            ),
                            Text(
                              _formatDuration(_duration),
                              style: const TextStyle(
                                color: Colors.grey,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              // Lower Workspace: Segment List
              Expanded(
                flex: 3,
                child: Container(
                  decoration: const BoxDecoration(color: Color(0xFF121212)),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(20, 20, 20, 10),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text(
                              "Saved Segments",
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            if (_currentEntry != null &&
                                _currentEntry!.segments.isNotEmpty)
                              SizedBox(
                                width: 140,
                                child: TextField(
                                  decoration: InputDecoration(
                                    hintText: "Search...",
                                    hintStyle: const TextStyle(
                                      color: Colors.grey,
                                      fontSize: 13,
                                    ),
                                    isDense: true,
                                    prefixIcon: const Icon(
                                      Icons.search,
                                      size: 16,
                                      color: Colors.grey,
                                    ),
                                    contentPadding: EdgeInsets.zero,
                                    filled: true,
                                    fillColor: const Color(0xFF282828),
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(20),
                                      borderSide: BorderSide.none,
                                    ),
                                  ),
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 14,
                                  ),
                                  onChanged: (val) {
                                    setState(() => _segmentSearchQuery = val);
                                  },
                                ),
                              ),
                          ],
                        ),
                      ),
                      Expanded(
                        child:
                            _currentEntry == null ||
                                _currentEntry!.segments.isEmpty
                            ? const Center(
                                child: Text(
                                  "No segments saved yet.",
                                  style: TextStyle(color: Colors.grey),
                                ),
                              )
                            : Builder(
                                builder: (context) {
                                  final filteredSegments = _currentEntry!
                                      .segments
                                      .where(
                                        (s) => s.name.toLowerCase().contains(
                                          _segmentSearchQuery.toLowerCase(),
                                        ),
                                      )
                                      .toList();

                                  if (filteredSegments.isEmpty) {
                                    return const Center(
                                      child: Text(
                                        "No matching segments.",
                                        style: TextStyle(color: Colors.grey),
                                      ),
                                    );
                                  }

                                  return ReorderableListView.builder(
                                    itemCount: filteredSegments.length,
                                    onReorder: (oldIndex, newIndex) {
                                      // Disable reordering when filtering since indices won't match
                                      if (_segmentSearchQuery.isNotEmpty)
                                        return;

                                      setState(() {
                                        if (newIndex > oldIndex) newIndex -= 1;
                                        final item = _currentEntry!.segments
                                            .removeAt(oldIndex);
                                        _currentEntry!.segments.insert(
                                          newIndex,
                                          item,
                                        );
                                      });
                                      _upsertAudioEntry();
                                    },
                                    itemBuilder: (context, index) {
                                      final segment = filteredSegments[index];
                                      final isSelected =
                                          _loopStart == segment.start &&
                                          _loopEnd == segment.end;
                                      final titleColor = isSelected
                                          ? const Color(0xFF1DB954)
                                          : Colors.white;

                                      return ListTile(
                                        key: ValueKey(segment.id),
                                        contentPadding:
                                            const EdgeInsets.symmetric(
                                              horizontal: 20,
                                              vertical: 4,
                                            ),
                                        title: Row(
                                          children: [
                                            Expanded(
                                              child: Text(
                                                segment.name,
                                                style: TextStyle(
                                                  color: titleColor,
                                                  fontWeight: FontWeight.w600,
                                                ),
                                              ),
                                            ),
                                            IconButton(
                                              icon: const Icon(
                                                Icons.edit,
                                                color: Colors.grey,
                                                size: 18,
                                              ),
                                              onPressed: () =>
                                                  _editSegmentName(segment),
                                            ),
                                          ],
                                        ),
                                        subtitle: Text(
                                          "${_formatDuration(segment.start)} - ${_formatDuration(segment.end)}",
                                          style: TextStyle(
                                            color: isSelected
                                                ? const Color(
                                                    0xFF1DB954,
                                                  ).withAlpha(204)
                                                : Colors.grey,
                                          ),
                                        ),
                                        trailing: IconButton(
                                          icon: const Icon(
                                            Icons.delete_outline,
                                            color: Colors.redAccent,
                                          ),
                                          onPressed: () =>
                                              _deleteSegment(segment),
                                        ),
                                        onTap: () {
                                          _player.seek(segment.start);
                                          _player.play();
                                          setState(() {
                                            _loopStart = segment.start;
                                            _loopEnd = segment.end;
                                          });
                                          // Find the correct absolute index for the SegmentPlayer
                                          int originalIndex = _currentEntry!
                                              .segments
                                              .indexOf(segment);
                                          _openSegmentPlayer(originalIndex);
                                        },
                                      );
                                    },
                                  );
                                },
                              ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildControlBtn(String label, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: const Color(0xFF282828),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          label,
          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
        ),
      ),
    );
  }
}

// --- WAVEFORM PAINTER ---

class _WaveformPainter extends CustomPainter {
  final List<double> samples;
  final double positionPercent;
  final double loopStartPercent;
  final double loopEndPercent;

  _WaveformPainter({
    required this.samples,
    required this.positionPercent,
    required this.loopStartPercent,
    required this.loopEndPercent,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (samples.isEmpty) return;

    final paintNormal = Paint()
      ..color = Colors.grey[800]!
      ..style = PaintingStyle.fill
      ..strokeCap = StrokeCap.round;

    final paintHighlight = Paint()
      ..color = const Color(0xFF1DB954)
      ..style = PaintingStyle.fill
      ..strokeCap = StrokeCap.round;

    final double barWidth = (size.width / samples.length) * 0.7;
    final double spacing = (size.width / samples.length) * 0.3;

    for (int i = 0; i < samples.length; i++) {
      final double percent = i / samples.length;
      final bool inLoop =
          percent >= loopStartPercent && percent <= loopEndPercent;

      final Paint currentPaint = inLoop ? paintHighlight : paintNormal;

      final double barHeight = samples[i] * size.height;
      final double x = i * (barWidth + spacing);
      final double y = (size.height - barHeight) / 2;

      final roundedRect = RRect.fromRectAndRadius(
        Rect.fromLTWH(x, y, barWidth, barHeight),
        const Radius.circular(4),
      );

      canvas.drawRRect(roundedRect, currentPaint);
    }

    // Draw position line
    final posPaint = Paint()
      ..color = Colors.white
      ..strokeWidth = 2;
    final xPos = positionPercent * size.width;
    canvas.drawLine(Offset(xPos, 0), Offset(xPos, size.height), posPaint);
  }

  @override
  bool shouldRepaint(covariant _WaveformPainter oldDelegate) {
    return oldDelegate.positionPercent != positionPercent ||
        oldDelegate.loopStartPercent != loopStartPercent ||
        oldDelegate.loopEndPercent != loopEndPercent ||
        oldDelegate.samples != samples;
  }
}

// --- DEDICATED SEGMENT PLAYER ---

class SegmentPlayerScreen extends StatefulWidget {
  final AudioPlayer player;
  final List<LoopBookmark> segments;
  final int initialIndex;
  final String trackName;

  const SegmentPlayerScreen({
    super.key,
    required this.player,
    required this.segments,
    required this.initialIndex,
    required this.trackName,
  });

  @override
  State<SegmentPlayerScreen> createState() => _SegmentPlayerScreenState();
}

class _SegmentPlayerScreenState extends State<SegmentPlayerScreen> {
  bool _isPlaying = true;
  bool _isLooping = true;
  Duration _position = Duration.zero;
  late int _currentIndex;

  // Stream subscriptions to clean up
  late var _positionSubscription;
  late var _stateSubscription;

  LoopBookmark get currentSegment => widget.segments[_currentIndex];

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
    _position = currentSegment.start;

    _positionSubscription = widget.player.positionStream.listen((pos) {
      if (!mounted) return;
      setState(() => _position = pos);

      if (pos >= currentSegment.end) {
        if (_isLooping) {
          widget.player.seek(currentSegment.start);
        } else {
          _goToNextSegmentOrStop();
        }
      }
    });

    _stateSubscription = widget.player.playerStateStream.listen((state) {
      if (!mounted) return;
      setState(() => _isPlaying = state.playing);
    });
  }

  @override
  void dispose() {
    _positionSubscription.cancel();
    _stateSubscription.cancel();
    super.dispose();
  }

  void _goToNextSegmentOrStop() {
    if (_currentIndex < widget.segments.length - 1) {
      setState(() {
        _currentIndex++;
      });
      widget.player.seek(currentSegment.start);
    } else {
      widget.player.pause();
    }
  }

  void _goToPrevSegment() {
    HapticFeedback.mediumImpact();
    // If we've played for more than 3 seconds or it's the first segment, restart current.
    if ((_position - currentSegment.start).inSeconds >= 3 ||
        _currentIndex == 0) {
      widget.player.seek(currentSegment.start);
    } else {
      setState(() {
        _currentIndex--;
      });
      widget.player.seek(currentSegment.start);
    }
  }

  void _goToNextSegment() {
    HapticFeedback.mediumImpact();
    if (_currentIndex < widget.segments.length - 1) {
      setState(() {
        _currentIndex++;
      });
      widget.player.seek(currentSegment.start);
    } else {
      widget.player.seek(currentSegment.end);
    }
  }

  void _seekRelative(Duration offset) {
    HapticFeedback.selectionClick();
    final newPos = _position + offset;
    final maxPos = newPos > currentSegment.end ? currentSegment.end : newPos;
    final minPos = maxPos < currentSegment.start
        ? currentSegment.start
        : maxPos;
    widget.player.seek(minPos);
  }

  String _formatDuration(Duration d) {
    final minutes = d.inMinutes;
    final seconds = d.inSeconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final segmentDuration = currentSegment.end - currentSegment.start;
    final currentSegmentPos = _position - currentSegment.start;

    // Safety clamp
    final clampedPos = currentSegmentPos.isNegative
        ? Duration.zero
        : (currentSegmentPos > segmentDuration
              ? segmentDuration
              : currentSegmentPos);

    return Container(
      color: const Color(0xFF121212),
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.keyboard_arrow_down),
            onPressed: () => Navigator.pop(context),
          ),
          title: const Text(
            "PLAYING SEGMENT",
            style: TextStyle(
              fontSize: 12,
              letterSpacing: 1.5,
              color: Colors.grey,
            ),
          ),
          centerTitle: true,
        ),
        body: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Album Art Placeholder
              Expanded(
                child: Center(
                  child: Container(
                    width: MediaQuery.of(context).size.width * 0.8,
                    height: MediaQuery.of(context).size.width * 0.8,
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [Color(0xFF282828), Color(0xFF181818)],
                      ),
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withAlpha(128),
                          blurRadius: 20,
                          offset: const Offset(0, 10),
                        ),
                      ],
                    ),
                    child: const Center(
                      child: Icon(
                        Icons.music_note,
                        size: 80,
                        color: Colors.grey,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 40),

              // Track Info
              Text(
                currentSegment.name,
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                widget.trackName,
                style: const TextStyle(fontSize: 16, color: Colors.grey),
              ),
              const SizedBox(height: 32),

              // Segment Progress
              SliderTheme(
                data: SliderTheme.of(context).copyWith(
                  activeTrackColor: const Color(0xFF1DB954),
                  inactiveTrackColor: Colors.grey[800],
                  thumbColor: Colors.white,
                  trackHeight: 4.0,
                  thumbShape: const RoundSliderThumbShape(
                    enabledThumbRadius: 6.0,
                  ),
                  overlayShape: const RoundSliderOverlayShape(
                    overlayRadius: 14.0,
                  ),
                ),
                child: Slider(
                  value: segmentDuration.inMilliseconds > 0
                      ? clampedPos.inMilliseconds /
                            segmentDuration.inMilliseconds
                      : 0.0,
                  onChanged: (value) {
                    final newPos =
                        currentSegment.start +
                        Duration(
                          milliseconds: (segmentDuration.inMilliseconds * value)
                              .toInt(),
                        );
                    widget.player.seek(newPos);
                  },
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16.0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      _formatDuration(clampedPos),
                      style: const TextStyle(color: Colors.grey, fontSize: 12),
                    ),
                    Text(
                      _formatDuration(segmentDuration),
                      style: const TextStyle(color: Colors.grey, fontSize: 12),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),

              // Micro-adjustments
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _buildMicroBtn(
                    "-5s",
                    () => _seekRelative(const Duration(seconds: -5)),
                  ),
                  _buildMicroBtn(
                    "+5s",
                    () => _seekRelative(const Duration(seconds: 5)),
                  ),
                ],
              ),
              const SizedBox(height: 24),

              // Controls
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  IconButton(
                    icon: Icon(
                      _isLooping ? Icons.repeat_on : Icons.repeat,
                      color: _isLooping ? const Color(0xFF1DB954) : Colors.grey,
                    ),
                    onPressed: () {
                      HapticFeedback.selectionClick();
                      setState(() => _isLooping = !_isLooping);
                    },
                  ),
                  IconButton(
                    iconSize: 36,
                    icon: const Icon(Icons.skip_previous, color: Colors.white),
                    onPressed: _goToPrevSegment,
                  ),
                  Container(
                    decoration: const BoxDecoration(
                      color: Color(0xFF1DB954),
                      shape: BoxShape.circle,
                    ),
                    child: IconButton(
                      iconSize: 48,
                      padding: const EdgeInsets.all(16),
                      icon: Icon(
                        _isPlaying ? Icons.pause : Icons.play_arrow,
                        color: Colors.black,
                      ),
                      onPressed: () {
                        HapticFeedback.mediumImpact();
                        _isPlaying
                            ? widget.player.pause()
                            : widget.player.play();
                      },
                    ),
                  ),
                  IconButton(
                    iconSize: 36,
                    icon: const Icon(Icons.skip_next, color: Colors.white),
                    onPressed: _goToNextSegment,
                  ),
                  IconButton(
                    icon: const Icon(
                      Icons.favorite_border,
                      color: Colors.grey,
                    ), // Placeholder
                    onPressed: () {},
                  ),
                ],
              ),
              const SizedBox(height: 48),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMicroBtn(String label, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: const Color(0xFF282828),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          label,
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
        ),
      ),
    );
  }
}
