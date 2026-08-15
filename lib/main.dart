import 'dart:math' as math;
import 'dart:ui';
import 'dart:typed_data'; // 🟢 追加：Uint8List用
import 'package:flutter/material.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:file_picker/file_picker.dart'; // 🟢 追加
import 'package:hive_flutter/hive_flutter.dart'; // 🟢 追加
import 'dart:async';

void main() async {
  // 🟢 Web環境でのストレージ初期化処理を追加
  WidgetsFlutterBinding.ensureInitialized();
  await Hive.initFlutter();
  await Hive.openBox('user_audio_box'); // カスタム音声を保存するデータベースを開く
  runApp(const FocusWaveApp());
}

class FocusWaveApp extends StatelessWidget {
  const FocusWaveApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'FocusWave',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFF0A0A12),
      ),
      home: const SoundStageScreen(),
    );
  }
}

class SoundNodeData {
  final String id;
  final String name;
  final IconData icon;
  final String? assetPath;     // 🟡 修正：nullable に変更
  final Uint8List? audioBytes; // 🟢 追加：ローカルから読み込んだバイナリデータ
  final bool isAsset;          // 🟢 追加：アセット音源かどうかの識別フラグ
  final Color themeColor;
  Offset position;
  
  double currentVolume; // 現在の実際の音量
  double targetVolume;  // 本来あるべき目標の音量
  AudioPlayer? player;

  SoundNodeData({
    required this.id,
    required this.name,
    required this.icon,
    this.assetPath,            // 🟡 修正
    this.audioBytes,           // 🟢 追加
    this.isAsset = true,       // 🟢 追加（デフォルトは既存のアセット）
    required this.themeColor,
    required this.position,
    this.currentVolume = 0.0,
    this.targetVolume = 0.0,
  });
}

class SoundStageScreen extends StatefulWidget {
  const SoundStageScreen({super.key});

  @override
  State<SoundStageScreen> createState() => _SoundStageScreenState();
}

class PresetData {
  final String id;
  final String name;
  final IconData icon;
  final Color themeColor;
  final Map<String, Offset> nodePositions;

  PresetData({
    required this.id,
    required this.name,
    required this.icon,
    required this.themeColor,
    required this.nodePositions,
  });
}

class _SoundStageScreenState extends State<SoundStageScreen> with SingleTickerProviderStateMixin {
  final double _distanceScaleFactor = 3 / 8;
  
  late AnimationController _bgAnimationController;
  Timer? _fadeTimer;

  // 🟢 追加：ローカルデータベースのボックスを取得
  final Box _audioBox = Hive.box('user_audio_box');

  // ─── シートの表示切り替え用フラグ ───
  int _currentSheetTabIndex = 0;

  // ─── スリープタイマー用 ───
  Timer? _countdownTimer;
  int _remainingSeconds = 0; 
  int _totalSeconds = 0;     
  bool _isTimerActive = false;
  StateSetter? _currentSheetLiveSetter;

  // ─── アラーム機能用 ───
  bool _isAlarmEnabled = false;
  TimeOfDay _selectedAlarmTime = const TimeOfDay(hour: 7, minute: 0); 
  AudioPlayer? _alarmPlayer;            
  bool _hasTriggeredAlarmToday = false; 
  bool _isAlarmRinging = false;         
  
  bool _isMuted = true;
  String _activePresetId = 'midnight';

  // 🟢 追加：直前のセッションのノード配置を保存・復元するためのキー
  static const String _layoutStateKey = '__layout_state__';

  void _startSleepTimer(int minutes) {
    _stopSleepTimer();
    setState(() {
      _totalSeconds = minutes * 60;
      _remainingSeconds = _totalSeconds;
      _isTimerActive = true;
    });
    _runTick(); 
  }

