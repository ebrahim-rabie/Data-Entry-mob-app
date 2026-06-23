import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';
import 'package:excel/excel.dart' hide Border;
import 'package:flutter_application_1/shared.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_application_1/database.dart';

class FinalScreen extends StatefulWidget {
  final String projectId;
  final String fileName;
  final List<SchemaColumn> columns;

  const FinalScreen({
    super.key,
    required this.projectId,
    required this.fileName,
    required this.columns,
  });

  @override
  State<FinalScreen> createState() => _FinalScreenState();
}

class _FinalScreenState extends State<FinalScreen> {
  final TextEditingController _searchCtrl = TextEditingController();
  final FocusNode _searchFocus = FocusNode();
  String _searchQuery = '';
  final Map<String, String?> _filters = {};
  final Set<String> _selectedIds = {};
  List<RecordData> _allRecords = [];
  int _currentPage = 1;
  static const int _pageSize = 25;

  final Set<String> _hiddenColumns = {};
  String? _sortColumn;
  bool _sortAscending = true;
  bool _schemaUpdating = false;

  late Stream<DocumentSnapshot<Map<String, dynamic>>> _projectStream;
  late Stream<QuerySnapshot<Map<String, dynamic>>> _recordsStream;

  @override
  void initState() {
    super.initState();
    _projectStream = databaseService.watchProject(widget.projectId);
    _recordsStream = databaseService.watchRecords(widget.projectId);
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  List<String> _filterableKeys(List<SchemaColumn> cols) => cols
      .where((c) => c.type == ColumnType.text || c.type == ColumnType.dropdown)
      .map((c) => c.name)
      .toList();

  List<RecordData> _allFiltered(List<SchemaColumn> cols) {
    final q = _searchQuery.toLowerCase();
    final list = _allRecords.where((r) {
      final matchSearch =
          q.isEmpty ||
          r.data.values.any((v) => v?.toString().toLowerCase().contains(q) ?? false);
      final matchFilters = _filterableKeys(cols).every((k) {
        final filterVal = _filters[k];
        return filterVal == null || r.data[k]?.toString() == filterVal;
      });
      return matchSearch && matchFilters;
    }).toList();

    if (_sortColumn != null) {
      list.sort((a, b) {
        final valA = a.data[_sortColumn];
        final valB = b.data[_sortColumn];
        if (valA == null && valB == null) return 0;
        if (valA == null) return _sortAscending ? 1 : -1;
        if (valB == null) return _sortAscending ? -1 : 1;

        final numA = num.tryParse(valA.toString());
        final numB = num.tryParse(valB.toString());
        if (numA != null && numB != null) {
          return _sortAscending ? numA.compareTo(numB) : numB.compareTo(numA);
        }

        return _sortAscending
            ? valA.toString().toLowerCase().compareTo(valB.toString().toLowerCase())
            : valB.toString().toLowerCase().compareTo(valA.toString().toLowerCase());
      });
    }
    return list;
  }

  List<RecordData> _filtered(List<SchemaColumn> cols) {
    final list = _allFiltered(cols);
    final startIndex = (_currentPage - 1) * _pageSize;
    if (startIndex >= list.length) return [];
    final endIndex = startIndex + _pageSize;
    return list.sublist(startIndex, endIndex > list.length ? list.length : endIndex);
  }

  List<String> filterOptions(String key) =>
      _allRecords.map((r) => r.data[key]?.toString() ?? '').toSet().toList()..sort();

  String? filterValue(String key) => _filters[key];

  void setSearch(String q) {
    setState(() {
      _searchQuery = q;
      _currentPage = 1;
    });
  }

  void setFilter(String key, String? value) {
    setState(() {
      _filters[key] = value;
      _currentPage = 1;
    });
  }

  bool _allFilteredSelected(List<SchemaColumn> cols) {
    final list = _filtered(cols);
    return list.isNotEmpty && list.every((r) => _selectedIds.contains(r.id));
  }

  int get _selectedCount => _selectedIds.length;

  void _toggleSelect(String id) {
    setState(() {
      if (_selectedIds.contains(id)) {
        _selectedIds.remove(id);
      } else {
        _selectedIds.add(id);
      }
    });
  }

  void _toggleSelectAll(bool? value, List<SchemaColumn> cols) {
    setState(() {
      final list = _filtered(cols);
      if (value == true) {
        for (final r in list) {
          _selectedIds.add(r.id);
        }
      } else {
        for (final r in list) {
          _selectedIds.remove(r.id);
        }
      }
    });
  }

  void _cancelSelection() {
    setState(() => _selectedIds.clear());
  }

  void _showSnackBar(String msg, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(
              isError ? Icons.error_outline : Icons.check_circle_outline,
              color: Colors.white,
              size: 16,
            ),
            const SizedBox(width: 8),
            Expanded(child: Text(msg, style: GoogleFonts.inter(fontSize: 13))),
          ],
        ),
        backgroundColor: isError ? AppColors.error : AppColors.success,
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.all(16),
        duration: Duration(seconds: isError ? 5 : 3),
      ),
    );
  }

  Future<void> _onAddRecord(List<SchemaColumn> cols) async {
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => _RecordDialog(columns: cols),
    );
    if (result != null) {
      try {
        await databaseService.addRecord(widget.projectId, result);
        _showSnackBar('Record added');
      } catch (e) {
        _showSnackBar('Failed to add record: $e', isError: true);
      }
    }
  }

  Future<void> _onEditRecord(RecordData record, List<SchemaColumn> cols) async {
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) =>
          _RecordDialog(columns: cols, existing: record.data),
    );
    if (result != null) {
      try {
        await databaseService.updateRecord(widget.projectId, record.id, result);
        _showSnackBar('Record updated');
      } catch (e) {
        _showSnackBar('Failed to update record: $e', isError: true);
      }
    }
  }

  Future<void> _onDeleteRecord(String id) async {
    final confirmed = await _confirmDelete(1);
    if (!confirmed) return;
    try {
      await databaseService.deleteRecord(widget.projectId, id);
      _showSnackBar('Record deleted');
    } catch (e) {
      _showSnackBar('Failed to delete record: $e', isError: true);
    }
  }

  Future<void> _onDeleteSelected() async {
    final count = _selectedCount;
    final confirmed = await _confirmDelete(count);
    if (!confirmed) return;
    try {
      await databaseService.deleteRecords(widget.projectId, _selectedIds.toList());
      _selectedIds.clear();
      _showSnackBar('$count record${count == 1 ? '' : 's'} deleted');
    } catch (e) {
      _showSnackBar('Failed to delete records: $e', isError: true);
    }
  }

  Future<bool> _confirmDelete(int count) async {
    return await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            title: Text(
              'Delete $count record${count > 1 ? 's' : ''}?',
              style: GoogleFonts.inter(
                color: AppColors.textPrimary,
                fontWeight: FontWeight.w600,
              ),
            ),
            content: Text(
              'This action cannot be undone.',
              style: GoogleFonts.inter(color: AppColors.textSecondary),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: Text(
                  'Cancel',
                  style: GoogleFonts.inter(color: AppColors.textSecondary),
                ),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.error,
                  foregroundColor: AppColors.textInverse,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                onPressed: () => Navigator.pop(ctx, true),
                child: Text(
                  'Delete',
                  style: GoogleFonts.inter(fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
        ) ??
        false;
  }

  Future<void> _onExport(List<SchemaColumn> cols) async {
    final format = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: Text('Export as…', style: GoogleFonts.inter(color: AppColors.textPrimary, fontWeight: FontWeight.w600)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: double.infinity,
              child: TextButton.icon(
                onPressed: () => Navigator.pop(ctx, 'csv'),
                icon: const Icon(Icons.description_outlined),
                label: Text('CSV', style: GoogleFonts.inter(fontSize: 15)),
                style: TextButton.styleFrom(
                  foregroundColor: AppColors.textPrimary,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
              ),
            ),
            const SizedBox(height: 4),
            SizedBox(
              width: double.infinity,
              child: TextButton.icon(
                onPressed: () => Navigator.pop(ctx, 'xlsx'),
                icon: const Icon(Icons.table_chart_outlined),
                label: Text('Excel (.xlsx)', style: GoogleFonts.inter(fontSize: 15)),
                style: TextButton.styleFrom(
                  foregroundColor: AppColors.textPrimary,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Cancel', style: GoogleFonts.inter(color: AppColors.textSecondary)),
          ),
        ],
      ),
    );
    if (format == null || !mounted) return;

    final flds = cols;
    try {
      if (format == 'csv') {
        final buf = StringBuffer(flds.map((f) => '"${f.name}"').join(','));
        buf.writeln();
        for (final r in _allFiltered(cols)) {
          buf.writeln(
            flds.map((f) {
              final v = r.data[f.name];
              final s = v?.toString() ?? '';
              return '"${s.replaceAll('"', '""')}"';
            }).join(','),
          );
        }
        final path = await FilePicker.platform.saveFile(
          dialogTitle: 'Export CSV',
          fileName: '${widget.fileName}_export.csv',
          type: FileType.custom,
          allowedExtensions: ['csv'],
          bytes: Uint8List.fromList(utf8.encode(buf.toString())),
        );
        if (path != null && mounted) _showSnackBar('Exported successfully');
      } else {
        final excel = Excel.createExcel();
        final sheet = excel['Sheet1'];
        for (var c = 0; c < flds.length; c++) {
          sheet.cell(CellIndex.indexByColumnRow(columnIndex: c, rowIndex: 0)).value = TextCellValue(flds[c].name);
        }
        final filteredRecords = _allFiltered(cols);
        for (var r = 0; r < filteredRecords.length; r++) {
          for (var c = 0; c < flds.length; c++) {
            final v = filteredRecords[r].data[flds[c].name];
            final s = v?.toString() ?? '';
            sheet.cell(CellIndex.indexByColumnRow(columnIndex: c, rowIndex: r + 1)).value = TextCellValue(s);
          }
        }
        final data = excel.encode();
        if (data == null) throw Exception('Failed to encode Excel file');
        final path = await FilePicker.platform.saveFile(
          dialogTitle: 'Export Excel',
          fileName: '${widget.fileName}_export.xlsx',
          type: FileType.custom,
          allowedExtensions: ['xlsx'],
          bytes: Uint8List.fromList(data),
        );
        if (path != null && mounted) _showSnackBar('Exported successfully');
      }
    } catch (e) {
      if (mounted) _showSnackBar('Export failed: $e', isError: true);
    }
  }

  Future<void> _onAddColumn(List<SchemaColumn> activeColumns) async {
    final result = await showDialog<SchemaColumn>(
      context: context,
      builder: (_) => _ColumnDialog(existingColumns: activeColumns),
    );
    if (result != null) {
      setState(() => _schemaUpdating = true);
      try {
        final newCols = [...activeColumns, result];
        await databaseService.updateSchema(widget.projectId, newCols);
        _showSnackBar('Column "${result.name}" added');
      } catch (e) {
        _showSnackBar('Failed to add column: $e', isError: true);
      } finally {
        setState(() => _schemaUpdating = false);
      }
    }
  }

  Future<void> _onEditColumn(SchemaColumn column, List<SchemaColumn> activeColumns) async {
    final result = await showDialog<SchemaColumn>(
      context: context,
      builder: (_) => _ColumnDialog(existingColumns: activeColumns, editingColumn: column),
    );
    if (result != null) {
      setState(() => _schemaUpdating = true);
      try {
        final oldName = column.name;
        final newName = result.name;

        final newCols = activeColumns.map((c) => c.name == oldName ? result : c).toList();
        await databaseService.updateSchema(widget.projectId, newCols);

        if (oldName != newName) {
          await databaseService.renameColumnKey(widget.projectId, oldName, newName);
          if (_filters.containsKey(oldName)) {
            final filterVal = _filters.remove(oldName);
            if (filterVal != null) {
              _filters[newName] = filterVal;
            }
          }
          if (_hiddenColumns.contains(oldName)) {
            _hiddenColumns.remove(oldName);
            _hiddenColumns.add(newName);
          }
          if (_sortColumn == oldName) {
            _sortColumn = newName;
          }
        }
        _showSnackBar('Column "${result.name}" updated');
      } catch (e) {
        _showSnackBar('Failed to update column: $e', isError: true);
      } finally {
        setState(() => _schemaUpdating = false);
      }
    }
  }

  Future<void> _onDeleteColumn(SchemaColumn column, List<SchemaColumn> activeColumns) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: Text('Delete column "${column.name}"?', style: GoogleFonts.inter(color: AppColors.textPrimary, fontWeight: FontWeight.w600)),
        content: Text('This will permanently delete this column and all its values from existing records.', style: GoogleFonts.inter(color: AppColors.textSecondary)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text('Cancel', style: GoogleFonts.inter(color: AppColors.textSecondary))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.error, foregroundColor: AppColors.textInverse, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('Delete', style: GoogleFonts.inter(fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      setState(() => _schemaUpdating = true);
      try {
        final newCols = activeColumns.where((c) => c.name != column.name).toList();
        await databaseService.updateSchema(widget.projectId, newCols);
        await databaseService.deleteColumnKey(widget.projectId, column.name);

        _filters.remove(column.name);
        _hiddenColumns.remove(column.name);
        if (_sortColumn == column.name) {
          _sortColumn = null;
        }

        _showSnackBar('Column "${column.name}" deleted');
      } catch (e) {
        _showSnackBar('Failed to delete column: $e', isError: true);
      } finally {
        setState(() => _schemaUpdating = false);
      }
    }
  }

  void _handleKey(KeyEvent e) {
    if (e is KeyDownEvent) {
      final isCtrlF =
          e.logicalKey == LogicalKeyboardKey.keyF &&
          (HardwareKeyboard.instance.isControlPressed ||
              HardwareKeyboard.instance.isMetaPressed);
      if (isCtrlF || e.logicalKey == LogicalKeyboardKey.slash) {
        _searchFocus.requestFocus();
      }
    }
  }

  Widget _buildLoadingSkeleton() {
    final mediaQuery = MediaQuery.of(context);
    final compact = mediaQuery.size.width < 600;
    final isShort = mediaQuery.size.height < 500;

    if (isShort) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            color: AppColors.surface,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 36,
                      height: 36,
                      decoration: const BoxDecoration(
                        color: AppColors.primaryLight,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.arrow_back_rounded, color: AppColors.primary, size: 20),
                    ),
                    const SizedBox(width: 12),
                    const ShimmerLoading(width: 100, height: 20),
                    const SizedBox(width: 8),
                    const ShimmerLoading(width: 40, height: 16, borderRadius: 10),
                    const Spacer(),
                    const ShimmerLoading(width: 120, height: 28, borderRadius: 8),
                    const SizedBox(width: 6),
                    const ShimmerLoading(width: 32, height: 32, borderRadius: 6),
                  ],
                ),
                const SizedBox(height: 6),
                const SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      ShimmerLoading(width: 90, height: 28, borderRadius: 8),
                      SizedBox(width: 6),
                      ShimmerLoading(width: 90, height: 28, borderRadius: 8),
                      SizedBox(width: 6),
                      ShimmerLoading(width: 70, height: 28, borderRadius: 8),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: SizedBox(
                width: (widget.columns.length * 130.0 + 100).clamp(600, 1400),
                child: Container(
                  margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        child: Row(
                          children: [
                            const SizedBox(width: 40, child: Icon(Icons.check_box_outline_blank, color: AppColors.border, size: 20)),
                            ...widget.columns.map((c) => Expanded(
                              flex: c.type == ColumnType.number ? 1 : 2,
                              child: Text(
                                c.name.toUpperCase(),
                                style: GoogleFonts.inter(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.textMuted,
                                  letterSpacing: 0.6,
                                ),
                              ),
                            )),
                            const SizedBox(width: 60),
                          ],
                        ),
                      ),
                      const Divider(height: 1, color: AppColors.border),
                      Expanded(
                        child: ListView.separated(
                          itemCount: 8,
                          separatorBuilder: (_, _) => const Divider(height: 1, color: AppColors.border),
                          itemBuilder: (_, index) => Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                            child: Row(
                              children: [
                                const SizedBox(width: 40, child: Icon(Icons.check_box_outline_blank, color: AppColors.border, size: 20)),
                                ...widget.columns.map((c) => Expanded(
                                  flex: c.type == ColumnType.number ? 1 : 2,
                                  child: Align(
                                    alignment: Alignment.centerLeft,
                                    child: ShimmerLoading(
                                      width: c.type == ColumnType.number ? 60 : 100,
                                      height: 16,
                                    ),
                                  ),
                                )),
                                const SizedBox(width: 60, child: Row(
                                  children: [
                                    Icon(Icons.edit_outlined, size: 16, color: AppColors.border),
                                    SizedBox(width: 8),
                                    Icon(Icons.delete_outline, size: 16, color: AppColors.border),
                                  ],
                                )),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          Container(
            color: AppColors.surface,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            child: const Row(
              children: [
                ShimmerLoading(width: 150, height: 16),
                Spacer(),
                ShimmerLoading(width: 28, height: 28, borderRadius: 6),
                SizedBox(width: 6),
                ShimmerLoading(width: 28, height: 28, borderRadius: 6),
                SizedBox(width: 6),
                ShimmerLoading(width: 28, height: 28, borderRadius: 6),
              ],
            ),
          ),
        ],
      );
    }

    final List<Widget> headerChildren = [
      Container(
        width: 36,
        height: 36,
        decoration: const BoxDecoration(
          color: AppColors.primaryLight,
          shape: BoxShape.circle,
        ),
        child: const Icon(Icons.arrow_back_rounded, color: AppColors.primary, size: 20),
      ),
      const SizedBox(width: 12),
      const ShimmerLoading(width: 120, height: 24),
      const SizedBox(width: 8),
      const ShimmerLoading(width: 50, height: 20, borderRadius: 10),
    ];

    if (!compact) {
      headerChildren.addAll([
        const Spacer(),
        const ShimmerLoading(width: 120, height: 36, borderRadius: 8),
        const SizedBox(width: 10),
        const ShimmerLoading(width: 90, height: 36, borderRadius: 8),
      ]);
    } else {
      headerChildren.addAll([
        const Spacer(),
        const ShimmerLoading(width: 36, height: 36, borderRadius: 8),
      ]);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          color: AppColors.surface,
          padding: EdgeInsets.symmetric(
            horizontal: isShort ? 16 : 24,
            vertical: isShort ? 8 : 14,
          ),
          child: Row(children: headerChildren),
        ),
        Expanded(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: SizedBox(
              width: (widget.columns.length * 130.0 + 100).clamp(600, 1400),
              child: Container(
                margin: EdgeInsets.symmetric(
                  horizontal: isShort ? 16 : 20,
                  vertical: isShort ? 4 : 20,
                ),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.border),
                ),
                child: Column(
                  children: [
                    Padding(
                      padding: EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: isShort ? 8 : 12,
                      ),
                      child: Row(
                        children: [
                          const SizedBox(width: 40, child: Icon(Icons.check_box_outline_blank, color: AppColors.border, size: 20)),
                          ...widget.columns.map((c) => Expanded(
                            flex: c.type == ColumnType.number ? 1 : 2,
                            child: Text(
                              c.name.toUpperCase(),
                              style: GoogleFonts.inter(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: AppColors.textMuted,
                                letterSpacing: 0.6,
                              ),
                            ),
                          )),
                          const SizedBox(width: 60),
                        ],
                      ),
                    ),
                    const Divider(height: 1, color: AppColors.border),
                    Expanded(
                      child: ListView.separated(
                        itemCount: 8,
                        separatorBuilder: (_, _) => const Divider(height: 1, color: AppColors.border),
                        itemBuilder: (_, index) => Padding(
                          padding: EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: isShort ? 8 : 14,
                          ),
                          child: Row(
                            children: [
                              const SizedBox(width: 40, child: Icon(Icons.check_box_outline_blank, color: AppColors.border, size: 20)),
                              ...widget.columns.map((c) => Expanded(
                                flex: c.type == ColumnType.number ? 1 : 2,
                                child: Align(
                                  alignment: Alignment.centerLeft,
                                  child: ShimmerLoading(
                                    width: c.type == ColumnType.number ? 60 : 100,
                                    height: 16,
                                  ),
                                ),
                              )),
                              const SizedBox(width: 60, child: Row(
                                children: [
                                  Icon(Icons.edit_outlined, size: 16, color: AppColors.border),
                                  SizedBox(width: 8),
                                  Icon(Icons.delete_outline, size: 16, color: AppColors.border),
                                ],
                              )),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        Container(
          color: AppColors.surface,
          padding: EdgeInsets.symmetric(
            horizontal: isShort ? 16 : 24,
            vertical: isShort ? 6 : 12,
          ),
          child: Row(
            children: [
              const ShimmerLoading(width: 200, height: 16),
              const Spacer(),
              const ShimmerLoading(width: 32, height: 32, borderRadius: 6),
              const SizedBox(width: 6),
              const ShimmerLoading(width: 32, height: 32, borderRadius: 6),
              const SizedBox(width: 6),
              const ShimmerLoading(width: 32, height: 32, borderRadius: 6),
            ],
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return KeyboardListener(
      focusNode: FocusNode()..requestFocus(),
      onKeyEvent: _handleKey,
      child: Scaffold(
        backgroundColor: AppColors.background,
        body: SafeArea(
          child: Stack(
            children: [
              StreamBuilder(
                stream: _projectStream,
                builder: (context, projectSnapshot) {
                  if (projectSnapshot.connectionState == ConnectionState.waiting) {
                    return _buildLoadingSkeleton();
                  }
                  if (projectSnapshot.hasError) {
                    return Center(
                      child: Text('Error: ${projectSnapshot.error}',
                          style: GoogleFonts.inter(color: AppColors.error)),
                    );
                  }
                  final projectDoc = projectSnapshot.data;
                  if (projectDoc == null || !projectDoc.exists) {
                    return const Center(child: Text('Project not found.'));
                  }
                  final projectData = ProjectData.fromSnapshot(projectDoc);
                  final activeColumns = projectData.columns;

                  return StreamBuilder(
                    stream: _recordsStream,
                    builder: (context, snapshot) {
                      if (snapshot.connectionState == ConnectionState.waiting) {
                        return _buildLoadingSkeleton();
                      }
                      if (snapshot.hasError) {
                        return Center(
                          child: Text('Error: ${snapshot.error}',
                              style: GoogleFonts.inter(color: AppColors.error)),
                        );
                      }
                      _allRecords = snapshot.data?.docs
                          .map((d) => RecordData.fromSnapshot(d))
                          .toList() ?? [];

                      final totalFiltered = _allFiltered(activeColumns).length;
                      final maxPage = (totalFiltered / _pageSize).ceil();
                      if (_currentPage > maxPage && maxPage > 0) {
                        _currentPage = maxPage;
                      } else if (maxPage == 0) {
                        _currentPage = 1;
                      }

                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _buildTopBar(activeColumns),
                          if (_selectedIds.isNotEmpty) _buildSelectionBar(activeColumns),
                          Expanded(child: _buildTableArea(activeColumns)),
                          _buildFooter(activeColumns),
                        ],
                      );
                    },
                  );
                },
              ),
              if (_schemaUpdating)
                Container(
                  color: Colors.black.withValues(alpha: 0.35),
                  child: Center(
                    child: Card(
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const CircularProgressIndicator(strokeWidth: 3),
                            const SizedBox(width: 20),
                            Text(
                              'Syncing database schema...',
                              style: GoogleFonts.inter(
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                                color: AppColors.textPrimary,
                              ),
                            ),
                          ],
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

  Widget _buildTopBar(List<SchemaColumn> cols) {
    final mediaQuery = MediaQuery.of(context);
    final isShort = mediaQuery.size.height < 500;
    return Container(
      color: AppColors.surface,
      padding: EdgeInsets.symmetric(
        horizontal: isShort ? 16 : 24,
        vertical: isShort ? 6 : 14,
      ),
      child: LayoutBuilder(
        builder: (ctx, constraints) {
          final compact = constraints.maxWidth < 860;
          
          Widget buildVisibilityMenu() => PopupMenuButton<String>(
                icon: const Icon(Icons.view_column_rounded, color: AppColors.primary, size: 20),
                tooltip: 'Show/Hide Columns',
                offset: const Offset(0, 40),
                itemBuilder: (context) => cols.map((c) {
                  final isVisible = !_hiddenColumns.contains(c.name);
                  return CheckedPopupMenuItem(
                    value: c.name,
                    checked: isVisible,
                    child: Text(c.name, style: GoogleFonts.inter(fontSize: 13)),
                  );
                }).toList(),
                onSelected: (colName) {
                  setState(() {
                    if (_hiddenColumns.contains(colName)) {
                      _hiddenColumns.remove(colName);
                    } else {
                      if (_hiddenColumns.length < cols.length - 1) {
                        _hiddenColumns.add(colName);
                      } else {
                        _showSnackBar('At least one column must be visible', isError: true);
                      }
                    }
                  });
                },
              );

          if (compact) {
            final filterableCols = cols
                .where((c) => c.type == ColumnType.text || c.type == ColumnType.dropdown)
                .toList();

            if (isShort) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      _IconBtn(
                        icon: Icons.arrow_back_rounded,
                        tooltip: 'Back',
                        onTap: () => Navigator.pop(context),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          widget.fileName,
                          style: GoogleFonts.inter(
                            color: AppColors.textPrimary,
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            letterSpacing: -0.3,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 6),
                      _RecordCountBadge(count: _allRecords.length),
                      const SizedBox(width: 6),
                      SizedBox(
                        width: 130,
                        height: 32,
                        child: TextField(
                          controller: _searchCtrl,
                          focusNode: _searchFocus,
                          onChanged: setSearch,
                          style: GoogleFonts.inter(fontSize: 12),
                          decoration: InputDecoration(
                            hintText: 'Search…',
                            hintStyle: GoogleFonts.inter(
                              color: AppColors.textMuted,
                              fontSize: 12,
                            ),
                            prefixIcon: const Icon(
                              Icons.search_rounded,
                              color: AppColors.textMuted,
                              size: 14,
                            ),
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 6,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 4),
                      buildVisibilityMenu(),
                    ],
                  ),
                  const SizedBox(height: 6),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        _OutlineBtn(
                          label: 'Add record',
                          icon: Icons.add_rounded,
                          onTap: () => _onAddRecord(cols),
                        ),
                        const SizedBox(width: 6),
                        _OutlineBtn(
                          label: 'Add column',
                          icon: Icons.add_chart_rounded,
                          onTap: () => _onAddColumn(cols),
                        ),
                        const SizedBox(width: 6),
                        _PrimaryBtn(
                          label: 'Export',
                          icon: Icons.download_rounded,
                          onTap: () => _onExport(cols),
                        ),
                        if (filterableCols.isNotEmpty) ...[
                          const SizedBox(width: 10),
                          Container(
                            width: 1,
                            height: 20,
                            color: AppColors.border,
                          ),
                          const SizedBox(width: 10),
                          ..._buildFilterDropdowns(cols),
                        ],
                      ],
                    ),
                  ),
                ],
              );
            }

            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    _IconBtn(
                      icon: Icons.arrow_back_rounded,
                      tooltip: 'Back',
                      onTap: () => Navigator.pop(context),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        widget.fileName,
                        style: GoogleFonts.inter(
                          color: AppColors.textPrimary,
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          letterSpacing: -0.3,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    _RecordCountBadge(count: _allRecords.length),
                    const SizedBox(width: 4),
                    buildVisibilityMenu(),
                  ],
                ),
                SizedBox(height: isShort ? 4 : 10),
                Wrap(
                  spacing: 8,
                  runSpacing: isShort ? 4 : 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    SizedBox(
                      width: 180,
                      child: TextField(
                        controller: _searchCtrl,
                        focusNode: _searchFocus,
                        onChanged: setSearch,
                        decoration: InputDecoration(
                          hintText: 'Search…  (Ctrl+F)',
                          hintStyle: GoogleFonts.inter(
                            color: AppColors.textMuted,
                            fontSize: 13,
                          ),
                          prefixIcon: const Icon(
                            Icons.search_rounded,
                            color: AppColors.textMuted,
                            size: 16,
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 8,
                          ),
                        ),
                      ),
                    ),
                    _OutlineBtn(
                      label: 'Add record',
                      icon: Icons.add_rounded,
                      onTap: () => _onAddRecord(cols),
                    ),
                    _OutlineBtn(
                      label: 'Add column',
                      icon: Icons.add_chart_rounded,
                      onTap: () => _onAddColumn(cols),
                    ),
                    _PrimaryBtn(
                      label: 'Export',
                      icon: Icons.download_rounded,
                      onTap: () => _onExport(cols),
                    ),
                  ],
                ),
                if (filterableCols.isNotEmpty) ...[
                  SizedBox(height: isShort ? 4 : 10),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: _buildFilterDropdowns(cols),
                    ),
                  ),
                ],
              ],
            );
          }
          return Row(
            children: [
              _IconBtn(
                icon: Icons.arrow_back_rounded,
                tooltip: 'Back',
                onTap: () => Navigator.pop(context),
              ),
              const SizedBox(width: 8),
              Text(
                widget.fileName,
                style: GoogleFonts.inter(
                  color: AppColors.textPrimary,
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.3,
                ),
              ),
              const SizedBox(width: 10),
              _RecordCountBadge(count: _allRecords.length),
              const SizedBox(width: 10),
              buildVisibilityMenu(),
              const SizedBox(width: 10),
              SizedBox(
                width: 200,
                child: TextField(
                  controller: _searchCtrl,
                  focusNode: _searchFocus,
                  onChanged: setSearch,
                  decoration: InputDecoration(
                    hintText: 'Search…  (Ctrl+F)',
                    hintStyle: GoogleFonts.inter(
                      color: AppColors.textMuted,
                      fontSize: 13,
                    ),
                    prefixIcon: const Icon(
                      Icons.search_rounded,
                      color: AppColors.textMuted,
                      size: 16,
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 8,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Flexible(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: _buildFilterDropdowns(cols),
                  ),
                ),
              ),
              const Spacer(),
              const SizedBox(width: 10),
              _OutlineBtn(
                label: 'Add record',
                icon: Icons.add_rounded,
                onTap: () => _onAddRecord(cols),
              ),
              const SizedBox(width: 10),
              _OutlineBtn(
                label: 'Add column',
                icon: Icons.add_chart_rounded,
                onTap: () => _onAddColumn(cols),
              ),
              const SizedBox(width: 10),
              _PrimaryBtn(
                label: 'Export',
                icon: Icons.download_rounded,
                onTap: () => _onExport(cols),
              ),
            ],
          );
        },
      ),
    );
  }

  List<Widget> _buildFilterDropdowns(List<SchemaColumn> cols) {
    final filterable = cols
        .where(
          (c) => c.type == ColumnType.text || c.type == ColumnType.dropdown,
        )
        .toList();
    final widgets = <Widget>[];
    for (var i = 0; i < filterable.length; i++) {
      final c = filterable[i];
      widgets.add(
        _DropdownFilter<String?>(
          value: _filters[c.name],
          hint: 'All ${c.name}s',
          items: filterOptions(c.name),
          onChanged: (v) => setFilter(c.name, v),
        ),
      );
      if (i < filterable.length - 1) widgets.add(const SizedBox(width: 8));
    }
    return widgets;
  }

  Widget _buildSelectionBar(List<SchemaColumn> cols) {
    final mediaQuery = MediaQuery.of(context);
    final compact = mediaQuery.size.width < 600;

    return Container(
      color: AppColors.primaryLight,
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 12 : 24,
        vertical: 10,
      ),
      child: Row(
        children: [
          Text(
            compact
                ? '$_selectedCount selected'
                : '$_selectedCount record${_selectedCount > 1 ? 's' : ''} selected',
            style: GoogleFonts.inter(
              color: AppColors.primary,
              fontWeight: FontWeight.w600,
              fontSize: 14,
            ),
          ),
          const Spacer(),
          TextButton(
            onPressed: _cancelSelection,
            style: TextButton.styleFrom(
              foregroundColor: AppColors.textSecondary,
              padding: compact ? const EdgeInsets.symmetric(horizontal: 8) : null,
            ),
            child: Text('Cancel', style: GoogleFonts.inter(fontSize: 13)),
          ),
          SizedBox(width: compact ? 4 : 10),
          ElevatedButton.icon(
            onPressed: _onDeleteSelected,
            icon: const Icon(Icons.delete_outline_rounded, size: 14),
            label: Text(
              compact ? 'Delete' : 'Delete selected',
              style: GoogleFonts.inter(
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.error,
              foregroundColor: AppColors.textInverse,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
              padding: EdgeInsets.symmetric(
                horizontal: compact ? 10 : 14,
                vertical: 8,
              ),
              elevation: 0,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTableArea(List<SchemaColumn> cols) {
    final visibleCols = cols.where((c) => !_hiddenColumns.contains(c.name)).toList();
    final list = _filtered(cols);
    final mediaQuery = MediaQuery.of(context);
    final isShort = mediaQuery.size.height < 500;
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: SizedBox(
        width: (visibleCols.length * 130.0 + 100).clamp(600, 1400),
        child: Container(
          margin: EdgeInsets.symmetric(
            horizontal: isShort ? 16 : 20,
            vertical: isShort ? 0 : 20,
          ),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.border),
          ),
          child: Column(
            children: [
              _buildTableHeader(cols),
              const Divider(height: 1, color: AppColors.border),
              Expanded(
                child: list.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Container(
                              width: 56,
                              height: 56,
                              decoration: BoxDecoration(
                                color: AppColors.primaryLight,
                                borderRadius: BorderRadius.circular(16),
                              ),
                              child: const Icon(
                                Icons.table_rows_outlined,
                                size: 28,
                                color: AppColors.primary,
                              ),
                            ),
                            const SizedBox(height: 14),
                            Text(
                              'No records match your filters.',
                              style: GoogleFonts.inter(
                                color: AppColors.textPrimary,
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Add a new record to get started.',
                              style: GoogleFonts.inter(
                                color: AppColors.textSecondary,
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ),
                      )
                    : ListView.separated(
                        itemCount: list.length,
                        separatorBuilder: (_, _) =>
                            const Divider(height: 1, color: AppColors.border),
                        itemBuilder: (_, i) {
                          final rec = list[i];
                          return _DataRow(
                            record: rec,
                            columns: visibleCols,
                            selected: _selectedIds.contains(rec.id),
                            onToggle: () => _toggleSelect(rec.id),
                            onEdit: () => _onEditRecord(rec, cols),
                            onDelete: () => _onDeleteRecord(rec.id),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTableHeader(List<SchemaColumn> cols) {
    final visibleCols = cols.where((c) => !_hiddenColumns.contains(c.name)).toList();
    final mediaQuery = MediaQuery.of(context);
    final isShort = mediaQuery.size.height < 500;
    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: 16,
        vertical: isShort ? 4 : 12,
      ),
      child: Row(
        children: [
          SizedBox(
            width: 40,
            child: Checkbox(
              value: _allFilteredSelected(cols),
              tristate:
                  _filtered(cols).any(
                    (r) => _selectedIds.contains(r.id),
                  ) &&
                  !_allFilteredSelected(cols),
              onChanged: (v) => _toggleSelectAll(v, cols),
            ),
          ),
          ...visibleCols.map(
            (c) => Expanded(
              flex: c.type == ColumnType.number ? 1 : 2,
              child: PopupMenuButton<String>(
                tooltip: 'Column options',
                offset: const Offset(0, 30),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Flexible(
                      child: Text(
                        c.name.toUpperCase(),
                        style: GoogleFonts.inter(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: _sortColumn == c.name ? AppColors.primary : AppColors.textMuted,
                          letterSpacing: 0.6,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 4),
                    if (_sortColumn == c.name)
                      Icon(
                        _sortAscending ? Icons.arrow_upward_rounded : Icons.arrow_downward_rounded,
                        size: 12,
                        color: AppColors.primary,
                      )
                    else
                      const Icon(Icons.arrow_drop_down_rounded, size: 14, color: AppColors.textMuted),
                  ],
                ),
                itemBuilder: (context) => [
                  PopupMenuItem(
                    value: 'sort_asc',
                    child: Row(
                      children: [
                        const Icon(Icons.arrow_upward_rounded, size: 16, color: AppColors.textSecondary),
                        const SizedBox(width: 8),
                        Text('Sort Ascending', style: GoogleFonts.inter(fontSize: 13)),
                      ],
                    ),
                  ),
                  PopupMenuItem(
                    value: 'sort_desc',
                    child: Row(
                      children: [
                        const Icon(Icons.arrow_downward_rounded, size: 16, color: AppColors.textSecondary),
                        const SizedBox(width: 8),
                        Text('Sort Descending', style: GoogleFonts.inter(fontSize: 13)),
                      ],
                    ),
                  ),
                  const PopupMenuDivider(),
                  PopupMenuItem(
                    value: 'edit',
                    child: Row(
                      children: [
                        const Icon(Icons.edit_outlined, size: 16, color: AppColors.textSecondary),
                        const SizedBox(width: 8),
                        Text('Edit Column', style: GoogleFonts.inter(fontSize: 13)),
                      ],
                    ),
                  ),
                  PopupMenuItem(
                    value: 'hide',
                    child: Row(
                      children: [
                        const Icon(Icons.visibility_off_outlined, size: 16, color: AppColors.textSecondary),
                        const SizedBox(width: 8),
                        Text('Hide Column', style: GoogleFonts.inter(fontSize: 13)),
                      ],
                    ),
                  ),
                  PopupMenuItem(
                    value: 'delete',
                    child: Row(
                      children: [
                        const Icon(Icons.delete_outline_rounded, size: 16, color: AppColors.error),
                        const SizedBox(width: 8),
                        Text('Delete Column', style: GoogleFonts.inter(fontSize: 13, color: AppColors.error)),
                      ],
                    ),
                  ),
                ],
                onSelected: (action) {
                  if (action == 'sort_asc') {
                    setState(() {
                      _sortColumn = c.name;
                      _sortAscending = true;
                    });
                  } else if (action == 'sort_desc') {
                    setState(() {
                      _sortColumn = c.name;
                      _sortAscending = false;
                    });
                  } else if (action == 'edit') {
                    _onEditColumn(c, cols);
                  } else if (action == 'hide') {
                    setState(() {
                      _hiddenColumns.add(c.name);
                    });
                  } else if (action == 'delete') {
                    _onDeleteColumn(c, cols);
                  }
                },
              ),
            ),
          ),
          SizedBox(
            width: 60,
            child: Text(
              'ACTIONS',
              style: GoogleFonts.inter(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: AppColors.textMuted,
                letterSpacing: 0.6,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFooter(List<SchemaColumn> cols) {
    final allFiltered = _allFiltered(cols);
    final total = allFiltered.length;
    final totalRecords = _allRecords.length;
    final startIndex = total == 0 ? 0 : (_currentPage - 1) * _pageSize + 1;
    final endIndex = (_currentPage * _pageSize) > total ? total : (_currentPage * _pageSize);
    final totalPages = (total / _pageSize).ceil();
    final canPrev = _currentPage > 1;
    final canNext = _currentPage < totalPages;
    final mediaQuery = MediaQuery.of(context);
    final compact = mediaQuery.size.width < 600;
    final isShort = mediaQuery.size.height < 500;

    return Container(
      color: AppColors.surface,
      padding: EdgeInsets.symmetric(
        horizontal: isShort ? 16 : 24,
        vertical: isShort ? 4 : 12,
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              '${startIndex}–${endIndex} / $total records${total != totalRecords ? ' (filtered from $totalRecords)' : ''}',
              style: GoogleFonts.inter(color: AppColors.textMuted, fontSize: 13),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (totalPages > 1) ...[
            const SizedBox(width: 12),
            _PageNavBtn(
              icon: Icons.chevron_left_rounded,
              onPressed: canPrev ? () => setState(() => _currentPage--) : null,
            ),
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 6),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: AppColors.primary,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                '$_currentPage',
                style: GoogleFonts.inter(
                  color: AppColors.textInverse,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            _PageNavBtn(
              icon: Icons.chevron_right_rounded,
              onPressed: canNext ? () => setState(() => _currentPage++) : null,
            ),
          ],
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// DATA ROW
// ─────────────────────────────────────────────────────────────────────────────
class _DataRow extends StatefulWidget {
  final RecordData record;
  final List<SchemaColumn> columns;
  final bool selected;
  final VoidCallback onToggle;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _DataRow({
    required this.record,
    required this.columns,
    required this.selected,
    required this.onToggle,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  State<_DataRow> createState() => _DataRowState();
}

class _DataRowState extends State<_DataRow> {
  bool _hov = false;

  @override
  Widget build(BuildContext context) {
    final mediaQuery = MediaQuery.of(context);
    final isShort = mediaQuery.size.height < 500;
    return MouseRegion(
      onEnter: (_) => setState(() => _hov = true),
      onExit: (_) => setState(() => _hov = false),
      child: InkWell(
        onTap: widget.onToggle,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 100),
          color: widget.selected
              ? AppColors.primaryLight
              : _hov
              ? AppColors.primaryLight.withValues(alpha: 0.2)
              : Colors.transparent,
          padding: EdgeInsets.symmetric(
            horizontal: 16,
            vertical: isShort ? 6 : 14,
          ),
          child: Row(
            children: [
              SizedBox(
                width: 40,
                child: Checkbox(
                  value: widget.selected,
                  onChanged: (_) => widget.onToggle(),
                ),
              ),
              ...widget.columns.map(
                (c) => Expanded(
                  flex: c.type == ColumnType.number ? 1 : 2,
                  child: _buildCell(widget.record, c),
                ),
              ),
              SizedBox(
                width: 60,
                child: _iconRow(
                  onEdit: widget.onEdit,
                  onDelete: widget.onDelete,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

Widget _buildCell(RecordData record, SchemaColumn col) {
  try {
    final rawVal = record.data[col.name];
    final val = rawVal?.toString() ?? '';

    if (col.type == ColumnType.dropdown && col.dropdownOptions.length <= 4) {
      Color bg, fg;
      switch (val) {
        case 'New':
          bg = AppColors.successLight;
          fg = AppColors.success;
        case 'Good':
          bg = AppColors.infoBadgeLight;
          fg = AppColors.infoBadge;
        case 'Fair':
          bg = AppColors.warningLight;
          fg = AppColors.warning;
        default:
          bg = AppColors.border.withValues(alpha: 0.3);
          fg = AppColors.textSecondary;
      }
      return FittedBox(
        fit: BoxFit.scaleDown,
        alignment: Alignment.centerLeft,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text(
            val,
            style: TextStyle(
              color: fg,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      );
    }
    if (val.isEmpty && col.type != ColumnType.boolean) {
      return Text(
        '\u2014',
        style: GoogleFonts.inter(
          fontSize: 14,
          color: AppColors.textMuted,
        ),
      );
    }
    if (col.type == ColumnType.boolean) {
      final isTrue = rawVal == true ||
          val.toLowerCase() == 'yes' ||
          val.toLowerCase() == 'true' ||
          val == '1';
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            isTrue ? Icons.check_circle : Icons.cancel_outlined,
            size: 16,
            color: isTrue ? AppColors.success : AppColors.textMuted,
          ),
          const SizedBox(width: 4),
          Text(
            isTrue ? 'Yes' : 'No',
            style: GoogleFonts.inter(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: AppColors.textPrimary,
            ),
          ),
        ],
      );
    }
    return Text(
      val,
      style: GoogleFonts.inter(
        fontSize: 14,
        fontWeight: FontWeight.w500,
        color: AppColors.textPrimary,
      ),
    );
  } catch (e) {
    return Text(
      'Error',
      style: GoogleFonts.inter(
        fontSize: 14,
        color: AppColors.error,
      ),
    );
  }
}

Widget _iconRow({
  required VoidCallback onEdit,
  required VoidCallback onDelete,
}) {
  return Row(
    children: [
      _IconBtn(
        icon: Icons.edit_outlined,
        tooltip: 'Edit',
        color: AppColors.textSecondary,
        onTap: onEdit,
      ),
      const SizedBox(width: 4),
      _IconBtn(
        icon: Icons.delete_outline_rounded,
        tooltip: 'Delete',
        color: AppColors.error,
        onTap: onDelete,
      ),
    ],
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// ADD / EDIT DIALOG
// ─────────────────────────────────────────────────────────────────────────────
class _RecordDialog extends StatefulWidget {
  final List<SchemaColumn> columns;
  final Map<String, dynamic>? existing;

  const _RecordDialog({required this.columns, this.existing});

  @override
  State<_RecordDialog> createState() => _RecordDialogState();
}

class _RecordDialogState extends State<_RecordDialog> {
  final _formKey = GlobalKey<FormState>();
  final Map<String, TextEditingController> _ctrls = {};
  final Map<String, String> _dropdownValues = {};
  bool _submitting = false;

  bool get _isEditing => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final data = widget.existing ?? {};
    for (final c in widget.columns) {
      if (c.type == ColumnType.dropdown || c.type == ColumnType.boolean) {
        final def = c.type == ColumnType.boolean
            ? (data[c.name]?.toString().isNotEmpty == true
                  ? data[c.name].toString()
                  : 'Yes')
            : (data[c.name]?.toString() ??
                  (c.dropdownOptions.isNotEmpty
                      ? c.dropdownOptions.first
                      : ''));
        _dropdownValues[c.name] = def;
      } else {
        _ctrls[c.name] = TextEditingController(
          text: data[c.name]?.toString() ?? '',
        );
      }
    }
  }

  @override
  void dispose() {
    for (final c in _ctrls.values) {
      c.dispose();
    }
    super.dispose();
  }

  void _submit() {
    if (_submitting || !_formKey.currentState!.validate()) return;
    setState(() => _submitting = true);
    final data = <String, dynamic>{};
    for (final c in widget.columns) {
      if (c.type == ColumnType.dropdown || c.type == ColumnType.boolean) {
        data[c.name] = _dropdownValues[c.name] ?? '';
      } else if (c.type == ColumnType.number) {
        data[c.name] = (_ctrls[c.name]?.text ?? '').trim();
      } else {
        data[c.name] = (_ctrls[c.name]?.text ?? '').trim();
      }
    }
    Navigator.pop(context, data);
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: SizedBox(
        width: 520,
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _isEditing ? 'Edit Record' : 'Add Record',
                  style: GoogleFonts.inter(
                    color: AppColors.textPrimary,
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 20),
                Flexible(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 420),
                    child: SingleChildScrollView(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: _buildFormFields(widget.columns),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: _submitting
                          ? null
                          : () => Navigator.pop(context),
                      child: Text(
                        'Cancel',
                        style: GoogleFonts.inter(
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    ElevatedButton(
                      onPressed: _submitting ? null : _submit,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: AppColors.textInverse,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                        elevation: 0,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 10,
                        ),
                      ),
                      child: _submitting
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : Text(_isEditing ? 'Save changes' : 'Add record'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _buildFormFields(List<SchemaColumn> cols) {
    final widgets = <Widget>[];
    for (var i = 0; i < cols.length; i += 2) {
      final a = cols[i];
      final b = i + 1 < cols.length ? cols[i + 1] : null;
      widgets.add(
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Row(
            children: [
              Expanded(child: _buildField(a)),
              if (b != null) ...[
                const SizedBox(width: 12),
                Expanded(child: _buildField(b)),
              ] else
                const Expanded(child: SizedBox.shrink()),
            ],
          ),
        ),
      );
    }
    return widgets;
  }

  Widget _buildField(SchemaColumn c) {
    if (c.type == ColumnType.dropdown) {
      return DropdownButtonFormField<String>(
        isExpanded: true,
        initialValue:
            _dropdownValues[c.name] ??
            (c.dropdownOptions.isNotEmpty ? c.dropdownOptions.first : ''),
        decoration: InputDecoration(labelText: c.name),
        items: (c.dropdownOptions.isNotEmpty ? c.dropdownOptions : [''])
            .map((opt) => DropdownMenuItem(
                  value: opt,
                  child: Text(opt, overflow: TextOverflow.ellipsis),
                ))
            .toList(),
        onChanged: (v) => setState(() => _dropdownValues[c.name] = v ?? ''),
        validator: c.required
            ? (v) => (v == null || v.isEmpty) ? 'Required' : null
            : null,
      );
    }
    if (c.type == ColumnType.boolean) {
      return DropdownButtonFormField<String>(
        isExpanded: true,
        initialValue: _dropdownValues[c.name] ?? 'Yes',
        decoration: InputDecoration(labelText: c.name),
        items: [
          'Yes',
          'No',
        ].map((opt) => DropdownMenuItem(
              value: opt,
              child: Text(opt, overflow: TextOverflow.ellipsis),
            )).toList(),
        onChanged: (v) => setState(() => _dropdownValues[c.name] = v ?? 'Yes'),
        validator: c.required
            ? (v) => (v == null || v.isEmpty) ? 'Required' : null
            : null,
      );
    }
    final ctrl = _ctrls[c.name]!;
    if (c.type == ColumnType.date) {
      return TextFormField(
        controller: ctrl,
        readOnly: true,
        decoration: InputDecoration(
          labelText: c.name,
          suffixIcon: const Icon(Icons.calendar_today_outlined, size: 16),
        ),
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
            ctrl.text = '${picked.day.toString().padLeft(2, '0')} / '
                '${picked.month.toString().padLeft(2, '0')} / '
                '${picked.year}';
          }
        },
        validator: c.required
            ? (v) => (v == null || v.trim().isEmpty) ? 'Required' : null
            : null,
      );
    }
    return TextFormField(
      controller: ctrl,
      keyboardType: c.type == ColumnType.number
          ? TextInputType.number
          : TextInputType.text,
      decoration: InputDecoration(labelText: c.name),
      validator: c.required
          ? (v) => (v == null || v.trim().isEmpty) ? 'Required' : null
          : null,
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// REUSABLE WIDGETS
// ─────────────────────────────────────────────────────────────────────────────
class _RecordCountBadge extends StatelessWidget {
  final int count;
  const _RecordCountBadge({required this.count});
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    decoration: BoxDecoration(
      color: AppColors.primaryLight,
      borderRadius: BorderRadius.circular(20),
    ),
    child: Text(
      '$count records',
      style: GoogleFonts.inter(
        color: AppColors.primary,
        fontSize: 12,
        fontWeight: FontWeight.w600,
      ),
    ),
  );
}

class _DropdownFilter<T> extends StatelessWidget {
  final T value;
  final String hint;
  final List<String> items;
  final ValueChanged<T?> onChanged;

  const _DropdownFilter({
    required this.value,
    required this.hint,
    required this.items,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 150,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: AppColors.surface,
          border: Border.all(color: AppColors.border),
          borderRadius: BorderRadius.circular(8),
        ),
        child: DropdownButtonHideUnderline(
          child: DropdownButton<String?>(
            isExpanded: true,
            value: value as String?,
            hint: Text(
              hint,
              style: GoogleFonts.inter(
                color: AppColors.textSecondary,
                fontSize: 14,
              ),
              overflow: TextOverflow.ellipsis,
            ),
            style: GoogleFonts.inter(color: AppColors.textPrimary, fontSize: 14),
            icon: const Icon(
              Icons.keyboard_arrow_down_rounded,
              color: AppColors.textSecondary,
              size: 18,
            ),
            onChanged: (v) => onChanged(v as T?),
            items: [
              DropdownMenuItem(
                value: null,
                child: Text(hint, overflow: TextOverflow.ellipsis),
              ),
              ...items.map(
                (s) => DropdownMenuItem(
                  value: s,
                  child: Text(s, overflow: TextOverflow.ellipsis),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// ANIMATED BUTTON WIDGETS
// ─────────────────────────────────────────────────────────────────────────────
class _PrimaryBtn extends StatefulWidget {
  final String label;
  final IconData icon;
  final VoidCallback onTap;
  const _PrimaryBtn({
    required this.label,
    required this.icon,
    required this.onTap,
  });
  @override
  State<_PrimaryBtn> createState() => _PrimaryBtnState();
}

class _PrimaryBtnState extends State<_PrimaryBtn> {
  bool _hov = false;
  bool _press = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hov = true),
      onExit: (_) => setState(() => _hov = false),
      child: GestureDetector(
        onTapDown: (_) => setState(() => _press = true),
        onTapUp: (_) => setState(() => _press = false),
        onTapCancel: () => setState(() => _press = false),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          curve: Curves.easeOutCubic,
          transform: _press
              ? Matrix4.diagonal3Values(0.96, 0.96, 1.0)
              : Matrix4.identity(),
          transformAlignment: Alignment.center,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: _hov
                  ? [AppColors.primaryHover, AppColors.primary]
                  : [
                      AppColors.primary,
                      AppColors.primary.withValues(alpha: 0.9),
                    ],
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
            ),
            borderRadius: BorderRadius.circular(8),
            boxShadow: [
              if (_hov)
                BoxShadow(
                  color: AppColors.primary.withValues(alpha: 0.35),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
            ],
          ),
          child: Material(
            type: MaterialType.transparency,
            child: InkWell(
              onTap: widget.onTap,
              borderRadius: BorderRadius.circular(8),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 10,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(widget.icon, size: 14, color: Colors.white),
                    const SizedBox(width: 6),
                    Text(
                      widget.label,
                      style: GoogleFonts.inter(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _OutlineBtn extends StatefulWidget {
  final String label;
  final IconData icon;
  final VoidCallback onTap;
  const _OutlineBtn({
    required this.label,
    required this.icon,
    required this.onTap,
  });
  @override
  State<_OutlineBtn> createState() => _OutlineBtnState();
}

class _OutlineBtnState extends State<_OutlineBtn> {
  bool _hov = false;
  bool _press = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hov = true),
      onExit: (_) => setState(() => _hov = false),
      child: GestureDetector(
        onTapDown: (_) => setState(() => _press = true),
        onTapUp: (_) => setState(() => _press = false),
        onTapCancel: () => setState(() => _press = false),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          curve: Curves.easeOutCubic,
          transform: _press
              ? Matrix4.diagonal3Values(0.96, 0.96, 1.0)
              : Matrix4.identity(),
          transformAlignment: Alignment.center,
          decoration: BoxDecoration(
            color: _hov
                ? AppColors.primaryLight.withValues(alpha: 0.4)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: _hov ? AppColors.primary : AppColors.border,
              width: 1.5,
            ),
          ),
          child: Material(
            type: MaterialType.transparency,
            child: InkWell(
              onTap: widget.onTap,
              borderRadius: BorderRadius.circular(8),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 10,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      widget.icon,
                      size: 14,
                      color: _hov ? AppColors.primary : AppColors.textSecondary,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      widget.label,
                      style: GoogleFonts.inter(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        color: _hov ? AppColors.primary : AppColors.textPrimary,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _IconBtn extends StatefulWidget {
  final IconData icon;
  final String tooltip;
  final Color color;
  final VoidCallback onTap;
  const _IconBtn({
    required this.icon,
    required this.tooltip,
    this.color = AppColors.textSecondary,
    required this.onTap,
  });
  @override
  State<_IconBtn> createState() => _IconBtnState();
}

class _IconBtnState extends State<_IconBtn> {
  bool _hov = false;
  bool _press = false;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: widget.tooltip,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hov = true),
        onExit: (_) => setState(() => _hov = false),
        child: GestureDetector(
          onTapDown: (_) => setState(() => _press = true),
          onTapUp: (_) => setState(() => _press = false),
          onTapCancel: () => setState(() => _press = false),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            curve: Curves.easeOutCubic,
            transform: _press
                ? Matrix4.diagonal3Values(0.88, 0.88, 1.0)
                : Matrix4.identity(),
            transformAlignment: Alignment.center,
            decoration: BoxDecoration(
              color: _hov
                  ? widget.color.withValues(alpha: 0.12)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(6),
            ),
            child: InkWell(
              onTap: widget.onTap,
              borderRadius: BorderRadius.circular(6),
              child: Padding(
                padding: const EdgeInsets.all(6),
                child: Icon(
                  widget.icon,
                  size: 16,
                  color: _hov
                      ? widget.color
                      : widget.color.withValues(alpha: 0.7),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _PageNavBtn extends StatefulWidget {
  final IconData icon;
  final VoidCallback? onPressed;
  const _PageNavBtn({required this.icon, required this.onPressed});
  @override
  State<_PageNavBtn> createState() => _PageNavBtnState();
}

class _PageNavBtnState extends State<_PageNavBtn> {
  bool _hov = false;
  bool _press = false;

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onPressed != null;
    return MouseRegion(
      cursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
      onEnter: (_) => setState(() => _hov = true),
      onExit: (_) => setState(() => _hov = false),
      child: GestureDetector(
        onTapDown: enabled ? (_) => setState(() => _press = true) : null,
        onTapUp: enabled ? (_) => setState(() => _press = false) : null,
        onTapCancel: () => setState(() => _press = false),
        onTap: widget.onPressed,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          curve: Curves.easeOutCubic,
          transform: _press
              ? Matrix4.diagonal3Values(0.9, 0.9, 1.0)
              : Matrix4.identity(),
          transformAlignment: Alignment.center,
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: _hov && enabled
                ? AppColors.primaryLight
                : Colors.transparent,
            border: Border.all(
              color: !enabled
                  ? AppColors.border.withValues(alpha: 0.5)
                  : _hov
                  ? AppColors.primary
                  : AppColors.border,
            ),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Icon(
            widget.icon,
            size: 18,
            color: !enabled
                ? AppColors.textMuted
                : _hov
                ? AppColors.primary
                : AppColors.textSecondary,
          ),
        ),
      ),
    );
  }
}

class _ColumnDialog extends StatefulWidget {
  final List<SchemaColumn> existingColumns;
  final SchemaColumn? editingColumn;

  const _ColumnDialog({
    required this.existingColumns,
    this.editingColumn,
  });

  @override
  State<_ColumnDialog> createState() => _ColumnDialogState();
}

class _ColumnDialogState extends State<_ColumnDialog> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _nameCtrl;
  late ColumnType _type;
  late TextEditingController _optionsCtrl;
  late bool _required;

  bool get _isEditing => widget.editingColumn != null;

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController(text: widget.editingColumn?.name ?? '');
    _type = widget.editingColumn?.type ?? ColumnType.text;
    _optionsCtrl = TextEditingController(
      text: widget.editingColumn?.dropdownOptions.join(', ') ?? '',
    );
    _required = widget.editingColumn?.required ?? false;
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _optionsCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: SizedBox(
        width: 400,
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _isEditing ? 'Edit Column' : 'Add Column',
                  style: GoogleFonts.inter(
                    color: AppColors.textPrimary,
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 20),
                Flexible(
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        TextFormField(
                          controller: _nameCtrl,
                          decoration: const InputDecoration(
                            labelText: 'Column Name',
                            hintText: 'e.g. Price, Category',
                          ),
                          style: GoogleFonts.inter(fontSize: 14),
                          validator: (v) {
                            if (v == null || v.trim().isEmpty) return 'Required';
                            final name = v.trim();
                            final isDuplicate = widget.existingColumns.any((c) =>
                                c.name.toLowerCase() == name.toLowerCase() &&
                                (!_isEditing || widget.editingColumn!.name.toLowerCase() != name.toLowerCase()));
                            if (isDuplicate) return 'Column name already exists';
                            return null;
                          },
                        ),
                        const SizedBox(height: 16),
                        DropdownButtonFormField<ColumnType>(
                          isExpanded: true,
                          initialValue: _type,
                          decoration: const InputDecoration(labelText: 'Column Type'),
                          items: ColumnType.values.map((t) {
                            String label = t.name;
                            if (t == ColumnType.boolean) label = 'Yes/No (Boolean)';
                            return DropdownMenuItem(
                              value: t,
                              child: Text(label[0].toUpperCase() + label.substring(1)),
                            );
                          }).toList(),
                          onChanged: (val) {
                            if (val != null) {
                              setState(() => _type = val);
                            }
                          },
                        ),
                        if (_type == ColumnType.dropdown) ...[
                          const SizedBox(height: 16),
                          TextFormField(
                            controller: _optionsCtrl,
                            decoration: const InputDecoration(
                              labelText: 'Dropdown Options',
                              hintText: 'Option 1, Option 2, Option 3',
                              helperText: 'Separate options with commas',
                            ),
                            style: GoogleFonts.inter(fontSize: 14),
                            validator: (v) {
                              if (_type == ColumnType.dropdown) {
                                if (v == null || v.trim().isEmpty) return 'Required';
                                final opts = v.split(',').map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
                                if (opts.isEmpty) return 'Enter at least one option';
                              }
                              return null;
                            },
                          ),
                        ],
                        const SizedBox(height: 16),
                        CheckboxListTile(
                          value: _required,
                          title: Text(
                            'Required field',
                            style: GoogleFonts.inter(fontSize: 14, color: AppColors.textPrimary),
                          ),
                          contentPadding: EdgeInsets.zero,
                          controlAffinity: ListTileControlAffinity.leading,
                          onChanged: (val) => setState(() => _required = val ?? false),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: Text(
                        'Cancel',
                        style: GoogleFonts.inter(color: AppColors.textSecondary),
                      ),
                    ),
                    const SizedBox(width: 10),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: AppColors.textInverse,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      onPressed: () {
                        if (_formKey.currentState!.validate()) {
                          final name = _nameCtrl.text.trim();
                          final opts = _type == ColumnType.dropdown
                              ? _optionsCtrl.text
                                  .split(',')
                                  .map((s) => s.trim())
                                  .where((s) => s.isNotEmpty)
                                  .toList()
                              : <String>[];
                          final newCol = SchemaColumn(
                            name: name,
                            type: _type,
                            required: _required,
                            dropdownOptions: opts,
                          );
                          Navigator.pop(context, newCol);
                        }
                      },
                      child: Text(_isEditing ? 'Save' : 'Add'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
