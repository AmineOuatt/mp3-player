import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:just_audio/just_audio.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

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
  String? groupId;
  String? sourceReciterName;
  String? sourceSurahName;
  String? sourceSurahId;

  SavedAudioEntry({
    required this.path,
    required this.name,
    List<LoopBookmark>? segments,
    this.groupId,
    this.sourceReciterName,
    this.sourceSurahName,
    this.sourceSurahId,
  }) : segments = segments ?? [];

  Map<String, dynamic> toJson() => {
    'path': path,
    'name': name,
    'segments': segments.map((s) => s.toJson()).toList(),
    'groupId': groupId,
    'sourceReciterName': sourceReciterName,
    'sourceSurahName': sourceSurahName,
    'sourceSurahId': sourceSurahId,
  };

  factory SavedAudioEntry.fromJson(Map<String, dynamic> json) =>
      SavedAudioEntry(
        path: json['path'],
        name: json['name'],
        segments: (json['segments'] as List)
            .map((s) => LoopBookmark.fromJson(s as Map<String, dynamic>))
            .toList(),
        groupId: json['groupId'],
        sourceReciterName: json['sourceReciterName'],
        sourceSurahName: json['sourceSurahName'],
        sourceSurahId: json['sourceSurahId'],
      );
}

class AudioGroup {
  final String id;
  String name;
  bool isExpanded;

  AudioGroup({required this.id, required this.name, this.isExpanded = true});

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'isExpanded': isExpanded,
  };

  factory AudioGroup.fromJson(Map<String, dynamic> json) => AudioGroup(
    id: json['id'],
    name: json['name'],
    isExpanded: json['isExpanded'] ?? true,
  );
}

// --- NOTIFICATION SERVICE ---

class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  static const channelId = 'audio_playback';
  static const channelName = 'Audio Playback';
  static const notificationId = 1;

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  Function(String action)? _actionCallback;

  NotificationService._internal();

  factory NotificationService() {
    return _instance;
  }

  void setActionCallback(Function(String action) callback) {
    _actionCallback = callback;
  }

  Future<void> init() async {
    const AndroidInitializationSettings android = AndroidInitializationSettings(
      '@mipmap/ic_launcher',
    );
    const DarwinInitializationSettings ios = DarwinInitializationSettings(
      requestSoundPermission: false,
      requestBadgePermission: false,
      requestAlertPermission: false,
    );
    const InitializationSettings settings = InitializationSettings(
      android: android,
      iOS: ios,
    );

    await _plugin.initialize(
      settings,
      onDidReceiveNotificationResponse: _onNotificationResponse,
    );

    // Create notification channel for Android
    const AndroidNotificationChannel channel = AndroidNotificationChannel(
      channelId,
      channelName,
      importance: Importance.low,
      enableVibration: false,
      playSound: false,
    );

    await _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.createNotificationChannel(channel);
  }

  Future<void> showPlaybackNotification({
    required String title,
    required String subtitle,
    required bool isPlaying,
  }) async {
    final List<AndroidNotificationAction> actions = [
      const AndroidNotificationAction(
        'prev_segment',
        'Previous',
        showsUserInterface: true,
        cancelNotification: false,
      ),
      AndroidNotificationAction(
        'play_pause',
        isPlaying ? 'Pause' : 'Play',
        showsUserInterface: true,
        cancelNotification: false,
      ),
      const AndroidNotificationAction(
        'next_segment',
        'Next',
        showsUserInterface: true,
        cancelNotification: false,
      ),
      const AndroidNotificationAction(
        'stop',
        'Stop',
        showsUserInterface: true,
        cancelNotification: true,
      ),
    ];

    final androidDetails = AndroidNotificationDetails(
      channelId,
      channelName,
      importance: Importance.low,
      priority: Priority.low,
      showProgress: false,
      playSound: false,
      actions: actions,
    );

    final iosDetails = DarwinNotificationDetails(
      presentAlert: false,
      presentBadge: false,
      presentSound: false,
      subtitle: subtitle,
    );

    final NotificationDetails details = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );

    await _plugin.show(notificationId, title, subtitle, details);
  }

  Future<void> cancelNotification() async {
    await _plugin.cancel(notificationId);
  }

  void _onNotificationResponse(NotificationResponse response) {
    final actionId = response.actionId;
    if (actionId != null && actionId.isNotEmpty && _actionCallback != null) {
      debugPrint("Notification action triggered: $actionId");
      _actionCallback!(actionId);
    }
  }
}

// --- MAIN APP ---

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await NotificationService().init();
  runApp(const AudioRepeaterApp());
}

class AudioRepeaterApp extends StatelessWidget {
  const AudioRepeaterApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'MP360',
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
  List<AudioGroup> _audioGroups = [];
  SavedAudioEntry? _currentEntry;

  bool _isPlaying = false;
  bool _isLooping = true;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;

  Duration _loopStart = Duration.zero;
  Duration _loopEnd = Duration.zero;
  String? _selectedSegmentId;

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
    NotificationService().setActionCallback(_handleNotificationAction);

