import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_application_1/shared.dart';
import 'package:flutter_application_1/database.dart';

class SchemaAddRowsScreen extends StatefulWidget {
  final String? projectId;
  final String fileName;
  final List<SchemaColumn> columns;
  final List<Map<String, dynamic>>? initialRecords;

  const SchemaAddRowsScreen({
    super.key,
    this.projectId,
    required this.fileName,
    required this.columns,
    this.initialRecords,
  });

  @override
  State<SchemaAddRowsScreen> createState() => _SchemaAddRowsScreenState();
}

class _SchemaAddRowsScreenState extends State<SchemaAddRowsScreen> {
  final List<Map<String, dynamic>> _records = [];
  late String _projectId;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _projectId = widget.projectId ?? '';
    if (widget.initialRecords != null && widget.initialRecords!.isNotEmpty) {
      _records.addAll(widget.initialRecords!);
    } else {
      _addBlankRow();
    }
  }

  void _addBlankRow() {
    final blank = <String, dynamic>{};
    for (final col in widget.columns) {
      blank[col.name] = null;
    }
    setState(() => _records.add(blank));
  }

  void _deleteRow(int index) {
    if (_records.length <= 1) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(errorSnack('At least one row is required.'));
      return;
    }
    setState(() => _records.removeAt(index));
  }

  void _updateCell(int rowIndex, String columnName, dynamic value) {
    setState(() => _records[rowIndex][columnName] = value);
  }

  Future<void> _continueToFinal() async {
    for (int r = 0; r < _records.length; r++) {
      for (final col in widget.columns) {
        if (col.required) {
          final v = _records[r][col.name];
          if (v == null || (v is String && v.trim().isEmpty)) {
            ScaffoldMessenger.of(context).showSnackBar(
              errorSnack('Row ${r + 1}: "${col.name}" is required.'),
            );
            return;
          }
        }
      }
    }
    setState(() => _saving = true);
    try {
      if (_projectId.isEmpty) {
        _projectId = await databaseService.createProject(widget.fileName, widget.columns);
      }
      for (final r in _records) {
        await databaseService.addRecord(_projectId, Map<String, dynamic>.from(r));
      }
      if (mounted) {
        Navigator.pushNamed(
          context,
          SchemaRoute.finalScreen,
          arguments: {
            'projectId': _projectId,
            'fileName': widget.fileName,
            'columns': widget.columns,
          },
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(errorSnack('Failed to save: $e'));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final w = MediaQuery.of(context).size.width;
    final p = pagePadding(w);
    final isWide = isDesktopWidth(w);

    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFFF0F2FF), Color(0xFFFFFFFF)],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
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
                  fileName: widget.fileName,
                  recordCount: _records.length,
                  onContinue: _continueToFinal,
                  saving: _saving,
                ),
                const Divider(height: 1, color: AppColors.border),
                Expanded(
                  child: _records.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.table_rows_outlined,
                                size: 48,
                                color: AppColors.textMuted.withValues(
                                  alpha: 0.5,
                                ),
                              ),
                              const SizedBox(height: 12),
                              Text(
                                'No records yet',
                                style: GoogleFonts.inter(
                                  fontSize: 15,
                                  color: AppColors.textSecondary,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Tap "Add row" to start entering data',
                                style: GoogleFonts.inter(
                                  fontSize: 13,
                                  color: AppColors.textMuted,
                                ),
                              ),
                            ],
                          ),
                        )
                      : isWide
                      ? _TableView(
                          columns: widget.columns,
                          records: _records,
                          onUpdate: _updateCell,
                          onDelete: _deleteRow,
                        )
                      : _CardView(
                          columns: widget.columns,
                          records: _records,
                          onUpdate: _updateCell,
                          onDelete: _deleteRow,
                        ),
                ),
                Container(
                  padding: EdgeInsets.symmetric(horizontal: p, vertical: 12),
                  decoration: const BoxDecoration(
                    color: AppColors.surface,
                    border: Border(top: BorderSide(color: AppColors.border)),
                  ),
                  child: SizedBox(
                    width: double.infinity,
                    child: ScaleButton(
                      onTap: _addBlankRow,
                      child: AbsorbPointer(
                        child: OutlinedButton.icon(
                          onPressed: () {},
                          icon: const Icon(Icons.add, size: 16),
                          label: Text(
                            'Add row',
                            style: GoogleFonts.inter(
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AppColors.primary,
                            side: const BorderSide(color: AppColors.primary),
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
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
      ),
    );
  }
}

// ── Top bar ───────────────────────────────────────────────────────────────────

class _TopBar extends StatelessWidget {
  final String fileName;
  final int recordCount;
  final Future<void> Function() onContinue;
  final bool saving;

  const _TopBar({
    required this.fileName,
    required this.recordCount,
    required this.onContinue,
    this.saving = false,
  });

  @override
  Widget build(BuildContext context) {
    final isPhone = MediaQuery.of(context).size.width < 600;
    return Container(
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
                    IconButton(
                      icon: const Icon(Icons.arrow_back, size: 20),
                      color: AppColors.textPrimary,
                      onPressed: () => Navigator.pop(context),
                      splashRadius: 20,
                    ),
                    Expanded(
                      child: Text(
                        fileName,
                        style: GoogleFonts.inter(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textPrimary,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    _recordPill(),
                  ],
                ),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: ScaleButton(
                    onTap: saving ? null : onContinue,
                    child: AbsorbPointer(
                      absorbing: !saving,
                      child: ElevatedButton(
                        onPressed: saving ? null : () {},
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          foregroundColor: AppColors.textInverse,
                          elevation: 0,
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                          textStyle: GoogleFonts.inter(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        child: saving
                            ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                            : const Text('Continue to summary'),
                      ),
                    ),
                  ),
                ),
              ],
            )
          : Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.arrow_back, size: 20),
                  color: AppColors.textPrimary,
                  onPressed: () => Navigator.pop(context),
                  splashRadius: 20,
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    fileName,
                    style: GoogleFonts.inter(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                _recordPill(),
                const SizedBox(width: 12),
                ScaleButton(
                  onTap: saving ? null : onContinue,
                  child: AbsorbPointer(
                    absorbing: !saving,
                    child: ElevatedButton(
                      onPressed: saving ? null : () {},
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: AppColors.textInverse,
                        elevation: 0,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 18,
                          vertical: 10,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                        textStyle: GoogleFonts.inter(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      child: saving
                          ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                          : const Text('Continue to summary'),
                    ),
                  ),
                ),
              ],
            ),
    );
  }

  Widget _recordPill() => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
    decoration: BoxDecoration(
      color: AppColors.background,
      borderRadius: BorderRadius.circular(99),
      border: Border.all(color: AppColors.border),
    ),
    child: Text(
      '$recordCount rows',
      style: GoogleFonts.inter(fontSize: 12, color: AppColors.textSecondary),
    ),
  );
}

