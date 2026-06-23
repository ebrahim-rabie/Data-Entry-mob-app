import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_application_1/firebase_options.dart';
import 'package:flutter_application_1/shared.dart';
import 'package:flutter_application_1/database.dart';
import 'package:flutter_application_1/login.dart';
import 'package:flutter_application_1/register.dart';
import 'package:flutter_application_1/home_import.dart';
import 'package:flutter_application_1/schema_add_rows.dart';
import 'package:flutter_application_1/final_screen.dart';
import 'package:flutter_application_1/onboarding.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  FirebaseFirestore.instance.settings = const Settings(
    persistenceEnabled: true,
    cacheSizeBytes: Settings.CACHE_SIZE_UNLIMITED,
  );
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'SmartEntry',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        textTheme: Theme.of(context).textTheme,
        colorScheme: ColorScheme.fromSeed(seedColor: AppColors.primary),
        useMaterial3: true,
      ),
      home: const AuthGate(),
      onGenerateRoute: _onGenerateRoute,
    );
  }

  Route<dynamic>? _onGenerateRoute(RouteSettings settings) {
    switch (settings.name) {
      case SchemaRoute.onboarding:
        return slideRoute(const OnboardingScreen());
      case SchemaRoute.login:
        return slideRoute(const LoginScreen());
      case SchemaRoute.register:
        return slideRoute(const RegisterScreen());
      case SchemaRoute.home:
        return slideRoute(const HomeImportScreen());
      case SchemaRoute.schema:
        final args = settings.arguments as Map<String, dynamic>?;
        return slideRoute(SchemaBuilderScreen(
          projectId: args?['projectId'] as String?,
          importedColumns: args?['columns'] as List<SchemaColumn>?,
          importedFileName: args?['fileName'] as String?,
          importedRecords: args?['records'] as List<Map<String, dynamic>>?,
        ));
      case SchemaRoute.addRows:
        final args = settings.arguments as Map<String, dynamic>?;
        return slideRoute(SchemaAddRowsScreen(
          projectId: args?['projectId'] as String?,
          fileName: args?['fileName'] as String? ?? 'Untitled',
          columns: args?['columns'] as List<SchemaColumn>? ?? [],
          initialRecords: args?['records'] as List<Map<String, dynamic>>?,
        ));
      case SchemaRoute.finalScreen:
        final args = settings.arguments as Map<String, dynamic>?;
        return slideRoute(FinalScreen(
          projectId: args?['projectId'] as String? ?? '',
          fileName: args?['fileName'] as String? ?? 'Untitled',
          columns: args?['columns'] as List<SchemaColumn>? ?? [],
        ));
      default:
        return slideRoute(const LoginScreen());
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  AUTH GATE — listens to Firebase auth state
// ─────────────────────────────────────────────────────────────────────────────

class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        if (snapshot.hasData) {
          return const HomeImportScreen();
        }
        return const OnboardingScreen();
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  SCREEN 1 — SCHEMA BUILDER
// ─────────────────────────────────────────────────────────────────────────────

class SchemaBuilderScreen extends StatefulWidget {
  final String? projectId;
  final List<SchemaColumn>? importedColumns;
  final String?             importedFileName;
  final List<Map<String, dynamic>>? importedRecords;

  const SchemaBuilderScreen({
    super.key,
    this.projectId,
    this.importedColumns,
    this.importedFileName,
    this.importedRecords,
  });

  @override
  State<SchemaBuilderScreen> createState() => _SchemaBuilderScreenState();
}

class _SchemaBuilderScreenState extends State<SchemaBuilderScreen> {
  late List<SchemaColumn> _columns;
  late List<Map<String, dynamic>> _importedRecords;
  late TextEditingController _fileNameCtrl;
  bool _previewOpen = false;
  String? _projectId;

  @override
  void initState() {
    super.initState();
    _projectId = widget.projectId;
    _fileNameCtrl = TextEditingController(
      text: widget.importedFileName ?? 'Untitled file',
    );
    _columns = widget.importedColumns != null
        ? List.from(widget.importedColumns!)
        : [SchemaColumn(name: 'Column 1')];
    _importedRecords = widget.importedRecords ?? [];
  }

  @override
  void dispose() {
    _fileNameCtrl.dispose();
    super.dispose();
  }

  void _addColumn() {
    setState(() => _columns.add(
      SchemaColumn(name: 'Column ${_columns.length + 1}'),
    ));
  }

  void _removeColumn(int index) {
    if (_columns.length == 1) return;
    setState(() => _columns.removeAt(index));
  }

  void _updateColumn(int index, SchemaColumn updated) {
    setState(() => _columns[index] = updated);
  }

  void _reorder(int oldIndex, int newIndex) {
    setState(() {
      if (newIndex > oldIndex) newIndex--;
      final col = _columns.removeAt(oldIndex);
      _columns.insert(newIndex, col);
    });
  }

  Future<void> _saveAndEnter() async {
    final emptyNames = _columns.any((c) => c.name.trim().isEmpty);
    if (emptyNames) {
      ScaffoldMessenger.of(context).showSnackBar(errorSnack(
        'Please name all columns before continuing.',
      ));
      return;
    }
    final seen = <String>{};
    for (final c in _columns) {
      final key = c.name.trim().toLowerCase();
      if (!seen.add(key)) {
        ScaffoldMessenger.of(context).showSnackBar(errorSnack(
          'Duplicate column name: "${c.name.trim()}"',
        ));
        return;
      }
    }
    try {
      final fileName = _fileNameCtrl.text.trim().isEmpty ? 'Untitled' : _fileNameCtrl.text.trim();
      if (_projectId == null) {
        _projectId = await databaseService.createProject(fileName, _columns);
        if (_importedRecords.isNotEmpty) {
          await databaseService.importRecords(_projectId!, _importedRecords);
        }
      } else {
        await databaseService.updateSchema(_projectId!, _columns, fileName: fileName);
      }
      if (mounted) {
        Navigator.pushNamed(
          context,
          SchemaRoute.addRows,
          arguments: {
            'projectId': _projectId,
            'fileName': fileName,
            'columns': _columns,
            if (_importedRecords.isNotEmpty) 'records': _importedRecords,
          },
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(errorSnack('Failed to save: $e'));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final isWide = isDesktopWidth(screenWidth);
    final editorWidth = isDesktopWidth(screenWidth)
        ? 460.0
        : (screenWidth * 0.48).clamp(330.0, 420.0).toDouble();

    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFFF0F2FF), Color(0xFFFFFFFF)],
          begin: Alignment.topCenter, end: Alignment.bottomCenter,
        ),
      ),
      child: Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(
        child: GestureDetector(
          onTap: () => FocusScope.of(context).unfocus(),
          child: Column(
          children: [
            _TopBar(
              breadcrumb: widget.importedFileName != null
                  ? 'Import CSV → Define structure'
                  : 'New file → Define structure',
              onBack: () => Navigator.pop(context),
              onPreview: isWide ? null : () => setState(() => _previewOpen = !_previewOpen),
              onSave: _saveAndEnter,
            ),
            Expanded(
              child: isWide
                  ? Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(
                          width: editorWidth,
                          child: _EditorPanel(
                            fileNameCtrl: _fileNameCtrl,
                            columns: _columns,
                            onAdd: _addColumn,
                            onRemove: _removeColumn,
                            onUpdate: _updateColumn,
                            onReorder: _reorder,
                          ),
                        ),
                        const VerticalDivider(width: 1, color: AppColors.border),
                        Expanded(
                          child: _FormPreviewPanel(columns: _columns),
                        ),
                      ],
                    )
                  : _previewOpen
                      ? _FormPreviewPanel(columns: _columns)
                      : _EditorPanel(
                          fileNameCtrl: _fileNameCtrl,
                          columns: _columns,
                          onAdd: _addColumn,
                          onRemove: _removeColumn,
                          onUpdate: _updateColumn,
                          onReorder: _reorder,
                        ),
            ),
          ],
        ),
        ),
      ),
      ),
    );
  }
}

