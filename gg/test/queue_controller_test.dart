import 'package:flutter_test/flutter_test.dart';
import 'package:gg/main.dart';
import 'package:gg/controllers.dart';

Song createMockSong(String name) {
  return Song(
    title: name,
    artist: 'Artist',
    album: 'Album',
    audioUrl: 'http://example.com/$name.mp3',
    coverUrl: 'http://example.com/$name.jpg',
    lyrics: 'Lyrics',
  );
}

void main() {
  group('QueueController Unit Tests', () {
    test('Default initialization', () {
      final songA = createMockSong('Song A');
      final songB = createMockSong('Song B');
      final songC = createMockSong('Song C');

      final controller = QueueController<Song>(
        songs: [songA, songB, songC],
      );
      expect(controller.activeIndex, equals(0));
      expect(controller.isShuffleEnabled, isFalse);
      expect(controller.loopMode, equals(CustomLoopMode.off));
      expect(controller.currentSongs, equals([songA, songB, songC]));
    });

    test('Sequential skipping', () {
      final songA = createMockSong('Song A');
      final songB = createMockSong('Song B');
      final songC = createMockSong('Song C');

      final controller = QueueController<Song>(
        songs: [songA, songB, songC],
      );
      expect(controller.activeIndex, equals(0));

      controller.skipNext();
      expect(controller.activeIndex, equals(1));

      controller.skipNext();
      expect(controller.activeIndex, equals(2));

      controller.skipPrevious();
      expect(controller.activeIndex, equals(1));

      controller.skipPrevious();
      expect(controller.activeIndex, equals(0));
    });

    test('Boundaries for loopMode.off (no wrap around)', () {
      final songA = createMockSong('Song A');
      final songB = createMockSong('Song B');
      final songC = createMockSong('Song C');

      final controller = QueueController<Song>(
        songs: [songA, songB, songC],
      );
      expect(controller.loopMode, equals(CustomLoopMode.off));

      // Skip previous at start boundary
      controller.skipPrevious();
      expect(controller.activeIndex, equals(0));

      // Go to end boundary
      controller.skipNext();
      controller.skipNext();
      expect(controller.activeIndex, equals(2));

      // Skip next at end boundary
      controller.skipNext();
      expect(controller.activeIndex, equals(2));
    });

    test('LoopMode.all (correct wrap around at start and end)', () {
      final songA = createMockSong('Song A');
      final songB = createMockSong('Song B');
      final songC = createMockSong('Song C');

      final controller = QueueController<Song>(
        songs: [songA, songB, songC],
      );
      controller.setLoopMode(CustomLoopMode.all);

      // Skip previous at start wraps to end
      controller.skipPrevious();
      expect(controller.activeIndex, equals(2));

      // Skip next at end wraps to start
      controller.skipNext();
      expect(controller.activeIndex, equals(0));
    });

    test('LoopMode.one behavior during normal skips', () {
      final songA = createMockSong('Song A');
      final songB = createMockSong('Song B');
      final songC = createMockSong('Song C');

      final controller = QueueController<Song>(
        songs: [songA, songB, songC],
      );
      controller.setLoopMode(CustomLoopMode.one);

      controller.skipNext();
      expect(controller.activeIndex, equals(0));

      controller.skipPrevious();
      expect(controller.activeIndex, equals(0));
    });

    test('Shuffle behavior', () {
      final songs = List.generate(5, (i) => createMockSong('Song $i'));

      final controller = QueueController<Song>(
        songs: songs,
      );

      // Change active index to 2 (Song 2)
      controller.skipNext();
      controller.skipNext();
      expect(controller.activeIndex, equals(2));
      expect(controller.currentSongs[controller.activeIndex].title, equals('Song 2'));

      // Enable shuffle
      controller.setShuffleEnabled(true);
      expect(controller.isShuffleEnabled, isTrue);
      
      // In the new controller, activeIndex becomes 0, and the current song (Song 2) is at index 0 of currentSongs
      expect(controller.activeIndex, equals(0));
      expect(controller.currentSongs[0].title, equals('Song 2'));

      // All songs must still be present in the shuffled queue
      expect(controller.currentSongs.length, equals(5));
      expect(controller.currentSongs.map((s) => s.title), containsAll(['Song 0', 'Song 1', 'Song 2', 'Song 3', 'Song 4']));

      // Disable shuffle
      controller.setShuffleEnabled(false);
      expect(controller.isShuffleEnabled, isFalse);

      // Original order and activeIndex (2) should be restored
      expect(controller.currentSongs, equals(songs));
      expect(controller.activeIndex, equals(2));
    });

    test('Loop and Shuffle interactions', () {
      final songs = List.generate(5, (i) => createMockSong('Song $i'));

      final controller = QueueController<Song>(
        songs: songs,
      );
      controller.setLoopMode(CustomLoopMode.all);

      // Currently at index 0
      expect(controller.activeIndex, equals(0));

      // Enable shuffle
      controller.setShuffleEnabled(true);
      expect(controller.activeIndex, equals(0));

      // Skip previous with loop all and shuffle enabled should wrap to end of shuffled queue
      controller.skipPrevious();
      expect(controller.activeIndex, equals(4));

      // Skip next should wrap back to 0
      controller.skipNext();
      expect(controller.activeIndex, equals(0));
    });
  });
}
