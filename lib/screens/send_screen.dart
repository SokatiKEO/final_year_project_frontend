// lib/screens/send_screen.dart

import 'dart:io';
import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/discovered_device.dart';
import '../models/transfer_file.dart';
import '../providers/transfer_provider.dart';
import 'progress_screen.dart';

class SendScreen extends StatefulWidget {
  final List<DiscoveredDevice> devices;
  final List<TransferFile> initialFiles;

  const SendScreen({
    super.key,
    required this.devices,
    this.initialFiles = const [],
  });

  @override
  State<SendScreen> createState() => _SendScreenState();
}

class _SendScreenState extends State<SendScreen> {
  final List<TransferFile> _selectedFiles = [];
  bool _picking = false;
  bool _dropHovering = false;

  @override
  void initState() {
    super.initState();
    if (widget.initialFiles.isNotEmpty) {
      _selectedFiles.addAll(widget.initialFiles);
    }
  }

  Future<void> _onDropped(List<String> paths) async {
    for (final path in paths) {
      final f = File(path);
      if (await f.exists()) {
        final tf = await TransferFile.fromFile(f);
        if (mounted) setState(() => _selectedFiles.add(tf));
      }
    }
  }

  int get _totalBytes =>
      _selectedFiles.fold(0, (sum, f) => sum + f.sizeBytes);

  String get _totalLabel {
    if (_totalBytes < 1024 * 1024)
      return '${(_totalBytes / 1024).toStringAsFixed(1)} KB';
    return '${(_totalBytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  Future<void> _pickFiles() async {
    setState(() => _picking = true);
    try {
      final result = await FilePicker.platform.pickFiles(allowMultiple: true);
      if (result != null) {
        for (final pf in result.files) {
          if (pf.path != null) {
            final tf = await TransferFile.fromFile(File(pf.path!));
            setState(() => _selectedFiles.add(tf));
          }
        }
      }
    } finally {
      setState(() => _picking = false);
    }
  }

  void _removeFile(TransferFile file) {
    setState(() => _selectedFiles.remove(file));
  }

  Future<void> _send() async {
    if (_selectedFiles.isEmpty) return;

    final provider = context.read<TransferProvider>();
    await provider.sendFiles(devices: widget.devices, files: _selectedFiles);

    if (mounted) {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const ProgressScreen()),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDesktop =
        Platform.isWindows || Platform.isMacOS || Platform.isLinux;
    final isMulti = widget.devices.length > 1;

    final scaffold = Scaffold(
      backgroundColor: const Color(0xFF080C14),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Nav header ───────────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
              child: Row(
                children: [
                  GestureDetector(
                    onTap: () => Navigator.pop(context),
                    child: Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: const Color(0xFF0E1422),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: Colors.white.withOpacity(0.07),
                        ),
                      ),
                      child: const Icon(
                        Icons.arrow_back_ios_new_rounded,
                        color: Colors.white,
                        size: 15,
                      ),
                    ),
                  ),
                  const SizedBox(width: 14),
                  const Text(
                    'Send Files',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 16),

            // ── Sending to (single or multi) ─────────────────────────────────
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: isMulti
                  ? _MultiDeviceChips(devices: widget.devices)
                  : _SingleDeviceCard(device: widget.devices.first),
            ),

            const SizedBox(height: 20),

