import 'package:flutter/material.dart';

// 🚨 プロジェクト名（uniflow_miyazaki）を頭に付け、実際の配置パスに合わせます
import 'package:uniflow_miyazaki/storage/app_storage.dart'; 
import 'package:uniflow_miyazaki/services/syllabus_service.dart';

import 'dart:convert'; // jsonEncode / jsonDecode 用
import 'package:shared_preferences/shared_preferences.dart'; // SharedPreferences 用

// 🚨 main関数の前に async を付与します
void main() async {
  // SharedPreferencesなどのネイティブ通信のバインドを担保する必須処理
  WidgetsFlutterBinding.ensureInitialized();
  
  // 端末ストレージから保存されていた既存データを完全に復元
  await AppStorage.loadFromStorage();
  
  // 静的シラバスJSONデータのロード（非同期）
  SyllabusService.loadSyllabusJson();
  runApp(const UniFlowMiyazakiApp());
}

class UniFlowMiyazakiApp extends StatelessWidget {
  const UniFlowMiyazakiApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'UniFlow Miyazaki',
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF005BAC),
          primary: const Color(0xFF005BAC),
          secondary: const Color(0xFF00A79D),
          tertiary: const Color(0xFFFFC107),
        ),
      ),
      home: const MainNavigationScreen(),
      debugShowCheckedModeBanner: false,
    );
  }
}

// ==========================================
// 💾 【1. データレイヤー】永続化・遅刻欠席ロジック
// ==========================================
class AppStorage {
  // ---------------------------------------------------------------------------
  // 状態データ（メモリ上のキャッシュ）- 【出荷状態】すべて初期化・空に設定
  // ---------------------------------------------------------------------------
  static double _gpa = 0.0;
  static int _credits = 0;
  static final List<Map<String, dynamic>> _attendanceLog = [];

  /// 各講義の 欠席数(absence) と 遅刻数(lateness)
  static Map<String, Map<String, int>> _attendanceCounts = {};

  /// シラバス情報
  static Map<String, Map<String, dynamic>> syllabusMaster = {};

  /// 時間割配置データ
  static Map<int, Map<int, String>> userTimetableCodes = {
    0: {}, // 月
    1: {}, // 火
    2: {}, // 水
    3: {}, // 木
    4: {}, // 金
  };

  /// 【新規】ユーザー作成のメモ一覧
  /// 構造: {'id': String, 'title': String, 'content': String, 'priority': int (3=高, 2=中, 1=低), 'createdAt': String}
  static List<Map<String, dynamic>> _memos = [];

  // ストレージ保存用の固定キー名
  static const String _keyGpa = 'uniflow_gpa';
  static const String _keyCredits = 'uniflow_credits';
  static const String _keyLog = 'uniflow_attendance_log';
  static const String _keyCounts = 'uniflow_attendance_counts';
  static const String _keySyllabus = 'uniflow_syllabus_master';
  static const String _keyTimetable = 'uniflow_user_timetable';
  static const String _keyMemos = 'uniflow_user_memos'; // メモ用のキー

  // ---------------------------------------------------------------------------
  // 🔄 永続化ストレージ制御 (Save & Load)
  // ---------------------------------------------------------------------------

  /// アプリ起動時にローカルストレージからユーザーデータを復元するメソッド
  static Future<void> loadFromStorage() async {
    final prefs = await SharedPreferences.getInstance();
    try {
      // 出荷時のデフォルト値を 0.0 / 0 に変更
      _gpa = prefs.getDouble(_keyGpa) ?? 0.0;
      _credits = prefs.getInt(_keyCredits) ?? 0;

      // 2. 出席ログ
      final String? logJson = prefs.getString(_keyLog);
      if (logJson != null) {
        _attendanceLog.clear();
        final List<dynamic> decodedList = jsonDecode(logJson);
        _attendanceLog.addAll(decodedList.map((e) => Map<String, dynamic>.from(e)));
      }

      // 3. 出席カウンター
      final String? countsJson = prefs.getString(_keyCounts);
      if (countsJson != null) {
        final Map<String, dynamic> decoded = jsonDecode(countsJson);
        _attendanceCounts = decoded.map((key, value) {
          final map = Map<String, dynamic>.from(value);
          return MapEntry(key, {
            'absence': (map['absence'] as num).toInt(), 
            'lateness': (map['lateness'] as num).toInt()
          });
        });
      }

      // 4. シラバスマスター
      final String? syllabusJson = prefs.getString(_keySyllabus);
      if (syllabusJson != null) {
        final Map<String, dynamic> decoded = jsonDecode(syllabusJson);
        syllabusMaster = decoded.map((key, value) => MapEntry(key, Map<String, dynamic>.from(value)));
      }

      // 5. 時間割配置
      final String? timetableJson = prefs.getString(_keyTimetable);
      if (timetableJson != null) {
        final Map<String, dynamic> decoded = jsonDecode(timetableJson);
        userTimetableCodes.clear(); 
        decoded.forEach((key, value) {
          final Map<int, String> innerMap = {};
          Map<String, dynamic>.from(value).forEach((pKey, pValue) {
            innerMap[int.parse(pKey)] = pValue.toString();
          });
          userTimetableCodes[int.parse(key)] = innerMap;
        });
      }

      // 【新規追加】メモデータのロード
      final String? memosJson = prefs.getString(_keyMemos);
      if (memosJson != null) {
        _memos.clear();
        final List<dynamic> decodedMemos = jsonDecode(memosJson);
        _memos.addAll(decodedMemos.map((e) => Map<String, dynamic>.from(e)));
      }

      print("📦 [AppStorage] ユーザーデータを完全に復元しました。");
    } catch (e) {
      print("🚨 [AppStorage] データ復元中にエラーが発生しました: $e");
    }
  }

  /// 現在のメモリ状態をローカルストレージに非同期保存する内部関数
  static Future<void> _saveToStorage() async {
    final prefs = await SharedPreferences.getInstance();
    try {
      await prefs.setDouble(_keyGpa, _gpa);
      await prefs.setInt(_keyCredits, _credits);
      await prefs.setString(_keyLog, jsonEncode(_attendanceLog));
      await prefs.setString(_keyCounts, jsonEncode(_attendanceCounts));
      await prefs.setString(_keySyllabus, jsonEncode(syllabusMaster));

      final Map<String, Map<String, String>> timetableToSave = {};
      userTimetableCodes.forEach((dayKey, periodMap) {
        final Map<String, String> stringPeriodMap = {};
        periodMap.forEach((periodKey, lectureId) {
          stringPeriodMap[periodKey.toString()] = lectureId;
        });
        timetableToSave[dayKey.toString()] = stringPeriodMap;
      });
      await prefs.setString(_keyTimetable, jsonEncode(timetableToSave));
      
      // メモデータの保存
      await prefs.setString(_keyMemos, jsonEncode(_memos));

      print("💾 [AppStorage] データを正常にストレージへ永続化しました。");
    } catch (e) {
      print("🚨 [AppStorage] データの自動保存に失敗しました: $e");
    }
  }

  // ---------------------------------------------------------------------------
  // ゲッター & セッター 
  // ---------------------------------------------------------------------------
  static double getGpa() => _gpa;
  static int getCredits() => _credits;
  static List<Map<String, dynamic>> getAttendanceLog() => _attendanceLog;