  void _runTick() {
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_remainingSeconds > 0) {
        _remainingSeconds--;
        if (_currentSheetLiveSetter != null) {
          try { _currentSheetLiveSetter!((){}); } catch (_) {}
        }
      } else {
        _stopSleepTimer();
        if (!_isMuted) _toggleMute();
      }
    });
  }

  void _toggleTimerState() {
    setState(() {
      _isTimerActive = !_isTimerActive;
    });
    if (_isTimerActive) {
      _runTick();
    } else {
      _countdownTimer?.cancel();
    }
  }

  void _stopSleepTimer() {
    _countdownTimer?.cancel();
    setState(() {
      _isTimerActive = false;
      _remainingSeconds = 0;
    });
  }

  final List<PresetData> _presets = [
    PresetData(
      id: 'midnight',
      name: '深夜の書斎',
      icon: Icons.nights_stay_rounded,
      themeColor: const Color(0xFF6C5CE7),
      nodePositions: {
        'rain': const Offset(-50, -40),
        'fire': const Offset(40, -30),
        'cafe': const Offset(150, 150), 
        'wave': const Offset(-160, 120),
      },
    ),
    PresetData(
      id: 'cafe_terrace',
      name: '雨のカフェ',
      icon: Icons.umbrella_rounded,
      themeColor: const Color(0xFF00CEC9),
      nodePositions: {
        'rain': const Offset(-30, 20),  
        'fire': const Offset(200, -200), 
        'cafe': const Offset(40, -40),
        'wave': const Offset(-200, -200),
      },
    ),
    PresetData(
      id: 'forest',
      name: '森の夜明け',
      icon: Icons.wb_twilight_rounded,
      themeColor: const Color(0xFF74B9FF),
      nodePositions: {
        'rain': const Offset(-180, -180),
        'fire': const Offset(30, -50),
        'cafe': const Offset(-220, 150),
        'wave': const Offset(60, 60),
      },
    ),
  ];

  // 🟡 修正：動的追加に対応させるため `final` リストとして定義（中身は初期アセット）
  final List<SoundNodeData> _nodes = [
    SoundNodeData(id: 'rain', name: '雨音', icon: Icons.umbrella, assetPath: 'audio/rain.mp3', themeColor: const Color(0xFF00CEC9), position: const Offset(-50, -40)),
    SoundNodeData(id: 'fire', name: '焚き火', icon: Icons.local_fire_department, assetPath: 'audio/fire.mp3', themeColor: const Color(0xFFFF7675), position: const Offset(40, -30)),
    SoundNodeData(id: 'cafe', name: 'カフェの雑音', icon: Icons.local_cafe, assetPath: 'audio/cafe.mp3', themeColor: const Color(0xFFFFEAA7), position: const Offset(150, 150)),
    SoundNodeData(id: 'wave', name: '波の音', icon: Icons.tsunami, assetPath: 'audio/wave.mp3', themeColor: const Color(0xFF74B9FF), position: const Offset(-160, 120)),
  ];

  @override
  void initState() {
    super.initState();
    _bgAnimationController = AnimationController(
      duration: const Duration(seconds: 10),
      vsync: this,
    )..repeat(reverse: true);

    _loadUserSounds(); // 🟢 追加：過去に保存されたカスタム音声を先に読み込む
    _loadSavedLayout(); // 🟢 追加：直前のセッションで配置していたノード位置を復元
    _initAudio();
    _alarmPlayer = AudioPlayer(); 
    
    _fadeTimer = Timer.periodic(const Duration(milliseconds: 16), (timer) {
      _applyVolumeFade();
      _checkAlarmRoutine(); 
    });
  }

  // 🟢 追加：起動時にストレージからカスタム音声を展開しノード化
  void _loadUserSounds() {
    final savedKeys = _audioBox.keys;
    for (var key in savedKeys) {
      final Map? audioData = _audioBox.get(key) as Map?;
      if (audioData != null) {
        final String name = audioData['name'] ?? 'カスタム音声';
        final Uint8List bytes = audioData['bytes'] as Uint8List;

        // ステージの中央付近に少し散らして初期配置
        _nodes.add(SoundNodeData(
          id: key.toString(),
          name: name,
          icon: Icons.audio_file_rounded,
          audioBytes: bytes,
          isAsset: false,
          themeColor: const Color(0xFFA8A5FF),
          position: Offset(
            (math.Random().nextDouble() * 160) - 80,
            (math.Random().nextDouble() * 160) - 120,
          ),
        ));
      }
    }
  }

  // 🟢 追加：直前のセッションで保存されたノード配置（位置＝音量・LRパン）を復元
  void _loadSavedLayout() {
    final Map? saved = _audioBox.get(_layoutStateKey) as Map?;
    if (saved == null) return;
    for (var node in _nodes) {
      final posData = saved[node.id];
      if (posData is List && posData.length == 2) {
        node.position = Offset(
          (posData[0] as num).toDouble(),
          (posData[1] as num).toDouble(),
        );
      }
    }
    _activePresetId = ''; // 復元後は既定プリセットと一致しない状態として扱う
  }

  // 🟢 追加：現在のノード配置をローカルストレージへ永続化
  // ドラッグ終了時・プリセット読込時・カスタム音声追加時に呼び出す
  void _saveCurrentLayout() {
    final Map<String, List<double>> layout = {
      for (var node in _nodes) node.id: [node.position.dx, node.position.dy],
    };
    _audioBox.put(_layoutStateKey, layout);
  }

  // 🟢 追加：ローカルのストレージから音声ファイルを読み込んで追加するメソッド
  Future<void> _pickAndAddAudio() async {
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['mp3', 'm4a', 'wav'],
        withData: true, // Web環境でバイナリを直接メモリ展開する設定
      );

      if (result != null && result.files.first.bytes != null) {
        final platformFile = result.files.first;
        final String id = 'user_${DateTime.now().millisecondsSinceEpoch}';
        final String name = platformFile.name.replaceAll(RegExp(r'\.(mp3|m4a|wav)$'), '');
        final Uint8List bytes = platformFile.bytes!;

        // 1. ブラウザデータベースに永続保存
        await _audioBox.put(id, {
          'name': name,
          'bytes': bytes,
        });

        // 2. 新しいノードのインスタンスを作成
        final newNode = SoundNodeData(
          id: id,
          name: name,
          icon: Icons.audio_file_rounded,
          audioBytes: bytes,
          isAsset: false,
          themeColor: const Color(0xFFA8A5FF),
          position: const Offset(0, -100), // ステージ中央より少し上に配置
        );

        // 3. プレイヤーの初期設定とロード
        newNode.player = AudioPlayer();
        await newNode.player!.setReleaseMode(ReleaseMode.loop);
        await newNode.player!.setVolume(0.0);
        await newNode.player!.setSource(BytesSource(bytes));

        setState(() {
          _nodes.add(newNode);
          _activePresetId = ''; // プリセット状態を解除
        });
        _saveCurrentLayout(); // 🟢 追加：新規ノード追加時点の配置を保存

        // ミュート中でなければその場で再生開始
        if (!_isMuted) {
          final screenWidth = MediaQuery.of(context).size.width;
          _updateVolumeWithMaxDistance(newNode, newNode.position, screenWidth * _distanceScaleFactor);
          await newNode.player!.resume();
        }
      }
    } catch (e) {
      debugPrint('音声ファイルの追加に失敗しました: $e');
    }
  }

  Future<void> _initAudio() async {
    for (var node in _nodes) {
      if (node.player != null) continue; // 🟢 既に初期化済みのカスタムノードはスキップ
      
      node.player = AudioPlayer();
      await node.player!.setReleaseMode(ReleaseMode.loop);
      try {
        await node.player!.setVolume(0.0);
        
        // ─── 🟡 修正：アセットかカスタムバイナリかで再生ソースを分岐 ───
        if (node.isAsset) {
          await node.player!.setSource(AssetSource(node.assetPath!));
        } else {
          await node.player!.setSource(BytesSource(node.audioBytes!));
        }
        
        _updateVolumeWithMaxDistance(node, node.position, 200.0);
        
        if (_isMuted) {
          node.targetVolume = 0.0;
          node.currentVolume = 0.0;
          await node.player!.setVolume(0.0);
          await node.player!.stop();
        } else {
          node.currentVolume = node.targetVolume;
          await node.player!.setVolume(node.currentVolume);
          await node.player!.resume();
        }
      } catch (e) {
        debugPrint('${node.name} の初期化失敗: $e');
      }
    }
  }

  void _checkAlarmRoutine() async {
    if (!_isAlarmEnabled) return;

    final now = DateTime.now();
    if (now.hour == _selectedAlarmTime.hour && now.minute == _selectedAlarmTime.minute) {
      if (!_hasTriggeredAlarmToday) {
        _hasTriggeredAlarmToday = true;
        
        setState(() {
          _isAlarmRinging = true; 
        });

        try {
          await _alarmPlayer?.setReleaseMode(ReleaseMode.loop);
          await _alarmPlayer?.setVolume(1.0);
          await _alarmPlayer?.play(AssetSource('audio/alert.mp3'));
        } catch (e) {
          debugPrint('アラーム音声再生失敗: $e');
        }

        _triggerAlarmAction(); 
      }
    } else {
      if (_hasTriggeredAlarmToday) {
        _hasTriggeredAlarmToday = false;
      }
    }
  }

  void _stopAlarmSound() async {
    await _alarmPlayer?.setReleaseMode(ReleaseMode.release);
    await _alarmPlayer?.stop();
    setState(() {
      _isAlarmEnabled = false;
      _isAlarmRinging = false; 
    });
    if (_currentSheetLiveSetter != null) {
      try { _currentSheetLiveSetter!((){}); } catch (_) {}
    }
  }

  void _triggerAlarmAction() async {
    if (_currentSheetLiveSetter != null) {
      try { _currentSheetLiveSetter!((){}); } catch (_) {}
    }
    
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        backgroundColor: Color(0xFF6C5CE7),
        content: Row(
          children: [
            Icon(Icons.alarm_on_rounded, color: Colors.white),
            SizedBox(width: 12),
            Text('設定時間になりました！アラームを作動します。', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
          ],
        ),
        duration: Duration(seconds: 5),
      ),
    );
  }

  void _applyVolumeFade() {
    bool hasChanges = false;
    for (var node in _nodes) {
      if (node.currentVolume != node.targetVolume) {
        double step = 0.05;
        if (node.currentVolume < node.targetVolume) {
          node.currentVolume = (node.currentVolume + step).clamp(0.0, node.targetVolume);
        } else {
          node.currentVolume = (node.currentVolume - step).clamp(node.targetVolume, 1.0);
        }
        node.player?.setVolume(node.currentVolume);
        hasChanges = true;
      }
    }
    if (hasChanges) {
      setState(() {});
    }
  }

  void _toggleMute() async {
    setState(() {
      _isMuted = !_isMuted;
    });

    final screenWidth = MediaQuery.of(context).size.width;
    final maxDistance = screenWidth * _distanceScaleFactor;

    for (var node in _nodes) {
      if (node.player == null) continue;
      try {
        if (_isMuted) {
          node.targetVolume = 0.0;
        } else {
          await node.player!.resume();
          _updateVolumeWithMaxDistance(node, node.position, maxDistance);
        }
      } catch (e) {
        debugPrint('${node.name} の状態変更失敗: $e');
      }
    }
  }

  void _updateVolumeWithMaxDistance(SoundNodeData node, Offset localPos, double maxDistance) {
    double distance = math.sqrt(localPos.dx * localPos.dx + localPos.dy * localPos.dy);
    double calculatedVolume = (1.0 - (distance / maxDistance)).clamp(0.0, 1.0);

    if (!_isMuted) {
      node.targetVolume = calculatedVolume;
    } else {
      node.targetVolume = 0.0;
    }

    // 🟢 追加：中央からの左右方向のズレを、そのままステレオLRパンに反映する
    // 左に置けば左耳寄りに、右に置けば右耳寄りに聞こえる
    final double balance = (localPos.dx / maxDistance).clamp(-1.0, 1.0);
    node.player?.setBalance(balance);
  }

  void _loadPreset(PresetData preset, double maxDistance) async {
    setState(() {
      _activePresetId = preset.id;
    });

    for (var node in _nodes) {
      // 🟡 既存の4音源のみ座標データを上書きし、カスタム音声は現在の位置を維持させる安全設計
      if (preset.nodePositions.containsKey(node.id)) {
        final savedPosition = preset.nodePositions[node.id] ?? Offset.zero;
        setState(() {
          node.position = savedPosition;
        });
      }

      if (!_isMuted && node.player != null) {
        _updateVolumeWithMaxDistance(node, node.position, maxDistance);
      }
    }
    _saveCurrentLayout(); // 🟢 追加：プリセット読込後の配置を保存
  }

  void _saveCurrentAsNewPreset() {
    final TextEditingController controller = TextEditingController();
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF161823),
        title: const Text('現在の配置をプリセット保存', style: TextStyle(color: Colors.white, fontSize: 16)),
        content: TextField(
          controller: controller,
          style: const TextStyle(color: Colors.white),
          decoration: InputDecoration(
            hintText: 'プリセット名を入力',
            hintStyle: TextStyle(color: Colors.white.withOpacity(0.3)),
            enabledBorder: const UnderlineInputBorder(borderSide: BorderSide(color: Colors.white24)),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('キャンセル', style: TextStyle(color: Colors.white38)),
          ),
          TextButton(
            onPressed: () {
              if (controller.text.trim().isEmpty) return;
              
              final Map<String, Offset> currentPositions = {};
              for (var node in _nodes) {
                currentPositions[node.id] = node.position;
              }

              setState(() {
                final newId = 'custom_${DateTime.now().millisecondsSinceEpoch}';
                _presets.add(PresetData(
                  id: newId,
                  name: controller.text.trim(),
                  icon: Icons.bookmark_added_rounded,
                  themeColor: const Color(0xFFFFEAA7), 
                  nodePositions: currentPositions,
                ));
                _activePresetId = newId; 
              });

              Navigator.pop(context); 
              Navigator.pop(context); 
            },
            child: const Text('保存', style: TextStyle(color: Color(0xFF6C5CE7), fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _fadeTimer?.cancel();
    _countdownTimer?.cancel();
    _bgAnimationController.dispose();
    for (var node in _nodes) {
      node.player?.dispose();
    }
    _alarmPlayer?.dispose(); 
    super.dispose();
  }

  // 🟢 追加：アプリ情報とTHE BONJINクレジットを表示するシート
  void _showAboutSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withOpacity(0.4),
      builder: (context) {
        return ClipRRect(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 25, sigmaY: 25),
            child: Container(
              decoration: BoxDecoration(
                color: const Color(0xFF161823).withOpacity(0.9),
                border: Border(top: BorderSide(color: Colors.white.withOpacity(0.1), width: 1)),
              ),
              child: SafeArea(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 36,
                        height: 4,
                        decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2)),
                      ),
                      const SizedBox(height: 24),
                      const Text(
                        'FocusWave',
                        style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.white),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '環境音ミキサー × スリープタイマー × アラーム',
                        style: TextStyle(fontSize: 12, color: Colors.white.withOpacity(0.4)),
                      ),
                      const SizedBox(height: 32),
                      Container(
                        width: 56,
                        height: 56,
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Image.asset('assets/branding/bonjin_logo.png', fit: BoxFit.contain),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'produced by THE BONJIN',
                        style: TextStyle(fontSize: 12, color: Colors.white.withOpacity(0.4), letterSpacing: 0.5),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  void _showGlassBottomSheet(String title, int initialTabIndex, double maxDistance) {
    _currentSheetTabIndex = initialTabIndex; 

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withOpacity(0.4),
      isScrollControlled: true, 
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setOuterSheetState) {
            return Container(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(context).size.height * 0.85,
              ),
              child: ClipRRect(
                borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 25, sigmaY: 25),
                  child: Container(
                    decoration: BoxDecoration(
                      color: const Color(0xFF161823).withOpacity(0.9),
                      border: Border(
                        top: BorderSide(color: Colors.white.withOpacity(0.1), width: 1),
                      ),
                    ),
                    child: SafeArea(
                      child: Column(
                        mainAxisSize: MainAxisSize.min, 
                        children: [
                          const SizedBox(height: 16),
                          Container(
                            width: 36,
                            height: 4,
                            decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2)),
                          ),
                          const SizedBox(height: 12),
                          
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 24),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                const SizedBox(width: 32), 
                                Text(
                                  _currentSheetTabIndex == 0 
                                      ? 'PresetManager' 
                                      : (_currentSheetTabIndex == 1 ? 'SleepTimer' : 'AlarmClock'), 
                                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white, letterSpacing: 0.5),
                                ),
                                GestureDetector(
                                  onTap: () => Navigator.pop(context),
                                  child: Container(
                                    padding: const EdgeInsets.all(6),
                                    decoration: BoxDecoration(color: Colors.white.withOpacity(0.08), shape: BoxShape.circle),
                                    child: const Icon(Icons.close, size: 16, color: Colors.white70),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 24),
                          
                          Flexible(
                            child: SingleChildScrollView(
                              padding: const EdgeInsets.symmetric(horizontal: 24),
                              child: _currentSheetTabIndex == 0
                                  ? _buildPresetList(maxDistance)
                                  : (_currentSheetTabIndex == 1 ? _buildTimerSelection() : _buildAlarmSelection()),
                            ),
                          ),
                          
                          const SizedBox(height: 16),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            );
          }
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;
    final center = Offset(screenSize.width / 2, screenSize.height / 2 - 20);
    final double maxDistance = screenSize.width * _distanceScaleFactor;

    return Scaffold(
      body: Stack(
        children: [
          AnimatedBuilder(
            animation: _bgAnimationController,
            builder: (context, child) {
              return Container(
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    center: Alignment(
                      0.3 + 0.2 * math.sin(_bgAnimationController.value * math.pi),
                      -0.4 + 0.2 * math.cos(_bgAnimationController.value * math.pi),
                    ),
                    radius: 1.5,
                    colors: const [
                      Color(0xFF1B2A47),
                      Color(0xFF0F1123),
                      Color(0xFF07070A),
                    ],
                  ),
                ),
              );
            },
          ),
          _buildSpaceGrid(center, maxDistance),
          
          Positioned(
            left: center.dx - 40,
            top: center.dy - 40,
            child: GestureDetector(
              onTap: _toggleMute,
              child: _buildListenerNode(),
            ),
          ),
          
          if (_isAlarmRinging)
            Positioned(
              left: center.dx - 75,
              top: center.dy + 55, 
              child: AnimatedOpacity(
                opacity: _isAlarmRinging ? 1.0 : 0.0,
                duration: const Duration(milliseconds: 300),
                child: SizedBox(
                  width: 150,
                  height: 46,
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFFF7675),
                      foregroundColor: Colors.white,
                      elevation: 8,
                      shadowColor: const Color(0xFFFF7675).withOpacity(0.5),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
                    ),
                    onPressed: _stopAlarmSound,
                    icon: const Icon(Icons.alarm_off_rounded, size: 18),
                    label: const Text('アラーム停止', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                  ),
                ),
              ),
            ),
          
          ..._nodes.map((node) {
            final absolutePosition = center + node.position;
            return Positioned(
              left: absolutePosition.dx - 45,
              top: absolutePosition.dy - 55,
              child: GestureDetector(
                onPanUpdate: (details) {
                  setState(() {
                    node.position += details.delta;
                    _updateVolumeWithMaxDistance(node, node.position, maxDistance);
                    _activePresetId = '';
                  });
                },
                // 🟢 追加：ドラッグ終了時点の配置を保存（ドラッグ中は毎フレーム保存しない）
                onPanEnd: (_) => _saveCurrentLayout(),
                child: _buildSoundNode(node, maxDistance),
              ),
            );
          }),

          Positioned(
            top: 50,
            left: 20,
            right: 20,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                IconButton(
                  icon: const Icon(Icons.menu, color: Colors.white70),
                  onPressed: _showAboutSheet, // 🟢 追加：アプリ情報 / THE BONJINクレジット表示
                ),
                const Text(
                  'Sound Stage',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, letterSpacing: 0.8, color: Colors.white),
                ),
                // 🟡 修正：グラフアイコンから、ローカルストレージからの「音声ファイル追加ボタン」に変更
                IconButton(
                  icon: const Icon(Icons.add_to_photos_rounded, color: Colors.white70), 
                  onPressed: _pickAndAddAudio,
                ),
              ],
            ),
          ),

          Positioned(
            top: 110,
            left: 0,
            right: 0,
            child: Center(
              child: Text(
                _isMuted ? '中央のアイコンをタップしてスタート' : 'ノードをドラッグして音を配置。',
                style: TextStyle(color: _isMuted ? const Color(0xFFFF7675) : Colors.white.withOpacity(0.35), fontSize: 13, letterSpacing: 0.5),
              ),
            ),
          ),

          Positioned(
            bottom: 34,
            left: 24,
            right: 24,
            child: _buildBottomGlassMenu(maxDistance),
          ),
        ],
      ),
    );
  }

  Widget _buildSpaceGrid(Offset center, double maxDistance) {
    return Center(
      child: Stack(
        alignment: Alignment.center,
        children: [
          Container(
            width: maxDistance * 2,
            height: maxDistance * 2,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white.withOpacity(0.04), width: 1.5),
            ),
          ),
          Container(
            width: maxDistance,
            height: maxDistance,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white.withOpacity(0.06), width: 1),
            ),
          ),
          Container(
            width: maxDistance * 0.5,
            height: maxDistance * 0.5,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white.withOpacity(0.09), width: 1),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildListenerNode() {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      width: 80,
      height: 80,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: _isMuted ? Colors.red.withOpacity(0.1) : const Color(0xFF6C5CE7).withOpacity(0.15),
        boxShadow: [
          BoxShadow(
            color: _isMuted ? Colors.red.withOpacity(0.3) : const Color(0xFF6C5CE7).withOpacity(0.4), 
            blurRadius: 25, 
            spreadRadius: 2
          ),
        ],
        border: Border.all(
          color: _isMuted ? Colors.redAccent.withOpacity(0.8) : const Color(0xFFA8A5FF).withOpacity(0.8), 
          width: 2.5
        ),
      ),
      child: Icon(
        _isMuted ? Icons.volume_off_rounded : Icons.headphones_rounded, 
        color: Colors.white, 
        size: 32
      ),
    );
  }

  Widget _buildSoundNode(SoundNodeData node, double maxDistance) {
    final double effectiveVolume = node.currentVolume; 
    final double scale = 0.8 + (effectiveVolume * 0.4);
    final double opacity = 0.4 + (effectiveVolume * 0.6);

    double distance = math.sqrt(node.position.dx * node.position.dx + node.position.dy * node.position.dy);
    double displayVolumePercent = (1.0 - (distance / maxDistance)).clamp(0.0, 1.0);

    return Transform.scale(
      scale: scale,
      child: Opacity(
        opacity: opacity,
        child: Column(
          children: [
            Container(
              width: 70,
              height: 70,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withOpacity(0.06),
                border: Border.all(
                  color: effectiveVolume > 0.1 ? node.themeColor.withOpacity(0.6) : Colors.white.withOpacity(0.2),
                  width: 1.5,
                ),
                boxShadow: effectiveVolume > 0.1
                    ? [BoxShadow(color: node.themeColor.withOpacity(effectiveVolume * 0.4), blurRadius: 20, spreadRadius: 2)]
                    : [],
              ),
              child: Icon(
                node.icon,
                color: effectiveVolume > 0.1 ? node.themeColor : Colors.white,
                size: 30,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              node.name,
              style: const TextStyle(color: Color(0xFFEEEEEE), fontSize: 12, fontWeight: FontWeight.w500),
            ),
            Text(
              _isMuted ? '0%' : '${(displayVolumePercent * 100).toInt()}%',
              style: TextStyle(color: Colors.white.withOpacity(0.4), fontSize: 10),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBottomGlassMenu(double maxDistance) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.07),
            borderRadius: BorderRadius.circular(24), 
            border: Border.all(color: Colors.white.withOpacity(0.08), width: 1),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _buildBottomTabItem(
                icon: Icons.apps_rounded, 
                label: 'プリセット',
                onTap: () => _showGlassBottomSheet('PresetManager', 0, maxDistance),
              ),
              _buildBottomTabItem(
                icon: Icons.access_time_rounded,
                label: 'タイマー',
                onTap: () => _showGlassBottomSheet('SleepTimer', 1, maxDistance),
              ),
              _buildBottomTabItem(
                icon: Icons.alarm_rounded, 
                label: 'アラーム',
                onTap: () => _showGlassBottomSheet('AlarmClock', 2, maxDistance),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBottomTabItem({required IconData icon, required String label, required VoidCallback onTap}) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: SizedBox(
        width: 90,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: Colors.white70, size: 24),
            const SizedBox(height: 5),
            Text(
              label, 
              style: TextStyle(color: Colors.white.withOpacity(0.6), fontSize: 11, fontWeight: FontWeight.w500),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPresetList(double maxDistance) {
    return StatefulBuilder(
      builder: (BuildContext context, StateSetter setSheetState) {
        final activePreset = _presets.firstWhere(
          (p) => p.id == _activePresetId,
          orElse: () => _presets.first,
        );

        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'お気に入りプリセット',
                style: TextStyle(
                  color: Colors.white.withOpacity(0.6), 
                  fontSize: 13, 
                  fontWeight: FontWeight.w500
                ),
              ),
            ),
            const SizedBox(height: 16),
            
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  flex: 3,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: _presets.map((preset) {
                      final bool isActive = preset.id == _activePresetId;
                      return GestureDetector(
                        onTap: () {
                          _loadPreset(preset, maxDistance);
                          setSheetState(() {
                            _activePresetId = preset.id;
                          });
                        },
                        child: _buildPresetCard(
                          preset.name,
                          preset.id.startsWith('custom_') ? 'カスタム配置' : '焚き火・雨・カフェ・時計',
                          preset.icon,
                          preset.themeColor,
                          isActive: isActive,
                        ),
                      );
                    }).toList(),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 2,
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      return _buildMiniMapPreview(activePreset);
                    },
                  ),
                ),
              ],
            ),
            
            const SizedBox(height: 24),
            
            SizedBox(
              width: double.infinity,
              height: 50,
              child: OutlinedButton(
                onPressed: () {
                  _saveCurrentAsNewPreset();
                },
                style: OutlinedButton.styleFrom(
                  side: BorderSide(color: Colors.white.withOpacity(0.2)),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  backgroundColor: Colors.white.withOpacity(0.05),
                ),
                child: const Text(
                  '新しい配置を保存',
                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildPresetCard(String title, String subtitle, IconData icon, Color color, {bool isActive = false}) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      margin: const EdgeInsets.symmetric(vertical: 6),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isActive ? color.withOpacity(0.18) : Colors.white.withOpacity(0.03),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isActive ? color : Colors.white.withOpacity(0.06),
          width: isActive ? 1.5 : 1.0,
        ),
        boxShadow: isActive
            ? [
                BoxShadow(
                  color: color.withOpacity(0.25),
                  blurRadius: 12,
                  spreadRadius: 1,
                )
              ]
            : [],
      ),
      child: Row(
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: isActive ? color.withOpacity(0.3) : color.withOpacity(0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              icon, 
              color: isActive ? Colors.white : color.withOpacity(0.8), 
              size: 20
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title, 
                  style: TextStyle(
                    color: Colors.white, 
                    fontSize: 14, 
                    fontWeight: isActive ? FontWeight.bold : FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle, 
                  style: TextStyle(
                    color: isActive ? Colors.white.withOpacity(0.5) : Colors.white.withOpacity(0.3), 
                    fontSize: 10,
                  ),
                ),
              ],
            ),
          ),
          if (isActive)
            Icon(Icons.check_circle_rounded, color: color, size: 18),
        ],
      ),
    );
  }

  Widget _buildMiniMapPreview(PresetData preset) {
    Offset getMiniOffset(String nodeId) {
      final originOffset = preset.nodePositions[nodeId] ?? Offset.zero;
      return Offset(originOffset.dx / 3.5, originOffset.dy / 3.5);
    }

    return Column(
      children: [
        Container(
          height: 140,
          width: double.infinity,
          decoration: BoxDecoration(
            color: Colors.black.withOpacity(0.2),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Colors.white.withOpacity(0.05)),
          ),
          child: Stack(
            alignment: Alignment.center,
            children: [
              Container(
                width: 12,
                height: 12,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: const Color(0xFF6C5CE7),
                  boxShadow: [BoxShadow(color: const Color(0xFF6C5CE7).withOpacity(0.5), blurRadius: 4)],
                ),
                child: const Icon(Icons.headphones, size: 6, color: Colors.white),
              ),
              _buildMiniMapDot(getMiniOffset('fire'), const Color(0xFFFF7675)), 
              _buildMiniMapDot(getMiniOffset('cafe'), const Color(0xFFFFEAA7)),  
              _buildMiniMapDot(getMiniOffset('rain'), const Color(0xFF00CEC9)), 
              _buildMiniMapDot(getMiniOffset('wave'), const Color(0xFF74B9FF)), 
            ],
          ),
        ),
        const SizedBox(height: 12),
        Text(
          preset.name,
          style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w500),
        ),
      ],
    );
  }

  Widget _buildMiniMapDot(Offset offset, Color color) {
    return Transform.translate(
      offset: offset,
      child: Container(
        width: 8,
        height: 8,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: color,
          boxShadow: [BoxShadow(color: color.withOpacity(0.5), blurRadius: 6)],
        ),
      ),
    );
  }

  Widget _buildTimerSelection() {
    return StatefulBuilder(
      builder: (context, setSheetState) {
        _currentSheetLiveSetter = setSheetState;

        int displayMinutes;
        String timeDisplayString;

        if (_remainingSeconds > 0) {
          final int m = _remainingSeconds ~/ 60;
          final int s = _remainingSeconds % 60;
          timeDisplayString = '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
          displayMinutes = m;
        } else {
          displayMinutes = _totalSeconds > 0 ? (_totalSeconds / 60).round() : 30;
          timeDisplayString = '$displayMinutes:00';
        }

        final double progress = _totalSeconds > 0 ? _remainingSeconds / _totalSeconds : 0.0;

        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              _remainingSeconds > 0 ? 'バックグラウンドでフェードアウト中' : '時間を設定してください',
              style: TextStyle(
                color: _remainingSeconds > 0 ? const Color(0xFF74B9FF) : Colors.white, 
                fontSize: 14, 
                fontWeight: FontWeight.w600,
                letterSpacing: 0.5
              ),
            ),
            const SizedBox(height: 24),

            Stack(
              alignment: Alignment.center,
              children: [
                SizedBox(
                  width: 180,
                  height: 180,
                  child: CircularProgressIndicator(
                    value: 1.0,
                    strokeWidth: 8,
                    valueColor: AlwaysStoppedAnimation<Color>(Colors.white.withOpacity(0.04)),
                  ),
                ),
                SizedBox(
                  width: 180,
                  height: 180,
                  child: CircularProgressIndicator(
                    value: _remainingSeconds > 0 ? progress : 1.0,
                    strokeWidth: 8,
                    strokeCap: StrokeCap.round,
                    valueColor: AlwaysStoppedAnimation<Color>(
                      _remainingSeconds > 0 ? const Color(0xFF74B9FF) : const Color(0xFF6C5CE7).withOpacity(0.3),
                    ),
                  ),
                ),
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      timeDisplayString,
                      style: TextStyle(
                        fontSize: _remainingSeconds > 0 ? 32 : 38, 
                        fontWeight: FontWeight.bold, 
                        color: Colors.white,
                        letterSpacing: _remainingSeconds > 0 ? 1.0 : 0.0
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _remainingSeconds > 0 ? 'REMAINING' : 'MINUTES', 
                      style: TextStyle(color: Colors.white.withOpacity(0.4), fontSize: 9, letterSpacing: 1.5, fontWeight: FontWeight.bold)
                    ),
                    const SizedBox(height: 12),
                    GestureDetector(
                      onTap: () {
                        setSheetState(() {
                          if (_remainingSeconds > 0) {
                            _toggleTimerState(); 
                          } else {
                            _startSleepTimer(displayMinutes); 
                          }
                        });
                      },
                      child: Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: _isTimerActive ? const Color(0xFFFF7675) : const Color(0xFF6C5CE7),
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: (_isTimerActive ? const Color(0xFFFF7675) : const Color(0xFF6C5CE7)).withOpacity(0.4),
                              blurRadius: 10,
                            )
                          ],
                        ),
                        child: Icon(
                          _remainingSeconds == 0 
                              ? Icons.play_arrow_rounded 
                              : (_isTimerActive ? Icons.pause_rounded : Icons.play_arrow_rounded),
                          color: Colors.white,
                          size: 22,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 24),

            Opacity(
              opacity: _remainingSeconds > 0 ? 0.3 : 1.0,
              child: Column(
                children: [
                  SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      activeTrackColor: const Color(0xFF74B9FF),
                      inactiveTrackColor: Colors.white12,
                      thumbColor: Colors.white,
                      overlayColor: const Color(0xFF74B9FF).withOpacity(0.2),
                    ),
                    child: Slider(
                      value: displayMinutes.toDouble().clamp(1.0, 120.0),
                      min: 1.0,
                      max: 120.0,
                      divisions: 119,
                      onChanged: _remainingSeconds > 0 ? null : (double newValue) {
                        setSheetState(() {
                          _totalSeconds = newValue.round() * 60;
                        });
                      },
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('1分', style: TextStyle(color: Colors.white.withOpacity(0.3), fontSize: 11)),
                        Text('ドラッグして時間をカスタム調整', style: TextStyle(color: Colors.white.withOpacity(0.4), fontSize: 11)),
                        Text('120分', style: TextStyle(color: Colors.white.withOpacity(0.3), fontSize: 11)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            if (_remainingSeconds == 0)
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [30, 60, 90].map((m) => Container(
                  margin: const EdgeInsets.symmetric(horizontal: 6),
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.white.withOpacity(0.06),
                      foregroundColor: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                    ),
                    onPressed: () {
                      setSheetState(() {
                        _startSleepTimer(m); 
                      });
                    },
                    child: Text('${m}分'),
                  ),
                )).toList(),
              )
            else
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.white.withOpacity(0.08),
                  foregroundColor: const Color(0xFFFF7675),
                  elevation: 0,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                ),
                onPressed: () {
                  setSheetState(() {
                    _stopSleepTimer();
                  });
                },
                icon: const Icon(Icons.refresh_rounded, size: 18),
                label: const Text('タイマーをキャンセル', style: TextStyle(fontWeight: FontWeight.bold)),
              ),

            const SizedBox(height: 24),
            // 🟡 修正：「バックグラウンド再生対応」という誤解を招く表記を撤回し、
            // アラーム画面と同じ内容の正直な注意書きに統一する
            // （画面ロック・バックグラウンド移行でタイマーが一時停止する制約は両画面で共通のため）
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 12),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFFFF7675).withOpacity(0.08),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: const Color(0xFFFF7675).withOpacity(0.25),
                  width: 1,
                ),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Padding(
                    padding: EdgeInsets.only(top: 2),
                    child: Icon(Icons.warning_amber_rounded, color: Color(0xFFFF7675), size: 18),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      '画面をロックしたりバックグラウンドに移行すると、タイマーが一時停止する場合があります。使用中は画面を点灯したままにすることをおすすめします。',
                      style: TextStyle(color: Colors.white.withOpacity(0.6), fontSize: 11, height: 1.4),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _buildStatusIcon(Icons.wifi, 'PWA', const Color(0xFF2ECC71)),
                const SizedBox(width: 24),
                _buildStatusIcon(Icons.person_off_rounded, 'オフライン対応', Colors.white24),
              ],
            ),
          ],
        );
      }
    );
  }

  Widget _buildStatusIcon(IconData icon, String label, Color color) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16, color: color),
        const SizedBox(width: 8),
        Text(
          label, 
          style: TextStyle(
            color: color.withOpacity(0.8), 
            fontSize: 12,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }

  Widget _buildAlarmSelection() {
    return StatefulBuilder(
      builder: (context, setSheetState) {
        _currentSheetLiveSetter = setSheetState;

        final String hourStr = _selectedAlarmTime.hour.toString().padLeft(2, '0');
        final String minuteStr = _selectedAlarmTime.minute.toString().padLeft(2, '0');
        final String periodStr = _selectedAlarmTime.period == DayPeriod.am ? 'AM' : 'PM';

        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              _isAlarmEnabled ? '指定時刻にアラームが鳴ります' : 'アラームはオフです',
              style: TextStyle(
                color: _isAlarmEnabled ? const Color(0xFF2ECC71) : Colors.white60,
                fontSize: 14,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.5,
              ),
            ),
            const SizedBox(height: 24),

            GestureDetector(
              onTap: () async {
                final TimeOfDay? picked = await showTimePicker(
                  context: context,
                  initialTime: _selectedAlarmTime,
                  builder: (BuildContext context, Widget? child) {
                    return Theme(
                      data: ThemeData.dark().copyWith(
                        colorScheme: const ColorScheme.dark(
                          primary: Color(0xFF6C5CE7), 
                          onPrimary: Colors.white,
                          surface: Color(0xFF1E1E24), 
                          onSurface: Colors.white,
                        ),
                        timePickerTheme: TimePickerThemeData(
                          backgroundColor: const Color(0xFF1E1E24),
                          hourMinuteColor: Colors.white.withOpacity(0.05),
                          hourMinuteTextColor: Colors.white,
                          dayPeriodColor: Colors.white.withOpacity(0.05),
                          dayPeriodTextColor: Colors.white,
                        ),
                      ),
                      child: child!,
                    );
                  },
                );

                if (picked != null && picked != _selectedAlarmTime) {
                  setSheetState(() {
                    _selectedAlarmTime = picked;
                    _isAlarmEnabled = true;
                    _hasTriggeredAlarmToday = false;
                  });
                  setState(() {});
                }
              },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 20),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.03),
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(
                    color: _isAlarmEnabled ? const Color(0xFF6C5CE7).withOpacity(0.3) : Colors.white10,
                    width: 1,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    Icon(
                      Icons.access_time_filled_rounded,
                      size: 20,
                      color: _isAlarmEnabled ? const Color(0xFF74B9FF) : Colors.white38,
                    ),
                    const SizedBox(width: 12),
                    Text(
                      '$hourStr:$minuteStr',
                      style: const TextStyle(
                        fontSize: 42,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                        letterSpacing: 1,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      periodStr,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: _isAlarmEnabled ? const Color(0xFF74B9FF) : Colors.white38,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              '数値をタップして時刻を変更',
              style: TextStyle(color: Colors.white.withOpacity(0.3), fontSize: 11),
            ),
            const SizedBox(height: 24),

            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFFF7675).withOpacity(0.15),
                foregroundColor: const Color(0xFFFF7675),
                elevation: 0,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              ),
              onPressed: _stopAlarmSound,
              icon: const Icon(Icons.alarm_off_rounded, size: 16),
              label: const Text('アラーム音を停止', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
            const SizedBox(height: 24),

            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              margin: const EdgeInsets.symmetric(horizontal: 24), 
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.02),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Row(
                      children: [
                        Icon(
                          _isAlarmEnabled ? Icons.alarm_on_rounded : Icons.alarm_off_rounded,
                          color: _isAlarmEnabled ? const Color(0xFF2ECC71) : Colors.white30,
                        ),
                        const SizedBox(width: 12),
                        const Expanded(
                          child: Text(
                            'アラームを有効にする',
                            style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w500),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Switch(
                    value: _isAlarmEnabled,
                    activeColor: const Color(0xFF2ECC71),
                    activeTrackColor: const Color(0xFF2ECC71).withOpacity(0.3),
                    inactiveThumbColor: Colors.white60,
                    inactiveTrackColor: Colors.white12,
                    onChanged: (bool value) {
                      if (!value) {
                        _stopAlarmSound();
                      }
                      setSheetState(() {
                        _isAlarmEnabled = value;
                        if (value) _hasTriggeredAlarmToday = false;
                      });
                      setState(() {});
                    },
                  ),
                ],
              ),
            ),

            const SizedBox(height: 16),
            
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 24),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFFFF7675).withOpacity(0.08),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: const Color(0xFFFF7675).withOpacity(0.25),
                  width: 1,
                ),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Padding(
                    padding: EdgeInsets.only(top: 2),
                    child: Icon(Icons.warning_amber_rounded, color: Color(0xFFFF7675), size: 18),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'PWA環境での動作に関するご注意',
                          style: TextStyle(color: Color(0xFFFF7675), fontSize: 12, fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'お使いのOS（特にiOS）の仕様により、画面をロックしたりバックグラウンドに移行すると、タイマーが一時停止しアラームが予定時刻に鳴らない場合があります。確実な動作のため、使用中は画面を点灯したまま（自動スリープオフ）にすることをおすすめします。',
                          style: TextStyle(color: Colors.white.withOpacity(0.6), fontSize: 11, height: 1.4),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 32),
            Text(
              'スマート通知対応',
              style: TextStyle(color: Colors.white.withOpacity(0.2), fontSize: 11),
            ),
            const SizedBox(height: 20),

            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _buildStatusIcon(Icons.wifi, 'PWA', const Color(0xFF2ECC71)),
                const SizedBox(width: 24),
                _buildStatusIcon(Icons.person_off_rounded, 'オフライン対応', Colors.white24),
              ],
            ),
          ],
        );
      }
    );
  }
}