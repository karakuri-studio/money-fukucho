import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

// ==========================================
// Utils & Constants
// ==========================================
class AppColors {
  static const Color sumi = Color(0xFF1a1a1a);
  static const Color washi = Color(0xFFf4f1e8);
  static const Color kin = Color(0xFFc4a668);
  static const Color gin = Color(0xFF9ea8a0);
  static const Color beni = Color(0xFFbf3943);
  static const Color fire = Color(0xFFff4757);
  static const Color moegi = Color(0xFF4a7c59);
  static const Color ai = Color(0xFF2d5986);
  static const Color bgDark = Color(0xFF2a0808);
}

String formatYen(int value) {
  final formatter = RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))');
  return '¥${value.toString().replaceAllMapped(formatter, (m) => '${m[1]},')}';
}

final Map<String, String> typeLabels = {
  'card': 'カードローン',
  'housing': '住宅ローン',
  'car': '自動車ローン',
  'education': '教育ローン',
  'business': '事業融資',
  'personal': '個人借入',
  'other': 'その他',
};

// ==========================================
// Models & Finance Math
// ==========================================
class ScheduleItem {
  final int month;
  final int interest;
  final int principalPart;
  final int balance;
  ScheduleItem(this.month, this.interest, this.principalPart, this.balance);
}

class RepaymentResult {
  final int months; // -1 means Infinity
  final int totalInterest; // -1 means Infinity
  final int totalPayment;
  final List<ScheduleItem> schedule;
  RepaymentResult(
    this.months,
    this.totalInterest,
    this.totalPayment,
    this.schedule,
  );
}

RepaymentResult calcRepayment(
  int principal,
  double annualRate,
  int monthlyPayment,
) {
  if (principal <= 0) return RepaymentResult(0, 0, 0, []);
  if (annualRate == 0) {
    int months = (principal / monthlyPayment).ceil();
    int bal = principal;
    List<ScheduleItem> schedule = [];
    for (int i = 0; i < months; i++) {
      int pPart = math.min(monthlyPayment, bal);
      bal = math.max(0, bal - pPart);
      schedule.add(ScheduleItem(i + 1, 0, pPart, bal));
    }
    return RepaymentResult(months, 0, principal, schedule);
  } else {
    double r = annualRate / 100 / 12;
    int balance = principal;
    int totalInterest = 0;
    int months = 0;
    List<ScheduleItem> schedule = [];
    const int maxMonths = 600;

    while (balance > 0 && months < maxMonths) {
      int interest = (balance * r).round();
      if (interest >= monthlyPayment)
        return RepaymentResult(-1, -1, -1, []); // Infinity
      int pPart = math.min(monthlyPayment - interest, balance);
      balance = math.max(0, balance - pPart);
      totalInterest += interest;
      months++;
      schedule.add(ScheduleItem(months, interest, pPart, balance));
    }
    return RepaymentResult(
      months,
      totalInterest,
      principal + totalInterest,
      schedule,
    );
  }
}

class Debt {
  String id;
  String name;
  int amount;
  int originalAmount;
  double rate;
  int monthly;
  int? dueDay;
  String startDate; // YYYY-MM
  String type;
  String memo;
  bool isCleared;

  Debt({
    required this.id,
    required this.name,
    required this.amount,
    required this.originalAmount,
    required this.rate,
    required this.monthly,
    this.dueDay,
    required this.startDate,
    required this.type,
    required this.memo,
    this.isCleared = false,
  });
}

// ==========================================
// State Management
// ==========================================
class AppState extends ChangeNotifier {
  List<Debt> debts = [];
  Map<String, bool> paidRecords = {};

  int get totalDebt =>
      debts.where((d) => !d.isCleared).fold(0, (s, d) => s + d.amount);
  int get originalTotalDebt => debts.fold(
    0,
    (s, d) => s + (d.originalAmount > d.amount ? d.originalAmount : d.amount),
  );
  int get totalMonthly =>
      debts.where((d) => !d.isCleared).fold(0, (s, d) => s + d.monthly);
  int get totalInterest {
    return debts.where((d) => !d.isCleared).fold(0, (s, d) {
      final r = calcRepayment(d.amount, d.rate, d.monthly);
      return s + (r.totalInterest >= 0 ? r.totalInterest : 0);
    });
  }

  void addDebt(Debt debt) {
    debts.add(debt);
    notifyListeners();
  }

  void updateDebt(Debt debt) {
    final idx = debts.indexWhere((d) => d.id == debt.id);
    if (idx != -1) {
      debts[idx] = debt;
      notifyListeners();
    }
  }

  void repayDebt(String id, int amountToRepay) {
    final idx = debts.indexWhere((d) => d.id == id);
    if (idx != -1) {
      debts[idx].amount -= amountToRepay;
      if (debts[idx].amount <= 0) {
        debts[idx].amount = 0;
        debts[idx].isCleared = true;
      }
      notifyListeners();
    }
  }

  void deleteDebt(String id) {
    debts.removeWhere((d) => d.id == id);
    paidRecords.removeWhere((k, v) => k.startsWith('${id}_'));
    notifyListeners();
  }

  void togglePaid(String key) {
    if (paidRecords.containsKey(key)) {
      paidRecords.remove(key);
    } else {
      paidRecords[key] = true;
      HapticFeedback.lightImpact();
    }
    notifyListeners();
  }
}

// ==========================================
// Main Entry
// ==========================================
void main() {
  runApp(KarakuriApp());
}

