import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';

import '../../models/walk_models.dart';
import '../../state/walk_providers.dart';

/// Saved walks from Room with GPX view / share / export (Blueprint 30% scope).
class GpxHistoryScreen extends ConsumerWidget {
  const GpxHistoryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sessionsAsync = ref.watch(sessionsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('GPX History'),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            icon: const Icon(Icons.refresh),
            onPressed: () => ref.read(sessionsProvider.notifier).refresh(),
          ),
        ],
      ),
      body: sessionsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Failed to load sessions:\n$e')),
        data: (sessions) {
          if (sessions.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.route, size: 64, color: Color(0xFF10B981)),
                    const SizedBox(height: 16),
                    const Text(
                      'No saved walks yet',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Record a walk on the Live Map, or generate a demo Abbottabad walk for the presentation.',
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 16),
                    FilledButton.icon(
                      onPressed: () async {
                        await ref.read(sessionsProvider.notifier).generateDemoWalk();
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Demo walk generated')),
                          );
                        }
                      },
                      icon: const Icon(Icons.science),
                      label: const Text('Generate demo walk'),
                    ),
                  ],
                ),
              ),
            );
          }
          return RefreshIndicator(
            onRefresh: () => ref.read(sessionsProvider.notifier).refresh(),
            child: ListView.builder(
              itemCount: sessions.length,
              itemBuilder: (context, i) {
                final s = sessions[i];
                return _SessionCard(session: s);
              },
            ),
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
          await ref.read(sessionsProvider.notifier).generateDemoWalk();
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Demo walk generated')),
            );
          }
        },
        icon: const Icon(Icons.science),
        label: const Text('Demo walk'),
      ),
    );
  }
}

class _SessionCard extends ConsumerWidget {
  final WalkSession session;
  const _SessionCard({required this.session});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dateFmt = DateFormat('dd MMM yyyy, hh:mm a');
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: ListTile(
        leading: const CircleAvatar(
          backgroundColor: Color(0xFF10B981),
          child: Icon(Icons.route, color: Colors.white),
        ),
        title: Text(session.title, maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: Text(
          '${dateFmt.format(session.startDateTime)} • '
          '${session.totalSteps} steps • ${formatDistance(session.totalDistanceMeters)} • '
          '${formatMmSs(session.movingDurationMs)}',
        ),
        trailing: Chip(label: Text(session.status)),
        onTap: () => _openDetail(context, ref),
      ),
    );
  }

  Future<void> _openDetail(BuildContext context, WidgetRef ref) async {
    showDialog<void>(
      context: context,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );
    try {
      final detail = await ref.read(sessionsProvider.notifier).getDetail(session.sessionId);
      if (context.mounted) Navigator.pop(context);
      if (!context.mounted) return;
      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        builder: (ctx) => _DetailSheet(detail: detail, session: session),
      );
    } catch (e) {
      if (context.mounted) Navigator.pop(context);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to load detail: $e')),
        );
      }
    }
  }
}

class _DetailSheet extends ConsumerWidget {
  final SessionDetail detail;
  final WalkSession session;
  const _DetailSheet({required this.detail, required this.session});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.85,
      builder: (_, controller) => ListView(
        controller: controller,
        padding: const EdgeInsets.all(16),
        children: [
          Text(session.title, style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 4),
          Text(
            '${detail.pointCount} points • ${detail.hexPolygons.length} hex cells • ${session.status}',
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: () async {
                    try {
                      final saved = await ref
                          .read(sessionsProvider.notifier)
                          .exportToDownloads(session.sessionId);
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('Saved to $saved')),
                        );
                      }
                    } catch (e) {
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('Export failed: $e')),
                        );
                      }
                    }
                  },
                  icon: const Icon(Icons.download),
                  label: const Text('Export to Downloads'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () {
                    if (detail.gpxFilePath.isNotEmpty) {
                      Share.shareXFiles([XFile(detail.gpxFilePath)], text: session.title);
                    } else {
                      Share.share(detail.gpxXml, subject: session.title);
                    }
                  },
                  icon: const Icon(Icons.share),
                  label: const Text('Share GPX'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text('GPX 1.1 XML', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.grey.shade100,
              borderRadius: BorderRadius.circular(8),
            ),
            child: SelectableText(
              detail.gpxXml.isEmpty ? '(no GPX content)' : detail.gpxXml,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 11),
            ),
          ),
        ],
      ),
    );
  }
}
