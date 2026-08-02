import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../../core/sync/local_sync_store.dart';

typedef AccountDataDirectoryProvider = Future<Directory> Function();

class LocalAccountDataCleaner {
  LocalAccountDataCleaner(
    this._store, {
    AccountDataDirectoryProvider? documentsDirectory,
    AccountDataDirectoryProvider? cacheDirectory,
  }) : _documentsDirectory =
           documentsDirectory ?? getApplicationDocumentsDirectory,
       _cacheDirectory = cacheDirectory ?? getApplicationCacheDirectory;

  static const _pendingMarkerName =
      '.homepilot-account-deletion-cleanup-pending';
  static const _documentDirectories = [
    'photos',
    'profile',
    'cloud_media',
    'backups',
  ];
  static const _documentFiles = ['homepilot-backup-state.json'];
  static const _cacheDirectories = ['avatars'];

  final LocalSyncStore _store;
  final AccountDataDirectoryProvider _documentsDirectory;
  final AccountDataDirectoryProvider _cacheDirectory;

  Future<void> clearAfterCloudDeletion(String userId) async {
    final account = await _store.account();
    if (account.boundUserId != null && account.boundUserId != userId) {
      throw StateError('Local data belongs to a different cloud identity.');
    }

    final documents = await _documentsDirectory();
    await documents.create(recursive: true);
    final marker = _marker(documents);
    await marker.writeAsString('pending', flush: true);
    await _clear(documents: documents, expectedUserId: userId);
    if (await marker.exists()) await marker.delete();
  }

  Future<bool> resumePendingCleanup() async {
    final documents = await _documentsDirectory();
    final marker = _marker(documents);
    if (!await marker.exists()) return false;
    await _clear(documents: documents);
    if (await marker.exists()) await marker.delete();
    return true;
  }

  Future<void> _clear({
    required Directory documents,
    String? expectedUserId,
  }) async {
    await _store.clearAllAccountData(expectedUserId: expectedUserId);
    for (final name in _documentDirectories) {
      await _deleteDirectoryWithin(documents, name);
    }
    for (final name in _documentFiles) {
      await _deleteFileWithin(documents, name);
    }
    final cache = await _cacheDirectory();
    for (final name in _cacheDirectories) {
      await _deleteDirectoryWithin(cache, name);
    }
  }

  File _marker(Directory documents) =>
      File(p.join(documents.path, _pendingMarkerName));

  Future<void> _deleteDirectoryWithin(Directory root, String name) async {
    final target = Directory(p.normalize(p.join(root.path, name)));
    if (!p.isWithin(p.normalize(root.path), target.path)) {
      throw StateError('Account cleanup path escaped app storage.');
    }
    if (await target.exists()) await target.delete(recursive: true);
  }

  Future<void> _deleteFileWithin(Directory root, String name) async {
    final target = File(p.normalize(p.join(root.path, name)));
    if (!p.isWithin(p.normalize(root.path), target.path)) {
      throw StateError('Account cleanup path escaped app storage.');
    }
    if (await target.exists()) await target.delete();
  }
}
