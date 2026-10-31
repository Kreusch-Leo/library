import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:material_ui/material_ui.dart';

import '../../data/models.dart';
import '../theme.dart';

/// Result of editing an annotation.
sealed class AnnotationEdit {
  const AnnotationEdit();
}

class AnnotationSaved extends AnnotationEdit {
  const AnnotationSaved({required this.note, required this.color});
  final String note;
  final int color;
}

class AnnotationDeleted extends AnnotationEdit {
  const AnnotationDeleted();
}

/// Bottom sheet for writing a markdown note on a highlighted passage.
///
/// Returns `null` when dismissed without saving.
Future<AnnotationEdit?> showAnnotationEditor(
  BuildContext context, {
  required String quote,
  String initialNote = '',
  int initialColor = Annotation.defaultColor,
  bool canDelete = false,
  String? sectionLabel,
}) {
  return showModalBottomSheet<AnnotationEdit>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (context) => _AnnotationEditor(
      quote: quote,
      initialNote: initialNote,
      initialColor: initialColor,
      canDelete: canDelete,
      sectionLabel: sectionLabel,
    ),
  );
}

class _AnnotationEditor extends StatefulWidget {
  const _AnnotationEditor({
    required this.quote,
    required this.initialNote,
    required this.initialColor,
    required this.canDelete,
    this.sectionLabel,
  });

  final String quote;
  final String initialNote;
  final int initialColor;
  final bool canDelete;
  final String? sectionLabel;

  @override
  State<_AnnotationEditor> createState() => _AnnotationEditorState();
}

class _AnnotationEditorState extends State<_AnnotationEditor> {
  late final _controller = TextEditingController(text: widget.initialNote);
  late int _color = widget.initialColor;
  bool _preview = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _save() => Navigator.pop(
    context,
    AnnotationSaved(note: _controller.text.trim(), color: _color),
  );

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 0, 20, 16 + bottomInset),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          QuoteBlock(
            text: widget.quote,
            color: Color(_color),
            caption: widget.sectionLabel,
            maxLines: 6,
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              for (final c in Annotation.palette)
                Padding(
                  padding: const EdgeInsets.only(right: 10),
                  child: _ColorDot(
                    color: Color(c),
                    selected: c == _color,
                    onTap: () => setState(() => _color = c),
                  ),
                ),
              const Spacer(),
              SegmentedButton<bool>(
                showSelectedIcon: false,
                style: const ButtonStyle(visualDensity: VisualDensity.compact),
                segments: const [
                  ButtonSegment(value: false, label: Text('Write')),
                  ButtonSegment(value: true, label: Text('Preview')),
                ],
                selected: {_preview},
                onSelectionChanged: (s) => setState(() => _preview = s.first),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 140, maxHeight: 320),
            child: _preview
                ? Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: HearthColors.surfaceHigh,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: SingleChildScrollView(
                      child: _controller.text.trim().isEmpty
                          ? const Text(
                              'Nothing to preview yet.',
                              style: TextStyle(color: HearthColors.textFaint),
                            )
                          : MarkdownBody(data: _controller.text),
                    ),
                  )
                : TextField(
                    controller: _controller,
                    autofocus: widget.initialNote.isEmpty,
                    maxLines: null,
                    minLines: 6,
                    keyboardType: TextInputType.multiline,
                    style: const TextStyle(height: 1.45),
                    decoration: const InputDecoration(
                      hintText:
                          'Write a note… Markdown works: **bold**, '
                          '*italic*, - lists, > quotes',
                      hintStyle: TextStyle(color: HearthColors.textFaint),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.all(Radius.circular(6)),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              if (widget.canDelete)
                TextButton.icon(
                  onPressed: () =>
                      Navigator.pop(context, const AnnotationDeleted()),
                  icon: const Icon(Icons.delete_outline),
                  label: const Text('Delete highlight'),
                  style: TextButton.styleFrom(
                    foregroundColor: const Color(0xFFE08A80),
                  ),
                ),
              const Spacer(),
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel'),
              ),
              const SizedBox(width: 8),
              FilledButton(onPressed: _save, child: const Text('Save')),
            ],
          ),
        ],
      ),
    );
  }
}

class _ColorDot extends StatelessWidget {
  const _ColorDot({
    required this.color,
    required this.selected,
    required this.onTap,
  });

  final Color color;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      label: 'Highlight colour',
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          width: 26,
          height: 26,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            border: Border.all(
              color: selected ? HearthColors.text : Colors.transparent,
              width: 2,
            ),
          ),
        ),
      ),
    );
  }
}

/// A highlighted passage, shown as a quote with a coloured rule.
class QuoteBlock extends StatelessWidget {
  const QuoteBlock({
    super.key,
    required this.text,
    required this.color,
    this.caption,
    this.maxLines,
  });

  final String text;
  final Color color;
  final String? caption;
  final int? maxLines;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 10, 12, 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        border: Border(left: BorderSide(color: color, width: 3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            text,
            maxLines: maxLines,
            overflow: maxLines == null ? null : TextOverflow.ellipsis,
            style: const TextStyle(
              fontFamily: kSerifFont,
              fontStyle: FontStyle.italic,
              color: HearthColors.text,
              height: 1.45,
            ),
          ),
          if (caption != null) ...[
            const SizedBox(height: 6),
            Text(
              caption!,
              style: const TextStyle(
                color: HearthColors.textFaint,
                fontSize: 12,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
