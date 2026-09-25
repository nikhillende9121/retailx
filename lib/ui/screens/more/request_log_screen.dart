import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/formatters.dart';
import '../../../data/request_log.dart';
import '../../theme.dart';
import '../../widgets/common.dart';

/// Every API call this session made, newest first — on-device, no laptop.
///
/// Exists because Android Studio's Network Inspector only instruments the
/// Java/Kotlin HTTP stacks and therefore shows nothing for a Flutter app.
/// Tap a row for the payloads; long-press to copy it.
class RequestLogScreen extends StatelessWidget {
  const RequestLogScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final log = RequestLog.instance;

    return ValueListenableBuilder<int>(
      valueListenable: log.revision,
      builder: (context, _, __) {
        final records = log.records;

        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(kScreenMargin, 12, 8, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      records.isEmpty
                          ? 'No calls yet'
                          : '${records.length} call'
                              '${records.length == 1 ? '' : 's'}'
                              '${log.failureCount > 0 ? ' · ${log.failureCount} failed' : ''}',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                  TextButton.icon(
                    onPressed: records.isEmpty ? null : log.clear,
                    icon: const Icon(Icons.delete_sweep_outlined, size: 18),
                    label: const Text('Clear'),
                  ),
                ],
              ),
            ),
            const _ErrorSection(),
            if (records.isEmpty)
              const Expanded(
                child: EmptyView(
                  icon: Icons.wifi_tethering_rounded,
                  title: 'Nothing recorded yet',
                  message: 'Pull a list, ring up a sale, or sign in again — '
                      'every request shows up here as it happens.',
                ),
              )
            else
              Expanded(
                child: ListView.separated(
                  padding: const EdgeInsets.fromLTRB(
                      kScreenMargin, 0, kScreenMargin, 24),
                  itemCount: records.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (context, index) =>
                      _RecordTile(record: records[index]),
                ),
              ),
          ],
        );
      },
    );
  }
}

/// Framework errors, newest first — shown above the network log because a
/// layout assertion is nearly always more urgent than a request.
class _ErrorSection extends StatelessWidget {
  const _ErrorSection();

  @override
  Widget build(BuildContext context) {
    final log = ErrorLog.instance;
    final scheme = Theme.of(context).colorScheme;

    return ValueListenableBuilder<int>(
      valueListenable: log.revision,
      builder: (context, _, __) {
        final errors = log.records;
        if (errors.isEmpty) return const SizedBox.shrink();

        return Padding(
          padding: const EdgeInsets.fromLTRB(
              kScreenMargin, 0, kScreenMargin, kCardGap),
          child: AppCard(
            statusEdge: scheme.error,
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.error_outline_rounded,
                        size: 18, color: scheme.error),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '${errors.length} framework error'
                        '${errors.length == 1 ? '' : 's'}',
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                    ),
                    TextButton(
                      onPressed: log.clear,
                      child: const Text('Clear'),
                    ),
                  ],
                ),
                for (final error in errors.take(5)) ...[
                  const Divider(height: 14),
                  GestureDetector(
                    onLongPress: () {
                      Clipboard.setData(ClipboardData(
                        text: [
                          error.summary,
                          if (error.widget != null) 'Widget: ${error.widget}',
                          if (error.library != null) 'Library: ${error.library}',
                          if (error.stack != null) error.stack!,
                        ].join('\n\n'),
                      ));
                      showInfoSnack(context, 'Copied to clipboard.');
                    },
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          clock(error.at),
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                        const SizedBox(height: 2),
                        SelectableText(
                          error.summary,
                          style: const TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 11,
                            height: 1.35,
                          ),
                        ),
                        if (error.widget != null) ...[
                          const SizedBox(height: 4),
                          Text(
                            'Widget: ${error.widget}',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: scheme.error,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 6),
                Text(
                  'Long-press an error to copy it.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _RecordTile extends StatelessWidget {
  const _RecordTile({required this.record});

  final RequestRecord record;

  Color _color(ColorScheme scheme) {
    if (record.pending) return scheme.outline;
    if (record.ok) return successColor(scheme.brightness);
    return scheme.error;
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = _color(scheme);

    final details = [
      if (record.requestBody != null) 'Request body\n${record.requestBody}',
      if (record.errorMessage != null) 'Error\n${record.errorMessage}',
      if (record.responsePreview != null) 'Response\n${record.responsePreview}',
    ].join('\n\n');

    return AppCard(
      statusEdge: color,
      padding: const EdgeInsets.all(12),
      child: Theme(
        // The expander shouldn't paint its own divider inside the card.
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: EdgeInsets.zero,
          childrenPadding: const EdgeInsets.only(top: 4),
          title: Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                decoration: BoxDecoration(
                  color: Color.alphaBlend(
                      color.withAlpha(32), scheme.surfaceContainerLowest),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  record.outcome,
                  style: TextStyle(
                    color: color,
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '${record.method} /${record.path}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleSmall,
                ),
              ),
              if (record.fromDemo)
                Container(
                  margin: const EdgeInsets.only(left: 6),
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: scheme.tertiaryContainer,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    'DEMO',
                    style: TextStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.w800,
                      color: scheme.onTertiaryContainer,
                    ),
                  ),
                ),
            ],
          ),
          subtitle: Padding(
            padding: const EdgeInsets.only(top: 3),
            child: Text(
              [
                clock(record.startedAt),
                if (!record.pending) '${record.elapsedMs}ms',
                if ((record.query ?? '').isNotEmpty) record.query!,
              ].join(' · '),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
          children: [
            if (details.isEmpty)
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'No payload recorded.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              )
            else
              GestureDetector(
                onLongPress: () {
                  Clipboard.setData(ClipboardData(
                    text: '${record.method} /${record.path}${record.query ?? ''}'
                        '\n\n$details',
                  ));
                  showInfoSnack(context, 'Copied to clipboard.');
                },
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: scheme.surfaceContainerLow,
                    borderRadius: BorderRadius.circular(kRadiusCard),
                  ),
                  child: SelectableText(
                    details,
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 11,
                      height: 1.4,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