// ── Desktop table view ────────────────────────────────────────────────────────

class _TableView extends StatelessWidget {
  final List<SchemaColumn> columns;
  final List<Map<String, dynamic>> records;
  final void Function(int, String, dynamic) onUpdate;
  final void Function(int) onDelete;

  const _TableView({
    required this.columns,
    required this.records,
    required this.onUpdate,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          headingRowColor: WidgetStateProperty.all(AppColors.primaryLight),
          border: TableBorder.all(
            color: AppColors.border,
            borderRadius: BorderRadius.circular(8),
          ),
          columnSpacing: 16,
          columns: [
            ...columns.map(
              (col) => DataColumn(
                label: Text(
                  col.name,
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: AppColors.primary,
                  ),
                ),
              ),
            ),
            const DataColumn(label: Text('', style: TextStyle(fontSize: 12))),
          ],
          rows: List.generate(records.length, (i) {
            return DataRow(
              cells: [
                ...columns.map(
                  (col) => DataCell(
                    _TableCell(
                      column: col,
                      value: records[i][col.name],
                      onChanged: (v) => onUpdate(i, col.name, v),
                    ),
                  ),
                ),
                DataCell(
                  IconButton(
                    icon: const Icon(
                      Icons.delete_outline,
                      size: 16,
                      color: AppColors.textMuted,
                    ),
                    onPressed: () => onDelete(i),
                    splashRadius: 16,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(
                      minWidth: 24,
                      minHeight: 24,
                    ),
                  ),
                ),
              ],
            );
          }),
        ),
      ),
    );
  }
}

// ── Mobile card view ──────────────────────────────────────────────────────────

class _CardView extends StatelessWidget {
  final List<SchemaColumn> columns;
  final List<Map<String, dynamic>> records;
  final void Function(int, String, dynamic) onUpdate;
  final void Function(int) onDelete;

