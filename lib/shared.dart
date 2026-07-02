import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

export 'package:google_fonts/google_fonts.dart' show GoogleFonts;
export 'package:firebase_auth/firebase_auth.dart';

bool isPhoneWidth(double width) => width < 600;
bool isTabletWidth(double width) => width >= 600 && width < 1024;
bool isDesktopWidth(double width) => width >= 1024;

double pagePadding(double width) {
  if (isPhoneWidth(width)) return 16;
  if (isTabletWidth(width)) return 24;
  return 32;
}

class AppColors {
  static const Color primary      = Color(0xFF4F46E5);
  static const Color primaryHover = Color(0xFF4338CA);
  static const Color primaryLight = Color(0xFFEEF2FF);
  static const Color background   = Color(0xFFF8FAFC);
  static const Color surface      = Color(0xFFFFFFFF);
  static const Color textPrimary  = Color(0xFF0F172A);
  static const Color textSecondary= Color(0xFF64748B);
  static const Color textMuted    = Color(0xFF94A3B8);
  static const Color textInverse  = Color(0xFFFFFFFF);
  static const Color border       = Color(0xFFE2E8F0);
  static const Color success      = Color(0xFF10B981);
  static const Color successLight = Color(0xFFD1FAE5);
  static const Color error        = Color(0xFFEF4444);
  static const Color errorLight   = Color(0xFFFFE4E6);
  static const Color warning      = Color(0xFFF59E0B);
  static const Color warningLight = Color(0xFFFEF3C7);
  static const Color infoBadge    = Color(0xFF3B82F6);
  static const Color infoBadgeLight= Color(0xFFEFF6FF);
}

enum ColumnType { text, number, date, boolean, dropdown }

extension ColumnTypeLabel on ColumnType {
  String get label {
    switch (this) {
      case ColumnType.text:     return 'Text';
      case ColumnType.number:   return 'Number';
      case ColumnType.date:     return 'Date';
      case ColumnType.boolean:  return 'Boolean';
      case ColumnType.dropdown: return 'Dropdown';
    }
  }

  IconData get icon {
    switch (this) {
      case ColumnType.text:     return Icons.text_fields_rounded;
      case ColumnType.number:   return Icons.tag_rounded;
      case ColumnType.date:     return Icons.calendar_today_rounded;
      case ColumnType.boolean:  return Icons.toggle_on_rounded;
      case ColumnType.dropdown: return Icons.arrow_drop_down_circle_outlined;
    }
  }
}

class SchemaColumn {
  String      name;
  ColumnType  type;
  bool        required;
  List<String> dropdownOptions;
  String?     semanticKey;
  String?     parentKey;

  SchemaColumn({
    required this.name,
    this.type     = ColumnType.text,
    this.required = true,
    this.dropdownOptions = const [],
    this.semanticKey,
    this.parentKey,
  });

  SchemaColumn copyWith({
    String?      name,
    ColumnType?  type,
    bool?        required,
    List<String>? dropdownOptions,
    String?      semanticKey,
    String?      parentKey,
  }) => SchemaColumn(
    name:            name            ?? this.name,
    type:            type            ?? this.type,
    required:        required        ?? this.required,
    dropdownOptions: dropdownOptions ?? List.from(this.dropdownOptions),
    semanticKey:     semanticKey     ?? this.semanticKey,
    parentKey:       parentKey       ?? this.parentKey,
  );

  Map<String, dynamic> toJson() => {
    'name': name,
    'type': type.name,
    'required': required,
    'dropdownOptions': dropdownOptions,
    if (semanticKey != null) 'semanticKey': semanticKey,
    if (parentKey != null) 'parentKey': parentKey,
  };

  factory SchemaColumn.fromJson(Map<String, dynamic> json) => SchemaColumn(
    name: json['name'] as String? ?? '',
    type: ColumnType.values.firstWhere(
      (e) => e.name == json['type'],
      orElse: () => ColumnType.text,
    ),
    required: json['required'] as bool? ?? true,
    dropdownOptions: (json['dropdownOptions'] as List<dynamic>?)
        ?.map((e) => e.toString())
        .toList() ?? [],
    semanticKey: json['semanticKey'] as String?,
    parentKey: json['parentKey'] as String?,
  );
}

SnackBar errorSnack(String msg) => SnackBar(
  content: Text(msg),
  backgroundColor: AppColors.error,
  behavior: SnackBarBehavior.floating,
  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
);

String authErrorMessage(FirebaseAuthException e, {required bool isRegister}) {
  switch (e.code) {
    case 'configuration-not-found':
      return 'Firebase Auth is not configured. Enable Email/Password sign-in in Firebase Console.';
    case 'email-already-in-use':
      return 'An account already exists for this email.';
    case 'weak-password':
      return 'Password should be at least 6 characters.';
    case 'invalid-email':
      return 'Enter a valid email address.';
    case 'user-not-found':
      return 'No account found for this email.';
    case 'wrong-password':
    case 'invalid-credential':
      return 'Incorrect email or password.';
    case 'network-request-failed':
      return 'Network error. Check your internet connection and try again.';
    default:
      return e.message ?? (isRegister ? 'Registration failed.' : 'Sign in failed.');
  }
}