    try {
      _player.positionStream.listen(
        (pos) {
          if (!mounted) return;
          setState(() => _position = pos);

          // Auto-looping logic
          if (_isLooping && _loopEnd > Duration.zero && pos >= _loopEnd) {
            _player.seek(_loopStart);
          }

          // Update notification with current position
          if (_isPlaying && _currentEntry != null) {
            _showPlaybackNotification();
          }
        },
        onError: (error) {
          debugPrint("Position stream error: $error");
        },
      );

      _player.durationStream.listen(
        (dur) {
          if (!mounted) return;
          setState(() {
            _duration = dur ?? Duration.zero;
            if (_loopEnd == Duration.zero || _loopEnd > _duration) {
              _loopEnd = _duration;
            }
          });
        },
        onError: (error) {
          debugPrint("Duration stream error: $error");
        },
      );

      _player.playerStateStream.listen(
        (state) {
          if (!mounted) return;
          setState(() {
            _isPlaying = state.playing;
          });

          // Show/update notification when playing
          if (state.playing && _currentEntry != null) {
            _showPlaybackNotification();
          } else if (!state.playing) {
            // Cancel notification when paused/stopped
            NotificationService().cancelNotification();
          }

          if (state.processingState == ProcessingState.completed) {
            if (_isLooping) {
              _player.seek(_loopStart);
              _player.play();
            } else {
              _player.seek(Duration.zero);
              _player.pause();
            }
          }
        },
        onError: (error) {
          debugPrint("Player state stream error: $error");
        },
      );
    } catch (e) {
      debugPrint("Error initializing audio player: $e");
    }
  }

  bool _replaceStreamEntryWithOffline({
    required String offlinePath,
    required String offlineName,
    String? replaceStreamPath,
    String? sourceReciterName,
    String? sourceSurahId,
    String? sourceSurahName,
  }) {
    int index = -1;

    if (replaceStreamPath != null && replaceStreamPath.isNotEmpty) {
      index = _library.indexWhere((entry) => entry.path == replaceStreamPath);
    }

    if (index == -1 &&
        sourceReciterName != null &&
        sourceReciterName.isNotEmpty &&
        sourceSurahId != null &&
        sourceSurahId.isNotEmpty) {
      index = _library.indexWhere(
        (entry) =>
            (entry.path.startsWith('http://') ||
                entry.path.startsWith('https://')) &&
            (entry.sourceReciterName ?? '').trim() ==
                sourceReciterName.trim() &&
            (entry.sourceSurahId ?? '').trim() == sourceSurahId.trim(),
      );
    }

    if (index == -1) return false;

    final existing = _library[index];
    final updated = SavedAudioEntry(
      path: offlinePath,
      name: offlineName,
      segments: existing.segments,
      groupId: existing.groupId,
      sourceReciterName: sourceReciterName?.isNotEmpty == true
          ? sourceReciterName
          : existing.sourceReciterName,
      sourceSurahName: sourceSurahName?.isNotEmpty == true
          ? sourceSurahName
          : existing.sourceSurahName,
      sourceSurahId: sourceSurahId?.isNotEmpty == true
          ? sourceSurahId
          : existing.sourceSurahId,
    );

    setState(() {
      _library[index] = updated;
      if (_currentEntry?.path == existing.path) {
        _currentEntry = updated;
      }
    });

    return true;
  }

  void _loadLibrary() {
    try {
      final libraryJson = _prefs?.getString('library');
      final groupsJson = _prefs?.getString('audioGroups');

      if (libraryJson != null && libraryJson.isNotEmpty) {
        try {
          final List decoded = jsonDecode(libraryJson);
          setState(() {
            _library = decoded
                .map((e) {
                  try {
                    return SavedAudioEntry.fromJson(e as Map<String, dynamic>);
                  } catch (e) {
                    debugPrint("Error parsing library entry: $e");
                    return null;
                  }
                  ;
                })
                .whereType<SavedAudioEntry>()
                .toList();
          });
        } catch (e) {
          debugPrint("Error decoding library JSON: $e");
        }
      }

      if (groupsJson != null && groupsJson.isNotEmpty) {
        try {
          final List decoded = jsonDecode(groupsJson);
          setState(() {
            _audioGroups = decoded
                .map((e) {
                  try {
                    return AudioGroup.fromJson(e as Map<String, dynamic>);
                  } catch (e) {
                    debugPrint("Error parsing group entry: $e");
                    return null;
                  }
                  ;
                })
                .whereType<AudioGroup>()
                .toList();
          });
        } catch (e) {
          debugPrint("Error decoding groups JSON: $e");
        }
      }
    } catch (e) {
      debugPrint("Error loading library: $e");
    }
  }

  Future<void> _saveLibrary() async {
    final libraryJson = jsonEncode(_library.map((e) => e.toJson()).toList());
    await _prefs?.setString('library', libraryJson);

    final groupsJson = jsonEncode(_audioGroups.map((g) => g.toJson()).toList());
    await _prefs?.setString('audioGroups', groupsJson);
  }

  void _consumeQuranBrowserResult(Map result) {
    final path = result['path']?.toString() ?? '';
    final filename = result['name']?.toString() ?? '';
    final sourceReciterName = result['sourceReciterName']?.toString();
    final sourceSurahName = result['sourceSurahName']?.toString();
    final sourceSurahId = result['sourceSurahId']?.toString();
    final replaceStreamPath = result['replaceStreamPath']?.toString();

    if (path.isEmpty || filename.isEmpty) return;

    final didReplaceStreamEntry = _replaceStreamEntryWithOffline(
      offlinePath: path,
      offlineName: filename,
      replaceStreamPath: replaceStreamPath,
      sourceReciterName: sourceReciterName,
      sourceSurahName: sourceSurahName,
      sourceSurahId: sourceSurahId,
    );

    if (didReplaceStreamEntry) {
      _saveLibrary();
      _loadFile(path, filename);
      return;
    }

    final index = _library.indexWhere((entry) => entry.path == path);
    if (index == -1) {
      setState(() {
        _library.add(
          SavedAudioEntry(
            path: path,
            name: filename,
            segments: [],
            sourceReciterName: sourceReciterName,
            sourceSurahName: sourceSurahName,
            sourceSurahId: sourceSurahId,
          ),
        );
      });
      _saveLibrary();
      _loadFile(path, filename);
    } else {
      // Audio already exists - show confirmation dialog
      if (!mounted) return;
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          backgroundColor: const Color(0xFF181818),
          title: const Text(
            'Audio Already in Library',
            style: TextStyle(color: Colors.white),
          ),
          content: Text(
            'This voice is already in your library:\n\n"${_library[index].name}"\n\nDo you want to use it again?',
            style: const TextStyle(color: Colors.white70),
          ),
          actions: [
            TextButton(
              child: const Text('CANCEL', style: TextStyle(color: Colors.grey)),
              onPressed: () => Navigator.pop(context),
            ),
            TextButton(
              child: const Text(
                'USE ANYWAY',
                style: TextStyle(color: Color(0xFF1DB954)),
              ),
              onPressed: () {
                Navigator.pop(context);
                setState(() {
                  final existing = _library[index];
                  if (sourceReciterName != null &&
                      sourceReciterName.isNotEmpty) {
                    existing.sourceReciterName = sourceReciterName;
                  }
                  if (sourceSurahName != null && sourceSurahName.isNotEmpty) {
                    existing.sourceSurahName = sourceSurahName;
                  }
                  if (sourceSurahId != null && sourceSurahId.isNotEmpty) {
                    existing.sourceSurahId = sourceSurahId;
                  }
                });
                _saveLibrary();
                _loadFile(path, filename);
              },
            ),
          ],
        ),
      );
    }
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
      _consumeQuranBrowserResult(result);
    }
  }

  String _formatFileSize(int bytes) {
    if (bytes <= 0) return '0 B';
    const units = ['B', 'KB', 'MB', 'GB'];
    double size = bytes.toDouble();
    int unit = 0;
    while (size >= 1024 && unit < units.length - 1) {
      size /= 1024;
      unit++;
    }
    return '${size.toStringAsFixed(size < 10 && unit > 0 ? 1 : 0)} ${units[unit]}';
  }

  IconData _getAudioStatusIcon(SavedAudioEntry entry) {
    // Streaming from network
    if (entry.path.startsWith('http://') || entry.path.startsWith('https://')) {
      return Icons.cloud_upload;
    }

    // Check if local file exists (downloaded)
    try {
      final file = File(entry.path);
      if (file.existsSync()) {
        return Icons.download_done; // Downloaded icon
      }
    } catch (e) {
      debugPrint("Error checking file: $e");
    }

    // File not found or error
    return Icons.album;
  }

  Color _getAudioStatusIconColor(SavedAudioEntry entry) {
    // Streaming from network
    if (entry.path.startsWith('http://') || entry.path.startsWith('https://')) {
      return const Color(0xFF1DB954); // Green for streaming
    }

    // Check if local file exists (downloaded)
    try {
      final file = File(entry.path);
      if (file.existsSync()) {
        return const Color(0xFF1DB954); // Green for downloaded
      }
    } catch (e) {
      debugPrint("Error checking file color: $e");
    }

    // File not found
    return Colors.grey;
  }

  void _showAudioSize(SavedAudioEntry entry) async {
    String message;
    if (entry.path.startsWith('http://') || entry.path.startsWith('https://')) {
      // Try to fetch size from server headers
      try {
        final response = await http
            .head(Uri.parse(entry.path))
            .timeout(const Duration(seconds: 5));
        final contentLength = response.contentLength;
        if (contentLength != null && contentLength > 0) {
          message = 'Size: ${_formatFileSize(contentLength)}';
        } else {
          message = 'Size unavailable for streaming source.';
        }
      } catch (e) {
        message = 'Size unavailable for streaming source.';
      }
    } else {
      final file = File(entry.path);
      if (!file.existsSync()) {
        message = 'File not found on device.';
      } else {
        final bytes = file.lengthSync();
        message = 'Size: ${_formatFileSize(bytes)}';
      }
    }

    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  void _openAudioSource(SavedAudioEntry entry) async {
    String? reciter = entry.sourceReciterName;
    String? surah = entry.sourceSurahName;

    // Fallback for older library items: try parsing "Reciter - Surah".
    if ((reciter == null || reciter.trim().isEmpty) &&
        entry.name.contains(' - ')) {
      final parts = entry.name.split(' - ');
      if (parts.isNotEmpty) {
        reciter = parts.first.trim();
      }
      if ((surah == null || surah.trim().isEmpty) && parts.length > 1) {
        surah = parts.sublist(1).join(' - ').trim();
      }
    }

    if (reciter == null || reciter.trim().isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Source location is not available for this audio.'),
        ),
      );
      return;
    }

    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => QuranBrowserMode(
          initialReciterName: reciter,
          initialSurahName: surah,
          initialSurahId: entry.sourceSurahId,
        ),
        fullscreenDialog: true,
      ),
    );

    if (result != null && result is Map) {
      _consumeQuranBrowserResult(result);
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
      // Validate path
      if (path.isEmpty) {
        if (!mounted) return;
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Invalid audio path')));
        return;
      }

      final sourceUri =
          path.startsWith('http://') || path.startsWith('https://')
          ? Uri.parse(path)
          : Uri.file(path);

      await _player.setAudioSource(AudioSource.uri(sourceUri));

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
        _loopEnd = _player.duration ?? _duration;
        _selectedSegmentId = null;
      });

      _saveLibrary();
      _generateWaveform(path);

      // Delay play to ensure audio is ready
      Future.delayed(const Duration(milliseconds: 100), () {
        if (mounted) {
          _player.play();
        }
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Could not load audio: $e')));
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

  void _moveAudioToGroup(SavedAudioEntry entry) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF181818),
        title: const Text(
          'Move to Group',
          style: TextStyle(color: Colors.white),
        ),
        content: SizedBox(
          width: 300,
          height: 200,
          child: ListView(
            children: [
              ListTile(
                title: const Text(
                  'No Group',
                  style: TextStyle(color: Colors.white),
                ),
                onTap: () {
                  setState(() {
                    entry.groupId = null;
                  });
                  _saveLibrary();
                  Navigator.pop(context);
                },
              ),
              ..._audioGroups.map((group) {
                return ListTile(
                  title: Text(
                    group.name,
                    style: const TextStyle(color: Colors.white),
                  ),
                  onTap: () {
                    setState(() {
                      entry.groupId = group.id;
                    });
                    _saveLibrary();
                    Navigator.pop(context);
                  },
                );
              }).toList(),
            ],
          ),
        ),
        actions: [
          TextButton(
            child: const Text('CANCEL', style: TextStyle(color: Colors.grey)),
            onPressed: () => Navigator.pop(context),
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

  void _createNewGroup() {
    TextEditingController controller = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF181818),
        title: const Text(
          'Create New Group',
          style: TextStyle(color: Colors.white),
        ),
        content: TextField(
          controller: controller,
          style: const TextStyle(color: Colors.white),
          decoration: const InputDecoration(
            hintText: "Group name",
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
              'CREATE',
              style: TextStyle(color: Color(0xFF1DB954)),
            ),
            onPressed: () {
              if (controller.text.trim().isNotEmpty) {
                setState(() {
                  _audioGroups.add(
                    AudioGroup(
                      id: DateTime.now().millisecondsSinceEpoch.toString(),
                      name: controller.text.trim(),
                    ),
                  );
                });
                _saveLibrary();
              }
              Navigator.pop(context);
            },
          ),
        ],
      ),
    );
  }

  void _renameGroup(AudioGroup group) {
    TextEditingController controller = TextEditingController(text: group.name);

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF181818),
        title: const Text(
          'Rename Group',
          style: TextStyle(color: Colors.white),
        ),
        content: TextField(
          controller: controller,
          style: const TextStyle(color: Colors.white),
          decoration: const InputDecoration(
            hintText: "Group name",
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
              'RENAME',
              style: TextStyle(color: Color(0xFF1DB954)),
            ),
            onPressed: () {
              if (controller.text.trim().isNotEmpty) {
                setState(() {
                  group.name = controller.text.trim();
                });
                _saveLibrary();
              }
              Navigator.pop(context);
            },
          ),
        ],
      ),
    );
  }

  void _deleteGroup(AudioGroup group) {
    // Move all items in group to ungrouped
    for (var item in _library) {
      if (item.groupId == group.id) {
        item.groupId = null;
      }
    }
    setState(() {
      _audioGroups.removeWhere((g) => g.id == group.id);
    });
    _saveLibrary();
  }

  void _showAddAudiosToGroup(AudioGroup group) {
    String search = '';
    final selected = <String>{};

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          final filtered = _library
              .where((a) => a.name.toLowerCase().contains(search.toLowerCase()))
              .toList();

          return AlertDialog(
            backgroundColor: const Color(0xFF181818),
            title: Text(
              'Add audios to ${group.name}',
              style: const TextStyle(color: Colors.white),
            ),
            content: SizedBox(
              width: 360,
              height: 420,
              child: Column(
                children: [
                  TextField(
                    style: const TextStyle(color: Colors.white),
                    decoration: const InputDecoration(
                      hintText: 'Search audio...',
                      hintStyle: TextStyle(color: Colors.grey),
                      prefixIcon: Icon(Icons.search, color: Colors.grey),
                    ),
                    onChanged: (value) {
                      setDialogState(() => search = value);
                    },
                  ),
                  const SizedBox(height: 10),
                  Expanded(
                    child: filtered.isEmpty
                        ? const Center(
                            child: Text(
                              'No audio found',
                              style: TextStyle(color: Colors.grey),
                            ),
                          )
                        : ListView.builder(
                            itemCount: filtered.length,
                            itemBuilder: (context, index) {
                              final item = filtered[index];
                              final checked = selected.contains(item.path);
                              return CheckboxListTile(
                                value: checked,
                                activeColor: const Color(0xFF1DB954),
                                title: Text(
                                  item.name,
                                  style: const TextStyle(color: Colors.white),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                subtitle: Text(
                                  item.groupId == null
                                      ? 'Ungrouped'
                                      : 'In another group',
                                  style: const TextStyle(color: Colors.grey),
                                ),
                                controlAffinity:
                                    ListTileControlAffinity.leading,
                                onChanged: (value) {
                                  setDialogState(() {
                                    if (value == true) {
                                      selected.add(item.path);
                                    } else {
                                      selected.remove(item.path);
                                    }
                                  });
                                },
                              );
                            },
                          ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text(
                  'CANCEL',
                  style: TextStyle(color: Colors.grey),
                ),
              ),
              TextButton(
                onPressed: () {
                  setState(() {
                    for (final path in selected) {
                      final idx = _library.indexWhere((a) => a.path == path);
                      if (idx != -1) {
                        _library[idx].groupId = group.id;
                      }
                    }
                  });
                  _saveLibrary();
                  Navigator.pop(context);
                },
                child: const Text(
                  'ADD',
                  style: TextStyle(color: Color(0xFF1DB954)),
                ),
              ),
            ],
          );
        },
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
                          Row(
                            children: [
                              IconButton(
                                icon: const Icon(
                                  Icons.add_circle,
                                  color: Color(0xFF1DB954),
                                  size: 24,
                                ),
                                onPressed: () {
                                  Navigator.pop(context);
                                  _createNewGroup();
                                },
                              ),
                              SizedBox(
                                width: 120,
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
                                    setModalState(
                                      () => librarySearchQuery = val,
                                    );
                                  },
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: ListView.builder(
                        itemCount:
                            _audioGroups.length +
                            (_library.where((e) => e.groupId == null).length > 0
                                ? 1
                                : 0),
                        itemBuilder: (context, index) {
                          // Ungrouped items at the top
                          if (index == 0 &&
                              _library
                                  .where((e) => e.groupId == null)
                                  .isNotEmpty) {
                            final ungroupedItems = _library
                                .where(
                                  (e) =>
                                      e.groupId == null &&
                                      e.name.toLowerCase().contains(
                                        librarySearchQuery.toLowerCase(),
                                      ),
                                )
                                .toList();

                            return Column(
                              children: ungroupedItems.map((item) {
                                return Container(
                                  margin: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 4,
                                  ),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF181818),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: ListTile(
                                    leading: Icon(
                                      _getAudioStatusIcon(item),
                                      color: _getAudioStatusIconColor(item),
                                    ),
                                    title: Text(item.name),
                                    subtitle: Text(
                                      "${item.segments.length} segments",
                                      style: const TextStyle(
                                        color: Colors.grey,
                                      ),
                                    ),
                                    trailing: PopupMenuButton<String>(
                                      icon: const Icon(
                                        Icons.more_vert,
                                        color: Colors.grey,
                                        size: 18,
                                      ),
                                      color: const Color(0xFF222222),
                                      onSelected: (value) {
                                        if (value == 'source') {
                                          _openAudioSource(item);
                                        } else if (value == 'move') {
                                          _moveAudioToGroup(item);
                                        } else if (value == 'edit') {
                                          _editLibraryAudioName(item);
                                        } else if (value == 'delete') {
                                          setState(() {
                                            _library.remove(item);
                                            if (_currentEntry == item) {
                                              _currentEntry = null;
                                              _player.stop();
                                            }
                                          });
                                          _saveLibrary();
                                          setModalState(() {});
                                        }
                                      },
                                      itemBuilder: (context) => const [
                                        PopupMenuItem(
                                          value: 'source',
                                          child: Text(
                                            'Open source (Imam/Surah)',
                                          ),
                                        ),
                                        PopupMenuItem(
                                          value: 'move',
                                          child: Text('Move to group'),
                                        ),
                                        PopupMenuItem(
                                          value: 'edit',
                                          child: Text('Rename'),
                                        ),
                                        PopupMenuItem(
                                          value: 'delete',
                                          child: Text('Delete'),
                                        ),
                                      ],
                                    ),
                                    onTap: () {
                                      Navigator.pop(context);
                                      _loadFile(item.path, item.name);
                                    },
                                  ),
                                );
                              }).toList(),
                            );
                          }

                          // Groups
                          final groupIndex =
                              _library
                                  .where((e) => e.groupId == null)
                                  .isNotEmpty
                              ? index - 1
                              : index;
                          if (groupIndex < 0 ||
                              groupIndex >= _audioGroups.length) {
                            return const SizedBox.shrink();
                          }

                          final group = _audioGroups[groupIndex];
                          final groupItems = _library
                              .where(
                                (e) =>
                                    e.groupId == group.id &&
                                    e.name.toLowerCase().contains(
                                      librarySearchQuery.toLowerCase(),
                                    ),
                              )
                              .toList();

                          return Column(
                            children: [
                              ListTile(
                                leading: Icon(
                                  group.isExpanded
                                      ? Icons.folder_open
                                      : Icons.folder,
                                  color: const Color(0xFF1DB954),
                                ),
                                title: Text(
                                  group.name,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                subtitle: Text("${groupItems.length} items"),
                                trailing: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    IconButton(
                                      icon: const Icon(
                                        Icons.add_circle_outline,
                                        color: Color(0xFF1DB954),
                                        size: 20,
                                      ),
                                      tooltip: 'Add audio to group',
                                      onPressed: () {
                                        _showAddAudiosToGroup(group);
                                      },
                                    ),
                                    PopupMenuButton<String>(
                                      icon: const Icon(
                                        Icons.more_vert,
                                        color: Colors.grey,
                                        size: 18,
                                      ),
                                      color: const Color(0xFF222222),
                                      onSelected: (value) {
                                        if (value == 'rename') {
                                          _renameGroup(group);
                                        } else if (value == 'delete') {
                                          _deleteGroup(group);
                                          setModalState(() {});
                                        }
                                      },
                                      itemBuilder: (context) => const [
                                        PopupMenuItem(
                                          value: 'rename',
                                          child: Text('Rename group'),
                                        ),
                                        PopupMenuItem(
                                          value: 'delete',
                                          child: Text('Delete group'),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                                onTap: () {
                                  setState(() {
                                    group.isExpanded = !group.isExpanded;
                                  });
                                  setModalState(() {});
                                },
                              ),
                              if (group.isExpanded)
                                ...groupItems.map((item) {
                                  return Container(
                                    margin: const EdgeInsets.only(
                                      left: 10,
                                      right: 12,
                                      top: 2,
                                      bottom: 2,
                                    ),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFF181818),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: ListTile(
                                      leading: Padding(
                                        padding: const EdgeInsets.only(
                                          left: 12.0,
                                        ),
                                        child: Icon(
                                          _getAudioStatusIcon(item),
                                          color: _getAudioStatusIconColor(item),
                                          size: 18,
                                        ),
                                      ),
                                      title: Text(item.name),
                                      subtitle: Text(
                                        "${item.segments.length} segments",
                                        style: const TextStyle(
                                          color: Colors.grey,
                                        ),
                                      ),
                                      trailing: PopupMenuButton<String>(
                                        icon: const Icon(
                                          Icons.more_vert,
                                          color: Colors.grey,
                                          size: 18,
                                        ),
                                        color: const Color(0xFF222222),
                                        onSelected: (value) {
                                          if (value == 'source') {
                                            _openAudioSource(item);
                                          } else if (value == 'move') {
                                            _moveAudioToGroup(item);
                                          } else if (value == 'edit') {
                                            _editLibraryAudioName(item);
                                          } else if (value == 'delete') {
                                            setState(() {
                                              _library.remove(item);
                                              if (_currentEntry == item) {
                                                _currentEntry = null;
                                                _player.stop();
                                              }
                                            });
                                            _saveLibrary();
                                            setModalState(() {});
                                          }
                                        },
                                        itemBuilder: (context) => const [
                                          PopupMenuItem(
                                            value: 'source',
                                            child: Text(
                                              'Open source (Imam/Surah)',
                                            ),
                                          ),
                                          PopupMenuItem(
                                            value: 'move',
                                            child: Text('Move to group'),
                                          ),
                                          PopupMenuItem(
                                            value: 'edit',
                                            child: Text('Rename'),
                                          ),
                                          PopupMenuItem(
                                            value: 'delete',
                                            child: Text('Delete'),
                                          ),
                                        ],
                                      ),
                                      onTap: () {
                                        Navigator.pop(context);
                                        _loadFile(item.path, item.name);
                                      },
                                    ),
                                  );
                                }),
                            ],
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
          onSegmentsUpdated: _upsertAudioEntry,
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

  void _showPlaybackNotification() {
    if (_currentEntry == null) return;

    final currentTime = _formatDuration(_position);
    final totalTime = _formatDuration(_duration);
    final subtitle =
        '${_isPlaying ? "Playing" : "Paused"} • $currentTime / $totalTime';

    NotificationService().showPlaybackNotification(
      title: _currentEntry!.name,
      subtitle: subtitle,
      isPlaying: _isPlaying,
    );
  }

  void _handleNotificationAction(String action) {
    if (!mounted) return;

    switch (action) {
      case 'play_pause':
        _isPlaying ? _player.pause() : _player.play();
        break;
      case 'prev_segment':
        _seekBy(const Duration(seconds: -5));
        break;
      case 'next_segment':
        _seekBy(const Duration(seconds: 5));
        break;
      case 'stop':
        _player.stop();
        NotificationService().cancelNotification();
        break;
    }
  }

  @override
  void dispose() {
    _player.dispose();
    NotificationService().cancelNotification();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF121212),
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
                    fontSize: 15,
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
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
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
                      height: 72,
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      decoration: BoxDecoration(
                        color: const Color(0xFF181818).withAlpha(230),
                        borderRadius: BorderRadius.circular(12),
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
                  const SizedBox(height: 8),

                  // Range Slider
                  SizedBox(
                    height: 88,
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
                                    (_duration.inMilliseconds * values.start)
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
                          padding: const EdgeInsets.symmetric(horizontal: 16.0),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
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
                  const SizedBox(height: 6),

                  // Set Bounds Controls
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      _buildControlBtn("Set Start", () {
                        HapticFeedback.mediumImpact();
                        setState(() {
                          _loopStart = _position;
                          if (_loopStart > _loopEnd) _loopEnd = _duration;
                          _selectedSegmentId = null;
                        });
                      }),
                      _buildControlBtn("Reset", () {
                        HapticFeedback.mediumImpact();
                        setState(() {
                          _loopStart = Duration.zero;
                          _loopEnd = _duration;
                          _selectedSegmentId = null;
                        });
                        _player.seek(Duration.zero);
                      }),
                      _buildControlBtn("Set End", () {
                        HapticFeedback.mediumImpact();
                        setState(() {
                          _loopEnd = _position;
                          if (_loopEnd < _loopStart) {
                            _loopStart = Duration.zero;
                          }
                          _selectedSegmentId = null;
                        });
                      }),
                    ],
                  ),
                  const SizedBox(height: 8),

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
                          size: 22,
                        ),
                        onPressed: () {
                          HapticFeedback.selectionClick();
                          setState(() => _isLooping = !_isLooping);
                        },
                      ),
                      const SizedBox(width: 10),

                      IconButton(
                        iconSize: 26,
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
                        margin: const EdgeInsets.symmetric(horizontal: 6),
                        decoration: const BoxDecoration(
                          color: Color(0xFF1DB954),
                          shape: BoxShape.circle,
                        ),
                        child: IconButton(
                          iconSize: 40,
                          padding: const EdgeInsets.all(9),
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
                        iconSize: 26,
                        icon: const Icon(
                          Icons.fast_forward,
                          color: Colors.white,
                        ),
                        onPressed: () {
                          HapticFeedback.selectionClick();
                          _seekBy(const Duration(seconds: 5));
                        },
                      ),

                      const SizedBox(width: 10),
                      IconButton(
                        icon: const Icon(
                          Icons.bookmark_add,
                          color: Colors.white,
                          size: 22,
                        ),
                        onPressed: _currentEntry != null ? _saveSegment : null,
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  // Overall Progress Slider (Voice Tracer)
                  SizedBox(
                    height: 18,
                    child: SliderTheme(
                      data: SliderTheme.of(context).copyWith(
                        activeTrackColor: const Color(0xFF1DB954),
                        inactiveTrackColor: Colors.grey[800],
                        thumbColor: Colors.white,
                        trackHeight: 3.0,
                        thumbShape: const RoundSliderThumbShape(
                          enabledThumbRadius: 5.0,
                        ),
                        overlayShape: const RoundSliderOverlayShape(
                          overlayRadius: 10.0,
                        ),
                      ),
                      child: Slider(
                        value: _duration.inMilliseconds > 0
                            ? _position.inMilliseconds /
                                  _duration.inMilliseconds
                            : 0.0,
                        onChanged: (value) {
                          // Prevent bypassing loop boundaries when in loop mode
                          final newPos = Duration(
                            milliseconds: (_duration.inMilliseconds * value)
                                .toInt(),
                          );

                          // If looping the full audio (not a segment), constrain slider
                          if (_isLooping && _selectedSegmentId == null) {
                            if (newPos < _loopStart) {
                              _player.seek(_loopStart);
                            } else if (newPos > _loopEnd) {
                              _player.seek(_loopEnd);
                            } else {
                              _player.seek(newPos);
                            }
                          } else {
                            // No constraints when not looping
                            _player.seek(newPos);
                          }
                        },
                      ),
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
                            fontSize: 10,
                            height: 1.0,
                          ),
                        ),
                        Text(
                          _formatDuration(_duration),
                          style: const TextStyle(
                            color: Colors.grey,
                            fontSize: 10,
                            height: 1.0,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            // Lower Workspace: Segment List
            Expanded(
              child: Container(
                decoration: const BoxDecoration(color: Color(0xFF121212)),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 2, 16, 0),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            "Saved Segments",
                            style: TextStyle(
                              fontSize: 16,
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
                                final filteredSegments = _currentEntry!.segments
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
                                  padding: const EdgeInsets.fromLTRB(
                                    12,
                                    4,
                                    12,
                                    8,
                                  ),
                                  itemCount: filteredSegments.length,
                                  onReorder: (oldIndex, newIndex) {
                                    // Disable reordering when filtering since indices won't match
                                    if (_segmentSearchQuery.isNotEmpty) {
                                      return;
                                    }

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
                                        _selectedSegmentId == segment.id;

                                    return Container(
                                      key: ValueKey(segment.id),
                                      margin: const EdgeInsets.symmetric(
                                        vertical: 3,
                                      ),
                                      decoration: BoxDecoration(
                                        color: isSelected
                                            ? const Color(0xFF1E3C2D)
                                            : const Color(0xFF181818),
                                        borderRadius: BorderRadius.circular(8),
                                        border: Border.all(
                                          color: isSelected
                                              ? const Color(0xFF2FBF6C)
                                              : const Color(0xFF2A2A2A),
                                          width: 1,
                                        ),
                                      ),
                                      child: ListTile(
                                        dense: true,
                                        minVerticalPadding: 4,
                                        contentPadding: const EdgeInsets.only(
                                          left: 12,
                                          right: 2,
                                        ),
                                        leading: Icon(
                                          Icons.bookmark,
                                          size: 18,
                                          color: isSelected
                                              ? const Color(0xFF45D47F)
                                              : Colors.grey,
                                        ),
                                        onTap: () {
                                          _player.seek(segment.start);
                                          _player.play();
                                          setState(() {
                                            _loopStart = segment.start;
                                            _loopEnd = segment.end;
                                            _selectedSegmentId = segment.id;
                                          });
                                          int originalIndex = _currentEntry!
                                              .segments
                                              .indexOf(segment);
                                          _openSegmentPlayer(originalIndex);
                                        },
                                        title: Text(
                                          segment.name,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                            color: isSelected
                                                ? const Color(0xFFC9FBDD)
                                                : Colors.white,
                                            fontWeight: FontWeight.w600,
                                            fontSize: 14,
                                          ),
                                        ),
                                        subtitle: Text(
                                          "${_formatDuration(segment.start)} - ${_formatDuration(segment.end)}",
                                          style: TextStyle(
                                            color: isSelected
                                                ? const Color(0xFF9CE7BE)
                                                : Colors.grey,
                                            fontSize: 12,
                                          ),
                                        ),
                                        trailing: Wrap(
                                          spacing: 2,
                                          crossAxisAlignment:
                                              WrapCrossAlignment.center,
                                          children: [
                                            ReorderableDragStartListener(
                                              index: index,
                                              child: const Icon(
                                                Icons.drag_indicator,
                                                color: Colors.grey,
                                                size: 18,
                                              ),
                                            ),
                                            IconButton(
                                              visualDensity:
                                                  VisualDensity.compact,
                                              constraints:
                                                  const BoxConstraints.tightFor(
                                                    width: 28,
                                                    height: 28,
                                                  ),
                                              padding: EdgeInsets.zero,
                                              icon: const Icon(
                                                Icons.edit,
                                                color: Colors.grey,
                                                size: 17,
                                              ),
                                              onPressed: () =>
                                                  _editSegmentName(segment),
                                            ),
                                            IconButton(
                                              visualDensity:
                                                  VisualDensity.compact,
                                              constraints:
                                                  const BoxConstraints.tightFor(
                                                    width: 28,
                                                    height: 28,
                                                  ),
                                              padding: EdgeInsets.zero,
                                              icon: const Icon(
                                                Icons.delete_outline,
                                                color: Colors.redAccent,
                                                size: 18,
                                              ),
                                              onPressed: () =>
                                                  _deleteSegment(segment),
                                            ),
                                          ],
                                        ),
                                      ),
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

  Widget _buildSegmentRangeBar(LoopBookmark segment, bool isSelected) {
    final totalMs = _duration.inMilliseconds;
    final start = segment.start.inMilliseconds;
    final end = segment.end.inMilliseconds;

    double startRatio = 0.0;
    double endRatio = 1.0;
    if (totalMs > 0) {
      startRatio = (start / totalMs).clamp(0.0, 1.0);
      endRatio = (end / totalMs).clamp(startRatio, 1.0);
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final left = width * startRatio;
        final right = width * endRatio;
        final highlightWidth = (right - left).clamp(8.0, width);

        return Container(
          height: 8,
          decoration: BoxDecoration(
            color: const Color(0xFF2A2A2A),
            borderRadius: BorderRadius.circular(99),
          ),
          child: Stack(
            children: [
              Positioned(
                left: left,
                top: 0,
                bottom: 0,
                width: highlightWidth,
                child: Container(
                  decoration: BoxDecoration(
                    color: isSelected
                        ? const Color(0xFF45D47F)
                        : const Color(0xFF1DB954).withAlpha(180),
                    borderRadius: BorderRadius.circular(99),
                  ),
                ),
              ),
            ],
          ),
        );
      },
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
  final VoidCallback onSegmentsUpdated;

  const SegmentPlayerScreen({
    super.key,
    required this.player,
    required this.segments,
    required this.initialIndex,
    required this.trackName,
    required this.onSegmentsUpdated,
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
                    icon: const Icon(Icons.edit, color: Colors.white),
                    tooltip: "Edit segment bounds",
                    onPressed: _showEditSegmentSheet,
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

  void _showEditSegmentSheet() {
    Duration tempStart = currentSegment.start;
    Duration tempEnd = currentSegment.end;
    final Duration totalDuration =
        widget.player.duration ??
        (currentSegment.end > Duration.zero
            ? currentSegment.end
            : const Duration(seconds: 1));
    final int minGapMs = 500;

    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF181818),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setModalState) {
            return Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        "Edit Segment",
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close, color: Colors.grey),
                        onPressed: () => Navigator.pop(ctx),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    "Full audio: 00:00 - ${_formatDuration(totalDuration)}",
                    style: const TextStyle(color: Colors.grey),
                  ),
                  const SizedBox(height: 8),
                  RangeSlider(
                    values: RangeValues(
                      tempStart.inMilliseconds
                          .clamp(0, totalDuration.inMilliseconds)
                          .toDouble(),
                      tempEnd.inMilliseconds
                          .clamp(0, totalDuration.inMilliseconds)
                          .toDouble(),
                    ),
                    min: 0,
                    max: totalDuration.inMilliseconds.toDouble(),
                    activeColor: const Color(0xFF1DB954),
                    inactiveColor: Colors.grey[800],
                    labels: RangeLabels(
                      _formatDuration(tempStart),
                      _formatDuration(tempEnd),
                    ),
                    onChanged: (values) {
                      setModalState(() {
                        int startMs = values.start.round();
                        int endMs = values.end.round();

                        if (endMs - startMs < minGapMs) {
                          if (endMs + minGapMs <=
                              totalDuration.inMilliseconds) {
                            endMs = startMs + minGapMs;
                          } else {
                            startMs = (endMs - minGapMs).clamp(
                              0,
                              totalDuration.inMilliseconds,
                            );
                          }
                        }

                        tempStart = Duration(milliseconds: startMs);
                        tempEnd = Duration(milliseconds: endMs);
                      });
                    },
                  ),
                  const SizedBox(height: 8),
                  Text(
                    "Start: ${_formatDuration(tempStart)}",
                    style: const TextStyle(color: Colors.grey),
                  ),
                  const SizedBox(height: 4),
                  TextButton.icon(
                    icon: const Icon(Icons.flag, color: Color(0xFF1DB954)),
                    label: const Text(
                      "Set start to current position",
                      style: TextStyle(color: Colors.white),
                    ),
                    onPressed: () {
                      setModalState(() {
                        tempStart = _position;
                        if (tempStart > totalDuration) {
                          tempStart = totalDuration;
                        }
                        if (tempEnd <= tempStart) {
                          final candidate =
                              tempStart + Duration(milliseconds: minGapMs);
                          tempEnd = candidate > totalDuration
                              ? totalDuration
                              : candidate;
                        }
                      });
                    },
                  ),
                  const SizedBox(height: 12),
                  Text(
                    "End: ${_formatDuration(tempEnd)}",
                    style: const TextStyle(color: Colors.grey),
                  ),
                  const SizedBox(height: 4),
                  TextButton.icon(
                    icon: const Icon(
                      Icons.flag_circle,
                      color: Color(0xFF1DB954),
                    ),
                    label: const Text(
                      "Set end to current position",
                      style: TextStyle(color: Colors.white),
                    ),
                    onPressed: () {
                      setModalState(() {
                        tempEnd = _position;
                        if (tempEnd > totalDuration) {
                          tempEnd = totalDuration;
                        }
                        if (tempEnd <= tempStart) {
                          tempStart =
                              tempEnd - Duration(milliseconds: minGapMs);
                          if (tempStart < Duration.zero)
                            tempStart = Duration.zero;
                        }
                      });
                    },
                  ),
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(
                        child: const Text(
                          "CANCEL",
                          style: TextStyle(color: Colors.grey),
                        ),
                        onPressed: () => Navigator.pop(ctx),
                      ),
                      const SizedBox(width: 8),
                      ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF1DB954),
                          foregroundColor: Colors.black,
                        ),
                        onPressed: () {
                          setState(() {
                            currentSegment.start = tempStart;
                            currentSegment.end = tempEnd;
                          });
                          widget.player.seek(currentSegment.start);
                          widget.onSegmentsUpdated();
                          Navigator.pop(ctx);
                        },
                        child: const Text("Save"),
                      ),
                    ],
                  ),
                ],
              ),
            );
          },
        );
      },
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