            // ── Selected files list ──────────────────────────────────────────
            Expanded(
              child: _selectedFiles.isEmpty
                  ? _EmptyPicker(onPick: _pickFiles, picking: _picking)
                  : ListView(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      children: [
                        const Text(
                          'SELECTED FILES',
                          style: TextStyle(
                            color: Color(0xFF5A6580),
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 1.2,
                          ),
                        ),
                        const SizedBox(height: 10),
                        ..._selectedFiles.map((f) => _FileRow(
                              file: f,
                              onRemove: () => _removeFile(f),
                            )),
                        const SizedBox(height: 10),
                        GestureDetector(
                          onTap: _pickFiles,
                          child: Container(
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: const Color(0xFF0E1422),
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(
                                color: Colors.white.withOpacity(0.07),
                              ),
                            ),
                            child: const Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.add,
                                    color: Color(0xFF5A6580), size: 18),
                                SizedBox(width: 6),
                                Text(
                                  'Add more files',
                                  style: TextStyle(
                                    color: Color(0xFF5A6580),
                                    fontSize: 13,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
            ),

            // ── Send button ──────────────────────────────────────────────────
            if (_selectedFiles.isNotEmpty)
              Padding(
                padding: const EdgeInsets.all(20),
                child: GestureDetector(
                  onTap: _send,
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(17),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFF3D7BFF), Color(0xFF5B9BFF)],
                      ),
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFF3D7BFF).withOpacity(0.35),
                          blurRadius: 20,
                          offset: const Offset(0, 8),
                        )
                      ],
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          isMulti
                              ? 'Drop to ${widget.devices.length} devices · $_totalLabel'
                              : 'Drop ${_selectedFiles.length} file${_selectedFiles.length == 1 ? '' : 's'} · $_totalLabel',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );

    if (!isDesktop) return scaffold;

    return DropTarget(
      onDragEntered: (_) => setState(() => _dropHovering = true),
      onDragExited: (_) => setState(() => _dropHovering = false),
      onDragDone: (details) {
        setState(() => _dropHovering = false);
        _onDropped(details.files.map((f) => f.path).toList());
      },
      child: Stack(
        children: [
          scaffold,
          if (_dropHovering)
            Positioned.fill(
              child: Container(
                decoration: BoxDecoration(
                  color: const Color(0xFF3D7BFF).withOpacity(0.12),
                  border: Border.all(
                    color: const Color(0xFF3D7BFF).withOpacity(0.6),
                    width: 2,
                  ),
                ),
                child: const Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.upload_file_rounded,
                        size: 48, color: Color(0xFF3D7BFF)),
                    SizedBox(height: 12),
                    Text(
                      'Drop to add files',
                      style: TextStyle(
                        color: Color(0xFF3D7BFF),
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ── Single device header ──────────────────────────────────────────────────────

class _SingleDeviceCard extends StatelessWidget {
  final DiscoveredDevice device;
  const _SingleDeviceCard({required this.device});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            const Color(0xFF3D7BFF).withOpacity(0.1),
            const Color(0xFF00E5C0).withOpacity(0.05),
          ],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF3D7BFF).withOpacity(0.25)),
      ),
      child: Row(
        children: [
          Icon(device.platformIcon, size: 26, color: const Color(0xFF3D7BFF)),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Sending to',
                style: TextStyle(color: Color(0xFF5A6580), fontSize: 11),
              ),
              Text(
                device.name,
                style: const TextStyle(
                  color: Color(0xFF3D7BFF),
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ── Multi device chips ────────────────────────────────────────────────────────

class _MultiDeviceChips extends StatelessWidget {
  final List<DiscoveredDevice> devices;
  const _MultiDeviceChips({required this.devices});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            const Color(0xFF3D7BFF).withOpacity(0.1),
            const Color(0xFF00E5C0).withOpacity(0.05),
          ],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF3D7BFF).withOpacity(0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'SENDING TO ${devices.length} DEVICES',
            style: const TextStyle(
              color: Color(0xFF5A6580),
              fontSize: 10,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: devices.map((d) => _DeviceChip(device: d)).toList(),
          ),
        ],
      ),
    );
  }
}

class _DeviceChip extends StatelessWidget {
  final DiscoveredDevice device;
  const _DeviceChip({required this.device});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFF3D7BFF).withOpacity(0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFF3D7BFF).withOpacity(0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(device.platformIcon, size: 13, color: const Color(0xFF3D7BFF)),
          const SizedBox(width: 5),
          Text(
            device.name,
            style: const TextStyle(
              color: Color(0xFF3D7BFF),
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

// ── File row ──────────────────────────────────────────────────────────────────

class _FileRow extends StatelessWidget {
  final TransferFile file;
  final VoidCallback onRemove;
  const _FileRow({required this.file, required this.onRemove});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF0E1422),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withOpacity(0.07)),
      ),
      child: Row(
        children: [
          Text(file.emoji, style: const TextStyle(fontSize: 24)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  file.name,
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.w600),
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  file.sizeLabel,
                  style: const TextStyle(
                      color: Color(0xFF5A6580), fontSize: 11),
                ),
              ],
            ),
          ),
          GestureDetector(
            onTap: onRemove,
            child:
                const Icon(Icons.close, color: Color(0xFF5A6580), size: 18),
          ),
        ],
      ),
    );
  }
}

// ── Empty picker ──────────────────────────────────────────────────────────────

class _EmptyPicker extends StatelessWidget {
  final VoidCallback onPick;
  final bool picking;
  const _EmptyPicker({required this.onPick, required this.picking});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('📂', style: TextStyle(fontSize: 48)),
          const SizedBox(height: 16),
          const Text(
            'No files selected',
            style: TextStyle(
                color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 6),
          const Text(
            'Tap below to pick files to send',
            style: TextStyle(color: Color(0xFF5A6580), fontSize: 13),
          ),
          const SizedBox(height: 24),
          GestureDetector(
            onTap: picking ? null : onPick,
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 28, vertical: 14),
              decoration: BoxDecoration(
                color: const Color(0xFF0E1422),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                    color: const Color(0xFF3D7BFF).withOpacity(0.3)),
              ),
              child: picking
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Color(0xFF3D7BFF)),
                    )
                  : const Text(
                      'Browse Files',
                      style: TextStyle(
                          color: Color(0xFF3D7BFF),
                          fontWeight: FontWeight.w700),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}