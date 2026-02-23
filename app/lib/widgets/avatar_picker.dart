import 'package:flutter/material.dart';
import 'dart:io';
import 'package:image_picker/image_picker.dart';
import '../core/l10n.dart';

class AvatarPicker extends StatefulWidget {
  final ValueChanged<String?>? onChanged;
  final String? initialPath;

  const AvatarPicker({
    super.key,
    this.onChanged,
    this.initialPath,
  });

  @override
  State<AvatarPicker> createState() => _AvatarPickerState();
}

class _AvatarPickerState extends State<AvatarPicker> {
  final _picker = ImagePicker();
  String? _selectedPath;

  @override
  void initState() {
    super.initState();
    _selectedPath = widget.initialPath;
  }

  Future<void> _pickImage(ImageSource source) async {
    final picked = await _picker.pickImage(
      source: source,
      maxWidth: 1024,
      maxHeight: 1024,
      imageQuality: 85,
    );
    if (picked == null) return;
    setState(() => _selectedPath = picked.path);
    widget.onChanged?.call(_selectedPath);
  }

  void _clear() {
    setState(() => _selectedPath = null);
    widget.onChanged?.call(null);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Preview
        CircleAvatar(
          radius: 44,
          backgroundColor: Colors.grey.withOpacity(0.15),
          backgroundImage: _selectedPath != null ? FileImage(File(_selectedPath!)) : null,
          child: _selectedPath == null
              ? const Icon(Icons.person, size: 52, color: Colors.grey)
              : null,
        ),
        const SizedBox(height: 12),
        Text(AppL10n.t(context, 'select_avatar'),
            style: const TextStyle(fontSize: 16, color: Colors.grey)),
        const SizedBox(height: 10),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          alignment: WrapAlignment.center,
          children: [
            OutlinedButton.icon(
              onPressed: () => _pickImage(ImageSource.camera),
              icon: const Icon(Icons.photo_camera),
              label: const Text('拍照', style: TextStyle(fontSize: 16)),
            ),
            OutlinedButton.icon(
              onPressed: () => _pickImage(ImageSource.gallery),
              icon: const Icon(Icons.photo_library),
              label: const Text('相册', style: TextStyle(fontSize: 16)),
            ),
            if (_selectedPath != null)
              TextButton.icon(
                onPressed: _clear,
                icon: const Icon(Icons.close),
                label: const Text('清除', style: TextStyle(fontSize: 16)),
              ),
          ],
        ),
      ],
    );
  }
}
