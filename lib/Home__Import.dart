import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_application_1/shared.dart';
import 'package:file_picker/file_picker.dart';
import 'package:csv/csv.dart';

class HomeImportScreen extends StatelessWidget {
  const HomeImportScreen({super.key});

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
      final headers = rows.first.map((e) => e.toString().trim()).toList();
      final columns = headers.map((h) => SchemaColumn(name: h)).toList();
      final dataRows = rows.skip(1).map((row) {
        final map = <String, dynamic>{};
        for (var i = 0; i < headers.length && i < row.length; i++) {
          map[headers[i]] = row[i];
        }
        return map;
      }).toList();
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

  @override
  Widget build(BuildContext context) {
    final w = MediaQuery.of(context).size.width;
    final p = pagePadding(w);
    final isWide = isDesktopWidth(w);

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
                  const SizedBox(height: 24),
                  Text('Hello!', style: GoogleFonts.inter(fontSize: 28, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
                  const SizedBox(height: 4),
                  Text('What would you like to do today?', style: GoogleFonts.inter(fontSize: 15, color: AppColors.textSecondary)),
                  const SizedBox(height: 40),
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
                      ],
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

class _ActionCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _ActionCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

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
              decoration: BoxDecoration(
                color: AppColors.primaryLight,
                borderRadius: BorderRadius.circular(8),
              ),
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