class KarakuriApp extends StatelessWidget {
  final AppState state = AppState();

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'からくり大福帳',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        scaffoldBackgroundColor: AppColors.sumi,
        primaryColor: AppColors.sumi,
        canvasColor: AppColors.washi,
        colorScheme: ColorScheme.light(
          primary: AppColors.sumi,
          secondary: AppColors.beni,
        ),
        fontFamily: 'sans-serif',
      ),
      home: MainScreen(state: state),
    );
  }
}

// ==========================================
// UI: Main Screen
// ==========================================
class MainScreen extends StatefulWidget {
  final AppState state;
  const MainScreen({Key? key, required this.state}) : super(key: key);
  @override
  _MainScreenState createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  int _currentIndex = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.sumi,
      body: SafeArea(
        child: Center(
          child: Container(
            constraints: const BoxConstraints(maxWidth: 480),
            color: AppColors.washi,
            child: Column(
              children: [
                _buildHeader(),
                Expanded(
                  child: IndexedStack(
                    index: _currentIndex,
                    children: [
                      LedgerTab(state: widget.state),
                      PaymentTab(state: widget.state),
                      SimulationTab(state: widget.state),
                      KarmaTab(
                        state: widget.state,
                        isActive: _currentIndex == 3,
                      ),
                      OracleTab(state: widget.state),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      floatingActionButton: _currentIndex != 3
          ? FloatingActionButton(
              backgroundColor: AppColors.sumi,
              child: const Icon(Icons.add, color: AppColors.washi),
              onPressed: () => _showDebtFormSheet(context),
            )
          : null,
      bottomNavigationBar: Container(
        color: AppColors.washi,
        child: BottomNavigationBar(
          currentIndex: _currentIndex,
          type: BottomNavigationBarType.fixed,
          backgroundColor: AppColors.washi,
          selectedItemColor: AppColors.sumi,
          unselectedItemColor: AppColors.gin,
          selectedLabelStyle: const TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 10,
          ),
          unselectedLabelStyle: const TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 10,
          ),
          onTap: (i) {
            HapticFeedback.selectionClick();
            setState(() => _currentIndex = i);
          },
          items: const [
            BottomNavigationBarItem(
              icon: Text(
                '帳',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              label: '記帳',
            ),
            BottomNavigationBarItem(
              icon: Text(
                '暦',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              label: '支払',
            ),
            BottomNavigationBarItem(
              icon: Text(
                '算',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              label: '試算',
            ),
            BottomNavigationBarItem(
              icon: Text(
                '落',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              label: '業',
            ),
            BottomNavigationBarItem(
              icon: Text(
                '宣',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              label: '託宣',
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return ListenableBuilder(
      listenable: widget.state,
      builder: (context, _) {
        final isHell = widget.state.totalDebt > 1000000;
        final bgColor = isHell ? AppColors.bgDark : AppColors.washi;
        final textColor = isHell ? AppColors.washi : AppColors.sumi;
        double progress = 0;
        int reduced = 0;
        if (widget.state.originalTotalDebt > 0) {
          reduced = math.max(
            0,
            widget.state.originalTotalDebt - widget.state.totalDebt,
          );
          progress = reduced / widget.state.originalTotalDebt;
        }

        return Container(
          decoration: BoxDecoration(
            color: bgColor,
            border: Border(
              bottom: BorderSide(
                color: isHell ? AppColors.fire : AppColors.sumi,
                width: 2,
              ),
            ),
          ),
          child: Stack(
            children: [
              if (isHell)
                Positioned.fill(child: CustomPaint(painter: FirePainter())),
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 16, 24, 16),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'からくり大福帳',
                          style: TextStyle(
                            color: textColor,
                            fontWeight: FontWeight.w900,
                            fontSize: 16,
                            letterSpacing: 3,
                          ),
                        ),
                        if (widget.state.totalDebt > 0)
                          Text(
                            isHell ? '🔥 火の車 🔥' : '⚠ 要注意',
                            style: TextStyle(
                              color: isHell ? AppColors.fire : AppColors.beni,
                              fontWeight: FontWeight.bold,
                              fontSize: 12,
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        _buildStatBox(
                          '総借財',
                          formatYen(widget.state.totalDebt),
                          isHell ? AppColors.fire : AppColors.beni,
                          isHell,
                        ),
                        const SizedBox(width: 8),
                        _buildStatBox(
                          '月返済合計',
                          formatYen(widget.state.totalMonthly),
                          AppColors.ai,
                          isHell,
                        ),
                        const SizedBox(width: 8),
                        _buildStatBox(
                          '総利息',
                          formatYen(widget.state.totalInterest),
                          isHell ? AppColors.fire : AppColors.beni,
                          isHell,
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          '借金削減の歩み',
                          style: TextStyle(
                            color: textColor,
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          '▲ ${formatYen(reduced)}',
                          style: TextStyle(
                            color: textColor,
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    LinearProgressIndicator(
                      value: progress,
                      backgroundColor: isHell ? Colors.white24 : Colors.black12,
                      valueColor: AlwaysStoppedAnimation(
                        isHell ? AppColors.kin : AppColors.moegi,
                      ),
                      minHeight: 8,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildStatBox(String label, String val, Color valColor, bool isHell) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
        decoration: BoxDecoration(
          color: isHell ? Colors.white10 : Colors.black.withOpacity(0.04),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Column(
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 9,
                color: isHell ? Colors.white70 : AppColors.gin,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              val,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.bold,
                color: valColor,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }

  // Forms & Dialogs
  void _showDebtFormSheet(BuildContext context, [Debt? editDebt]) {
    String name = editDebt?.name ?? '';
    String amount = editDebt?.amount.toString() ?? '';
    String rate = editDebt?.rate.toString() ?? '';
    String monthly = editDebt?.monthly.toString() ?? '';
    String dueDay = editDebt?.dueDay?.toString() ?? '';
    String type = editDebt?.type ?? 'card';
    String memo = editDebt?.memo ?? '';

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => Container(
          height: MediaQuery.of(ctx).size.height * 0.85,
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(ctx).viewInsets.bottom,
            left: 24,
            right: 24,
            top: 20,
          ),
          decoration: const BoxDecoration(
            color: AppColors.washi,
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: ListView(
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppColors.gin,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                editDebt == null ? '借財の記帳' : '借財の編集',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
              const SizedBox(height: 20),
              _buildInputRow(
                '名目',
                (v) => name = v,
                initial: name,
                placeholder: '例: 住宅ローン',
              ),
              Row(
                children: [
                  Expanded(
                    child: _buildInputRow(
                      '借入残高（円）',
                      (v) => amount = v,
                      initial: amount,
                      isNum: true,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: _buildInputRow(
                      '年利（%）',
                      (v) => rate = v,
                      initial: rate,
                      isNum: true,
                    ),
                  ),
                ],
              ),
              Row(
                children: [
                  Expanded(
                    child: _buildInputRow(
                      '月返済額（円）',
                      (v) => monthly = v,
                      initial: monthly,
                      isNum: true,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: _buildInputRow(
                      '引き落とし日',
                      (v) => dueDay = v,
                      initial: dueDay,
                      isNum: true,
                    ),
                  ),
                ],
              ),
              const Padding(
                padding: EdgeInsets.only(bottom: 6),
                child: Text(
                  '種別',
                  style: TextStyle(
                    fontSize: 10,
                    color: AppColors.gin,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              DropdownButtonFormField<String>(
                value: type,
                items: typeLabels.entries
                    .map(
                      (e) =>
                          DropdownMenuItem(value: e.key, child: Text(e.value)),
                    )
                    .toList(),
                onChanged: (v) => type = v!,
                decoration: const InputDecoration(
                  border: UnderlineInputBorder(
                    borderSide: BorderSide(color: AppColors.gin),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              _buildInputRow('備考', (v) => memo = v, initial: memo, lines: 2),
              const SizedBox(height: 24),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.sumi,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
                onPressed: () {
                  int a = int.tryParse(amount) ?? 0;
                  double r = double.tryParse(rate) ?? 0;
                  int m = int.tryParse(monthly) ?? 0;
                  int? d = int.tryParse(dueDay);

                  if (a <= 0 || m <= 0) {
                    ScaffoldMessenger.of(ctx).showSnackBar(
                      const SnackBar(
                        content: Text('正しい金額を入力してください'),
                        backgroundColor: AppColors.beni,
                      ),
                    );
                    return;
                  }

                  final debt = Debt(
                    id:
                        editDebt?.id ??
                        DateTime.now().millisecondsSinceEpoch.toString(),
                    name: name.isEmpty ? '名無しの借財' : name,
                    amount: a,
                    originalAmount: editDebt != null
                        ? math.max(editDebt.originalAmount, a)
                        : a,
                    rate: r,
                    monthly: m,
                    dueDay: d,
                    startDate:
                        editDebt?.startDate ??
                        "${DateTime.now().year}-${DateTime.now().month.toString().padLeft(2, '0')}",
                    type: type,
                    memo: memo,
                  );

                  if (editDebt != null)
                    widget.state.updateDebt(debt);
                  else
                    widget.state.addDebt(debt);
                  Navigator.pop(ctx);
                },
                child: Text(
                  editDebt == null ? '帳簿に刻む' : '上書きする',
                  style: const TextStyle(
                    color: AppColors.washi,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 2,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInputRow(
    String label,
    Function(String) onChanged, {
    String initial = '',
    bool isNum = false,
    int lines = 1,
    String placeholder = '',
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontSize: 10,
              color: AppColors.gin,
              fontWeight: FontWeight.bold,
            ),
          ),
          TextFormField(
            initialValue: initial,
            keyboardType: isNum
                ? const TextInputType.numberWithOptions(decimal: true)
                : TextInputType.text,
            maxLines: lines,
            decoration: InputDecoration(
              hintText: placeholder,
              hintStyle: const TextStyle(color: Colors.black26),
              border: const UnderlineInputBorder(
                borderSide: BorderSide(color: AppColors.gin),
              ),
              focusedBorder: const UnderlineInputBorder(
                borderSide: BorderSide(color: AppColors.beni),
              ),
              contentPadding: const EdgeInsets.symmetric(vertical: 8),
            ),
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }
}

// ==========================================
// Tab 1: Ledger (記帳)
// ==========================================
class LedgerTab extends StatelessWidget {
  final AppState state;
  const LedgerTab({Key? key, required this.state}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: state,
      builder: (context, _) {
        if (state.debts.isEmpty) {
          return const Center(
            child: Text(
              '右下の「＋」から\n借財を記帳せよ。',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.gin, height: 2),
            ),
          );
        }
        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: state.debts.length,
          itemBuilder: (ctx, i) {
            final d = state.debts[i];
            final r = calcRepayment(d.amount, d.rate, d.monthly);
            return GestureDetector(
              onTap: () => _showDetailSheet(ctx, d),
              child: Container(
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: d.isCleared
                      ? AppColors.moegi.withOpacity(0.08)
                      : Colors.white.withOpacity(0.8),
                  border: Border.all(
                    color: d.isCleared
                        ? AppColors.moegi.withOpacity(0.3)
                        : Colors.black12,
                  ),
                  borderRadius: BorderRadius.circular(10),
                  boxShadow: const [
                    BoxShadow(
                      color: Colors.black12,
                      blurRadius: 4,
                      offset: Offset(0, 2),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          d.name,
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                          ),
                        ),
                        Text(
                          formatYen(d.amount),
                          style: TextStyle(
                            color: d.isCleared
                                ? AppColors.moegi
                                : AppColors.beni,
                            fontWeight: FontWeight.bold,
                            fontSize: 18,
                            decoration: d.isCleared
                                ? TextDecoration.lineThrough
                                : null,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        _tag(typeLabels[d.type] ?? 'その他'),
                        if (!d.isCleared) _tag('${d.rate}%'),
                        if (!d.isCleared) _tag('月 ${formatYen(d.monthly)}'),
                        if (d.isCleared)
                          _tag(
                            '✨ 完済済',
                            color: AppColors.moegi,
                            bg: AppColors.moegi.withOpacity(0.15),
                          )
                        else if (r.months < 0)
                          _tag(
                            '⚠ 完済不能',
                            color: AppColors.beni,
                            bg: AppColors.beni.withOpacity(0.15),
                          )
                        else
                          _tag(
                            '✓ 残${r.months}ヶ月',
                            color: AppColors.moegi,
                            bg: AppColors.moegi.withOpacity(0.15),
                          ),
                      ],
                    ),
                    if (!d.isCleared && d.originalAmount > 0) ...[
                      const SizedBox(height: 12),
                      LinearProgressIndicator(
                        value: 1 - (d.amount / d.originalAmount),
                        backgroundColor: Colors.black.withOpacity(0.08),
                        valueColor: const AlwaysStoppedAnimation(
                          AppColors.moegi,
                        ),
                        minHeight: 4,
                      ),
                    ],
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _tag(
    String text, {
    Color color = AppColors.sumi,
    Color bg = Colors.black12,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 10,
          color: color,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  void _showDetailSheet(BuildContext context, Debt debt) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.washi,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        final r = calcRepayment(debt.amount, debt.rate, debt.monthly);
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  debt.name,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 16),
                _row('借入残高', formatYen(debt.amount), AppColors.beni),
                _row('年利', '${debt.rate}%', AppColors.sumi),
                _row('月返済額', formatYen(debt.monthly), AppColors.sumi),
                _row(
                  '残り期間',
                  r.months < 0 ? '完済不能' : '${r.months}ヶ月',
                  AppColors.sumi,
                ),
                _row(
                  '支払利息総額',
                  r.totalInterest < 0 ? '−' : formatYen(r.totalInterest),
                  AppColors.beni,
                ),
                const SizedBox(height: 24),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () {
                          Navigator.pop(ctx);
                          state.deleteDebt(debt.id);
                        },
                        child: const Text(
                          '消去',
                          style: TextStyle(color: AppColors.beni),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.sumi,
                        ),
                        onPressed: () {
                          Navigator.pop(ctx);
                          _showRepaySheet(context, debt);
                        },
                        child: const Text(
                          '💸 返済を記帳',
                          style: TextStyle(color: AppColors.washi),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _row(String label, String val, Color valColor) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: const TextStyle(fontSize: 12, color: AppColors.gin),
          ),
          Text(
            val,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: valColor,
            ),
          ),
        ],
      ),
    );
  }

  void _showRepaySheet(BuildContext context, Debt debt) {
    String rep = '';
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.washi,
      isScrollControlled: true,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(ctx).viewInsets.bottom + 24, // ★ここでエラーを直しました！
          left: 24,
          right: 24,
          top: 24,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '対象: ${debt.name}',
              style: const TextStyle(fontSize: 12, color: AppColors.gin),
            ),
            Text(
              '残 ${formatYen(debt.amount)}',
              style: const TextStyle(
                fontSize: 18,
                color: AppColors.beni,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: '今回返済する額（円）',
                border: UnderlineInputBorder(),
              ),
              onChanged: (v) => rep = v,
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.sumi,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
                onPressed: () {
                  int val = int.tryParse(rep) ?? 0;
                  if (val > 0) {
                    state.repayDebt(debt.id, val);
                    Navigator.pop(ctx);
                  }
                },
                child: const Text(
                  '帳簿から差し引く',
                  style: TextStyle(
                    color: AppColors.washi,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ==========================================
// Tab 2: Payment (支払)
// ==========================================
class PaymentTab extends StatefulWidget {
  final AppState state;
  const PaymentTab({Key? key, required this.state}) : super(key: key);
  @override
  _PaymentTabState createState() => _PaymentTabState();
}

class _PaymentTabState extends State<PaymentTab> {
  DateTime viewDate = DateTime.now();

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.state,
      builder: (context, _) {
        final active = widget.state.debts
            .where((d) => !d.isCleared && d.dueDay != null)
            .toList();
        final monthKey =
            "${viewDate.year}-${viewDate.month.toString().padLeft(2, '0')}";

        int totalAmt = active.fold(0, (s, d) => s + d.monthly);
        int paidAmt = active
            .where((d) => widget.state.paidRecords['${d.id}_$monthKey'] == true)
            .fold(0, (s, d) => s + d.monthly);
        int remainAmt = totalAmt - paidAmt;

        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                IconButton(
                  icon: const Icon(Icons.chevron_left),
                  onPressed: () => setState(
                    () => viewDate = DateTime(
                      viewDate.year,
                      viewDate.month - 1,
                      1,
                    ),
                  ),
                ),
                Text(
                  '${viewDate.year}年${viewDate.month}月',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                    letterSpacing: 2,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.chevron_right),
                  onPressed: () => setState(
                    () => viewDate = DateTime(
                      viewDate.year,
                      viewDate.month + 1,
                      1,
                    ),
                  ),
                ),
              ],
            ),
            Container(
              padding: const EdgeInsets.all(12),
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.05),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                children: [
                  _psBox('今月合計', formatYen(totalAmt), AppColors.sumi),
                  _psBox('支払済', formatYen(paidAmt), AppColors.moegi),
                  _psBox('残り', formatYen(remainAmt), AppColors.beni),
                ],
              ),
            ),
            _buildCalendar(active, monthKey),
            const SizedBox(height: 16),
            const Text(
              '支払い一覧',
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.bold,
                color: AppColors.gin,
                letterSpacing: 3,
              ),
            ),
            const Divider(),
            ...active.map((d) {
              final key = '${d.id}_$monthKey';
              final isPaid = widget.state.paidRecords[key] == true;
              return Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.7),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.black12),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: isPaid ? AppColors.gin : AppColors.sumi,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            '${d.dueDay}',
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                              height: 1,
                            ),
                          ),
                          const Text(
                            '日',
                            style: TextStyle(
                              color: Colors.white70,
                              fontSize: 9,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            d.name,
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                              decoration: isPaid
                                  ? TextDecoration.lineThrough
                                  : null,
                              color: isPaid ? AppColors.gin : AppColors.sumi,
                            ),
                          ),
                          Text(
                            formatYen(d.monthly),
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: isPaid ? AppColors.gin : AppColors.beni,
                              decoration: isPaid
                                  ? TextDecoration.lineThrough
                                  : null,
                            ),
                          ),
                        ],
                      ),
                    ),
                    GestureDetector(
                      onTap: () => widget.state.togglePaid(key),
                      child: Container(
                        width: 32,
                        height: 32,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: isPaid ? AppColors.moegi : AppColors.gin,
                            width: 2,
                          ),
                          color: isPaid ? AppColors.moegi : Colors.transparent,
                        ),
                        child: Icon(
                          Icons.check,
                          size: 18,
                          color: isPaid ? Colors.white : AppColors.gin,
                        ),
                      ),
                    ),
                  ],
                ),
              );
            }).toList(),
          ],
        );
      },
    );
  }

  Widget _psBox(String label, String val, Color color) {
    return Expanded(
      child: Column(
        children: [
          Text(
            val,
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 14,
              color: color,
            ),
          ),
          Text(
            label,
            style: const TextStyle(fontSize: 9, color: AppColors.gin),
          ),
        ],
      ),
    );
  }

  Widget _buildCalendar(List<Debt> active, String monthKey) {
    int daysInMonth = DateTime(viewDate.year, viewDate.month + 1, 0).day;
    int firstDay = DateTime(viewDate.year, viewDate.month, 1).weekday % 7;

    List<Widget> cells = [];
    final daysOfWeek = ['日', '月', '火', '水', '木', '金', '土'];
    for (int i = 0; i < 7; i++) {
      cells.add(
        Center(
          child: Text(
            daysOfWeek[i],
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.bold,
              color: i == 0
                  ? AppColors.beni
                  : i == 6
                  ? AppColors.ai
                  : AppColors.gin,
            ),
          ),
        ),
      );
    }

    for (int i = 0; i < firstDay; i++) {
      cells.add(const SizedBox());
    }

    Map<int, List<Debt>> payMap = {};
    for (var d in active) {
      int day = math.min(d.dueDay!, daysInMonth);
      payMap.putIfAbsent(day, () => []).add(d);
    }

    DateTime today = DateTime.now();

    for (int day = 1; day <= daysInMonth; day++) {
      bool isToday =
          (today.year == viewDate.year &&
          today.month == viewDate.month &&
          today.day == day);
      int dow = (firstDay + day - 1) % 7;
      Color numColor = dow == 0
          ? AppColors.beni
          : dow == 6
          ? AppColors.ai
          : AppColors.sumi;

      cells.add(
        Container(
          margin: const EdgeInsets.all(1),
          decoration: BoxDecoration(
            color: isToday
                ? AppColors.kin.withOpacity(0.2)
                : Colors.black.withOpacity(0.03),
            border: isToday ? Border.all(color: AppColors.kin) : null,
            borderRadius: BorderRadius.circular(6),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                '$day',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: numColor,
                ),
              ),
              if (payMap[day] != null)
                Wrap(
                  spacing: 2,
                  children: payMap[day]!.map((d) {
                    bool paid =
                        widget.state.paidRecords['${d.id}_$monthKey'] == true;
                    return Container(
                      width: 5,
                      height: 5,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: paid ? AppColors.moegi : AppColors.beni,
                      ),
                    );
                  }).toList(),
                ),
            ],
          ),
        ),
      );
    }

    return GridView.count(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisCount: 7,
      children: cells,
    );
  }
}

// ==========================================
// Tab 3: Simulation (試算)
// ==========================================
class SimulationTab extends StatefulWidget {
  final AppState state;
  const SimulationTab({Key? key, required this.state}) : super(key: key);
  @override
  _SimulationTabState createState() => _SimulationTabState();
}

class _SimulationTabState extends State<SimulationTab> {
  bool isAvalanche = false;
  double extraPayment = 0;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.state,
      builder: (context, _) {
        final active = widget.state.debts.where((d) => !d.isCleared).toList();
        if (active.isEmpty) {
          return const Center(
            child: Text(
              '借財を記帳すると試算が表示されます',
              style: TextStyle(color: AppColors.gin, fontSize: 13),
            ),
          );
        }

        int maxM = 0;
        bool allFeasible = true;
        for (var d in active) {
          final r = calcRepayment(d.amount, d.rate, d.monthly);
          if (r.months < 0) allFeasible = false;
          if (r.months > maxM) maxM = r.months;
        }

        List<Debt> sorted = List.from(active);
        if (isAvalanche) {
          sorted.sort(
            (a, b) => b.rate != a.rate
                ? b.rate.compareTo(a.rate)
                : b.amount.compareTo(a.amount),
          );
        } else {
          sorted.sort((a, b) => a.amount.compareTo(b.amount));
        }

        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const Text(
              '総合返済シミュレーション',
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.bold,
                color: AppColors.gin,
                letterSpacing: 2,
              ),
            ),
            const SizedBox(height: 12),
            _card('総合サマリー', AppColors.beni, [
              _simRow(
                '最長完済期間',
                allFeasible
                    ? '$maxMヶ月 (${(maxM / 12).toStringAsFixed(1)}年)'
                    : '⚠完済不能',
                allFeasible ? AppColors.ai : AppColors.beni,
              ),
              _simRow(
                '総支払総額',
                formatYen(widget.state.totalDebt + widget.state.totalInterest),
                AppColors.beni,
              ),
            ]),
            _card('推奨返済プラン', AppColors.beni, [
              Row(
                children: [
                  Expanded(
                    child: _stratBtn(
                      '雪だるま式\n(モチベ維持)',
                      !isAvalanche,
                      () => setState(() => isAvalanche = false),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _stratBtn(
                      '雪崩式\n(利息節約)',
                      isAvalanche,
                      () => setState(() => isAvalanche = true),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              ...sorted
                  .asMap()
                  .entries
                  .map(
                    (e) => Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Row(
                        children: [
                          CircleAvatar(
                            radius: 10,
                            backgroundColor: AppColors.beni,
                            child: Text(
                              '${e.key + 1}',
                              style: const TextStyle(
                                fontSize: 10,
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              e.value.name,
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          Text(
                            '${formatYen(e.value.amount)} / ${e.value.rate}%',
                            style: const TextStyle(
                              fontSize: 11,
                              color: AppColors.gin,
                            ),
                          ),
                        ],
                      ),
                    ),
                  )
                  .toList(),
            ]),
            _card('繰り上げ返済', AppColors.moegi, [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    '毎月の追加額',
                    style: TextStyle(fontSize: 11, color: AppColors.gin),
                  ),
                  Text(
                    formatYen(extraPayment.toInt()),
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ],
              ),
              Slider(
                value: extraPayment,
                min: 0,
                max: math.max(100000, widget.state.totalMonthly.toDouble() * 2),
                activeColor: AppColors.sumi,
                inactiveColor: Colors.black12,
                onChanged: (v) => setState(() => extraPayment = v),
              ),
              _buildExtraResult(sorted.first, extraPayment.toInt()),
            ]),
            _card('返済推移グラフ', AppColors.ai, [
              SizedBox(
                height: 140,
                child: CustomPaint(
                  painter: ChartPainter(active, maxM),
                  size: Size.infinite,
                ),
              ),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(width: 8, height: 8, color: AppColors.ai),
                  const SizedBox(width: 4),
                  const Text('元金', style: TextStyle(fontSize: 10)),
                  const SizedBox(width: 16),
                  Container(width: 8, height: 8, color: AppColors.beni),
                  const SizedBox(width: 4),
                  const Text('利息', style: TextStyle(fontSize: 10)),
                ],
              ),
            ]),
          ],
        );
      },
    );
  }

  Widget _card(String title, Color dotColor, List<Widget> children) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.7),
        border: Border.all(color: Colors.black12),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: dotColor,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                title,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ...children,
        ],
      ),
    );
  }

  Widget _simRow(String label, String val, Color color) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: const TextStyle(fontSize: 11, color: AppColors.gin),
          ),
          Text(
            val,
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 14,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  Widget _stratBtn(String text, bool active, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(8),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: active ? AppColors.beni : Colors.black.withOpacity(0.05),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: active ? AppColors.beni : Colors.black12),
        ),
        child: Text(
          text,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.bold,
            color: active ? Colors.white : AppColors.gin,
          ),
        ),
      ),
    );
  }

  Widget _buildExtraResult(Debt target, int extra) {
    if (extra == 0)
      return const Center(
        child: Text(
          'スライダーを動かすと効果を試算します',
          style: TextStyle(fontSize: 11, color: AppColors.gin),
        ),
      );
    final orig = calcRepayment(target.amount, target.rate, target.monthly);
    final ne = calcRepayment(
      target.amount,
      target.rate,
      target.monthly + extra,
    );
    if (orig.months < 0 || ne.months < 0) return const SizedBox();
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.moegi.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        children: [
          Text(
            '「${target.name}」に集中返済',
            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 4),
          _simRow('完済短縮', '▲ ${orig.months - ne.months}ヶ月', AppColors.moegi),
          _simRow(
            '節約利息',
            '▲ ${formatYen(orig.totalInterest - ne.totalInterest)}',
            AppColors.moegi,
          ),
        ],
      ),
    );
  }
}