LinearGradient primaryGradient = const LinearGradient(
  colors: [Color(0xFF6C63FF), Color(0xFF8B83FF)],
  begin: Alignment.topLeft, end: Alignment.bottomRight,
);

BoxDecoration glassCard({double opacity = 0.6}) => BoxDecoration(
  color: Colors.white.withValues(alpha: opacity),
  borderRadius: BorderRadius.circular(12),
  border: Border.all(color: Colors.white.withValues(alpha: 0.3)),
  gradient: LinearGradient(
    colors: [Colors.white.withValues(alpha: 0.7), Colors.white.withValues(alpha: 0.3)],
    begin: Alignment.topLeft, end: Alignment.bottomRight,
  ),
);

class ScaleButton extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;
  const ScaleButton({super.key, required this.child, this.onTap});
  @override
  State<ScaleButton> createState() => _ScaleButtonState();
}
class _ScaleButtonState extends State<ScaleButton> with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(duration: const Duration(milliseconds: 120), vsync: this);
    _scale = Tween<double>(begin: 1.0, end: 0.95).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut));
  }

  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => _ctrl.forward(),
      onTapUp: (_) => _ctrl.reverse(),
      onTapCancel: () => _ctrl.reverse(),
      onTap: widget.onTap,
      child: AnimatedBuilder(animation: _scale, builder: (_, child) => Transform.scale(scale: _scale.value, child: child), child: widget.child),
    );
  }
}

Route<dynamic> slideRoute(Widget page) => PageRouteBuilder(
  pageBuilder: (context, animation, secondaryAnimation) => page,
  transitionsBuilder: (context, animation, secondaryAnimation, child) {
    const begin = Offset(0.1, 0.0);
    const end = Offset.zero;
    const curve = Curves.easeOutCubic;
    var tween = Tween(begin: begin, end: end).chain(CurveTween(curve: curve));
    var fadeTween = Tween<double>(begin: 0.0, end: 1.0).chain(CurveTween(curve: curve));
    return SlideTransition(
      position: animation.drive(tween),
      child: FadeTransition(
        opacity: animation.drive(fadeTween),
        child: child,
      ),
    );
  },
  transitionDuration: const Duration(milliseconds: 300),
);

class SchemaRoute {
  static const String onboarding  = '/onboarding';
  static const String login       = '/login';
  static const String register    = '/register';
  static const String home        = '/home';
  static const String schema      = '/schema';
  static const String addRows     = '/add-rows';
  static const String finalScreen = '/final';
}

class ProjectData {
  final String id;
  final String fileName;
  final List<SchemaColumn> columns;
  final Timestamp createdAt;
  final Timestamp updatedAt;

  ProjectData({
    required this.id,
    required this.fileName,
    required this.columns,
    required this.createdAt,
    required this.updatedAt,
  });

  Map<String, dynamic> toJson() => {
    'fileName': fileName,
    'columns': columns.map((c) => c.toJson()).toList(),
    'createdAt': createdAt,
    'updatedAt': updatedAt,
  };

  factory ProjectData.fromSnapshot(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return ProjectData(
      id: doc.id,
      fileName: data['fileName'] as String? ?? 'Untitled',
      columns: (data['columns'] as List<dynamic>?)
          ?.map((e) => SchemaColumn.fromJson(e as Map<String, dynamic>))
          .toList() ?? [],
      createdAt: data['createdAt'] as Timestamp? ?? Timestamp.now(),
      updatedAt: data['updatedAt'] as Timestamp? ?? Timestamp.now(),
    );
  }
}

class RecordData {
  final String id;
  final Map<String, dynamic> data;

  RecordData({required this.id, required this.data});

  factory RecordData.fromSnapshot(DocumentSnapshot doc) {
    final d = doc.data() as Map<String, dynamic>? ?? {};
    return RecordData(id: doc.id, data: Map<String, dynamic>.from(d));
  }
}

class ShimmerLoading extends StatefulWidget {
  final double width;
  final double height;
  final double borderRadius;
  const ShimmerLoading({
    super.key,
    required this.width,
    required this.height,
    this.borderRadius = 8,
  });

  @override
  State<ShimmerLoading> createState() => _ShimmerLoadingState();
}

class _ShimmerLoadingState extends State<ShimmerLoading> with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (_, child) {
        return Container(
          width: widget.width,
          height: widget.height,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(widget.borderRadius),
            gradient: LinearGradient(
              colors: [
                AppColors.border.withValues(alpha: 0.6),
                AppColors.border.withValues(alpha: 0.25),
                AppColors.border.withValues(alpha: 0.6),
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              stops: [
                0.0,
                _ctrl.value,
                1.0,
              ],
            ),
          ),
        );
      },
    );
  }
}
