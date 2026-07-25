import 'package:flutter/material.dart';
import 'package:gg/controllers.dart';

class EQSheet extends StatefulWidget {
  final EQController eqController;
  final VoidCallback onChanged;

  const EQSheet({
    super.key,
    required this.eqController,
    required this.onChanged,
  });

  @override
  State<EQSheet> createState() => _EQSheetState();
}

class _EQSheetState extends State<EQSheet> {
  String _formatFreq(double freq) {
    if (freq >= 1000) {
      return '${(freq / 1000).toStringAsFixed(0)}k';
    }
    return freq.toStringAsFixed(1).replaceAll('.0', '');
  }

  String _capitalize(String s) => s.isEmpty ? '' : s[0].toUpperCase() + s.substring(1);

  Widget _buildPresetButton(String label, String preset, bool isUser) {
    return Padding(
      padding: const EdgeInsets.only(right: 8.0),
      child: ElevatedButton(
        onPressed: () {
          setState(() {
            widget.eqController.applyPreset(preset);
          });
          widget.onChanged();
        },
        onLongPress: isUser ? () {
          showDialog(
            context: context,
            builder: (context) => AlertDialog(
              title: const Text('Delete Preset?'),
              content: Text('Delete user preset "$label"?'),
              actions: [
                TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
                TextButton(
                  onPressed: () {
                    setState(() {
                      widget.eqController.deleteUserPreset(preset);
                    });
                    Navigator.pop(context);
                  },
                  child: const Text('Delete', style: TextStyle(color: Colors.red)),
                ),
              ],
            ),
          );
        } : null,
        style: ElevatedButton.styleFrom(
          backgroundColor: isUser ? Theme.of(context).colorScheme.primaryContainer : null,
          foregroundColor: isUser ? Theme.of(context).colorScheme.onPrimaryContainer : null,
        ),
        child: Text(label),
      ),
    );
  }

  void _showSavePresetDialog() {
    final TextEditingController nameController = TextEditingController();
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Save Preset'),
          content: TextField(
            controller: nameController,
            decoration: const InputDecoration(hintText: 'Preset Name'),
            autofocus: true,
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
            TextButton(
              onPressed: () {
                final name = nameController.text.trim();
                if (name.isNotEmpty) {
                  setState(() {
                    widget.eqController.saveUserPreset(name);
                  });
                }
                Navigator.pop(context);
              },
              child: const Text('Save'),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16.0),
      height: 420,
      decoration: BoxDecoration(
        color: Colors.grey[950],
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(20),
          topRight: Radius.circular(20),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Equalizer',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.white),
              ),
              IconButton(
                icon: const Icon(Icons.close, color: Colors.white),
                onPressed: () => Navigator.pop(context),
              ),
            ],
          ),
          const SizedBox(height: 10),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                ActionChip(
                  avatar: const Icon(Icons.add, size: 16),
                  label: const Text('Save'),
                  onPressed: _showSavePresetDialog,
                ),
                const SizedBox(width: 12),
                ...widget.eqController.allPresets.keys.map((key) {
                  final isUser = widget.eqController.userPresets.containsKey(key);
                  final label = key == 'bassBoost' ? 'Bass Boost' : _capitalize(key);
                  return _buildPresetButton(label, key, isUser);
                }),
              ],
            ),
          ),
          const SizedBox(height: 20),
          Expanded(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: List.generate(10, (index) {
                final freq = EQController.frequencies[index];
                final gain = widget.eqController.gains[index];

                return Column(
                  children: [
                    Text(
                      '${gain > 0 ? "+" : ""}${gain.toStringAsFixed(1)}',
                      style: const TextStyle(fontSize: 10, color: Colors.grey),
                    ),
                    Expanded(
                      child: RotatedBox(
                        quarterTurns: 3,
                        child: SliderTheme(
                          data: SliderTheme.of(context).copyWith(
                            trackHeight: 2.0,
                            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6.0),
                            overlayShape: const RoundSliderOverlayShape(overlayRadius: 12.0),
                          ),
                          child: Slider(
                            value: gain,
                            min: -10.0,
                            max: 10.0,
                            onChanged: (newValue) {
                              setState(() {
                                widget.eqController.setGain(index, newValue);
                              });
                              widget.onChanged();
                            },
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _formatFreq(freq),
                      style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.white),
                    ),
                  ],
                );
              }),
            ),
          ),
        ],
      ),
    );
  }
}
