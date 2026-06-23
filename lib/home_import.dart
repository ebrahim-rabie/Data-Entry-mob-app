import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_application_1/shared.dart';
import 'package:flutter_application_1/database.dart';
import 'package:file_picker/file_picker.dart';
import 'package:csv/csv.dart';
import 'package:excel/excel.dart' hide Border;
import 'package:cloud_firestore/cloud_firestore.dart';

class HomeImportScreen extends StatefulWidget {
  const HomeImportScreen({super.key});

  @override
  State<HomeImportScreen> createState() => _HomeImportScreenState();
}

class _HomeImportScreenState extends State<HomeImportScreen> {
  final TextEditingController _searchCtrl = TextEditingController();
  String _searchQuery = '';
  bool _sortByLastUpdated = true;

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  String formatTimestamp(Timestamp timestamp) {
    final dt = timestamp.toDate();
    final year = dt.year;
    final month = dt.month.toString().padLeft(2, '0');
    final day = dt.day.toString().padLeft(2, '0');
    final hour = dt.hour.toString().padLeft(2, '0');
    final minute = dt.minute.toString().padLeft(2, '0');
    return '$day/$month/$year $hour:$minute';
  }

  Future<void> _importCsv(BuildContext context) async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['csv'],
      );
      if (result == null || result.files.isEmpty) return;
      final file = result.files.single;
      final bytes = file.bytes ?? await File(file.path!).readAsBytes();
      final content = String.fromCharCodes(bytes);
      final rows = const CsvToListConverter().convert(content);
      if (rows.isEmpty) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(errorSnack('CSV file is empty.'));
        }
        return;
      }
      final rawHeaders = rows.first.map((e) => e.toString().trim()).toList();
      final headers = _deduplicateHeaders(rawHeaders);
      final columns = headers.map((h) => SchemaColumn(name: h)).toList();
      final dataRows = rows.skip(1).map((row) {
        final map = <String, dynamic>{};
        for (var i = 0; i < headers.length && i < row.length; i++) {
          map[headers[i]] = row[i];
        }
        return map;
      }).toList();
      _inferColumnTypes(columns, dataRows);
      if (context.mounted) {
        Navigator.pushNamed(context, SchemaRoute.schema, arguments: {
          'columns': columns,
          'fileName': file.name.replaceAll('.csv', ''),
          'records': dataRows,
        });
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(errorSnack('Failed to import CSV: $e'));
      }
    }
  }

  Future<void> _importXlsx(BuildContext context) async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['xlsx'],
      );
      if (result == null || result.files.isEmpty) return;
      final file = result.files.single;
      final bytes = file.bytes ?? await File(file.path!).readAsBytes();
      final excel = Excel.decodeBytes(bytes);
      if (excel.sheets.isEmpty) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(errorSnack('Excel file is empty.'));
        }
        return;
      }
      final sheetsList = excel.sheets.values.toList();
      final sheet = sheetsList.first;
      final rows = sheet.rows;
      if (rows.isEmpty) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(errorSnack('Excel sheet is empty.'));
        }
        return;
      }
      final rawHeaders = rows.first.map((cell) => _normalizeCellValue(cell?.value)?.toString().trim() ?? '').toList();
      final headers = _deduplicateHeaders(rawHeaders);
      final columns = headers.map((h) => SchemaColumn(name: h)).toList();
      final dataRows = rows.skip(1).map((row) {
        final map = <String, dynamic>{};
        for (var i = 0; i < headers.length && i < row.length; i++) {
          map[headers[i]] = _normalizeCellValue(row[i]?.value);
        }
        return map;
      }).toList();

      Sheet? listSheet;
      if (sheetsList.length > 1) {
        listSheet = sheetsList.skip(1).firstWhere(
          (s) {
            final name = s.sheetName.toLowerCase();
            return name.contains('list') || name.contains('lookup') || name.contains('option');
          },
          orElse: () => sheetsList[1],
        );
      }

      if (listSheet != null) {
        final listRows = listSheet.rows;
        for (var i = 0; i < columns.length; i++) {
          final options = <String>[];
          for (final row in listRows) {
            if (i < row.length) {
              final cellVal = _normalizeCellValue(row[i]?.value)?.toString().trim();
              if (cellVal != null && cellVal.isNotEmpty) {
                options.add(cellVal);
              }
            }
          }
          if (options.isNotEmpty && options.first.toLowerCase() == columns[i].name.toLowerCase()) {
            options.removeAt(0);
          }
          if (options.isNotEmpty) {
            columns[i].type = ColumnType.dropdown;
            columns[i].dropdownOptions = options.toSet().toList()..sort();
          }
        }
      } else {
        _inferColumnTypes(columns, dataRows);
      }
      final fileName = file.name.replaceAll('.xlsx', '');
      final projectId = await databaseService.createProject(fileName, columns);
      if (dataRows.isNotEmpty) {
        await databaseService.importRecords(projectId, dataRows);
      }
      if (context.mounted) {
        Navigator.pushNamed(context, SchemaRoute.finalScreen, arguments: {
          'projectId': projectId,
          'fileName': fileName,
          'columns': columns,
        });
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(errorSnack('Failed to import Excel: $e'));
      }
    }
  }

  Object? _normalizeCellValue(Object? value) {
    if (value == null) return null;
    Object rawValue = value;
    if (value is CellValue) {
      rawValue = switch (value) {
        TextCellValue(value: var v) => v,
        IntCellValue(value: var v) => v,
        DoubleCellValue(value: var v) => v,
        BoolCellValue(value: var v) => v,
        FormulaCellValue(formula: var f) => f,
        DateCellValue(year: var y, month: var m, day: var d) => DateTime(y, m, d),
        DateTimeCellValue(year: var y, month: var m, day: var d, hour: var h, minute: var min, second: var s) => DateTime(y, m, d, h, min, s),
        TimeCellValue(hour: var h, minute: var min, second: var s) => Duration(hours: h, minutes: min, seconds: s),
      };
    }
    if (rawValue is DateTime) return rawValue.toIso8601String();
    if (rawValue is bool) return rawValue;
    if (rawValue is num) return rawValue;
    return rawValue.toString();
  }

  List<String> _deduplicateHeaders(List<String> rawHeaders) {
    final seen = <String, int>{};
    final result = <String>[];
    for (var h in rawHeaders) {
      var name = h.trim();
      if (name.isEmpty) {
        name = 'Column';
      }
      if (seen.containsKey(name.toLowerCase())) {
        final count = seen[name.toLowerCase()]! + 1;
        seen[name.toLowerCase()] = count;
        result.add('${name}_$count');
      } else {
        seen[name.toLowerCase()] = 0;
        result.add(name);
      }
    }
    return result;
  }

  void _inferColumnTypes(List<SchemaColumn> columns, List<Map<String, dynamic>> records) {
    if (records.isEmpty) return;
    for (final col in columns) {
      final values = records
          .map((r) => r[col.name])
          .where((v) => v != null && v.toString().trim().isNotEmpty)
          .map((v) => v.toString().trim())
          .toList();
      if (values.isEmpty) continue;

      final uniqueValues = values.toSet().toList()..sort();

      if (uniqueValues.length >= 2 &&
          (uniqueValues.length <= 25 || (uniqueValues.length / records.length) <= 0.25)) {
        col.type = ColumnType.dropdown;
        col.dropdownOptions = uniqueValues;
      }
    }
  }

  Future<void> _logOut(BuildContext context) async {
    await FirebaseAuth.instance.signOut();
    if (context.mounted) {
      Navigator.popUntil(context, (route) => route.isFirst);
    }
  }

  @override
  Widget build(BuildContext context) {
    final w = MediaQuery.of(context).size.width;
    final p = pagePadding(w);
    final isWide = isDesktopWidth(w);
    final user = FirebaseAuth.instance.currentUser;

    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFFF0F2FF), Color(0xFFFFFFFF)],
            begin: Alignment.topCenter, end: Alignment.bottomCenter,
          ),
        ),
        child: SafeArea(
        child: SingleChildScrollView(
          padding: EdgeInsets.all(p),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 720),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const SizedBox(height: 24),
                            Text('Hello${user?.displayName != null ? ', ${user!.displayName}' : ''}!', style: GoogleFonts.inter(fontSize: 28, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
                            const SizedBox(height: 4),
                            Text('What would you like to do today?', style: GoogleFonts.inter(fontSize: 15, color: AppColors.textSecondary)),
                          ],
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.logout_rounded, size: 20),
                        color: AppColors.textMuted,
                        onPressed: () => _logOut(context),
                        tooltip: 'Sign out',
                      ),
                    ],
                  ),
                  const SizedBox(height: 28),
                  if (isWide)
                    Row(
                      children: [
                        Expanded(child: _ActionCard(
                          icon: Icons.add_circle_outline,
                          title: 'Create New File',
                          subtitle: 'Define columns and start entering data',
                          onTap: () => Navigator.pushNamed(context, SchemaRoute.schema),
                        )),
                        const SizedBox(width: 16),
                        Expanded(child: _ActionCard(
                          icon: Icons.file_upload_outlined,
                          title: 'Import CSV',
                          subtitle: 'Upload a CSV file and map its columns',
                          onTap: () => _importCsv(context),
                        )),
                        const SizedBox(width: 16),
                        Expanded(child: _ActionCard(
                          icon: Icons.table_chart_outlined,
                          title: 'Import Excel',
                          subtitle: 'Upload an .xlsx file and map its columns',
                          onTap: () => _importXlsx(context),
                        )),
                      ],
                    )
                  else
                    Column(
                      children: [
                        _ActionCard(
                          icon: Icons.add_circle_outline,
                          title: 'Create New File',
                          subtitle: 'Define columns and start entering data',
                          onTap: () => Navigator.pushNamed(context, SchemaRoute.schema),
                        ),
                        const SizedBox(height: 12),
                        _ActionCard(
                          icon: Icons.file_upload_outlined,
                          title: 'Import CSV',
                          subtitle: 'Upload a CSV file and map its columns',
                          onTap: () => _importCsv(context),
                        ),
                        const SizedBox(height: 12),
                        _ActionCard(
                          icon: Icons.table_chart_outlined,
                          title: 'Import Excel',
                          subtitle: 'Upload an .xlsx file and map its columns',
                          onTap: () => _importXlsx(context),
                        ),
                      ],
                    ),
                  const SizedBox(height: 36),
                  Row(
                    children: [
                      Text(
                        'Your Projects',
                        style: GoogleFonts.inter(fontSize: 18, fontWeight: FontWeight.w600, color: AppColors.textPrimary),
                      ),
                      const Spacer(),
                      TextButton.icon(
                        icon: Icon(_sortByLastUpdated ? Icons.access_time_rounded : Icons.sort_by_alpha_rounded, size: 16),
                        label: Text(_sortByLastUpdated ? 'Recent' : 'Name', style: GoogleFonts.inter(fontSize: 13)),
                        style: TextButton.styleFrom(
                          foregroundColor: AppColors.primary,
                        ),
                        onPressed: () => setState(() => _sortByLastUpdated = !_sortByLastUpdated),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _searchCtrl,
                    onChanged: (v) => setState(() => _searchQuery = v),
                    style: GoogleFonts.inter(fontSize: 14, color: AppColors.textPrimary),
                    decoration: InputDecoration(
                      hintText: 'Search projects...',
                      hintStyle: GoogleFonts.inter(color: AppColors.textMuted, fontSize: 14),
                      prefixIcon: const Icon(Icons.search_rounded, color: AppColors.textMuted, size: 18),
                      suffixIcon: _searchQuery.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.close_rounded, size: 16),
                              onPressed: () {
                                _searchCtrl.clear();
                                setState(() => _searchQuery = '');
                              },
                            )
                          : null,
                      filled: true,
                      fillColor: AppColors.surface,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
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
                  const SizedBox(height: 16),
                  StreamBuilder(
                    stream: databaseService.watchProjects(),
                    builder: (context, snapshot) {
                      if (snapshot.connectionState == ConnectionState.waiting) {
                        return Column(
                          children: List.generate(3, (_) => const Padding(
                            padding: EdgeInsets.only(bottom: 8),
                            child: ShimmerLoading(width: double.infinity, height: 72),
                          )),
                        );
                      }
                      if (snapshot.hasError) {
                        return Padding(
                          padding: const EdgeInsets.all(16),
                          child: Text('Error loading projects: ${snapshot.error}',
                              style: GoogleFonts.inter(color: AppColors.error)),
                        );
                      }
                      final rawProjects = snapshot.data?.docs.map((d) => ProjectData.fromSnapshot(d)).toList() ?? [];
                      
                      final q = _searchQuery.toLowerCase();
                      final projects = rawProjects.where((p) {
                        return p.fileName.toLowerCase().contains(q);
                      }).toList();

                      if (_sortByLastUpdated) {
                        projects.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
                      } else {
                        projects.sort((a, b) => a.fileName.toLowerCase().compareTo(b.fileName.toLowerCase()));
                      }

                      if (projects.isEmpty) {
                        return Container(
                          padding: const EdgeInsets.all(32),
                          decoration: glassCard(),
                          child: Center(
                            child: Column(
                              children: [
                                Icon(Icons.folder_open_rounded, size: 48, color: AppColors.textMuted.withValues(alpha: 0.5)),
                                const SizedBox(height: 12),
                                Text(_searchQuery.isEmpty ? 'No projects yet' : 'No matching projects found',
                                    style: GoogleFonts.inter(fontSize: 15, color: AppColors.textSecondary)),
                                const SizedBox(height: 4),
                                Text(_searchQuery.isEmpty ? 'Create a new file or import a CSV to get started.' : 'Try a different search query.',
                                    style: GoogleFonts.inter(fontSize: 13, color: AppColors.textMuted)),
                              ],
                            ),
                          ),
                        );
                      }
                      return ListView.separated(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: projects.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 8),
                        itemBuilder: (_, i) {
                          final project = projects[i];
                          return _ProjectTile(
                            project: project,
                            formattedUpdateDate: formatTimestamp(project.updatedAt),
                            onTap: () => Navigator.pushNamed(context, SchemaRoute.finalScreen, arguments: {
                              'projectId': project.id,
                              'fileName': project.fileName,
                              'columns': project.columns,
                            }),
                            onDelete: () => _deleteProject(context, project.id),
                          );
                        },
                      );
                    },
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

  Future<void> _deleteProject(BuildContext context, String projectId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: Text('Delete project?', style: GoogleFonts.inter(color: AppColors.textPrimary, fontWeight: FontWeight.w600)),
        content: Text('All records will be permanently deleted.', style: GoogleFonts.inter(color: AppColors.textSecondary)),
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
    if (confirmed == true && context.mounted) {
      await databaseService.deleteProject(projectId);
    }
  }
}

class _ActionCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _ActionCard({required this.icon, required this.title, required this.subtitle, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return ScaleButton(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(24),
        decoration: glassCard(),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: AppColors.primaryLight, borderRadius: BorderRadius.circular(8)),
              child: Icon(icon, size: 28, color: AppColors.primary),
            ),
            const SizedBox(height: 16),
            Text(title, style: GoogleFonts.inter(fontSize: 18, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
            const SizedBox(height: 4),
            Text(subtitle, style: GoogleFonts.inter(fontSize: 13, color: AppColors.textSecondary)),
          ],
        ),
      ),
    );
  }
}

class _ProjectTile extends StatelessWidget {
  final ProjectData project;
  final String formattedUpdateDate;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  const _ProjectTile({
    required this.project,
    required this.formattedUpdateDate,
    required this.onTap,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return ScaleButton(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(color: AppColors.primaryLight, borderRadius: BorderRadius.circular(8)),
              child: const Icon(Icons.table_chart_outlined, size: 20, color: AppColors.primary),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(project.fileName, style: GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
                  const SizedBox(height: 2),
                  Text('${project.columns.length} columns  •  Updated $formattedUpdateDate', style: GoogleFonts.inter(fontSize: 12, color: AppColors.textMuted)),
                ],
              ),
            ),
            IconButton(
              icon: const Icon(Icons.delete_outline_rounded, size: 18, color: AppColors.textMuted),
              onPressed: onDelete,
              splashRadius: 18,
            ),
            const Icon(Icons.chevron_right_rounded, size: 20, color: AppColors.textMuted),
          ],
        ),
      ),
    );
  }
}