class ChartPainter extends CustomPainter {
  final List<Debt> debts;
  final int maxMonths;
  ChartPainter(this.debts, this.maxMonths);

  @override
  void paint(Canvas canvas, Size size) {
    if (debts.isEmpty || maxMonths <= 0) return;
    int cap = math.min(maxMonths, 120);
    int step = cap <= 24
        ? 1
        : cap <= 60
        ? 3
        : 6;
    List<Map<String, double>> points = [];
    double maxVal = 0;

    for (int m = step; m <= cap; m += step) {
      double p = 0, i = 0;
      for (var d in debts) {
        final r = calcRepayment(d.amount, d.rate, d.monthly);
        if (r.months < 0) continue;
        for (int j = 0; j < math.min(m, r.schedule.length); j++) {
          p += r.schedule[j].principalPart;
          i += r.schedule[j].interest;
        }
      }
      points.add({'m': m.toDouble(), 'p': p, 'i': i});
      if (p + i > maxVal) maxVal = p + i;
    }

    if (maxVal == 0) return;
    double barW = (size.width / points.length) * 0.8;
    double gap = (size.width / points.length) * 0.2;

    for (int idx = 0; idx < points.length; idx++) {
      double p = points[idx]['p']!;
      double i = points[idx]['i']!;
      double ph = (p / maxVal) * size.height;
      double ih = (i / maxVal) * size.height;
      double x = idx * (barW + gap) + gap / 2;

      // Principal (AI color)
      canvas.drawRect(
        Rect.fromLTWH(x, size.height - ph, barW, ph),
        Paint()..color = AppColors.ai,
      );
      // Interest (Beni color)
      canvas.drawRect(
        Rect.fromLTWH(x, size.height - ph - ih, barW, ih),
        Paint()..color = AppColors.beni,
      );
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}

// ==========================================
// Tab 4: Karma (業 - 物理エンジン)
// ==========================================
class KarmaTab extends StatefulWidget {
  final AppState state;
  final bool isActive;
  const KarmaTab({Key? key, required this.state, required this.isActive})
    : super(key: key);
  @override
  _KarmaTabState createState() => _KarmaTabState();
}

class _KarmaTabState extends State<KarmaTab>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  List<WoodTag> _tags = [];
  bool _initialized = false;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 1),
    )..addListener(() => setState(() {}));
  }

  @override
  void didUpdateWidget(KarmaTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isActive && !oldWidget.isActive) {
      _initTags();
      _ctrl.repeat();
    } else if (!widget.isActive && oldWidget.isActive) {
      _ctrl.stop();
    }
  }

  void _initTags() {
    final active = widget.state.debts.where((d) => !d.isCleared).toList();
    _tags.clear();
    for (int i = 0; i < active.length; i++) {
      _tags.add(WoodTag(active[i], i, active.length));
    }
    _initialized = true;
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.state.totalDebt == 0) {
      return const Center(
        child: Text(
          '業の可視化\n（清廉潔白）',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 22,
            color: Colors.black26,
            fontWeight: FontWeight.bold,
          ),
        ),
      );
    }
    return LayoutBuilder(
      builder: (ctx, consts) {
        if (_initialized) {
          for (var t in _tags) {
            t.update(consts.maxWidth, consts.maxHeight);
          }
        }
        return CustomPaint(painter: KarmaPainter(_tags), size: Size.infinite);
      },
    );
  }
}