// ── Top bar ───────────────────────────────────────────────────────────────────

class _TopBar extends StatelessWidget {
  final String breadcrumb;
  final VoidCallback onBack;
  final VoidCallback? onPreview;
  final Future<void> Function() onSave;

  const _TopBar({
    required this.breadcrumb,
    required this.onBack,
    this.onPreview,
    required this.onSave,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isPhone = constraints.maxWidth < 900;
        final horizontalPadding = isPhone ? 8.0 : 16.0;
        final saveButton = ScaleButton(
          onTap: () => onSave(),
          child: AbsorbPointer(
            child: ElevatedButton(
              onPressed: () {},
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: AppColors.textInverse,
                elevation: 0,
                padding: EdgeInsets.symmetric(
                  horizontal: isPhone ? 14 : 18,
                  vertical: 10,
                ),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                textStyle: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w600),
              ),
              child: Text(isPhone ? 'Save' : 'Save & start entering'),
            ),
          ),
        );
        final previewButton = onPreview == null
            ? null
            : OutlinedButton.icon(
                onPressed: onPreview,
                icon: const Icon(Icons.remove_red_eye_outlined, size: 16),
                label: Text('Preview', style: GoogleFonts.inter(fontSize: 13)),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.textPrimary,
                  side: const BorderSide(color: AppColors.border),
                  padding: EdgeInsets.symmetric(
                    horizontal: isPhone ? 10 : 12,
                    vertical: 8,
                  ),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
              );

