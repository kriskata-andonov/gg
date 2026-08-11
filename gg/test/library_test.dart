import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:just_audio_platform_interface/just_audio_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:gg/main.dart';

class MockJustAudioPlatform extends JustAudioPlatform
    with MockPlatformInterfaceMixin {
  @override
  Future<AudioPlayerPlatform> init(InitRequest request) async {
    return MockAudioPlayerPlatform(request.id);
  }

  @override
  Future<DisposePlayerResponse> disposePlayer(DisposePlayerRequest request) async {
    return DisposePlayerResponse();
  }

  @override
  Future<DisposeAllPlayersResponse> disposeAllPlayers(DisposeAllPlayersRequest request) async {
    return DisposeAllPlayersResponse();
  }
}

class MockAudioPlayerPlatform extends AudioPlayerPlatform {
  MockAudioPlayerPlatform(super.id);

  @override
  Stream<PlaybackEventMessage> get playbackEventMessageStream =>
      Stream.value(PlaybackEventMessage(
        processingState: ProcessingStateMessage.idle,
        updateTime: DateTime.now(),
        updatePosition: Duration.zero,
        bufferedPosition: Duration.zero,
        duration: null,
        icyMetadata: null,
        currentIndex: null,
        androidAudioSessionId: null,
      ));

  @override
  Stream<PlayerDataMessage> get playerDataMessageStream =>
      const Stream<PlayerDataMessage>.empty();

  @override
  Future<LoadResponse> load(LoadRequest request) async {
    return LoadResponse(duration: null);
  }

  @override
  Future<PlayResponse> play(PlayRequest request) async {
    return PlayResponse();
  }

  @override
  Future<PauseResponse> pause(PauseRequest request) async {
    return PauseResponse();
  }

  @override
  Future<SetVolumeResponse> setVolume(SetVolumeRequest request) async {
    return SetVolumeResponse();
  }

  @override
  Future<SetSpeedResponse> setSpeed(SetSpeedRequest request) async {
    return SetSpeedResponse();
  }

  @override
  Future<SetPitchResponse> setPitch(SetPitchRequest request) async {
    return SetPitchResponse();
  }

  @override
  Future<SetSkipSilenceResponse> setSkipSilence(SetSkipSilenceRequest request) async {
    return SetSkipSilenceResponse();
  }

  @override
  Future<SetLoopModeResponse> setLoopMode(SetLoopModeRequest request) async {
    return SetLoopModeResponse();
  }

  @override
  Future<SetShuffleModeResponse> setShuffleMode(SetShuffleModeRequest request) async {
    return SetShuffleModeResponse();
  }

  @override
  Future<SetShuffleOrderResponse> setShuffleOrder(SetShuffleOrderRequest request) async {
    return SetShuffleOrderResponse();
  }

  @override
  Future<SetAutomaticallyWaitsToMinimizeStallingResponse>
      setAutomaticallyWaitsToMinimizeStalling(
          SetAutomaticallyWaitsToMinimizeStallingRequest request) async {
    return SetAutomaticallyWaitsToMinimizeStallingResponse();
  }

  @override
  Future<SetCanUseNetworkResourcesForLiveStreamingWhilePausedResponse>
      setCanUseNetworkResourcesForLiveStreamingWhilePaused(
          SetCanUseNetworkResourcesForLiveStreamingWhilePausedRequest request) async {
    return SetCanUseNetworkResourcesForLiveStreamingWhilePausedResponse();
  }

  @override
  Future<SetPreferredPeakBitRateResponse> setPreferredPeakBitRate(
      SetPreferredPeakBitRateRequest request) async {
    return SetPreferredPeakBitRateResponse();
  }

  @override
  Future<SetAllowsExternalPlaybackResponse> setAllowsExternalPlayback(
      SetAllowsExternalPlaybackRequest request) async {
    return SetAllowsExternalPlaybackResponse();
  }