  const _CardView({
    required this.columns,
    required this.records,
    required this.onUpdate,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final p = pagePadding(MediaQuery.of(context).size.width);
    return ListView.builder(
      padding: EdgeInsets.all(p),
      itemCount: records.length,
      itemBuilder: (_, i) => Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppColors.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  'Row ${i + 1}',
                  style: GoogleFonts.inter(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textSecondary,
                  ),
                ),
                const Spacer(),
                GestureDetector(
                  onTap: () => onDelete(i),
                  child: const Icon(
                    Icons.delete_outline,
                    size: 16,
                    color: AppColors.textMuted,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            ...columns.map(
              (col) => Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      col.name + (col.required ? ' *' : ''),
                      style: GoogleFonts.inter(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 6),
                    _TableCell(
                      column: col,
                      value: records[i][col.name],
                      onChanged: (v) => onUpdate(i, col.name, v),
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
}

// ── Table cell widget (supports all column types) ─────────────────────────────

class _TableCell extends StatefulWidget {
  final SchemaColumn column;
  final dynamic value;
  final void Function(dynamic) onChanged;

  const _TableCell({
    required this.column,
    required this.value,
    required this.onChanged,
  });

  @override
  State<_TableCell> createState() => _TableCellState();
}

class _TableCellState extends State<_TableCell> {
  late TextEditingController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: widget.value?.toString() ?? '');
  }

  @override
  void didUpdateWidget(_TableCell old) {
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

  InputDecoration _decoration(String hint) => InputDecoration(
    hintText: hint,
    hintStyle: GoogleFonts.inter(color: AppColors.textMuted, fontSize: 13),
    filled: true,
    fillColor: AppColors.background,
    isDense: true,
    contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(6),
      borderSide: const BorderSide(color: AppColors.border),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(6),
      borderSide: const BorderSide(color: AppColors.border),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(6),
      borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final col = widget.column;
    switch (col.type) {
      case ColumnType.text:
        return TextFormField(
          controller: _ctrl,
          onChanged: widget.onChanged,
          textInputAction: TextInputAction.next,
          style: GoogleFonts.inter(fontSize: 13, color: AppColors.textPrimary),
          decoration: _decoration('Enter text'),
        );

      case ColumnType.number:
        return TextFormField(
          controller: _ctrl,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: [
            FilteringTextInputFormatter.allow(RegExp(r'[\d.]')),
          ],
          onChanged: (v) => widget.onChanged(v),
          textInputAction: TextInputAction.next,
          style: GoogleFonts.inter(fontSize: 13, color: AppColors.textPrimary),
          decoration: _decoration('Enter number'),
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
              style: GoogleFonts.inter(
                fontSize: 13,
                color: AppColors.textPrimary,
              ),
              decoration: _decoration('DD / MM / YYYY').copyWith(
                suffixIcon: const Icon(
                  Icons.calendar_today_outlined,
                  size: 14,
                  color: AppColors.textMuted,
                ),
              ),
            ),
          ),
        );

      case ColumnType.boolean:
        final current = widget.value as String?;
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: ['Yes', 'No'].map((opt) {
            final selected = current == opt;
            return GestureDetector(
              onTap: () => widget.onChanged(opt),
              child: Container(
                margin: const EdgeInsets.only(right: 6),
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: selected ? AppColors.primary : AppColors.surface,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                    color: selected ? AppColors.primary : AppColors.border,
                  ),
                ),
                child: Text(
                  opt,
                  style: GoogleFonts.inter(
                    fontSize: 12,
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

      case ColumnType.dropdown:
        final opts = col.dropdownOptions.where((o) => o.isNotEmpty).toList();
        if (opts.isEmpty) {
          return Text(
            'No options',
            style: GoogleFonts.inter(fontSize: 12, color: AppColors.textMuted),
          );
        }
        final current = widget.value as String?;
        return Wrap(
          spacing: 6,
          runSpacing: 6,
          children: opts.map((opt) {
            final selected = current == opt;
            return GestureDetector(
              onTap: () => widget.onChanged(opt),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 5,
                ),
                decoration: BoxDecoration(
                  color: selected ? AppColors.primary : AppColors.surface,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                    color: selected ? AppColors.primary : AppColors.border,
                  ),
                ),
                child: Text(
                  opt,
                  style: GoogleFonts.inter(
                    fontSize: 12,
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