        return Container(
          constraints: const BoxConstraints(minHeight: 56),
          padding: EdgeInsets.symmetric(
            horizontal: horizontalPadding,
            vertical: isPhone ? 8 : 0,
          ),
          decoration: const BoxDecoration(
            color: AppColors.surface,
            border: Border(bottom: BorderSide(color: AppColors.border)),
          ),
          child: isPhone
              ? Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        IconButton(
                          icon: const Icon(Icons.arrow_back, size: 20),
                          color: AppColors.textPrimary,
                          onPressed: onBack,
                          splashRadius: 20,
                        ),
                        Expanded(
                          child: Text(
                            breadcrumb,
                            style: GoogleFonts.inter(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: AppColors.textPrimary,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                    Row(
                      children: [
                        if (previewButton != null) ...[
                          Expanded(child: previewButton),
                          const SizedBox(width: 8),
                        ],
                        Expanded(child: saveButton),
                      ],
                    ),
                  ],
                )
              : Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.arrow_back, size: 20),
                      color: AppColors.textPrimary,
                      onPressed: onBack,
                      splashRadius: 20,
                    ),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        breadcrumb,
                        style: GoogleFonts.inter(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textPrimary,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (previewButton != null) ...[
                      previewButton,
                      const SizedBox(width: 8),
                    ],
                    saveButton,
                  ],
                ),
        );
      },
    );
  }
}

// ── Left editor panel ─────────────────────────────────────────────────────────

class _EditorPanel extends StatelessWidget {
  final TextEditingController fileNameCtrl;
  final List<SchemaColumn>    columns;
  final VoidCallback          onAdd;
  final void Function(int)    onRemove;
  final void Function(int, SchemaColumn) onUpdate;
  final void Function(int, int)          onReorder;

  const _EditorPanel({
    required this.fileNameCtrl,
    required this.columns,
    required this.onAdd,
    required this.onRemove,
    required this.onUpdate,
    required this.onReorder,
  });