  @override
  Future<SeekResponse> seek(SeekRequest request) async {
    return SeekResponse();
  }

  @override
  Future<SetAndroidAudioAttributesResponse> setAndroidAudioAttributes(
      SetAndroidAudioAttributesRequest request) async {
    return SetAndroidAudioAttributesResponse();
  }

  @override
  Future<DisposeResponse> dispose(DisposeRequest request) async {
    return DisposeResponse();
  }

  @override
  Future<ConcatenatingInsertAllResponse> concatenatingInsertAll(
      ConcatenatingInsertAllRequest request) async {
    return ConcatenatingInsertAllResponse();
  }

  @override
  Future<ConcatenatingRemoveRangeResponse> concatenatingRemoveRange(
      ConcatenatingRemoveRangeRequest request) async {
    return ConcatenatingRemoveRangeResponse();
  }

  @override
  Future<ConcatenatingMoveResponse> concatenatingMove(
      ConcatenatingMoveRequest request) async {
    return ConcatenatingMoveResponse();
  }

  @override
  Future<AudioEffectSetEnabledResponse> audioEffectSetEnabled(
      AudioEffectSetEnabledRequest request) async {
    return AudioEffectSetEnabledResponse();
  }

  @override
  Future<AndroidLoudnessEnhancerSetTargetGainResponse>
      androidLoudnessEnhancerSetTargetGain(
          AndroidLoudnessEnhancerSetTargetGainRequest request) async {
    return AndroidLoudnessEnhancerSetTargetGainResponse();
  }

  @override
  Future<AndroidEqualizerGetParametersResponse> androidEqualizerGetParameters(
      AndroidEqualizerGetParametersRequest request) async {
    throw UnimplementedError();
  }

  @override
  Future<AndroidEqualizerBandSetGainResponse> androidEqualizerBandSetGain(
      AndroidEqualizerBandSetGainRequest request) async {
    return AndroidEqualizerBandSetGainResponse();
  }

  @override
  Future<SetWebCrossOriginResponse> setWebCrossOrigin(
      SetWebCrossOriginRequest request) async {
    return SetWebCrossOriginResponse();
  }

  @override
  Future<SetWebSinkIdResponse> setWebSinkId(SetWebSinkIdRequest request) async {
    return SetWebSinkIdResponse();
  }
}