class WoodTag {
  Debt debt;
  double x = 0, y = 0, vx = 0, vy = 0, angle = 0, vAngle = 0;
  double w = 120, h = 40;
  double gravity = 0.8;
  double bounce = -0.3;
  int index;
  int total;
  bool initialized = false;

  WoodTag(this.debt, this.index, this.total) {
    gravity =
        0.7 +
        (debt.amount > 500000
            ? 0.5
            : debt.amount > 100000
            ? 0.3
            : 0);
  }

  void update(double sw, double sh) {
    if (!initialized) {
      x = math.Random().nextDouble() * (sw - w - 20) + 10;
      y = -100.0 - index * 100;
      vx = (math.Random().nextDouble() - 0.5) * 4;
      angle = (math.Random().nextDouble() - 0.5) * 0.5;
      vAngle = (math.Random().nextDouble() - 0.5) * 0.1;
      initialized = true;
    }

    vy += gravity;
    y += vy;
    x += vx;
    angle += vAngle;

    if (x < 10) {
      x = 10;
      vx *= -0.5;
    }
    if (x + w > sw - 10) {
      x = sw - w - 10;
      vx *= -0.5;
    }

    double groundY = sh - 40 - (total - index) * 10;
    if (y + h > groundY) {
      y = groundY - h;
      vy *= bounce;
      vx *= 0.8;
      vAngle *= 0.75;
      if (vy.abs() > 2) HapticFeedback.selectionClick();
      if (vy.abs() < 1.0) {
        vy = 0;
        vAngle = 0;
        vx = 0;
      }
    }
  }
}

