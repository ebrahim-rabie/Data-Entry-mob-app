import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';
import 'package:excel/excel.dart' hide Border;
import 'package:flutter_application_1/shared.dart';
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

  @override
  void initState() {
    super.initState();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  List<String> get _filterableKeys => widget.columns
      .where((c) => c.type == ColumnType.text || c.type == ColumnType.dropdown)
      .map((c) => c.name)
      .toList();

  List<RecordData> get _filtered {
    final q = _searchQuery.toLowerCase();
    return _allRecords.where((r) {
      final matchSearch =
          q.isEmpty ||
          r.data.values.any((v) => v?.toString().toLowerCase().contains(q) ?? false);
      final matchFilters = _filterableKeys.every((k) {
        final filterVal = _filters[k];
        return filterVal == null || r.data[k]?.toString() == filterVal;
      });
      return matchSearch && matchFilters;
    }).toList();
  }

  List<String> filterOptions(String key) =>
      _allRecords.map((r) => r.data[key]?.toString() ?? '').toSet().toList()..sort();

  String? filterValue(String key) => _filters[key];

  void setSearch(String q) {
    setState(() => _searchQuery = q);
  }

  void setFilter(String key, String? value) {
    setState(() => _filters[key] = value);
  }

  bool get _allFilteredSelected =>
      _filtered.isNotEmpty &&
      _filtered.every((r) => _selectedIds.contains(r.id));

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

  void _toggleSelectAll(bool? value) {
    setState(() {
      if (value == true) {
        for (final r in _filtered) {
          _selectedIds.add(r.id);
        }
      } else {
        for (final r in _filtered) {
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
        margin: const EdgeInsets.all(16),
        duration: Duration(seconds: isError ? 5 : 3),
      ),
    );
  }

  Future<void> _onAddRecord() async {
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => _RecordDialog(columns: widget.columns),
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

  Future<void> _onEditRecord(RecordData record) async {
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) =>
          _RecordDialog(columns: widget.columns, existing: record.data),
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

  Future<void> _onExport() async {
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

    final flds = widget.columns;
    try {
      if (format == 'csv') {
        final buf = StringBuffer(flds.map((f) => '"${f.name}"').join(','));
        buf.writeln();
        for (final r in _filtered) {
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
        for (var r = 0; r < _filtered.length; r++) {
          for (var c = 0; c < flds.length; c++) {
            final v = _filtered[r].data[flds[c].name];
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

  @override
  Widget build(BuildContext context) {
    return KeyboardListener(
      focusNode: FocusNode()..requestFocus(),
      onKeyEvent: _handleKey,
      child: Scaffold(
        backgroundColor: AppColors.background,
        body: SafeArea(
          child: StreamBuilder(
            stream: databaseService.watchRecords(widget.projectId),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
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

              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildTopBar(),
                  if (_selectedIds.isNotEmpty) _buildSelectionBar(),
                  Expanded(child: _buildTableArea()),
                  _buildFooter(),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildTopBar() {
    return Container(
      color: AppColors.surface,
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
      child: LayoutBuilder(
        builder: (ctx, constraints) {
          final compact = constraints.maxWidth < 860;
          if (compact) {
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
                  ],
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
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
                    ..._buildFilterDropdowns(),
                    _OutlineBtn(
                      label: 'Add record',
                      icon: Icons.add_rounded,
                      onTap: _onAddRecord,
                    ),
                    _PrimaryBtn(
                      label: 'Export',
                      icon: Icons.download_rounded,
                      onTap: _onExport,
                    ),
                  ],
                ),
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
              const SizedBox(width: 20),
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
              ..._buildFilterDropdowns(),
              const Spacer(),
              _OutlineBtn(
                label: 'Add record',
                icon: Icons.add_rounded,
                onTap: _onAddRecord,
              ),
              const SizedBox(width: 10),
              _PrimaryBtn(
                label: 'Export',
                icon: Icons.download_rounded,
                onTap: _onExport,
              ),
            ],
          );
        },
      ),
    );
  }

  List<Widget> _buildFilterDropdowns() {
    final filterable = widget.columns
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

  Widget _buildSelectionBar() {
    return Container(
      color: AppColors.primaryLight,
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
      child: Row(
        children: [
          Text(
            '$_selectedCount record${_selectedCount > 1 ? 's' : ''} selected',
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
            ),
            child: Text('Cancel', style: GoogleFonts.inter(fontSize: 13)),
          ),
          const SizedBox(width: 10),
          ElevatedButton.icon(
            onPressed: _onDeleteSelected,
            icon: const Icon(Icons.delete_outline_rounded, size: 14),
            label: Text(
              'Delete selected',
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
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              elevation: 0,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTableArea() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: SizedBox(
        width: (widget.columns.length * 130.0 + 100).clamp(600, 1400),
        child: Container(
          margin: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.border),
          ),
          child: Column(
            children: [
              _buildTableHeader(),
              const Divider(height: 1, color: AppColors.border),
              Expanded(
                child: _filtered.isEmpty
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
                        itemCount: _filtered.length,
                        separatorBuilder: (_, _) =>
                            const Divider(height: 1, color: AppColors.border),
                        itemBuilder: (_, i) {
                          final rec = _filtered[i];
                          return _DataRow(
                            record: rec,
                            columns: widget.columns,
                            selected: _selectedIds.contains(rec.id),
                            onToggle: () => _toggleSelect(rec.id),
                            onEdit: () => _onEditRecord(rec),
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

  Widget _buildTableHeader() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          SizedBox(
            width: 40,
            child: Checkbox(
              value: _allFilteredSelected,
              tristate:
                  _filtered.any(
                    (r) => _selectedIds.contains(r.id),
                  ) &&
                  !_allFilteredSelected,
              onChanged: _toggleSelectAll,
            ),
          ),
          ...widget.columns.map(
            (c) => Expanded(
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

  Widget _buildFooter() {
    final count = _filtered.length;
    final total = _allRecords.length;
    return Container(
      color: AppColors.surface,
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
      child: Row(
        children: [
          Text(
            'Showing 1\u2013$count of $total records',
            style: GoogleFonts.inter(color: AppColors.textMuted, fontSize: 13),
          ),
          const Spacer(),
          _PageNavBtn(icon: Icons.chevron_left_rounded, onPressed: null),
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 6),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: AppColors.primary,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              '1',
              style: GoogleFonts.inter(
                color: AppColors.textInverse,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          _PageNavBtn(icon: Icons.chevron_right_rounded, onPressed: null),
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
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
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
  final val = record.data[col.name]?.toString() ?? '';
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
    final isTrue =
        val.toLowerCase() == 'yes' || val.toLowerCase() == 'true' || val == '1';
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
        initialValue:
            _dropdownValues[c.name] ??
            (c.dropdownOptions.isNotEmpty ? c.dropdownOptions.first : ''),
        decoration: InputDecoration(labelText: c.name),
        items: (c.dropdownOptions.isNotEmpty ? c.dropdownOptions : [''])
            .map((opt) => DropdownMenuItem(value: opt, child: Text(opt)))
            .toList(),
        onChanged: (v) => setState(() => _dropdownValues[c.name] = v ?? ''),
        validator: c.required
            ? (v) => (v == null || v.isEmpty) ? 'Required' : null
            : null,
      );
    }
    if (c.type == ColumnType.boolean) {
      return DropdownButtonFormField<String>(
        initialValue: _dropdownValues[c.name] ?? 'Yes',
        decoration: InputDecoration(labelText: c.name),
        items: [
          'Yes',
          'No',
        ].map((opt) => DropdownMenuItem(value: opt, child: Text(opt))).toList(),
        onChanged: (v) => setState(() => _dropdownValues[c.name] = v ?? 'Yes'),
        validator: c.required
            ? (v) => (v == null || v.isEmpty) ? 'Required' : null
            : null,
      );
    }
    final ctrl = _ctrls[c.name]!;
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
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(8),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String?>(
          value: value as String?,
          hint: Text(
            hint,
            style: GoogleFonts.inter(
              color: AppColors.textSecondary,
              fontSize: 14,
            ),
          ),
          style: GoogleFonts.inter(color: AppColors.textPrimary, fontSize: 14),
          icon: const Icon(
            Icons.keyboard_arrow_down_rounded,
            color: AppColors.textSecondary,
            size: 18,
          ),
          onChanged: (v) => onChanged(v as T?),
          items: [
            DropdownMenuItem(value: null, child: Text(hint)),
            ...items.map((s) => DropdownMenuItem(value: s, child: Text(s))),
          ],
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