  static int getAbsenceCount(String id) => _attendanceCounts[id]?['absence'] ?? 0;
  static int getLatenessCount(String id) => _attendanceCounts[id]?['lateness'] ?? 0;
  static int getLatenessRate(String id) => syllabusMaster[id]?['latenessRate'] ?? 3;

  // メモ機能用ゲッター（重要度順 3=高、2=中、1=低 にソートして返す）
  static List<Map<String, dynamic>> getMemosSortedByPriority() {
    List<Map<String, dynamic>> sorted = List.from(_memos);
    sorted.sort((a, b) => (b['priority'] as int).compareTo(a['priority'] as int));
    return sorted;
  }

  /// メモの新規追加
  static void addMemo(String title, String content, int priority) {
    _memos.add({
      'id': 'MEMO_${DateTime.now().millisecondsSinceEpoch}',
      'title': title,
      'content': content,
      'priority': priority,
      'createdAt': DateTime.now().toIso8601String(),
    });
    _saveToStorage();
  }

  /// メモの削除
  static void removeMemo(String id) {
    _memos.removeWhere((memo) => memo['id'] == id);
    _saveToStorage();
  }

  static void setAbsenceCount(String id, int count) {
    if (!_attendanceCounts.containsKey(id)) {
      _attendanceCounts[id] = {'absence': 0, 'lateness': 0};
    }
    _attendanceCounts[id]?['absence'] = count;
    _saveToStorage();
  }

  static void setLatenessCount(String id, int count) {
    if (!_attendanceCounts.containsKey(id)) {
      _attendanceCounts[id] = {'absence': 0, 'lateness': 0};
    }
    _attendanceCounts[id]?['lateness'] = count;
    _saveToStorage();
  }

  static void setLatenessRate(String id, int rate) {
    if (!syllabusMaster.containsKey(id)) return; 
    syllabusMaster[id]?['latenessRate'] = rate;
    _saveToStorage();
  }

  static int getCalculatedTotalAbsence(String id) {
    int directAbsence = getAbsenceCount(id);
    int lateness = getLatenessCount(id);
    int rate = getLatenessRate(id);
    if (rate <= 0) return directAbsence; 
    return directAbsence + (lateness ~/ rate);
  }

  static List<Map<String, dynamic>> getAlertLectures() {
    List<Map<String, dynamic>> alerts = [];
    _attendanceCounts.forEach((id, _) {
      int totalAbsence = getCalculatedTotalAbsence(id);
      if (totalAbsence >= 3) {
        var lecture = syllabusMaster[id];
        if (lecture != null) {
          alerts.add({
            'id': id,
            'title': lecture['title'],
            'totalAbsence': totalAbsence,
            'status': totalAbsence >= 4 ? '単位不可確定' : '次で一発アウト',
          });
        }
      }
    });
    return alerts;
  }

  static List<Map<String, dynamic>> getTodayLectures(int dayIdx) {
    List<Map<String, dynamic>> todayList = [];
    final periodMap = userTimetableCodes[dayIdx];
    if (periodMap == null) return todayList;

    final periodTimes = [
      {'num': '1', 'time': '1限 (08:40~10:10)'},
      {'num': '2', 'time': '2限 (10:30~12:00)'},
      {'num': '3', 'time': '3限 (13:00~14:30)'},
      {'num': '4', 'time': '4限 (14:50~16:20)'},
      {'num': '5', 'time': '5限 (16:40~18:10)'},
    ];

    for (int i = 0; i < 5; i++) {
      String? code = periodMap[i];
      if (code != null) {
        var master = syllabusMaster[code];
        if (master != null) {
          todayList.add({
            'id': master['id'],
            'periodText': periodTimes[i]['time']!,
            'title': master['title'],
            'room': master['room'],
            'type': master['type'],
          });
        }
      }
    }
    return todayList;
  }

  static void saveGpaAndCredits(double gpa, int credits) {
    _gpa = gpa;
    _credits = credits;
    _saveToStorage();
  }

  static void saveAttendance(String lecture, DateTime time, bool isOffline) {
    _attendanceLog.add({
      'lecture': lecture,
      'time': time.toIso8601String(),
      'status': isOffline ? '仮受付(オフライン)' : '完了',
    });
    _saveToStorage();
  }

  static void addNewLecture({
    required String title,
    required String room,
    required String professor,
    required String type, 
    required int dayIdx,  
    required int periodIdx, 
  }) {
    String newId = 'M_${DateTime.now().millisecondsSinceEpoch}';

    syllabusMaster[newId] = {
      'id': newId,
      'title': title,
      'room': room,
      'professor': professor,
      'type': type,
      'evaluation': '未設定（シラバスを確認してください）',
      'latenessRate': 3, 
    };

    _attendanceCounts[newId] = {'absence': 0, 'lateness': 0};

    if (userTimetableCodes[dayIdx] == null) {
      userTimetableCodes[dayIdx] = {};
    }
    userTimetableCodes[dayIdx]![periodIdx] = newId;

    _saveToStorage();
  }

  static void removeLectureFromTimetable(int dayIdx, int periodIdx) {
    if (userTimetableCodes[dayIdx] != null) {
      String? id = userTimetableCodes[dayIdx]![periodIdx];
      if (id != null) {
        userTimetableCodes[dayIdx]!.remove(periodIdx);
        syllabusMaster.remove(id);
        _attendanceCounts.remove(id);
      }
      _saveToStorage();
    }
  }
}

// ==========================================
// 💻 【2. メイン外殻】ナビゲーション基盤
// ==========================================
class MainNavigationScreen extends StatefulWidget {
  const MainNavigationScreen({super.key});

  @override
  State<MainNavigationScreen> createState() => _MainNavigationScreenState();
}

class _MainNavigationScreenState extends State<MainNavigationScreen> {
  int _currentIndex = 0;