  @override
  Widget build(BuildContext context) {
    final padding = pagePadding(MediaQuery.of(context).size.width);

    return SingleChildScrollView(
      padding: EdgeInsets.symmetric(horizontal: padding, vertical: padding),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SectionLabel('FILE NAME'),
          const SizedBox(height: 8),
          TextField(
            controller: fileNameCtrl,
            style: GoogleFonts.inter(
              fontSize: 15,
              fontWeight: FontWeight.w500,
              color: AppColors.textPrimary,
            ),
            decoration: InputDecoration(
              hintText: 'e.g. Car Sales June 2024',
              hintStyle: GoogleFonts.inter(color: AppColors.textMuted, fontSize: 15),
              filled: true,
              fillColor: AppColors.surface,
              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(color: AppColors.border),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(color: AppColors.border),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
              ),
            ),
          ),
          const SizedBox(height: 28),
          Row(
            children: [
              _SectionLabel('COLUMNS'),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: AppColors.primary,
                  borderRadius: BorderRadius.circular(99),
                ),
                child: Text(
                  '${columns.length}',
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ReorderableListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            onReorder: onReorder,
            itemCount: columns.length,
            buildDefaultDragHandles: false,
            itemBuilder: (_, i) => _ColumnRow(
              key: ValueKey('col_$i'),
              index: i,
              column: columns[i],
              canDelete: columns.length > 1,
              onDelete: () => onRemove(i),
              onChanged: (updated) => onUpdate(i, updated),
            ),
          ),
          const SizedBox(height: 8),
          ScaleButton(
            onTap: onAdd,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 12),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: AppColors.border,
                  style: BorderStyle.solid,
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.add, size: 16, color: AppColors.textSecondary),
                  const SizedBox(width: 6),
                  Text(
                    'Add column',
                    style: GoogleFonts.inter(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Single column row ─────────────────────────────────────────────────────────

class _ColumnRow extends StatefulWidget {
  final int          index;
  final SchemaColumn column;
  final bool         canDelete;
  final VoidCallback onDelete;
  final void Function(SchemaColumn) onChanged;

  const _ColumnRow({
    super.key,
    required this.index,
    required this.column,
    required this.canDelete,
    required this.onDelete,
    required this.onChanged,
  });

  @override
  State<_ColumnRow> createState() => _ColumnRowState();
}

class _ColumnRowState extends State<_ColumnRow> {
  late TextEditingController _nameCtrl;
  bool _showDropdownEditor = false;

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController(text: widget.column.name);
    _showDropdownEditor = widget.column.type == ColumnType.dropdown;
  }

  @override
  void didUpdateWidget(_ColumnRow old) {
    super.didUpdateWidget(old);
    if (old.column.name != widget.column.name) {
      _nameCtrl.text = widget.column.name;
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  void _setType(ColumnType t) {
    setState(() {
      _showDropdownEditor = t == ColumnType.dropdown;
    });
    widget.onChanged(widget.column.copyWith(type: t));
  }

  void _toggleRequired() {
    widget.onChanged(widget.column.copyWith(required: !widget.column.required));
  }

  @override
  Widget build(BuildContext context) {
    Widget requiredChip() => GestureDetector(
          onTap: _toggleRequired,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: widget.column.required
                  ? const Color(0xFFFFF1F2)
                  : AppColors.background,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(
                color: widget.column.required
                    ? AppColors.error.withValues(alpha: 0.3)
                    : AppColors.border,
              ),
            ),
            child: Text(
              widget.column.required ? 'req' : 'opt',
              style: GoogleFonts.inter(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: widget.column.required
                    ? AppColors.error
                    : AppColors.textMuted,
              ),
            ),
          ),
        );

    Widget deleteButton() => widget.canDelete
        ? IconButton(
            icon: const Icon(Icons.close_rounded, size: 16),
            color: AppColors.textMuted,
            onPressed: widget.onDelete,
            splashRadius: 16,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
          )
        : const SizedBox(width: 28);

    return Column(
      children: [
        Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: AppColors.border),
          ),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final isCompact = constraints.maxWidth < 390;
              final nameField = Expanded(
                child: TextField(
                  controller: _nameCtrl,
                  onChanged: (v) =>
                      widget.onChanged(widget.column.copyWith(name: v)),
                  style: GoogleFonts.inter(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: AppColors.textPrimary,
                  ),
                  decoration: const InputDecoration(
                    border: InputBorder.none,
                    isDense: true,
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
              );
              final dragHandle = ReorderableDragStartListener(
                index: widget.index,
                child: const Padding(
                  padding: EdgeInsets.only(right: 8),
                  child: Icon(Icons.drag_indicator_rounded,
                      size: 18, color: AppColors.textMuted),
                ),
              );

              if (isCompact) {
                return Column(
                  children: [
                    Row(
                      children: [
                        dragHandle,
                        nameField,
                        deleteButton(),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: _TypeDropdownButton(
                            selected: widget.column.type,
                            onSelect: _setType,
                          ),
                        ),
                        const SizedBox(width: 8),
                        requiredChip(),
                      ],
                    ),
                  ],
                );
              }

              return Row(
                children: [
                  dragHandle,
                  nameField,
                  _TypeDropdownButton(
                    selected: widget.column.type,
                    onSelect: _setType,
                    compact: constraints.maxWidth < 470,
                  ),
                  const SizedBox(width: 6),
                  requiredChip(),
                  const SizedBox(width: 4),
                  deleteButton(),
                ],
              );
            },
          ),
        ),
        if (_showDropdownEditor)
          _DropdownOptionsEditor(
            options: widget.column.dropdownOptions,
            onChanged: (opts) =>
                widget.onChanged(widget.column.copyWith(dropdownOptions: opts)),
          ),
      ],
    );
  }
}

// ── Type selector dropdown ────────────────────────────────────────────────────

class _TypeDropdownButton extends StatelessWidget {
  final ColumnType selected;
  final void Function(ColumnType) onSelect;
  final bool compact;

  const _TypeDropdownButton({
    required this.selected,
    required this.onSelect,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<ColumnType>(
      initialValue: selected,
      onSelected: onSelect,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      elevation: 4,
      color: AppColors.surface,
      itemBuilder: (_) => ColumnType.values.map((t) {
        final isSelected = t == selected;
        return PopupMenuItem<ColumnType>(
          value: t,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: isSelected ? AppColors.primaryLight : Colors.transparent,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Row(
              children: [
                Icon(t.icon,
                    size: 15,
                    color: isSelected ? AppColors.primary : AppColors.textSecondary),
                const SizedBox(width: 8),
                Text(
                  t.label,
                  style: GoogleFonts.inter(
                    fontSize: 13,
                    fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                    color: isSelected ? AppColors.primary : AppColors.textPrimary,
                  ),
                ),
              ],
            ),
          ),
        );
      }).toList(),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: AppColors.background,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(selected.icon, size: 13, color: AppColors.textSecondary),
            if (!compact) ...[
              const SizedBox(width: 5),
              Text(
                selected.label,
                style: GoogleFonts.inter(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: AppColors.textPrimary,
                ),
              ),
            ],
            const SizedBox(width: 4),
            const Icon(Icons.keyboard_arrow_down_rounded,
                size: 14, color: AppColors.textMuted),
          ],
        ),
      ),
    );
  }
}