void main() {
  setUpAll(() {
    JustAudioPlatform.instance = MockJustAudioPlatform();
  });

  group('Library integration and state tests', () {
    late List<http.Request> capturedRequests;
    late List<String> likedSongs;
    late List<Map<String, dynamic>> folders;
    late List<Map<String, dynamic>> playlists;
    late Map<int, List<String>> playlistSongs;
    late http.Client mockClient;

    setUp(() {
      capturedRequests = [];
      likedSongs = ["/path/to/song2.mp3"];
      folders = [
        {"id": 1, "path": "/path/to/folder1"},
        {"id": 2, "path": "/path/to/folder2"}
      ];
      playlists = [
        {"id": 10, "name": "Favorites"},
        {"id": 11, "name": "Gym"}
      ];
      playlistSongs = {
        10: ["/path/to/song1.mp3"],
        11: []
      };

      mockClient = MockClient((request) async {
        capturedRequests.add(request);
        final path = request.url.path;
        final method = request.method;

        if (path == '/api/songs') {
          return http.Response(
            jsonEncode([
              {
                "id": "/path/to/song1.mp3",
                "title": "Song One",
                "artist": "Artist One",
                "album": "Album One",
                "audioUrl": "http://127.0.0.1:8000/api/audio?path=/path/to/song1.mp3",
                "coverUrl": "http://127.0.0.1:8000/cover1.jpg",
                "lyrics": "Lyrics One",
                "liked": likedSongs.contains("/path/to/song1.mp3")
              },
              {
                "id": "/path/to/song2.mp3",
                "title": "Song Two",
                "artist": "Artist Two",
                "album": "Album Two",
                "audioUrl": "http://127.0.0.1:8000/api/audio?path=/path/to/song2.mp3",
                "coverUrl": "http://127.0.0.1:8000/cover2.jpg",
                "lyrics": "Lyrics Two",
                "liked": likedSongs.contains("/path/to/song2.mp3")
              }
            ]),
            200,
          );
        } else if (path == '/api/folders') {
          if (method == 'GET') {
            return http.Response(jsonEncode(folders), 200);
          } else if (method == 'POST') {
            final body = jsonDecode(request.body);
            final newId = folders.length + 1;
            final newFolder = {"id": newId, "path": body['path']};
            folders.add(newFolder);
            return http.Response(jsonEncode(newFolder), 200);
          } else if (method == 'DELETE') {
            final idParam = request.url.queryParameters['id'];
            if (idParam != null) {
              final id = int.parse(idParam);
              folders.removeWhere((f) => f['id'] == id);
            }
            return http.Response(jsonEncode({"status": "success"}), 200);
          }
        } else if (path == '/api/playlists') {
          if (method == 'GET') {
            return http.Response(jsonEncode(playlists), 200);
          } else if (method == 'POST') {
            final body = jsonDecode(request.body);
            final newId = playlists.length + 10;
            final newPlaylist = {"id": newId, "name": body['name']};
            playlists.add(newPlaylist);
            playlistSongs[newId] = [];
            return http.Response(jsonEncode(newPlaylist), 200);
          }
        } else if (path.startsWith('/api/playlists/')) {
          final segments = request.url.pathSegments;
          final playlistId = int.parse(segments[2]);
          if (segments.length == 3) {
            if (method == 'DELETE') {
              playlists.removeWhere((p) => p['id'] == playlistId);
              playlistSongs.remove(playlistId);
              return http.Response(jsonEncode({"status": "success"}), 200);
            }
          } else if (segments.length == 4 && segments[3] == 'songs') {
            if (method == 'GET') {
              final paths = playlistSongs[playlistId] ?? [];
              return http.Response(jsonEncode(paths.map((p) => {"song_path": p}).toList()), 200);
            } else if (method == 'POST') {
              final body = jsonDecode(request.body);
              final songPath = body['song_path'] as String;
              if (!playlistSongs[playlistId]!.contains(songPath)) {
                playlistSongs[playlistId]!.add(songPath);
              }
              return http.Response(jsonEncode({"playlist_id": playlistId, "song_path": songPath, "status": "added"}), 200);
            } else if (method == 'DELETE') {
              final songPath = request.url.queryParameters['song_path'];
              if (songPath != null) {
                playlistSongs[playlistId]!.remove(songPath);
              }
              return http.Response(jsonEncode({"status": "removed"}), 200);
            }
          }
        } else if (path == '/api/liked') {
          if (method == 'GET') {
            return http.Response(jsonEncode(likedSongs.map((p) => {"song_path": p}).toList()), 200);
          } else if (method == 'POST') {
            final body = jsonDecode(request.body);
            final songPath = body['song_path'] as String;
            if (!likedSongs.contains(songPath)) {
              likedSongs.add(songPath);
            }
            return http.Response(jsonEncode({"song_path": songPath, "status": "liked"}), 200);
          } else if (method == 'DELETE') {
            final songPath = request.url.queryParameters['song_path'];
            if (songPath != null) {
              likedSongs.remove(songPath);
            }
            return http.Response(jsonEncode({"status": "unliked"}), 200);
          }
        }
        return http.Response('Not Found', 404);
      });
    });

    testWidgets('Toggling liked state on songs', (WidgetTester tester) async {
      await http.runWithClient(() async {
        await tester.pumpWidget(const MusicApp());
        await tester.pumpAndSettle();

        // Verify initial songs are loaded
        expect(find.text('Song One'), findsWidgets);
        expect(find.text('Song Two'), findsOneWidget);

        // Verify song one is unliked and song two is liked
        expect(find.byIcon(Icons.favorite_border), findsWidgets); // for Song One
        expect(find.byIcon(Icons.favorite), findsWidgets); // for Song Two

        // Tap the like icon on Song One (it is favorite_border)
        await tester.tap(
          find.descendant(
            of: find.ancestor(
              of: find.text('Song One'),
              matching: find.byType(ListTile),
            ),
            matching: find.byIcon(Icons.favorite_border),
          ).first,
        );
        await tester.pumpAndSettle();

        // Verify POST to /api/liked was triggered
        final postReq = capturedRequests.lastWhere((r) => r.url.path == '/api/liked' && r.method == 'POST');
        expect(jsonDecode(postReq.body)['song_path'], equals('/path/to/song1.mp3'));

        // Verify state is updated (both favorite icons are filled now)
        expect(find.byIcon(Icons.favorite), findsWidgets);
        expect(find.byIcon(Icons.favorite_border), findsNothing);

        // Tap liked icon again on Song One (which is now Icons.favorite)
        await tester.tap(
          find.descendant(
            of: find.ancestor(
              of: find.text('Song One'),
              matching: find.byType(ListTile),
            ),
            matching: find.byIcon(Icons.favorite),
          ).first,
        );
        await tester.pumpAndSettle();

        // Verify DELETE to /api/liked was triggered
        final deleteReq = capturedRequests.lastWhere((r) => r.url.path == '/api/liked' && r.method == 'DELETE');
        expect(deleteReq.url.queryParameters['song_path'], equals('/path/to/song1.mp3'));

        // Verify state is updated (one favorite_border and one favorite)
        expect(find.byIcon(Icons.favorite), findsWidgets);
        expect(find.byIcon(Icons.favorite_border), findsWidgets);
      }, () => mockClient);
    });

    testWidgets('Folder paths list additions and removals', (WidgetTester tester) async {
      await http.runWithClient(() async {
        await tester.pumpWidget(const MusicApp());
        await tester.pumpAndSettle();

        // Switch to settings
        await tester.tap(find.text('Settings'));
        await tester.pumpAndSettle();

        // Verify initial folders listed
        expect(find.text('/path/to/folder1'), findsOneWidget);
        expect(find.text('/path/to/folder2'), findsOneWidget);

        // Enter new path
        await tester.enterText(find.byKey(const Key('folder_input')), '/new/custom/folder');
        await tester.pump();

        // Tap Add Path
        await tester.tap(find.widgetWithText(ElevatedButton, 'Add Path'));
        for (int i = 0; i < 5; i++) {
          await tester.pump(const Duration(milliseconds: 100));
        }

        // Verify POST to /api/folders was triggered
        final postReq = capturedRequests.lastWhere((r) => r.url.path == '/api/folders' && r.method == 'POST');
        expect(jsonDecode(postReq.body)['path'], equals('/new/custom/folder'));

        // Verify folder is listed
        expect(find.text('/new/custom/folder', skipOffstage: false), findsOneWidget);

        // Tap delete button next to /path/to/folder1 (the first delete icon in settings)
        // Settings delete buttons use Icons.delete, app bar / others do not. Let's find first Icons.delete.
        final deleteIcon = find.byIcon(Icons.delete, skipOffstage: false).first;
        await tester.ensureVisible(deleteIcon);
        await tester.pumpAndSettle();
        await tester.tap(deleteIcon);
        await tester.pumpAndSettle();

        // Verify DELETE to /api/folders?id=1
        final deleteReq = capturedRequests.lastWhere((r) => r.url.path == '/api/folders' && r.method == 'DELETE');
        expect(deleteReq.url.queryParameters['id'], equals('1'));

        // Verify folder is removed from view
        expect(find.text('/path/to/folder1', skipOffstage: false), findsNothing);
      }, () => mockClient);
    });

    testWidgets('Playlists CRUD and adding/removing songs', (WidgetTester tester) async {
      await http.runWithClient(() async {
        await tester.pumpWidget(const MusicApp());
        await tester.pumpAndSettle();

        // Switch to Playlists
        await tester.tap(find.text('Playlists'));
        await tester.pumpAndSettle();

        // Verify lists playlists
        expect(find.text('Favorites'), findsOneWidget);
        expect(find.text('Gym'), findsOneWidget);

        // Add Playlist
        await tester.tap(find.byTooltip('Add Playlist'));
        await tester.pumpAndSettle();

        // Dialog should be shown, enter playlist name
        final dialogTextField = find.byType(TextField).last;
        await tester.enterText(dialogTextField, 'Metal Hits');
        await tester.pump();
        await tester.tap(find.text('Create'));
        await tester.pumpAndSettle();

        // Verify POST to /api/playlists
        final postPlaylistReq = capturedRequests.lastWhere((r) => r.url.path == '/api/playlists' && r.method == 'POST');
        expect(jsonDecode(postPlaylistReq.body)['name'], equals('Metal Hits'));

        // Verify new playlist is listed
        expect(find.text('Metal Hits'), findsOneWidget);

        // Delete playlist "Gym" (playlistId = 11).
        // Since Gym is at index 1 (id 11), let's tap delete on Gym.
        // It should be the second delete button in the playlists list.
        await tester.tap(find.byIcon(Icons.delete).at(1));
        await tester.pumpAndSettle();

        // Verify DELETE to /api/playlists/11
        final deletePlaylistReq = capturedRequests.lastWhere((r) => r.url.path == '/api/playlists/11' && r.method == 'DELETE');
        expect(deletePlaylistReq.url.path, equals('/api/playlists/11'));

        // Verify Gym is gone
        expect(find.text('Gym'), findsNothing);

        // Click Favorites playlist to view details
        await tester.tap(find.text('Favorites'));
        await tester.pumpAndSettle();

        // Verify favorites songs are shown (Song One is in Favorites)
        expect(find.text('Favorites'), findsWidgets); // header
        expect(find.text('Song One'), findsWidgets);

        // Remove Song One from Favorites playlist
        // Tapping the remove button (Icons.remove_circle_outline)
        await tester.tap(find.byIcon(Icons.remove_circle_outline).first);
        await tester.pumpAndSettle();

        // Verify DELETE to /api/playlists/10/songs?song_path=...
        final removeSongReq = capturedRequests.lastWhere((r) => r.url.path == '/api/playlists/10/songs' && r.method == 'DELETE');
        expect(removeSongReq.url.queryParameters['song_path'], equals('/path/to/song1.mp3'));

        // Verify Song One is no longer in the playlist view list
        expect(find.descendant(of: find.byType(ListView), matching: find.text('Song One')), findsNothing);

        // Go back to playlists list
        await tester.tap(find.byIcon(Icons.arrow_back));
        await tester.pumpAndSettle();

        // Go to All Songs, then try to add Song Two to playlist Favorites
        await tester.tap(find.text('All Songs'));
        await tester.pumpAndSettle();

        // Tap more_vert next to Song Two (at index 1)
        await tester.tap(find.byIcon(Icons.more_vert).at(1));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Add to Playlist'));
        await tester.pumpAndSettle();

        // Tap Favorites in the Dialog list
        await tester.tap(find.text('Favorites').last);
        await tester.pumpAndSettle();

        // Verify POST to /api/playlists/10/songs
        final addSongReq = capturedRequests.lastWhere((r) => r.url.path == '/api/playlists/10/songs' && r.method == 'POST');
        expect(jsonDecode(addSongReq.body)['song_path'], equals('/path/to/song2.mp3'));
      }, () => mockClient);
    });
  });
}