  void _onTabChanged(int index) {
    setState(() {
      // 📊 成績タブの削除に伴うインデックス変換処理
      // ナビゲーションバーの3項目目（index=2）の「設定」を、IndexedStackの4つ目（index=3）にマッピング
      if (index >= 2) {
        _currentIndex = index + 1; // AnalyticsScreen(2) をスキップ
      } else {
        _currentIndex = index;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    int alertCount = AppStorage.getAlertLectures().length;

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'UniFlow Miyazaki',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
        ),
        elevation: 1,
        scrolledUnderElevation: 1,
        actions: [
          Stack(
            alignment: Alignment.topRight,
            children: [
              IconButton(
                icon: const Icon(Icons.notifications_none_outlined),
                // 旧 index 3 (設定タブ) への遷移処理
                onPressed: () => setState(() => _currentIndex = 3),
              ),
              if (alertCount > 0)
                Positioned(
                  right: 8,
                  top: 8,
                  child: Container(
                    padding: const EdgeInsets.all(2),
                    decoration: const BoxDecoration(
                      color: Colors.red,
                      borderRadius: BorderRadius.all(Radius.circular(6)),
                    ),
                    constraints: const BoxConstraints(minWidth: 14, minHeight: 14),
                    child: Text(
                      '$alertCount',
                      style: const TextStyle(color: Colors.white, fontSize: 8, fontWeight: FontWeight.bold),
                      textAlign: TextAlign.center,
                    ),
                  ),
                )
            ],
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: IndexedStack(
        index: _currentIndex,
        children: [
          HomeScreen(
            onNavigateToAnalytics: () => setState(() => _currentIndex = 2), // バックエンド構造上は保持
            onNavigateToTimetable: () => setState(() => _currentIndex = 1),
          ),
          const TimetableScreen(),
          const AnalyticsScreen(), // 非表示状態（IndexedStack内には保持）
          const NotificationSettingsScreen(),
        ],
      ),
      bottomNavigationBar: Container(
        decoration: const BoxDecoration(
          boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 10, spreadRadius: 1)],
        ),
        child: BottomNavigationBar(
          // 表示上のインデックスを補正
          currentIndex: _currentIndex >= 3 ? _currentIndex - 1 : _currentIndex,
          onTap: _onTabChanged,
          type: BottomNavigationBarType.fixed,
          selectedItemColor: Theme.of(context).colorScheme.primary,
          unselectedItemColor: Colors.grey,
          selectedFontSize: 11,
          unselectedFontSize: 11,
          items: const [
            BottomNavigationBarItem(icon: Icon(Icons.dashboard_outlined), activeIcon: Icon(Icons.dashboard), label: 'ホーム'),
            BottomNavigationBarItem(icon: Icon(Icons.calendar_view_week_outlined), activeIcon: Icon(Icons.calendar_view_week), label: '時間割'),
            // 📊 成績・進捗のボトムタブ項目を非表示化（コメントアウト）
            // BottomNavigationBarItem(icon: Icon(Icons.bar_chart_outlined), activeIcon: Icon(Icons.bar_chart), label: '成績・進捗'),
            BottomNavigationBarItem(icon: Icon(Icons.settings_outlined), activeIcon: Icon(Icons.settings), label: '設定'),
          ],
        ),
      ),
    );
  }
}

// ==========================================
// 📱 【3. タブ1】ホーム画面（動的予定追従 ＆ メモ一覧）
// ==========================================
class HomeScreen extends StatefulWidget {
  final VoidCallback onNavigateToAnalytics;
  final VoidCallback onNavigateToTimetable;
  const HomeScreen({super.key, required this.onNavigateToAnalytics, required this.onNavigateToTimetable});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _attendanceCount = 0;

  @override
  void initState() {
    super.initState();
    _attendanceCount = AppStorage.getAttendanceLog().length;
  }

