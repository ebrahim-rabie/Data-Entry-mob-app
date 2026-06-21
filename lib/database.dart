import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_application_1/shared.dart';

class DatabaseService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  String get _userId => FirebaseAuth.instance.currentUser?.uid ?? '';

  CollectionReference<Map<String, dynamic>> get _projects =>
      _db.collection('users').doc(_userId).collection('projects');

  Future<String> createProject(String fileName, List<SchemaColumn> columns) async {
    final doc = await _projects.add({
      'fileName': fileName,
      'columns': columns.map((c) => c.toJson()).toList(),
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
    return doc.id;
  }

  Future<void> updateSchema(String projectId, List<SchemaColumn> columns, {String? fileName}) async {
    final update = <String, dynamic>{
      'columns': columns.map((c) => c.toJson()).toList(),
      'updatedAt': FieldValue.serverTimestamp(),
    };
    if (fileName != null) update['fileName'] = fileName;
    await _projects.doc(projectId).update(update);
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> watchProjects() =>
      _projects.orderBy('updatedAt', descending: true).snapshots();

  Future<ProjectData?> getProject(String projectId) async {
    final doc = await _projects.doc(projectId).get();
    if (!doc.exists) return null;
    return ProjectData.fromSnapshot(doc);
  }

  Future<void> deleteProject(String projectId) async {
    final batch = _db.batch();
    batch.delete(_projects.doc(projectId));
    final records = await _projects.doc(projectId).collection('records').get();
    for (final r in records.docs) {
      batch.delete(r.reference);
    }
    await batch.commit();
  }

  CollectionReference<Map<String, dynamic>> _recordsRef(String projectId) =>
      _projects.doc(projectId).collection('records');

  Future<String> addRecord(String projectId, Map<String, dynamic> data) async {
    final doc = await _recordsRef(projectId).add(data);
    return doc.id;
  }

  Future<void> updateRecord(String projectId, String recordId, Map<String, dynamic> data) async {
    await _recordsRef(projectId).doc(recordId).update(data);
  }

  Future<void> deleteRecord(String projectId, String recordId) async {
    await _recordsRef(projectId).doc(recordId).delete();
  }

  Future<void> deleteRecords(String projectId, List<String> recordIds) async {
    final batch = _db.batch();
    for (final id in recordIds) {
      batch.delete(_recordsRef(projectId).doc(id));
    }
    await batch.commit();
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> watchRecords(String projectId) =>
      _recordsRef(projectId).snapshots();

  Future<List<RecordData>> getAllRecords(String projectId) async {
    final snap = await _recordsRef(projectId).get();
    return snap.docs.map((d) => RecordData.fromSnapshot(d)).toList();
  }

  Future<void> importRecords(String projectId, List<Map<String, dynamic>> records) async {
    final batch = _db.batch();
    for (final r in records) {
      batch.set(_recordsRef(projectId).doc(), r);
    }
    await batch.commit();
  }
}

final DatabaseService databaseService = DatabaseService();
