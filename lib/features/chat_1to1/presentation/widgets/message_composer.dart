import 'package:flutter/material.dart';

class MessageComposer extends StatefulWidget {
  const MessageComposer({
    super.key,
    required this.onSend,
    required this.onChanged,
    this.onAttach,
    this.isSendingAttachment = false,
  });

  final ValueChanged<String> onSend;
  final ValueChanged<String> onChanged;
  final VoidCallback? onAttach;
  final bool isSendingAttachment;

  @override
  State<MessageComposer> createState() => _MessageComposerState();
}

class _MessageComposerState extends State<MessageComposer> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final text = _controller.text;
    if (text.trim().isEmpty) return;
    widget.onSend(text);
    _controller.clear();
    widget.onChanged('');
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (widget.isSendingAttachment) const LinearProgressIndicator(minHeight: 2),
          Padding(
            padding: const EdgeInsets.all(8),
            child: Row(
              children: [
                if (widget.onAttach != null)
                  IconButton(
                    onPressed: widget.isSendingAttachment ? null : widget.onAttach,
                    icon: const Icon(Icons.attach_file),
                  ),
                Expanded(
                  child: TextField(
                    controller: _controller,
                    minLines: 1,
                    maxLines: 5,
                    onChanged: widget.onChanged,
                    decoration: InputDecoration(
                      hintText: 'Message',
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(24)),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    ),
                    onSubmitted: (_) => _submit(),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.filled(onPressed: _submit, icon: const Icon(Icons.send)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