// ── Dropdown options inline editor ────────────────────────────────────────────

class _DropdownOptionsEditor extends StatefulWidget {
  final List<String>           options;
  final void Function(List<String>) onChanged;

  const _DropdownOptionsEditor({
    required this.options,
    required this.onChanged,
  });

  @override
  State<_DropdownOptionsEditor> createState() =>
      _DropdownOptionsEditorState();
}

class _DropdownOptionsEditorState extends State<_DropdownOptionsEditor> {
  late List<TextEditingController> _ctrls;

  @override
  void initState() {
    super.initState();
    _ctrls = widget.options.isEmpty
        ? [TextEditingController()]
        : widget.options.map((o) => TextEditingController(text: o)).toList();
  }

  @override
  void dispose() {
    for (final c in _ctrls) { c.dispose(); }
    super.dispose();
  }

  void _notify() {
    widget.onChanged(_ctrls.map((c) => c.text.trim()).toList());
  }

  void _addOption() {
    setState(() => _ctrls.add(TextEditingController()));
    _notify();
  }

  void _removeOption(int i) {
    if (_ctrls.length == 1) return;
    setState(() {
      _ctrls[i].dispose();
      _ctrls.removeAt(i);
    });
    _notify();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(left: 26, bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.primaryLight,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Dropdown options',
            style: GoogleFonts.inter(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: AppColors.primary,
            ),
          ),
          const SizedBox(height: 8),
          ...List.generate(_ctrls.length, (i) => Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _ctrls[i],
                    onChanged: (_) => _notify(),
                    style: GoogleFonts.inter(fontSize: 13, color: AppColors.textPrimary),
                    decoration: InputDecoration(
                      hintText: 'Option ${i + 1}',
                      hintStyle: GoogleFonts.inter(color: AppColors.textMuted, fontSize: 13),
                      filled: true,
                      fillColor: AppColors.surface,
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 8),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(6),
                        borderSide: BorderSide(color: AppColors.border),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(6),
                        borderSide: BorderSide(color: AppColors.border),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(6),
                        borderSide: const BorderSide(color: AppColors.primary),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                GestureDetector(
                  onTap: () => _removeOption(i),
                  child: const Icon(Icons.close_rounded,
                      size: 15, color: AppColors.textMuted),
                ),
              ],
            ),
          )),
          GestureDetector(
            onTap: _addOption,
            child: Row(
              children: [
                const Icon(Icons.add, size: 14, color: AppColors.primary),
                const SizedBox(width: 4),
                Text(
                  'Add option',
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: AppColors.primary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Right form-preview panel ──────────────────────────────────────────────────

class _FormPreviewPanel extends StatelessWidget {
  final List<SchemaColumn> columns;

  const _FormPreviewPanel({required this.columns});

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final padding = pagePadding(screenWidth);
    final cardPadding = isPhoneWidth(screenWidth) ? 16.0 : 24.0;

    return SingleChildScrollView(
      padding: EdgeInsets.all(padding),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Form preview',
            style: GoogleFonts.inter(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'How your entry form will look',
            style: GoogleFonts.inter(fontSize: 14, color: AppColors.textSecondary),
          ),
          const SizedBox(height: 28),
          Container(
            width: double.infinity,
            constraints: const BoxConstraints(maxWidth: 680),
            padding: EdgeInsets.all(cardPadding),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.border),
            ),
            child: columns.isEmpty
                ? Center(
                    child: Text(
                      'Add columns to see a preview',
                      style: GoogleFonts.inter(
                          fontSize: 14, color: AppColors.textMuted),
                    ),
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: columns.map((col) {
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 20),
                        child: _PreviewField(column: col),
                      );
                    }).toList(),
                  ),
          ),
        ],
      ),
    );
  }
}

class _PreviewField extends StatelessWidget {
  final SchemaColumn column;

