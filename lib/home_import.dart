import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_application_1/shared.dart';
import 'package:flutter_application_1/database.dart';
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

  Future<void> _logOut(BuildContext context) async {
    await FirebaseAuth.instance.signOut();
    if (context.mounted) {
      Navigator.pushReplacementNamed(context, SchemaRoute.login);
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
                  const SizedBox(height: 36),
                  Text(
                    'Your Projects',
                    style: GoogleFonts.inter(fontSize: 18, fontWeight: FontWeight.w600, color: AppColors.textPrimary),
                  ),
                  const SizedBox(height: 12),
                  StreamBuilder(
                    stream: databaseService.watchProjects(),
                    builder: (context, snapshot) {
                      if (snapshot.connectionState == ConnectionState.waiting) {
                        return const Center(
                          child: Padding(
                            padding: EdgeInsets.all(32),
                            child: CircularProgressIndicator(),
                          ),
                        );
                      }
                      if (snapshot.hasError) {
                        return Padding(
                          padding: const EdgeInsets.all(16),
                          child: Text('Error loading projects: ${snapshot.error}',
                              style: GoogleFonts.inter(color: AppColors.error)),
                        );
                      }
                      final projects = snapshot.data?.docs ?? [];
                      if (projects.isEmpty) {
                        return Container(
                          padding: const EdgeInsets.all(32),
                          decoration: glassCard(),
                          child: Center(
                            child: Column(
                              children: [
                                Icon(Icons.folder_open_rounded, size: 48, color: AppColors.textMuted.withValues(alpha: 0.5)),
                                const SizedBox(height: 12),
                                Text('No projects yet',
                                    style: GoogleFonts.inter(fontSize: 15, color: AppColors.textSecondary)),
                                const SizedBox(height: 4),
                                Text('Create a new file or import a CSV to get started.',
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
                          final project = ProjectData.fromSnapshot(projects[i]);
                          return _ProjectTile(
                            project: project,
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
  final VoidCallback onTap;
  final VoidCallback onDelete;

  const _ProjectTile({required this.project, required this.onTap, required this.onDelete});

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
                  Text('${project.columns.length} columns', style: GoogleFonts.inter(fontSize: 12, color: AppColors.textMuted)),
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