  // 📝 メモ新規作成ダイアログ
  void _showAddMemoDialog(BuildContext context) {
    final titleController = TextEditingController();
    final contentController = TextEditingController();
    int selectedPriority = 2; // デフォルト：中

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(builder: (context, setModalState) {
          return AlertDialog(
            title: const Text('メモ・タスクの追加', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: titleController,
                  decoration: const InputDecoration(labelText: 'タイトル', isDense: true),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: contentController,
                  decoration: const InputDecoration(labelText: '内容（詳細）', isDense: true),
                  maxLines: 2,
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    const Text('重要度: ', style: TextStyle(fontSize: 13)),
                    ChoiceChip(
                      label: const Text('低', style: TextStyle(fontSize: 12)),
                      selected: selectedPriority == 1,
                      onSelected: (val) => setModalState(() => selectedPriority = 1),
                    ),
                    const SizedBox(width: 4),
                    ChoiceChip(
                      label: const Text('中', style: TextStyle(fontSize: 12)),
                      selected: selectedPriority == 2,
                      onSelected: (val) => setModalState(() => selectedPriority = 2),
                    ),
                    const SizedBox(width: 4),
                    ChoiceChip(
                      label: const Text('高', style: TextStyle(fontSize: 12)),
                      selected: selectedPriority == 3,
                      selectedColor: Colors.red.shade100,
                      onSelected: (val) => setModalState(() => selectedPriority = 3),
                    ),
                  ],
                )
              ],
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context), child: const Text('キャンセル')),
              ElevatedButton(
                onPressed: () {
                  if (titleController.text.trim().isEmpty) return;
                  AppStorage.addMemo(titleController.text.trim(), contentController.text.trim(), selectedPriority);
                  setState(() {});
                  Navigator.pop(context);
                },
                child: const Text('追加'),
              ),
            ],
          );
        });
      },
    );
  }

  void _handleAttendance(BuildContext context) {
    final now = DateTime.now();
    int dayIdx = now.weekday - 1; 
    
    if (dayIdx > 4) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('本日は講義開講曜日（月〜金）ではありません。'), backgroundColor: Colors.orange),
      );
      return;
    }

    int? periodIdx;
    final currentTime = now.hour * 60 + now.minute;

    if (currentTime >= 520 && currentTime <= 610) {        
      periodIdx = 0; 
    } else if (currentTime >= 630 && currentTime <= 720) {  
      periodIdx = 1; 
    } else if (currentTime >= 780 && currentTime <= 870) {  
      periodIdx = 2; 
    } else if (currentTime >= 890 && currentTime <= 980) {  
      periodIdx = 3; 
    } else if (currentTime >= 1000 && currentTime <= 1090) { 
      periodIdx = 4; 
    }

    if (periodIdx == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('現在は通常の講義時間（1限〜5限）の外です。'), backgroundColor: Colors.grey),
      );
      return;
    }

    String? code = AppStorage.userTimetableCodes[dayIdx]?[periodIdx];
    
    if (code == null || AppStorage.syllabusMaster[code] == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('現在のコマに登録されている講義が時間割にありません。'), backgroundColor: Colors.blueGrey),
      );
      return;
    }

    final lecture = AppStorage.syllabusMaster[code]!;
    final lectureId = lecture['id'];

    showDialog(
      context: context,
      builder: (context) {
        int currentAbsence = AppStorage.getAbsenceCount(lectureId);
        int currentLateness = AppStorage.getLatenessCount(lectureId);
        int totalAbsence = AppStorage.getCalculatedTotalAbsence(lectureId);

        return AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.check_circle_outline, color: Colors.green),
              SizedBox(width: 8),
              Text('出席・状況確認', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('現在開講中の講義を検出しました：', style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
              const SizedBox(height: 4),
              Text('『${lecture['title']}』', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
              Text('教室: ${lecture['room']} | 担当: ${lecture['professor']}', style: const TextStyle(fontSize: 12)),
              const Divider(height: 24),
              Text('現在の欠課ステータス:', style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
              Text('・欠席回数: $currentAbsence 回', style: const TextStyle(fontSize: 13)),
              Text('・遅刻回数: $currentLateness 回', style: const TextStyle(fontSize: 13)),
              Text('・実質欠席換算: $totalAbsence 回', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: totalAbsence >= 3 ? Colors.red : Colors.green)),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('閉じる'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.green, foregroundColor: Colors.white),
              onPressed: () {
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('『${lecture['title']}』の出席確認を行いました。'), backgroundColor: Colors.green),
                );
              },
              child: const Text('出席を確定'),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    int weekday = DateTime.now().weekday; 
    int dayIdx = weekday - 1; 

    List<Map<String, dynamic>> todayLectures = [];
    if (dayIdx >= 0 && dayIdx <= 4) {
      todayLectures = AppStorage.getTodayLectures(dayIdx);
    }

    // 📋 すべての登録講義から、実質欠席数が多い（やばい）順にソートしたリストを作成
    List<Map<String, dynamic>> dangerousLectures = [];
    AppStorage.syllabusMaster.forEach((id, lecture) {
      int directAbsence = AppStorage.getAbsenceCount(id);
      int lateness = AppStorage.getLatenessCount(id);
      int totalAbsence = AppStorage.getCalculatedTotalAbsence(id);
      
      // 1回でも欠席または遅刻がある講義を対象として抽出
      if (totalAbsence > 0 || directAbsence > 0 || lateness > 0) {
        dangerousLectures.add({
          'id': id,
          'title': lecture['title'],
          'room': lecture['room'],
          'professor': lecture['professor'],
          'directAbsence': directAbsence,
          'lateness': lateness,
          'totalAbsence': totalAbsence,
        });
      }
    });

    // 🔴 実質欠席数（totalAbsence）が大きい順（降順）に並び替え
    dangerousLectures.sort((a, b) => (b['totalAbsence'] as int).compareTo(a['totalAbsence'] as int));

    final memos = AppStorage.getMemosSortedByPriority(); // 重要度順に並び替えられたメモの取得

    final daysJa = ['月', '火', '水', '木', '金', '土', '日'];
    String todayStr = "${DateTime.now().month}/${DateTime.now().day} (${daysJa[weekday - 1]})";

    return ListView(
      padding: const EdgeInsets.all(16.0),
      children: [
        // 🚨 1. 講義出欠ステータスセクション（警戒度順に自動ソート）
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text('講義出欠ステータス (警戒度順)', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            ElevatedButton.icon(
              onPressed: () => _handleAttendance(context),
              icon: const Icon(Icons.check_circle_outline, size: 16),
              label: const Text('出席登録', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
              style: ElevatedButton.styleFrom(
                backgroundColor: theme.colorScheme.tertiary,
                foregroundColor: Colors.black87,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),

        if (dangerousLectures.isEmpty)
          Card(
            color: Colors.green.shade50,
            elevation: 0,
            child: const Padding(
              padding: EdgeInsets.all(16.0),
              child: Center(
                child: Text(
                  'すべての講義が皆勤（クリーン）です！この調子を維持しましょう。',
                  style: TextStyle(color: Colors.green, fontSize: 13, fontWeight: FontWeight.bold),
                ),
              ),
            ),
          )
        else
          ...dangerousLectures.map((lec) {
            int total = lec['totalAbsence'];
            
            // 危険度に応じたカラーリングと状態ラベルの分岐
            Color cardBg = Colors.grey.shade50;
            Color borderCol = Colors.grey.shade300;
            String statusText = '安全';
            Color textColor = Colors.green.shade700;

            if (total >= 4) {
              cardBg = Colors.red.shade50;
              borderCol = Colors.red.shade400;
              statusText = '単位不可確定';
              textColor = Colors.red.shade800;
            } else if (total == 3) {
              cardBg = Colors.orange.shade50;
              borderCol = Colors.orange.shade400;
              statusText = '次で一発アウト';
              textColor = Colors.orange.shade900;
            } else if (total == 2) {
              cardBg = Colors.yellow.shade50;
              borderCol = Colors.yellow.shade600;
              statusText = '警戒モード';
              textColor = Colors.amber.shade900;
            }

            return Card(
              color: cardBg,
              elevation: 0,
              shape: RoundedRectangleBorder(
                side: BorderSide(color: borderCol, width: 1),
                borderRadius: BorderRadius.circular(8),
              ),
              margin: const EdgeInsets.symmetric(vertical: 4),
              child: ListTile(
                dense: true,
                title: Text(lec['title'], style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                subtitle: Text(
                  '欠席: ${lec['directAbsence']}回 / 遅刻: ${lec['lateness']}回\n教室: ${lec['room']}',
                  style: const TextStyle(fontSize: 12),
                ),
                trailing: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text('実質欠席: $total回', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: textColor)),
                    const SizedBox(height: 2),
                    Text(statusText, style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: textColor)),
                  ],
                ),
                onTap: widget.onNavigateToTimetable, // タップで時間割へジャンプして詳細確認可能
              ),
            );
          }),

        const SizedBox(height: 24),
        
        // 📅 2. 本日の予定セクション
        Text('本日の予定 - $todayStr', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),

        if (todayLectures.isEmpty)
          Card(
            color: Colors.grey.shade100,
            elevation: 0,
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Center(
                child: Text(
                  dayIdx > 4 ? '本日は週末でお休みです。' : '本日の予定（登録講義）はありません。',
                  style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
                ),
              ),
            ),
          )
        else
          ...todayLectures.map((lec) {
            Color cellBg = lec['type'] == 'major' ? Colors.blue.shade50 : Colors.amber.shade50;
            return _buildTimelineCard(context, lec['periodText'], lec['title'], lec['room'], cellBg, lec['id']);
          }),

        const SizedBox(height: 24),
        
        // 📝 3. マイメモ・タスクセクション（重要度順）
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text('マイメモ・タスク (重要度順)', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            IconButton(
              icon: const Icon(Icons.add_circle_outline, color: Colors.blue),
              onPressed: () => _showAddMemoDialog(context),
            )
          ],
        ),
        const SizedBox(height: 8),

        if (memos.isEmpty)
          Card(
            color: Colors.grey.shade50,
            elevation: 0,
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Center(
                child: Text(
                  '登録されたメモや課題はありません。',
                  style: TextStyle(color: Colors.grey.shade500, fontSize: 13),
                ),
              ),
            ),
          )
        else
          ...memos.map((memo) {
            // 重要度（3=高, 2=中, 1=低）に応じたカラーリング設定
            Color priorityColor = Colors.grey;
            String priorityText = '低';
            if (memo['priority'] == 3) {
              priorityColor = Colors.red;
              priorityText = '高';
            } else if (memo['priority'] == 2) {
              priorityColor = Colors.orange;
              priorityText = '中';
            }

            return Card(
              key: Key(memo['id']),
              margin: const EdgeInsets.symmetric(vertical: 4),
              child: ListTile(
                leading: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: priorityColor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: priorityColor, width: 1),
                  ),
                  child: Text(
                    priorityText,
                    style: TextStyle(color: priorityColor, fontSize: 10, fontWeight: FontWeight.bold),
                  ),
                ),
                title: Text(memo['title'], style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
                subtitle: memo['content'].toString().isNotEmpty ? Text(memo['content'], style: const TextStyle(fontSize: 12)) : null,
                trailing: IconButton(
                  icon: const Icon(Icons.delete_outline, size: 18, color: Colors.grey),
                  onPressed: () {
                    AppStorage.removeMemo(memo['id']);
                    setState(() {});
                  },
                ),
              ),
            );
          }),
      ],
    );
  }
  
  Widget _buildTimelineCard(BuildContext context, String time, String title, String room, Color bgColor, String lectureId) {
    int absence = AppStorage.getAbsenceCount(lectureId);
    int lateness = AppStorage.getLatenessCount(lectureId);
    int totalAbsence = AppStorage.getCalculatedTotalAbsence(lectureId);

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 6),
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Row(
          children: [
            Container(
              width: 6,
              height: 50,
              decoration: BoxDecoration(color: Theme.of(context).colorScheme.primary, borderRadius: BorderRadius.circular(3)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(time, style: const TextStyle(fontSize: 12, color: Colors.grey)),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      Text(title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
                      if (absence > 0 || lateness > 0) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(color: totalAbsence >= 3 ? Colors.red : Colors.grey.shade300, borderRadius: BorderRadius.circular(4)),
                          child: Text('欠$absence/遅$lateness (実質:$totalAbsence)', style: TextStyle(fontSize: 9, color: totalAbsence >= 3 ? Colors.white : Colors.black87, fontWeight: FontWeight.bold)),
                        )
                      ]
                    ],
                  ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(color: bgColor, borderRadius: BorderRadius.circular(4)),
              child: Text(room.toString().replaceAll('木花 ', ''), style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w500)),
            )
          ],
        ),
      ),
    );
  }
}

