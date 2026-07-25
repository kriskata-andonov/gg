import 'package:flutter_test/flutter_test.dart';
import 'package:gg/controllers.dart';

void main() {
  group('EQController Unit Tests', () {
    test('Initial flat state', () {
      final controller = EQController();
      
      // Verify 10 bands are initialized to 0.0
      expect(controller.gains.length, equals(10));
      for (final gain in controller.gains) {
        expect(gain, equals(0.0));
      }

      // Verify default flat filter string
      expect(
        controller.filterString,
        equals('equalizer=f=31.25:width_type=q:w=1:g=0.0,equalizer=f=62.5:width_type=q:w=1:g=0.0,equalizer=f=125:width_type=q:w=1:g=0.0,equalizer=f=250:width_type=q:w=1:g=0.0,equalizer=f=500:width_type=q:w=1:g=0.0,equalizer=f=1000:width_type=q:w=1:g=0.0,equalizer=f=2000:width_type=q:w=1:g=0.0,equalizer=f=4000:width_type=q:w=1:g=0.0,equalizer=f=8000:width_type=q:w=1:g=0.0,equalizer=f=16000:width_type=q:w=1:g=0.0'),
      );
    });

    test('Gain bounds clamping', () {
      final controller = EQController();
      
      // Upper bound clamping
      controller.setGain(0, 15.0);
      expect(controller.gains[0], equals(10.0));

      // Lower bound clamping
      controller.setGain(1, -12.5);
      expect(controller.gains[1], equals(-10.0));

      // Exact bounds
      controller.setGain(2, 10.0);
      expect(controller.gains[2], equals(10.0));
      controller.setGain(3, -10.0);
      expect(controller.gains[3], equals(-10.0));

      // Within bounds
      controller.setGain(4, 3.5);
      expect(controller.gains[4], equals(3.5));
    });

    test('Applying presets', () {
      final controller = EQController();

      // Pop preset
      controller.applyPreset('pop');
      expect(controller.gains, equals(EQController.presets['pop']));

      // Rock preset
      controller.applyPreset('rock');
      expect(controller.gains, equals(EQController.presets['rock']));

      // Bass Boost preset
      controller.applyPreset('bassBoost');
      expect(controller.gains, equals(EQController.presets['bassBoost']));

      // Flat preset
      controller.applyPreset('flat');
      expect(controller.gains, equals(EQController.presets['flat']));
    });

    test('Filter string syntax', () {
      final controller = EQController();
      controller.setGain(0, 5.0);   // 31.25 Hz
      controller.setGain(2, -3.5);  // 125 Hz
      controller.setGain(9, 8.2);   // 16000 Hz

      final filterString = controller.filterString;
      
      // Split and inspect elements
      final bands = filterString.split(',');
      expect(bands.length, equals(10));
      
      expect(bands[0], equals('equalizer=f=31.25:width_type=q:w=1:g=5.0'));
      expect(bands[2], equals('equalizer=f=125:width_type=q:w=1:g=-3.5'));
      expect(bands[9], equals('equalizer=f=16000:width_type=q:w=1:g=8.2'));
    });
  });
}