class KarmaPainter extends CustomPainter {
  final List<WoodTag> tags;
  KarmaPainter(this.tags);

  @override
  void paint(Canvas canvas, Size size) {
    for (var t in tags) {
      canvas.save();
      canvas.translate(t.x + t.w / 2, t.y + t.h / 2);
      canvas.rotate(t.angle);

      // Shadow
      canvas.drawRect(
        Rect.fromLTWH(-t.w / 2 + 2, -t.h / 2 + 4, t.w, t.h),
        Paint()
          ..color = Colors.black26
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4),
      );
      // Wood base
      canvas.drawRect(
        Rect.fromLTWH(-t.w / 2, -t.h / 2, t.w, t.h),
        Paint()..color = const Color(0xFFc9a227),
      );
      // Border
      canvas.drawRect(
        Rect.fromLTWH(-t.w / 2, -t.h / 2, t.w, t.h),
        Paint()
          ..color = const Color(0xFFa07c10)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1,
      );

      final textPainter = TextPainter(
        textDirection: TextDirection.ltr,
        textAlign: TextAlign.center,
      );
      // Name
      textPainter.text = TextSpan(
        text: t.debt.name.length > 6
            ? '${t.debt.name.substring(0, 5)}…'
            : t.debt.name,
        style: const TextStyle(
          color: AppColors.sumi,
          fontSize: 10,
          fontWeight: FontWeight.bold,
        ),
      );
      textPainter.layout();
      textPainter.paint(
        canvas,
        Offset(-textPainter.width / 2, -textPainter.height / 2 - 8),
      );
      // Amount
      textPainter.text = TextSpan(
        text: formatYen(t.debt.amount),
        style: const TextStyle(
          color: AppColors.beni,
          fontSize: 13,
          fontWeight: FontWeight.bold,
        ),
      );
      textPainter.layout();
      textPainter.paint(
        canvas,
        Offset(-textPainter.width / 2, -textPainter.height / 2 + 6),
      );

      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}

// ==========================================
// Tab 5: Oracle (託宣)
// ==========================================
class OracleTab extends StatelessWidget {
  final AppState state;
  const OracleTab({Key? key, required this.state}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: state,
      builder: (context, _) {
        final total = state.totalDebt;
        String title, oracle, hanko, proverb, src;
        if (total == 0) {
          title = "【無借金】";
          oracle = "清廉潔白。その身軽さを誇りに思い、堅実な歩みを続けられよ。";
          hanko = "清廉\n潔白";
          proverb = "借金は雪だるまのようなもの、転がるうちに大きくなる。";
          src = "欧州の格言";
        } else if (total <= 50000) {
          title = "【微借】";
          oracle = "まだ引き返せる範疇。今月の小さな我慢が、明日の平穏を生むであろう。";
          hanko = "早期\n返済";
          proverb = "節約は二番目の収入である。";
          src = "キケロ";
        } else if (total <= 300000) {
          title = "【黄色信号】";
          oracle = "油断が身を滅ぼす入り口。これ以上の借財は、貴方の未来を重く縛り付ける。";
          hanko = "浪費\n厳禁";
          proverb = "貧乏は恥ずかしくないが、貧乏を望むことは恥だ。";
          src = "ソクラテス";
        } else if (total <= 1000000) {
          title = "【火の車】";
          oracle = "足元に火が点いている。宵越しの銭を持たぬ生き方は、直ちに改めよ。";
          hanko = "炎上\n警戒";
          proverb = "借金をすることは、自由を売ることである。";
          src = "B.フランクリン";
        } else {
          title = "【泥沼の自転車操業】";
          oracle = "返すために借りる、終わりのない輪廻。すべてを売り払い、身の丈を知るべし。";
          hanko = "破滅\n寸前";
          proverb = "最大の勇気は、助けを求めることである。";
          src = "古代ローマの格言";
        }

        return Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: AppColors.sumi,
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: AppColors.gin),
                ),
                child: Text(
                  title,
                  style: const TextStyle(
                    color: AppColors.washi,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 3,
                  ),
                ),
              ),
              const SizedBox(height: 24),
              Transform.rotate(
                angle: -0.2,
                child: Container(
                  width: 88,
                  height: 88,
                  decoration: BoxDecoration(
                    border: Border.all(color: AppColors.beni, width: 4),
                    borderRadius: BorderRadius.circular(6),
                    color: Colors.white.withOpacity(0.5),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    hanko,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: AppColors.beni,
                      fontSize: 21,
                      fontWeight: FontWeight.w900,
                      height: 1.1,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 24),
              Text(
                oracle,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 14, height: 2),
              ),
              const SizedBox(height: 24),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.05),
                  border: const Border(
                    left: BorderSide(color: AppColors.kin, width: 3),
                  ),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      proverb,
                      style: const TextStyle(fontSize: 13, height: 1.6),
                    ),
                    const SizedBox(height: 8),
                    Align(
                      alignment: Alignment.centerRight,
                      child: Text(
                        '— $src',
                        style: const TextStyle(
                          fontSize: 10,
                          color: AppColors.gin,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const Spacer(),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.sumi,
                  minimumSize: const Size(double.infinity, 50),
                ),
                onPressed: () {
                  Clipboard.setData(
                    ClipboardData(
                      text:
                          '【からくり大福帳】\n私の総借財は ${formatYen(total)} です。\n判定: $title\n「$oracle」\n#借金管理',
                    ),
                  );
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('瓦版に晒しました (クリップボードにコピー)')),
                  );
                },
                child: const Text(
                  '瓦版に晒す (Share)',
                  style: TextStyle(
                    color: AppColors.washi,
                    fontWeight: FontWeight.bold,
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

// ==========================================
// Fire Effect Background
// ==========================================
class FirePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    // 簡易的な炎エフェクト（赤黒いグラデーション）
    final rect = Offset.zero & size;
    final gradient = LinearGradient(
      begin: Alignment.bottomCenter,
      end: Alignment.topCenter,
      colors: [AppColors.fire.withOpacity(0.3), Colors.transparent],
    );
    canvas.drawRect(rect, Paint()..shader = gradient.createShader(rect));
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