// ==========================================
// 🗓️ 【4. タブ2】時間割マトリクス＆詳細・追加設定
// ==========================================
class TimetableScreen extends StatefulWidget {
  const TimetableScreen({super.key});

  @override
  State<TimetableScreen> createState() => _TimetableScreenState();
}

class _TimetableScreenState extends State<TimetableScreen> {
  final TextEditingController _codeController = TextEditingController();

  @override
  void dispose() {
    _codeController.dispose();
    super.dispose();
  }

  void _showAddLectureSearchDialog(BuildContext context, int dayIdx, int periodIdx) {
    final TextEditingController titleController = TextEditingController();
    final TextEditingController idController = TextEditingController();
    final TextEditingController professorController = TextEditingController();
    
    int? selectedDayIdx = dayIdx;
    int? selectedPeriodIdx = periodIdx;

    List<Map<String, dynamic>> searchResults = [];

    void performSearch(StateSetter setModalState) {
      List<Map<String, dynamic>> allLectures = SyllabusService.allLectures; 

      final titleQuery = titleController.text.trim().toLowerCase();
      final idQuery = idController.text.trim().toLowerCase();
      final professorQuery = professorController.text.trim().toLowerCase();

      setModalState(() {
        searchResults = allLectures.where((lecture) {
          if (titleQuery.isNotEmpty && !lecture['title'].toString().toLowerCase().contains(titleQuery)) {
            return false;
          }
          if (idQuery.isNotEmpty && !lecture['id'].toString().toLowerCase().contains(idQuery)) {
            return false;
          }
          if (professorQuery.isNotEmpty && !lecture['professor'].toString().toLowerCase().contains(professorQuery)) {
            return false;
          }
          if (selectedDayIdx != null && lecture['dayIdx'] != selectedDayIdx) {
            return false;
          }
          if (selectedPeriodIdx != null && lecture['periodIdx'] != selectedPeriodIdx) {
            return false;
          }
          return true;
        }).toList();
      });
    }

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (context) {
        return StatefulBuilder(builder: (context, setModalState) {
          if (searchResults.isEmpty && 
              titleController.text.isEmpty && 
              idController.text.isEmpty && 
              professorController.text.isEmpty) {
            performSearch(setModalState);
          }

          return Container(
            padding: EdgeInsets.only(
              top: 20,
              left: 20,
              right: 20,
              bottom: MediaQuery.of(context).viewInsets.bottom + 20, 
            ),
            height: MediaQuery.of(context).size.height * 0.85, 
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('条件を指定して講義を検索', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
                const SizedBox(height: 12),
                TextField(
                  controller: titleController,
                  decoration: const InputDecoration(
                    labelText: '講義名（キーワード）', 
                    isDense: true,
                    prefixIcon: Icon(Icons.search, size: 20)
                  ),
                  onChanged: (_) => performSearch(setModalState),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: idController,
                        decoration: const InputDecoration(labelText: '講義ID / コード', isDense: true),
                        onChanged: (_) => performSearch(setModalState),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextField(
                        controller: professorController,
                        decoration: const InputDecoration(labelText: '先生の名前', isDense: true),
                        onChanged: (_) => performSearch(setModalState),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: DropdownButtonFormField<int?>(
                        value: selectedDayIdx,
                        decoration: const InputDecoration(labelText: '実施曜日', isDense: true),
                        items: const [
                          DropdownMenuItem(value: null, child: Text('指定なし')),
                          DropdownMenuItem(value: 0, child: Text('月曜日')),
                          DropdownMenuItem(value: 1, child: Text('火曜日')),
                          DropdownMenuItem(value: 2, child: Text('水曜日')),
                          DropdownMenuItem(value: 3, child: Text('木曜日')),
                          DropdownMenuItem(value: 4, child: Text('金曜日')),
                        ],
                        onChanged: (val) {
                          selectedDayIdx = val;
                          performSearch(setModalState);
                        },
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: DropdownButtonFormField<int?>(
                        value: selectedPeriodIdx,
                        decoration: const InputDecoration(labelText: '実施時間（コマ）', isDense: true),
                        items: const [
                          DropdownMenuItem(value: null, child: Text('指定なし')),
                          DropdownMenuItem(value: 0, child: Text('1コマ')),
                          DropdownMenuItem(value: 1, child: Text('2コマ')),
                          DropdownMenuItem(value: 2, child: Text('3コマ')),
                          DropdownMenuItem(value: 3, child: Text('4コマ')),
                          DropdownMenuItem(value: 4, child: Text('5コマ')),
                        ],
                        onChanged: (val) {
                          selectedPeriodIdx = val;
                          performSearch(setModalState);
                        },
                      ),
                    ),
                  ],
                ),
                const Divider(height: 24),
                Expanded(
                  child: searchResults.isEmpty
                      ? const Center(child: Text('条件に一致する講義が見つかりません', style: TextStyle(color: Colors.grey, fontSize: 13)))
                      : ListView.builder(
                          itemCount: searchResults.length,
                          itemBuilder: (context, index) {
                            final lecture = searchResults[index];
                            final days = ['月', '火', '水', '木', '金'];
                            
                            String lDay = lecture['dayIdx'] != null && lecture['dayIdx'] >= 0 && lecture['dayIdx'] < 5 
                                ? days[lecture['dayIdx']] : '未定';
                            String lPeriod = lecture['periodIdx'] != null ? '${lecture['periodIdx'] + 1}限' : '';

                            return ListTile(
                              title: Text(lecture['title'], style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                              subtitle: Text(
                                'ID: ${lecture['id']} | 担当: ${lecture['professor']}\n教室: ${lecture['room']} ($lDay$lPeriod)',
                                style: const TextStyle(fontSize: 11, color: Colors.black54),
                              ),
                              isThreeLine: true,
                              trailing: const Icon(Icons.add_circle_outline, size: 20, color: Colors.blue),
                              onTap: () {
                                AppStorage.addNewLecture(
                                  title: lecture['title'],
                                  room: lecture['room'],
                                  professor: lecture['professor'],
                                  type: lecture['type'] ?? 'major',
                                  dayIdx: lecture['dayIdx'] ?? dayIdx,
                                  periodIdx: lecture['periodIdx'] ?? periodIdx,
                                );
                                setState(() {});
                                Navigator.pop(context);
                              },
                            );
                          },
                        ),
                ),
                const Divider(height: 1),
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4.0),
                  child: SizedBox(
                    width: double.infinity,
                    child: TextButton.icon(
                      icon: const Icon(Icons.edit_note, size: 20),
                      label: const Text('シラバスにない講義を手動で登録する', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                      onPressed: () {
                        Navigator.pop(context);
                        _showManualAddDialog(context, dayIdx, periodIdx);
                      },
                    ),
                  ),
                ),
              ],
            ),
          );
        });
      },
    );
  }

  
  void _showLectureDetails(BuildContext context, Map<String, dynamic> lecture, int dayIdx, int periodIdx) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (context) {
        return StatefulBuilder(
          builder: (BuildContext context, StateSetter setModalState) {
            String lectureId = lecture['id'];
            int currentAbsence = AppStorage.getAbsenceCount(lectureId);
            int currentLateness = AppStorage.getLatenessCount(lectureId);
            int currentRate = AppStorage.getLatenessRate(lectureId);
            int totalAbsence = AppStorage.getCalculatedTotalAbsence(lectureId);

            return Padding(
              padding: EdgeInsets.only(
                top: 20,
                left: 20,
                right: 20,
                bottom: MediaQuery.of(context).viewInsets.bottom + 20, // キーボード表示時の底上げ
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Text(
                          lecture['title'], 
                          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                        ),
                      ),
                      const SizedBox(width: 8), 
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: totalAbsence >= 4 ? Colors.red.shade100 : (totalAbsence == 3 ? Colors.orange.shade100 : Colors.green.shade100),
                          borderRadius: BorderRadius.circular(4)
                        ),
                        child: Text(
                          '実質欠席: $totalAbsence回 (${totalAbsence >= 4 ? "不可確定" : (totalAbsence == 3 ? "要警戒" : "安全")})',
                          style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: totalAbsence >= 3 ? Colors.red : Colors.green.shade800),
                        ),
                      )
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text('教室: ${lecture['room']} | 担当: ${lecture['professor']}', style: const TextStyle(color: Colors.grey, fontSize: 12)),
                  const Divider(height: 20),
                  
                  // 欠席回数操作
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('欠席回数', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                      Row(
                        children: [
                          IconButton(
                            icon: const Icon(Icons.remove_circle_outline, size: 20),
                            onPressed: currentAbsence > 0 ? () {
                              setModalState(() => AppStorage.setAbsenceCount(lectureId, currentAbsence - 1));
                              setState(() {});
                            } : null,
                          ),
                          Text('$currentAbsence', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                          IconButton(
                            icon: const Icon(Icons.add_circle_outline, size: 20),
                            onPressed: () {
                              setModalState(() => AppStorage.setAbsenceCount(lectureId, currentAbsence + 1));
                              setState(() {});
                            },
                          ),
                        ],
                      )
                    ],
                  ),
                  
                  // 遅刻回数操作
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('遅刻回数', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                      Row(
                        children: [
                          IconButton(
                            icon: const Icon(Icons.remove_circle_outline, size: 20),
                            onPressed: currentLateness > 0 ? () {
                              setModalState(() => AppStorage.setLatenessCount(lectureId, currentLateness - 1));
                              setState(() {});
                            } : null,
                          ),
                          Text('$currentLateness', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                          IconButton(
                            icon: const Icon(Icons.add_circle_outline, size: 20),
                            onPressed: () {
                              setModalState(() => AppStorage.setLatenessCount(lectureId, currentLateness + 1));
                              setState(() {});
                            },
                          ),
                        ],
                      )
                    ],
                  ),
                  const SizedBox(height: 6),
                  
                  // 換算ルール
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                    decoration: BoxDecoration(color: Colors.grey.shade100, borderRadius: BorderRadius.circular(8)),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('遅刻の換算ルール設定', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500)),
                        DropdownButton<int>(
                          value: currentRate,
                          elevation: 2,
                          underline: const SizedBox(),
                          style: const TextStyle(fontSize: 12, color: Colors.black87, fontWeight: FontWeight.bold),
                          items: const [
                            DropdownMenuItem(value: 2, child: Text('遅刻 2回 = 欠席1回')),
                            DropdownMenuItem(value: 3, child: Text('遅刻 3回 = 欠席1回')),
                            DropdownMenuItem(value: 4, child: Text('遅刻 4回 = 欠席1回')),
                          ],
                          onChanged: (int? newRate) {
                            if (newRate != null) {
                              setModalState(() => AppStorage.setLatenessRate(lectureId, newRate));
                              setState(() {});
                            }
                          },
                        ),
                      ],
                    ),
                  ),
                  const Divider(height: 20),
                  const Text('【評価基準】', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                  Text(lecture['evaluation'] ?? '未設定', style: const TextStyle(fontSize: 12)),
                  
                  const Divider(height: 24),
                  
                  // ✨ 【新規追加】この授業のメモを追加するボタン
                  SizedBox(
                    width: double.infinity,
                    height: 40,
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Theme.of(context).colorScheme.secondary.withOpacity(0.1),
                        foregroundColor: Theme.of(context).colorScheme.secondary,
                        elevation: 0,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                      icon: const Icon(Icons.add_comment_outlined, size: 18),
                      label: const Text('この講義のメモ・タスクを追加', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                      onPressed: () {
                        Navigator.pop(context); // 詳細シートを一度閉じる
                        _showAddMemoFromLectureDialog(context, lecture['title']);
                      },
                    ),
                  ),
                  const SizedBox(height: 8),
                  
                  // 講義削除ボタン
                  SizedBox(
                    width: double.infinity,
                    height: 40,
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.red.shade700,
                        side: BorderSide(color: Colors.red.shade300),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                      icon: const Icon(Icons.delete_outline, size: 18),
                      label: const Text('この講義を時間割から削除する', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                      onPressed: () {
                        showDialog(
                          context: context,
                          builder: (context) => AlertDialog(
                            title: const Text('講義の削除', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                            content: Text('『${lecture['title']}』の登録を解除しますか？\n（これまでの欠席・遅刻データも破棄されます）'),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.pop(context),
                                child: const Text('キャンセル'),
                              ),
                              TextButton(
                                style: TextButton.styleFrom(foregroundColor: Colors.red),
                                onPressed: () {
                                  AppStorage.removeLectureFromTimetable(dayIdx, periodIdx);
                                  Navigator.pop(context); 
                                  Navigator.pop(context); 
                                  setState(() {}); 

                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(content: Text('『${lecture['title']}』を削除しました。'), backgroundColor: Colors.grey.shade800),
                                  );
                                },
                                child: const Text('削除する', style: TextStyle(fontWeight: FontWeight.bold)),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  // ✨ 【新規追加】講義詳細から呼び出される専用のメモ追加ダイアログ
  void _showAddMemoFromLectureDialog(BuildContext context, String lectureTitle) {
    final titleController = TextEditingController(text: '[$lectureTitle] ');
    final contentController = TextEditingController();
    int selectedPriority = 2; // デフォルト：中

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(builder: (context, setModalState) {
          return AlertDialog(
            title: const Text('メモ・タスクの追加', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: titleController,
                  decoration: const InputDecoration(labelText: 'タイトル', isDense: true),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: contentController,
                  decoration: const InputDecoration(labelText: '内容（詳細）', isDense: true),
                  maxLines: 2,
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    const Text('重要度: ', style: TextStyle(fontSize: 13)),
                    ChoiceChip(
                      label: const Text('低', style: TextStyle(fontSize: 12)),
                      selected: selectedPriority == 1,
                      onSelected: (val) => setModalState(() => selectedPriority = 1),
                    ),
                    const SizedBox(width: 4),
                    ChoiceChip(
                      label: const Text('中', style: TextStyle(fontSize: 12)),
                      selected: selectedPriority == 2,
                      onSelected: (val) => setModalState(() => selectedPriority = 2),
                    ),
                    const SizedBox(width: 4),
                    ChoiceChip(
                      label: const Text('高', style: TextStyle(fontSize: 12)),
                      selected: selectedPriority == 3,
                      selectedColor: Colors.red.shade100,
                      onSelected: (val) => setModalState(() => selectedPriority = 3),
                    ),
                  ],
                )
              ],
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context), child: const Text('キャンセル')),
              ElevatedButton(
                onPressed: () {
                  if (titleController.text.trim().isEmpty) return;
                  AppStorage.addMemo(titleController.text.trim(), contentController.text.trim(), selectedPriority);
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('メモを追加しました（ホーム画面に重要度順で表示されます）'), backgroundColor: Colors.green),
                  );
                },
                child: const Text('追加'),
              ),
            ],
          );
        });
      },
    );
  }

  void _showManualAddDialog(BuildContext context, int dayIdx, int periodIdx) {
    final titleController = TextEditingController();
    final roomController = TextEditingController();
    final professorController = TextEditingController();
    String selectedType = 'major';

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) => StatefulBuilder(builder: (context, setModalState) {
        return Padding(
          padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom + 20, top: 20, left: 20, right: 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(controller: titleController, decoration: const InputDecoration(labelText: '講義名')),
              TextField(controller: roomController, decoration: const InputDecoration(labelText: '教室')),
              TextField(controller: professorController, decoration: const InputDecoration(labelText: '担当教員')),
              Row(
                children: [
                  Radio(value: 'major', groupValue: selectedType, onChanged: (v) => setModalState(() => selectedType = v as String)),
                  const Text('専門'),
                  Radio(value: 'liberal', groupValue: selectedType, onChanged: (v) => setModalState(() => selectedType = v as String)),
                  const Text('教養'),
                ],
              ),
              ElevatedButton(
                onPressed: () {
                  AppStorage.addNewLecture(
                    title: titleController.text,
                    room: roomController.text,
                    professor: professorController.text,
                    type: selectedType,
                    dayIdx: dayIdx,
                    periodIdx: periodIdx,
                  );
                  setState(() {});
                  Navigator.pop(context);
                },
                child: const Text('登録'),
              )
            ],
          ),
        );
      }),
    );
  }

  @override
  Widget build(BuildContext context) {
    final days = ['月', '火', '水', '木', '金'];
    final periods = [
      {'num': '1', 'time': '8:40\n10:10'},
      {'num': '2', 'time': '10:30\n12:00'},
      {'num': '3', 'time': '13:00\n14:30'},
      {'num': '4', 'time': '14:50\n16:20'},
      {'num': '5', 'time': '16:40\n18:10'},
    ];

    return Padding(
      padding: const EdgeInsets.all(4.0),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6.0, vertical: 6.0),
            child: Row(
              children: [
                Expanded(
                  child: SizedBox(
                    height: 38,
                    child: TextField(
                      controller: _codeController,
                      decoration: const InputDecoration(
                        hintText: '宮大時間割コードを入力 (例: ksf91)',
                        hintStyle: TextStyle(fontSize: 12, color: Colors.grey),
                        border: OutlineInputBorder(),
                        contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 0),
                        isDense: true,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  height: 38,
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Theme.of(context).colorScheme.primary,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                    ),
                    icon: const Icon(Icons.bolt, size: 16),
                    label: const Text('シラバス追加', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                    onPressed: () {
                      String code = _codeController.text.trim();
                      if (code.isEmpty) return;

                      final lecture = SyllabusService.findLectureByCode(code);
                      
                      if (lecture != null) {
                        if (lecture['dayIdx'] == null || lecture['periodIdx'] == null) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text('『${lecture['title']}』は集中講義等のため時間割に自動配置できません。(${lecture['rawSchedule']})'),
                              backgroundColor: Colors.orange.shade800,
                            ),
                          );
                          return;
                        }

                        AppStorage.addNewLecture(
                          title: lecture['title'],
                          room: lecture['room'],
                          professor: lecture['professor'],
                          type: lecture['type'],
                          dayIdx: lecture['dayIdx'],
                          periodIdx: lecture['periodIdx'],
                        );

                        setState(() {});
                        _codeController.clear();
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('【自動マッピング】『${lecture['title']}』を配置しました。'),
                            backgroundColor: Colors.green.shade700,
                          ),
                        );
                      } else {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('指定された時間割コードはシラバスデータ内に見つかりません。'),
                            backgroundColor: Colors.redAccent,
                          ),
                        );
                      }
                    },
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 8, thickness: 0.5),

          Row(
            children: [
              const SizedBox(width: 45), 
              ...days.map((day) => Expanded(
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: Center(child: Text(day, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13))),
                    ),
                  )),
            ],
          ),
          
          Expanded(
            child: Column(
              children: periods.asMap().entries.map((periodEntry) {
                int periodIdx = periodEntry.key;
                var period = periodEntry.value;

                return Expanded(
                  child: Row(
                    children: [
                      Container(
                        width: 45,
                        decoration: BoxDecoration(
                          border: Border(bottom: BorderSide(color: Colors.grey.shade300, width: 0.5)),
                        ),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(period['num']!, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                            Text(period['time']!, style: const TextStyle(fontSize: 8, color: Colors.grey), textAlign: TextAlign.center),
                          ],
                        ),
                      ),
                      ...List.generate(5, (dayIdx) {
                        String? code = AppStorage.userTimetableCodes[dayIdx]?[periodIdx];
                        Map<String, dynamic>? lecture = code != null ? AppStorage.syllabusMaster[code] : null;

                        Color cellColor = Colors.grey.shade50;
                        Color borderColor = Colors.grey.shade200;
                        
                        int absence = 0;
                        int lateness = 0;
                        int totalAbsence = 0;

                        if (lecture != null) {
                          String lId = lecture['id'];
                          absence = AppStorage.getAbsenceCount(lId);
                          lateness = AppStorage.getLatenessCount(lId);
                          totalAbsence = AppStorage.getCalculatedTotalAbsence(lId);

                          if (totalAbsence >= 4) {
                            cellColor = Colors.red.shade50;
                            borderColor = Colors.red.shade300;
                          } else if (totalAbsence == 3) {
                            cellColor = Colors.orange.shade50;
                            borderColor = Colors.orange.shade300;
                          } else {
                            cellColor = lecture['type'] == 'major' ? const Color(0xFFE3F2FD) : const Color(0xFFFFFDE7);
                            borderColor = lecture['type'] == 'major' ? Colors.blue.shade200 : Colors.amber.shade200;
                          }
                        }

                        return Expanded(
                          child: GestureDetector(
                            onTap: () {
                              if (lecture != null) {
                                _showLectureDetails(context, lecture, dayIdx, periodIdx);
                              } else {
                                _showAddLectureSearchDialog(context, dayIdx, periodIdx);
                              }
                            },
                            child: Container(
                              margin: const EdgeInsets.all(2),
                              decoration: BoxDecoration(
                                color: cellColor,
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(color: borderColor, width: 1),
                              ),
                              child: lecture != null
                                  ? Padding(
                                      padding: const EdgeInsets.all(4.0),
                                      child: Stack(
                                        alignment: Alignment.center,
                                        children: [
                                          Column(
                                            mainAxisAlignment: MainAxisAlignment.center,
                                            children: [
                                              Text(
                                                lecture['title'],
                                                style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, height: 1.1),
                                                maxLines: 2,
                                                overflow: TextOverflow.ellipsis,
                                                textAlign: TextAlign.center,
                                              ),
                                              const SizedBox(height: 2),
                                              Text(
                                                lecture['room'].toString(),
                                                style: TextStyle(fontSize: 8, color: Colors.grey.shade700),
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            ],
                                          ),
                                          if (absence > 0 || lateness > 0)
                                            Positioned(
                                              right: 0,
                                              top: 0,
                                              child: Container(
                                                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                                                decoration: BoxDecoration(
                                                  color: totalAbsence >= 3 ? Colors.red : Colors.grey.shade600,
                                                  borderRadius: BorderRadius.circular(6)
                                                ),
                                                constraints: const BoxConstraints(minWidth: 12),
                                                child: Text(
                                                  '欠$absence/遅$lateness', 
                                                  style: const TextStyle(color: Colors.white, fontSize: 6, fontWeight: FontWeight.bold), 
                                                  textAlign: TextAlign.center
                                                ),
                                              ),
                                            )
                                        ],
                                      ),
                                    )
                                  : const Center(child: Icon(Icons.add, size: 14, color: Colors.black12)),
                            ),
                          ),
                        );
                      }),
                    ],
                  ),
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }
}

// ==========================================
// 📊 【5. タブ3】成績＆進捗アナリティクス（一時非表示中）
// ==========================================
class AnalyticsScreen extends StatefulWidget {
  const AnalyticsScreen({super.key});

  @override
  State<AnalyticsScreen> createState() => _AnalyticsScreenState();
}

class _AnalyticsScreenState extends State<AnalyticsScreen> {
  double _currentGpa = 0.0;
  int _currentCredits = 0;
  int _simulatedAClassesCount = 0;

  @override
  void initState() {
    super.initState();
    _currentGpa = AppStorage.getGpa();
    _currentCredits = AppStorage.getCredits();
  }

  void _runGpaSimulation() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (context) {
        return StatefulBuilder(
          builder: (BuildContext context, StateSetter setModalState) {
            double baseGpa = AppStorage.getGpa();
            int baseCredits = AppStorage.getCredits();

            double baseTotalGp = baseGpa * baseCredits;
            int additionalCredits = _simulatedAClassesCount * 2; 
            double additionalGp = _simulatedAClassesCount * 2 * 4.0; 
            double simulatedGpa = (baseTotalGp + additionalGp) / (baseCredits + additionalCredits);

            return Padding(
              padding: EdgeInsets.only(
                top: 20, left: 20, right: 20, 
                bottom: MediaQuery.of(context).viewInsets.bottom + 20
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('成績シミュレーター', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 4),
                  const Text('未確定の講義がすべて『優 (GP 4.0)』だった場合の総GPAを予測します。', style: TextStyle(fontSize: 12, color: Colors.grey)),
                  const Divider(height: 20),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('『優』と仮定する科目数 (各2単位)', style: TextStyle(fontSize: 13)),
                      Row(
                        children: [
                          IconButton(
                            icon: const Icon(Icons.remove_circle_outline),
                            onPressed: _simulatedAClassesCount > 0 ? () => setModalState(() => _simulatedAClassesCount--) : null,
                          ),
                          Text('$_simulatedAClassesCount', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                          IconButton(
                            icon: const Icon(Icons.add_circle_outline),
                            onPressed: () => setModalState(() => _simulatedAClassesCount++),
                          ),
                        ],
                      )
                    ],
                  ),
                  const SizedBox(height: 16),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(color: Colors.blue.shade50, borderRadius: BorderRadius.circular(8)),
                    child: Column(
                      children: [
                        const Text('シミュレーション結果', style: TextStyle(fontSize: 12, color: Colors.blueGrey)),
                        const SizedBox(height: 4),
                        Text('予測通算GPA: ${simulatedGpa.isNaN ? "0.00" : simulatedGpa.toStringAsFixed(2)}', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.blue)),
                        Text('(取得単位は ${baseCredits + additionalCredits} 単位へ増加)', style: const TextStyle(fontSize: 11, color: Colors.grey))
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: () {
                        AppStorage.saveGpaAndCredits(simulatedGpa.isNaN ? 0.0 : simulatedGpa, baseCredits + additionalCredits);
                        setState(() {
                          _currentGpa = AppStorage.getGpa();
                          _currentCredits = AppStorage.getCredits();
                        });
                        Navigator.pop(context);
                      },
                      child: const Text('この構成をストレージに保存・反映'),
                    ),
                  )
                ],
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    int alertCount = AppStorage.getAlertLectures().length;

    return ListView(
      padding: const EdgeInsets.all(16.0),
      children: [
        Card(
          elevation: 2,
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('通算GPA: ${_currentGpa.toStringAsFixed(2)}', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.blue)),
                      const SizedBox(height: 8),
                      Container(height: 50, color: Colors.grey.shade50, child: const Center(child: Text('[GPA推移バーチャート]', style: TextStyle(fontSize: 11, color: Colors.grey)))),
                    ],
                  ),
                ),
                const SizedBox(width: 16),
                Column(
                  children: [
                    Stack(
                      alignment: Alignment.center,
                      children: [
                        CircularProgressIndicator(value: _currentCredits / 128, strokeWidth: 6, backgroundColor: Colors.grey.shade200, color: alertCount > 0 ? Colors.red : Colors.blue),
                        Text('$_currentCredits/128', style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
                      ],
                    ),
                    const SizedBox(height: 4),
                    const Text('卒業要件単位', style: TextStyle(fontSize: 10, color: Colors.grey)),
                  ],
                )
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        Card(
          color: alertCount > 0 ? Colors.red.shade50 : Colors.amber.shade50,
          shape: RoundedRectangleBorder(side: BorderSide(color: alertCount > 0 ? Colors.red : Colors.amber.shade300), borderRadius: BorderRadius.circular(8)),
          child: Padding(
            padding: const EdgeInsets.all(12.0),
            child: Row(
              children: [
                Icon(alertCount > 0 ? Icons.error_outline : Icons.warning_amber_rounded, color: alertCount > 0 ? Colors.red : Colors.amber),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(alertCount > 0 ? '卒業判定：要注意要請あり' : '現在のペースでの卒業判定：A（安全）', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                      Text(alertCount > 0 ? '警告：遅刻・欠席の超過による危険講義が $alertCount 件あります。' : '警告：一般教養の単位が不足するリスクがあります。', style: const TextStyle(fontSize: 12, color: Colors.black87)),
                    ],
                  ),
                )
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        ElevatedButton.icon(
          onPressed: _runGpaSimulation,
          icon: const Icon(Icons.calculate_outlined),
          label: const Text('「もしこの科目が優だったら？」成績シミュレーション'),
        )
      ],
    );
  }
}

// ==========================================
// 🔔 【6. サブシステム】通知・アシスト設定
// ==========================================
class NotificationSettingsScreen extends StatelessWidget {
  const NotificationSettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16.0),
      children: [
        const Text('通知・アシスト設定', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
        SwitchListTile(
          title: const Text('講義開始前のリマインド', style: TextStyle(fontSize: 14)),
          value: true, onChanged: (val) {},
        ),
        SwitchListTile(
          title: const Text('出席忘れ防止アラート', style: TextStyle(fontSize: 14)),
          value: true, onChanged: (val) {},
        ),
      ],
    );
  }
}