  const _PreviewField({required this.column});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Flexible(
              child: Text(
                column.name.isEmpty ? 'Unnamed column' : column.name,
                style: GoogleFonts.inter(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: AppColors.textPrimary,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (column.required) ...[
              const SizedBox(width: 4),
              const Text('*',
                  style: TextStyle(
                      color: AppColors.error,
                      fontSize: 14,
                      fontWeight: FontWeight.w600)),
            ] else ...[
              const SizedBox(width: 6),
              Text(
                'optional',
                style: GoogleFonts.inter(
                    fontSize: 12, color: AppColors.textMuted),
              ),
            ],
          ],
        ),
        const SizedBox(height: 6),
        _previewWidget(column),
      ],
    );
  }

  Widget _previewWidget(SchemaColumn col) {
    final dummyDecoration = InputDecoration(
      hintText: _hint(col),
      hintStyle: GoogleFonts.inter(color: AppColors.textMuted, fontSize: 14),
      filled: true,
      fillColor: AppColors.background,
      enabled: false,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: AppColors.border),
      ),
      disabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: AppColors.border),
      ),
    );

    switch (col.type) {
      case ColumnType.boolean:
        return Row(
          children: ['Yes', 'No'].map((opt) {
            return Container(
              margin: const EdgeInsets.only(right: 8),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: AppColors.background,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppColors.border),
              ),
              child: Text(
                opt,
                style: GoogleFonts.inter(
                    fontSize: 14, color: AppColors.textSecondary),
              ),
            );
          }).toList(),
        );

      case ColumnType.dropdown:
        final opts = col.dropdownOptions.where((o) => o.isNotEmpty).toList();
        if (opts.isEmpty) {
          return TextFormField(enabled: false, decoration: dummyDecoration);
        }
        return Wrap(
          spacing: 8,
          runSpacing: 8,
          children: opts.map((opt) => Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: AppColors.background,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppColors.border),
            ),
            child: Text(
              opt,
              style: GoogleFonts.inter(
                  fontSize: 13, color: AppColors.textSecondary),
            ),
          )).toList(),
        );

      default:
        return TextFormField(enabled: false, decoration: dummyDecoration);
    }
  }

  String _hint(SchemaColumn col) {
    switch (col.type) {
      case ColumnType.number: return 'Enter number';
      case ColumnType.date:   return 'DD / MM / YYYY';
      case ColumnType.text:   return 'Enter text';
      default:                return '';
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  SCREEN 2 — DATA ENTRY FORM (kept for reference / alternate entry)
// ─────────────────────────────────────────────────────────────────────────────

class DataEntryScreen extends StatefulWidget {
  final String            fileName;
  final List<SchemaColumn> columns;

  const DataEntryScreen({
    super.key,
    required this.fileName,
    required this.columns,
  });

  @override
  State<DataEntryScreen> createState() => _DataEntryScreenState();
}

class _DataEntryScreenState extends State<DataEntryScreen> {
  final _formKey = GlobalKey<FormState>();
  late List<dynamic> _values;
  int _recordCount = 1;
  final List<Map<String, dynamic>> _saved = [];

  final List<List<dynamic>> _undoStack = [];
  final List<List<dynamic>> _redoStack = [];

  @override
  void initState() {
    super.initState();
    _values = _blankValues();
  }

  List<dynamic> _blankValues() =>
      List<dynamic>.filled(widget.columns.length, null);

  void _setValue(int i, dynamic v) {
    _undoStack.add(List.from(_values));
    _redoStack.clear();
    setState(() => _values[i] = v);
  }

  void _undo() {
    if (_undoStack.isEmpty) return;
    _redoStack.add(List.from(_values));
    setState(() => _values = _undoStack.removeLast());
  }

  void _redo() {
    if (_redoStack.isEmpty) return;
    _undoStack.add(List.from(_values));
    setState(() => _values = _redoStack.removeLast());
  }

  void _saveRecord() {
    for (int i = 0; i < widget.columns.length; i++) {
      final col = widget.columns[i];
      if (col.required) {
        final v = _values[i];
        if (v == null || (v is String && v.trim().isEmpty)) {
          ScaffoldMessenger.of(context).showSnackBar(
            errorSnack('Field "${col.name}" is required.'),
          );
          return;
        }
      }
    }
    final record = <String, dynamic>{};
    for (int i = 0; i < widget.columns.length; i++) {
      record[widget.columns[i].name] = _values[i];
    }
    setState(() {
      _saved.add(record);
      _recordCount++;
      _values = _blankValues();
      _undoStack.clear();
      _redoStack.clear();
    });
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text('Record ${_recordCount - 1} saved ✓'),
      backgroundColor: AppColors.success,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      duration: const Duration(seconds: 2),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final isPhone = screenWidth < 900;
    final padding = pagePadding(screenWidth);
    final recordPill = Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(99),
        border: Border.all(color: AppColors.border),
      ),
      child: Text(
        'Record $_recordCount',
        style: GoogleFonts.inter(
          fontSize: 12,
          color: AppColors.textSecondary,
        ),
      ),
    );
    final undoButton = IconButton(
      icon: const Icon(Icons.undo_rounded, size: 20),
      color: _undoStack.isEmpty ? AppColors.textMuted : AppColors.textPrimary,
      onPressed: _undoStack.isEmpty ? null : _undo,
      splashRadius: 18,
    );
    final redoButton = IconButton(
      icon: const Icon(Icons.redo_rounded, size: 20),
      color: _redoStack.isEmpty ? AppColors.textMuted : AppColors.textPrimary,
      onPressed: _redoStack.isEmpty ? null : _redo,
      splashRadius: 18,
    );
    final saveButton = ElevatedButton(
      onPressed: _saveRecord,
      style: ElevatedButton.styleFrom(
        backgroundColor: AppColors.primary,
        foregroundColor: AppColors.textInverse,
        elevation: 0,
        padding: EdgeInsets.symmetric(
          horizontal: isPhone ? 14 : 18,
          vertical: 10,
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        textStyle: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w600),
      ),
      child: const Text('Save record'),
    );

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: GestureDetector(
          onTap: () => FocusScope.of(context).unfocus(),
          child: Column(
          children: [
            Container(
              constraints: const BoxConstraints(minHeight: 56),
              padding: EdgeInsets.symmetric(
                horizontal: isPhone ? 12 : 16,
                vertical: isPhone ? 8 : 0,
              ),
              color: AppColors.surface,
              child: isPhone
                  ? Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                widget.fileName,
                                style: GoogleFonts.inter(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w600,
                                  color: AppColors.textPrimary,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const SizedBox(width: 10),
                            recordPill,
                          ],
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            undoButton,
                            redoButton,
                            const SizedBox(width: 8),
                            Expanded(child: saveButton),
                          ],
                        ),
                      ],
                    )
                  : Row(
                children: [
                  Expanded(
                    child: Row(
                      children: [
                        Flexible(
                          child: Text(
                            widget.fileName,
                            style: GoogleFonts.inter(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                              color: AppColors.textPrimary,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 3),
                          decoration: BoxDecoration(
                            color: AppColors.background,
                            borderRadius: BorderRadius.circular(99),
                            border: Border.all(color: AppColors.border),
                          ),
                          child: Text(
                            'Record $_recordCount of ∞',
                            style: GoogleFonts.inter(
                              fontSize: 12,
                              color: AppColors.textSecondary,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.undo_rounded, size: 20),
                    color: _undoStack.isEmpty
                        ? AppColors.textMuted
                        : AppColors.textPrimary,
                    onPressed: _undoStack.isEmpty ? null : _undo,
                    splashRadius: 18,
                  ),
                  IconButton(
                    icon: const Icon(Icons.redo_rounded, size: 20),
                    color: _redoStack.isEmpty
                        ? AppColors.textMuted
                        : AppColors.textPrimary,
                    onPressed: _redoStack.isEmpty ? null : _redo,
                    splashRadius: 18,
                  ),
                  const SizedBox(width: 4),
                  ElevatedButton(
                    onPressed: _saveRecord,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: AppColors.textInverse,
                      elevation: 0,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 18, vertical: 10),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8)),
                      textStyle: GoogleFonts.inter(
                          fontSize: 14, fontWeight: FontWeight.w600),
                    ),
                    child: const Text('Save record'),
                  ),
                ],
              ),
            ),
            const Divider(height: 1, color: AppColors.border),
            Expanded(
              child: Center(
                child: SingleChildScrollView(
                  padding: EdgeInsets.symmetric(
                    horizontal: padding,
                    vertical: padding,
                  ),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 680),
                    child: Form(
                      key: _formKey,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: List.generate(
                          widget.columns.length,
                          (i) => Padding(
                            padding: const EdgeInsets.only(bottom: 24),
                            child: _EntryField(
                              column: widget.columns[i],
                              value: _values[i],
                              onChanged: (v) => _setValue(i, v),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
        ),
      ),
    );
  }
}

// ── Individual entry field ────────────────────────────────────────────────────

class _EntryField extends StatefulWidget {
  final SchemaColumn column;
  final dynamic      value;
  final void Function(dynamic) onChanged;

  const _EntryField({
    required this.column,
    required this.value,
    required this.onChanged,
  });

  @override
  State<_EntryField> createState() => _EntryFieldState();
}

class _EntryFieldState extends State<_EntryField> {
  late TextEditingController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(
      text: widget.value != null ? widget.value.toString() : '',
    );
  }

  @override
  void didUpdateWidget(_EntryField old) {
    super.didUpdateWidget(old);
    if (widget.value == null && _ctrl.text.isNotEmpty) {
      _ctrl.clear();
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  InputDecoration _baseDecoration(String hint) => InputDecoration(
        hintText: hint,
        hintStyle: GoogleFonts.inter(color: AppColors.textMuted, fontSize: 15),
        filled: true,
        fillColor: AppColors.surface,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: AppColors.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: AppColors.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: AppColors.error),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final col = widget.column;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Flexible(
              child: Text(
                col.name,
                style: GoogleFonts.inter(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: AppColors.textPrimary,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (col.required)
              const Text(
                ' *',
                style: TextStyle(
                    color: AppColors.error,
                    fontSize: 14,
                    fontWeight: FontWeight.w600),
              )
            else
              Text(
                ' optional',
                style: GoogleFonts.inter(
                    fontSize: 12, color: AppColors.textMuted),
              ),
          ],
        ),
        const SizedBox(height: 6),
        _buildInput(col),
      ],
    );
  }

  Widget _buildInput(SchemaColumn col) {
    switch (col.type) {
      case ColumnType.text:
      case ColumnType.number:
        return TextFormField(
          controller: _ctrl,
          keyboardType: col.type == ColumnType.number
              ? const TextInputType.numberWithOptions(decimal: true)
              : TextInputType.text,
          maxLines: col.type == ColumnType.text ? null : 1,
          inputFormatters: col.type == ColumnType.number
              ? [FilteringTextInputFormatter.allow(RegExp(r'[\d.]'))]
              : null,
          onChanged: widget.onChanged,
          style: GoogleFonts.inter(fontSize: 15, color: AppColors.textPrimary),
          decoration: _baseDecoration(
            col.type == ColumnType.number ? 'Enter number' : 'Enter text',
          ),
        );

      case ColumnType.date:
        return GestureDetector(
          onTap: () async {
            final picked = await showDatePicker(
              context: context,
              initialDate: DateTime.now(),
              firstDate: DateTime(1900),
              lastDate: DateTime(2100),
              builder: (ctx, child) => Theme(
                data: Theme.of(ctx).copyWith(
                  colorScheme: const ColorScheme.light(
                    primary: AppColors.primary,
                  ),
                ),
                child: child!,
              ),
            );
            if (picked != null) {
              final formatted =
                  '${picked.day.toString().padLeft(2, '0')} / '
                  '${picked.month.toString().padLeft(2, '0')} / '
                  '${picked.year}';
              _ctrl.text = formatted;
              widget.onChanged(formatted);
            }
          },
          child: AbsorbPointer(
            child: TextFormField(
              controller: _ctrl,
              style: GoogleFonts.inter(fontSize: 15, color: AppColors.textPrimary),
              decoration: _baseDecoration('DD / MM / YYYY').copyWith(
                suffixIcon: const Icon(Icons.calendar_today_outlined,
                    size: 18, color: AppColors.textMuted),
              ),
            ),
          ),
        );

      case ColumnType.boolean:
        final current = widget.value as String?;
        return Row(
          children: ['Yes', 'No'].map((opt) {
            final selected = current == opt;
            return Expanded(
              child: GestureDetector(
                onTap: () => widget.onChanged(opt),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  margin: EdgeInsets.only(
                      right: opt == 'Yes' ? 8 : 0),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  decoration: BoxDecoration(
                    color: selected ? AppColors.primary : AppColors.surface,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: selected ? AppColors.primary : AppColors.border,
                    ),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    opt,
                    style: GoogleFonts.inter(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: selected
                          ? AppColors.textInverse
                          : AppColors.textPrimary,
                    ),
                  ),
                ),
              ),
            );
          }).toList(),
        );

      case ColumnType.dropdown:
        final opts = col.dropdownOptions.where((o) => o.isNotEmpty).toList();
        if (opts.isEmpty) {
          return TextFormField(
            enabled: false,
            decoration: _baseDecoration('No options defined yet'),
          );
        }
        final current = widget.value as String?;
        return Wrap(
          spacing: 8,
          runSpacing: 8,
          children: opts.map((opt) {
            final selected = current == opt;
            return GestureDetector(
              onTap: () => widget.onChanged(opt),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                padding: const EdgeInsets.symmetric(
                    horizontal: 16, vertical: 10),
                decoration: BoxDecoration(
                  color: selected ? AppColors.primary : AppColors.surface,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: selected ? AppColors.primary : AppColors.border,
                  ),
                ),
                child: Text(
                  opt,
                  style: GoogleFonts.inter(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: selected
                        ? AppColors.textInverse
                        : AppColors.textPrimary,
                  ),
                ),
              ),
            );
          }).toList(),
        );
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  HELPERS
// ─────────────────────────────────────────────────────────────────────────────

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);

  @override
  Widget build(BuildContext context) => Text(
        text,
        style: GoogleFonts.inter(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: AppColors.textMuted,
          letterSpacing: 0.8,
        ),
      );
}
