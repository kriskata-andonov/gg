import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'player/custom_just_audio_media_kit.dart';
import 'package:gg/controllers.dart';
import 'package:gg/layout_manager.dart';
import 'widgets/eq_sheet.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:audio_video_progress_bar/audio_video_progress_bar.dart';
import 'package:rxdart/rxdart.dart';
import 'package:desktop_drop/desktop_drop.dart';
import 'package:cross_file/cross_file.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/foundation.dart';
import 'backend_runner_stub.dart' if (dart.library.io) 'backend_runner_io.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (!kIsWeb) {
    CustomJustAudioMediaKit.ensureInitialized();
  }
  
  final prefs = await SharedPreferences.getInstance();
  final colorValue = prefs.getInt('themeColor');
  if (colorValue != null) {
    themeColorNotifier.value = Color(colorValue);
  }
  
  final isDark = prefs.getBool('isDarkTheme');
  if (isDark != null) {
    themeModeNotifier.value = isDark ? ThemeMode.dark : ThemeMode.light;
  }
  
  themeColorNotifier.addListener(() {
    prefs.setInt('themeColor', themeColorNotifier.value.value);
  });
  
  themeModeNotifier.addListener(() {
    prefs.setBool('isDarkTheme', themeModeNotifier.value == ThemeMode.dark);
  });

  await startBackend();
  
  runApp(const MusicApp());
}

class Song {
  final String id;
  final String title;
  final String artist;
  final String album;
  final String audioUrl;
  String coverUrl;
  String lyrics;
  bool liked;

  Song({
    this.id = '',
    required this.title,
    required this.artist,
    required this.album,
    required this.audioUrl,
    required this.coverUrl,
    required this.lyrics,
    this.liked = false,
  });
}

class PositionData {
  final Duration position;
  final Duration bufferedPosition;
  final Duration duration;
  PositionData(this.position, this.bufferedPosition, this.duration);
}

final ValueNotifier<Color> themeColorNotifier = ValueNotifier<Color>(Colors.deepPurpleAccent);

final ValueNotifier<ThemeMode> themeModeNotifier = ValueNotifier<ThemeMode>(ThemeMode.dark);

class DefaultCoverImage extends StatelessWidget {
  final String imageUrl;
  final double width;
  final double height;
  const DefaultCoverImage({super.key, required this.imageUrl, required this.width, required this.height});

  @override
  Widget build(BuildContext context) {
    if (imageUrl.isEmpty) {
      return Container(
        width: width,
        height: height,
        color: Colors.grey[800],
        child: Icon(Icons.music_note, size: width * 0.5, color: Colors.grey[500]),
      );
    }
    return CachedNetworkImage(
      imageUrl: imageUrl,
      width: width,
      height: height,
      fit: BoxFit.cover,
      errorWidget: (context, url, error) => Container(
        width: width,
        height: height,
        color: Colors.grey[800],
        child: Icon(Icons.music_note, size: width * 0.5, color: Colors.grey[500]),
      ),
    );
  }
}

class MusicApp extends StatelessWidget {
  const MusicApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<Color>(
      valueListenable: themeColorNotifier,
      builder: (context, color, child) {
        return ValueListenableBuilder<ThemeMode>(
          valueListenable: themeModeNotifier,
          builder: (context, themeMode, child) {
            return MaterialApp(
              title: 'GG Music',
              debugShowCheckedModeBanner: false,
              themeMode: themeMode,
              theme: ThemeData(
                colorScheme: ColorScheme.light(
                  primary: color,
                ),
                useMaterial3: true,
              ),
              darkTheme: ThemeData(
                colorScheme: ColorScheme.dark(
                  primary: color,
                  surface: const Color(0xFF121212),
                ),
                useMaterial3: true,
              ),
              home: const HomeScreen(),
            );
          },
        );
      },
    );
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late AudioPlayer _player;
  String _searchQuery = '';
  bool _isLoading = true;
  bool _isDragging = false;
  Song? _currentlyPlayingSong;

  List<Song> _allSongs = [];
  QueueController<Song>? _queueController;
  final EQController _eqController = EQController();
  final LayoutManager _layoutManager = LayoutManager();

  List<Map<String, dynamic>> _folders = [];
  List<Map<String, dynamic>> _playlists = [];
  Map<int, List<String>> _playlistSongPaths = {};
  int _currentViewIndex = 0;
  Map<String, dynamic>? _selectedPlaylist;
  final TextEditingController _folderController = TextEditingController();
  bool _isFolderDragging = false;

  Stream<PositionData> get _positionDataStream =>
      Rx.combineLatest3<Duration, Duration, Duration?, PositionData>(
          _player.positionStream,
          _player.bufferedPositionStream,
          _player.durationStream,
          (position, bufferedPosition, duration) => PositionData(
              position, bufferedPosition, duration ?? Duration.zero));

  @override
  void initState() {
    super.initState();
    _player = AudioPlayer();
    _fetchSongs();
    _fetchFolders();
    _fetchPlaylists();
    
    _player.playerStateStream.listen((state) {
      if (state.processingState == ProcessingState.completed) {
        if (_queueController?.loopMode == CustomLoopMode.one) {
          _player.seek(Duration.zero);
          _player.play();
        } else {
          _playNext();
        }
      }
    });

    _player.playbackEventStream.listen((event) {}, onError: (Object e, StackTrace stackTrace) {
      debugPrint('A stream error occurred: $e');
    });

    _initEQ();
  }

  Future<void> _initEQ() async {
    await _eqController.init();
    await _layoutManager.init();
    _applyEQ();
  }

  void _applyEQ() {
    if (CustomJustAudioMediaKit.activePlayers.isNotEmpty) {
      final player = CustomJustAudioMediaKit.activePlayers.values.first;
      final filter = _eqController.filterString;
      player.setAudioFilter(filter);
    }
  }

  Future<void> _fetchSongs() async {
    try {
      final response = await http.get(Uri.parse('http://127.0.0.1:8000/api/songs'));
      if (response.statusCode == 200) {
        final List<dynamic> data = jsonDecode(response.body);
        final fetchedSongs = data.map((item) => Song(
          id: item['id'] ?? '',
          title: item['title'] ?? 'Unknown Title',
          artist: item['artist'] ?? 'Unknown Artist',
          album: item['album'] ?? 'Unknown Album',
          audioUrl: item['audioUrl'] ?? '',
          lyrics: item['lyrics'] ?? 'No lyrics available.',
          coverUrl: item['coverUrl'] ?? '',
          liked: item['liked'] ?? false,
        )).toList();

        setState(() {
          _allSongs = fetchedSongs;
          _isLoading = false;
          _queueController = QueueController<Song>(
            songs: _allSongs,
            initialIndex: 0,
            shuffle: false,
            loop: CustomLoopMode.off,
          );
        });
      } else {
        throw Exception('Failed to load songs');
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading songs from API: $e')),
        );
      }
    }
  }

  Future<void> _fetchFolders() async {
    try {
      final response = await http.get(Uri.parse('http://127.0.0.1:8000/api/folders'));
      if (response.statusCode == 200) {
        final List<dynamic> data = jsonDecode(response.body);
        setState(() {
          _folders = data.map((item) => {
            'id': item['id'] as int,
            'path': item['path'] as String,
          }).toList();
        });
      }
    } catch (e) {
      debugPrint("Error fetching folders: $e");
    }
  }

  Future<void> _fetchPlaylists() async {
    try {
      final response = await http.get(Uri.parse('http://127.0.0.1:8000/api/playlists'));
      if (response.statusCode == 200) {
        final List<dynamic> data = jsonDecode(response.body);
        final fetchedPlaylists = data.map((item) => {
          'id': item['id'] as int,
          'name': item['name'] as String,
        }).toList();
        setState(() {
          _playlists = fetchedPlaylists;
        });
        for (final playlist in fetchedPlaylists) {
          await _fetchPlaylistSongs(playlist['id'] as int);
        }
      }
    } catch (e) {
      debugPrint("Error fetching playlists: $e");
    }
  }

  Future<void> _fetchPlaylistSongs(int playlistId) async {
    try {
      final response = await http.get(Uri.parse('http://127.0.0.1:8000/api/playlists/$playlistId/songs'));
      if (response.statusCode == 200) {
        final List<dynamic> data = jsonDecode(response.body);
        final List<String> paths = data.map((item) => item['song_path'] as String).toList();
        setState(() {
          _playlistSongPaths[playlistId] = paths;
        });
      }
    } catch (e) {
      debugPrint("Error fetching playlist songs: $e");
    }
  }

  List<Song> _getSongsInPlaylist(int playlistId) {
    final paths = _playlistSongPaths[playlistId] ?? [];
    return _allSongs.where((s) => paths.contains(s.id)).toList();
  }

  Future<void> _toggleLiked(Song song) async {
    final bool newLikedState = !song.liked;
    setState(() {
      song.liked = newLikedState;
    });
    try {
      final response = newLikedState
          ? await http.post(
              Uri.parse('http://127.0.0.1:8000/api/liked'),
              headers: {'Content-Type': 'application/json'},
              body: jsonEncode({'song_path': song.id}),
            )
          : await http.delete(
              Uri.parse('http://127.0.0.1:8000/api/liked?song_path=${Uri.encodeComponent(song.id)}'),
            );
      if (response.statusCode != 200) {
        setState(() {
          song.liked = !newLikedState;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to update liked state')),
        );
      }
    } catch (e) {
      setState(() {
        song.liked = !newLikedState;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error updating liked state: $e')),
      );
    }
  }

  Future<void> _addPlaylist(String name) async {
    try {
      final response = await http.post(
        Uri.parse('http://127.0.0.1:8000/api/playlists'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'name': name}),
      );
      if (response.statusCode == 200) {
        await _fetchPlaylists();
      } else {
        final error = jsonDecode(response.body);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error adding playlist: ${error['detail'] ?? response.body}')),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error adding playlist: $e')),
      );
    }
  }

  Future<void> _deletePlaylist(int id) async {
    try {
      final response = await http.delete(
        Uri.parse('http://127.0.0.1:8000/api/playlists/$id'),
      );
      if (response.statusCode == 200) {
        if (_selectedPlaylist != null && _selectedPlaylist!['id'] == id) {
          setState(() {
            _selectedPlaylist = null;
          });
        }
        await _fetchPlaylists();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Error deleting playlist')),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error deleting playlist: $e')),
      );
    }
  }

  Future<void> _addSongToPlaylist(int playlistId, Song song) async {
    try {
      final response = await http.post(
        Uri.parse('http://127.0.0.1:8000/api/playlists/$playlistId/songs'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'song_path': song.id}),
      );
      if (response.statusCode == 200) {
        await _fetchPlaylistSongs(playlistId);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Added ${song.title} to playlist')),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Error adding song to playlist')),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error adding song to playlist: $e')),
      );
    }
  }

  Future<void> _removeSongFromPlaylist(int playlistId, Song song) async {
    try {
      final response = await http.delete(
        Uri.parse('http://127.0.0.1:8000/api/playlists/$playlistId/songs?song_path=${Uri.encodeComponent(song.id)}'),
      );
      if (response.statusCode == 200) {
        await _fetchPlaylistSongs(playlistId);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Removed ${song.title} from playlist')),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Error removing song from playlist')),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error removing song from playlist: $e')),
      );
    }
  }

  Future<void> _addFolder(String path) async {
    try {
      final response = await http.post(
        Uri.parse('http://127.0.0.1:8000/api/folders'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'path': path}),
      );
      if (response.statusCode == 200) {
        await _fetchFolders();
        _fetchSongs();
      } else {
        final error = jsonDecode(response.body);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error adding folder: ${error['detail'] ?? response.body}')),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error adding folder: $e')),
      );
    }
  }

  Future<void> _deleteFolder(int id) async {
    try {
      final response = await http.delete(
        Uri.parse('http://127.0.0.1:8000/api/folders?id=$id'),
      );
      if (response.statusCode == 200) {
        await _fetchFolders();
        _fetchSongs();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Error deleting folder')),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error deleting folder: $e')),
      );
    }
  }

  void _setQueueAndPlay(List<Song> songs, int index) {
    if (songs.isEmpty) return;
    setState(() {
      _queueController = QueueController<Song>(
        songs: songs,
        initialIndex: index,
        shuffle: _queueController?.isShuffleEnabled ?? false,
        loop: _queueController?.loopMode ?? CustomLoopMode.off,
      );
    });
    _playSong(songs[index]);
  }

  void _showAddToPlaylistDialog(Song song) {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Add to Playlist'),
          content: _playlists.isEmpty
              ? const Text('No playlists. Create one in the Playlists tab.')
              : SizedBox(
                  width: 300,
                  height: 200,
                  child: ListView.builder(
                    itemCount: _playlists.length,
                    itemBuilder: (context, index) {
                      final playlist = _playlists[index];
                      return ListTile(
                        title: Text(playlist['name'] as String),
                        onTap: () {
                          Navigator.pop(context);
                          _addSongToPlaylist(playlist['id'] as int, song);
                        },
                      );
                    },
                  ),
                ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Close'),
            ),
          ],
        );
      },
    );
  }

  void _showAddPlaylistDialog() {
    final TextEditingController nameController = TextEditingController();
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('New Playlist'),
          content: TextField(
            controller: nameController,
            decoration: const InputDecoration(
              hintText: 'Playlist name',
            ),
            autofocus: true,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () {
                final name = nameController.text.trim();
                if (name.isNotEmpty) {
                  Navigator.pop(context);
                  _addPlaylist(name);
                }
              },
              child: const Text('Create'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _handleFileDrop(DropDoneDetails details) async {
    for (final file in details.files) {
      if (file.path.toLowerCase().endsWith('.mp3')) {
        await _uploadFile(file);
      }
    }
    // Refresh the library after uploads
    _fetchSongs();
  }

  Future<void> _uploadFile(XFile file) async {
    try {
      final request = http.MultipartRequest(
        'POST',
        Uri.parse('http://127.0.0.1:8000/api/upload'),
      );
      request.files.add(await http.MultipartFile.fromPath('file', file.path));
      
      final response = await request.send();
      if (response.statusCode == 200) {
        debugPrint('Uploaded ${file.name}');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Successfully uploaded ${file.name}')),
          );
        }
      } else {
        debugPrint('Failed to upload ${file.name}');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Failed to upload ${file.name}'), backgroundColor: Colors.red),
          );
        }
      }
    } catch (e) {
      debugPrint('Error uploading file: $e');
    }
  }

  @override
  void dispose() {
    stopBackend();
    _player.dispose();
    _folderController.dispose();
    super.dispose();
  }

  Future<void> _playSong(Song song, {bool forcePlay = false}) async {
    if (_queueController == null) return;
    final index = _queueController!.currentSongs.indexOf(song);
    if (index == -1) return;
    
    // Don't restart the song if it's already playing
    if (!forcePlay && _currentlyPlayingSong == song && _player.playing) return;

    _currentlyPlayingSong = song;

    setState(() {
      _queueController!.activeIndex = index;
    });

    try {
      print("PLAYING SONG: ${song.title} | URL: ${song.audioUrl}");
      // The backend now provides a fully encoded URL
      await _player.setAudioSource(AudioSource.uri(Uri.parse(song.audioUrl)));
      _player.play();
      Future.delayed(const Duration(milliseconds: 500), () {
        _applyEQ();
      });
    } catch (e) {
      debugPrint("Error playing audio: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error playing ${song.title}: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  void _playNext() {
    if (_queueController == null) return;
    setState(() {
      _queueController!.skipNext();
    });
    final songs = _queueController!.currentSongs;
    final newSong = _queueController!.activeIndex >= 0 && _queueController!.activeIndex < songs.length
        ? songs[_queueController!.activeIndex]
        : null;
    if (newSong != null) {
      _playSong(newSong, forcePlay: true);
    }
  }

  void _playPrevious() {
    if (_queueController == null) return;
    if (_player.position.inSeconds >= 3) {
      _player.seek(Duration.zero);
      return;
    }
    setState(() {
      _queueController!.skipPrevious();
    });
    final songs = _queueController!.currentSongs;
    final newSong = _queueController!.activeIndex >= 0 && _queueController!.activeIndex < songs.length
        ? songs[_queueController!.activeIndex]
        : null;
    if (newSong != null) {
      _playSong(newSong, forcePlay: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return DropTarget(
      onDragDone: _handleFileDrop,
      onDragEntered: (details) => setState(() => _isDragging = true),
      onDragExited: (details) => setState(() => _isDragging = false),
      child: ListenableBuilder(
        listenable: _layoutManager,
        builder: (context, _) {
          return Scaffold(
            appBar: AppBar(
              title: const Text('GG Music'),
              bottom: PreferredSize(
                preferredSize: Size.fromHeight((_layoutManager.currentMode == AppLayoutMode.ytMusic || 
                  (_layoutManager.currentMode == AppLayoutMode.custom && _layoutManager.navStyle == 'topBar' && _layoutManager.panelVisibility['sidebar'] == true)) ? 120 : 60),
                child: Column(
                  children: [
                    if (_layoutManager.currentMode == AppLayoutMode.ytMusic || 
                       (_layoutManager.currentMode == AppLayoutMode.custom && _layoutManager.navStyle == 'topBar' && _layoutManager.panelVisibility['sidebar'] == true))
                      _buildTopNavBar(),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                      child: TextField(
                        onChanged: (value) => setState(() => _searchQuery = value),
                        decoration: InputDecoration(
                          hintText: 'Search songs, artists, or albums...',
                          prefixIcon: const Icon(Icons.search),
                          filled: true,
                          fillColor: Colors.grey[900],
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(30),
                            borderSide: BorderSide.none,
                          ),
                          contentPadding: const EdgeInsets.symmetric(vertical: 0),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            body: Stack(
              children: [
                _isLoading
                    ? const Center(child: CircularProgressIndicator())
                    : _buildDynamicLayout(),
                if (_isDragging)
                  Container(
                    color: Theme.of(context).colorScheme.primary.withOpacity(0.4),
                    child: const Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.add_to_photos, size: 80, color: Colors.white),
                          SizedBox(height: 16),
                          Text(
                            "Drop MP3 files to add them to your library",
                            style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.white),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
            bottomNavigationBar: _buildBottomPlayer(),
          );
        },
      ),
    );
  }

  Widget _buildSidebar({double? width}) {
    final items = [
      {'icon': Icons.music_note, 'label': 'All Songs'},
      {'icon': Icons.playlist_play, 'label': 'Playlists'},
      {'icon': Icons.favorite, 'label': 'Liked Songs'},
      {'icon': Icons.settings, 'label': 'Settings'},
    ];

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final currentSongs = _queueController?.currentSongs;
    final currentSong = (_queueController != null &&
            currentSongs != null &&
            _queueController!.activeIndex >= 0 &&
            _queueController!.activeIndex < currentSongs.length)
        ? currentSongs[_queueController!.activeIndex]
        : null;

    return Container(
      width: width ?? 200,
      color: isDark ? Colors.grey[950] : Colors.grey[200],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 24),
          ...List.generate(items.length, (index) {
            final item = items[index];
            final isSelected = _currentViewIndex == index;
            return ListTile(
              leading: Icon(
                item['icon'] as IconData,
                color: isSelected ? Theme.of(context).colorScheme.primary : (isDark ? Colors.grey : Colors.black54),
              ),
              title: Text(
                item['label'] as String,
                style: TextStyle(
                  color: isSelected ? Theme.of(context).colorScheme.onSurface : (isDark ? Colors.grey : Colors.black54),
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                ),
              ),
              selected: isSelected,
              selectedTileColor: Theme.of(context).colorScheme.primary.withOpacity(0.15),
              onTap: () {
                setState(() {
                  _currentViewIndex = index;
                  if (index == 1) {
                    _selectedPlaylist = null;
                  }
                });
              },
            );
          }),
          const Spacer(),
          if (_layoutManager.currentMode == AppLayoutMode.spotify && currentSong != null)
             Padding(
                padding: const EdgeInsets.all(16.0),
                child: AspectRatio(
                  aspectRatio: 1,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: DefaultCoverImage(
                      imageUrl: currentSong.coverUrl,
                      width: double.infinity,
                      height: double.infinity,
                    ),
                  ),
                ),
             ),
        ],
      ),
    );
  }

  Widget _buildTopNavBar() {
    final items = [
      {'icon': Icons.music_note, 'label': 'All Songs'},
      {'icon': Icons.playlist_play, 'label': 'Playlists'},
      {'icon': Icons.favorite, 'label': 'Liked Songs'},
      {'icon': Icons.settings, 'label': 'Settings'},
    ];
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      height: 60,
      color: isDark ? Colors.grey[900] : Colors.grey[200],
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: List.generate(items.length, (index) {
          final item = items[index];
          final isSelected = _currentViewIndex == index;
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8.0),
            child: ChoiceChip(
              label: Text(item['label'] as String),
              selected: isSelected,
              avatar: Icon(item['icon'] as IconData, size: 18, color: isSelected ? Colors.white : null),
              onSelected: (selected) {
                if (selected) {
                  setState(() {
                    _currentViewIndex = index;
                    if (index == 1) _selectedPlaylist = null;
                  });
                }
              },
            ),
          );
        }),
      ),
    );
  }

  Widget _buildDraggableDivider({required ValueChanged<double> onDrag}) {
    return MouseRegion(
      cursor: SystemMouseCursors.resizeColumn,
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onPanUpdate: (details) {
          onDrag(details.delta.dx);
        },
        child: Container(
          width: 12,
          color: Colors.transparent,
          child: Stack(
            alignment: Alignment.center,
            children: [
              const VerticalDivider(width: 1, color: Colors.grey, thickness: 1),
              Container(
                width: 4,
                height: 32,
                decoration: BoxDecoration(
                  color: Colors.grey.withOpacity(0.5),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMainContent() {
    switch (_currentViewIndex) {
      case 0:
        return _buildAllSongsView();
      case 1:
        return _buildPlaylistsView();
      case 2:
        return _buildLikedSongsView();
      case 3:
        return _buildSettingsView();
      default:
        return const Center(child: Text('Unknown View'));
    }
  }

  Widget _buildAllSongsView() {
    final filteredSongs = _allSongs.where((song) {
      final query = _searchQuery.toLowerCase();
      return song.title.toLowerCase().contains(query) ||
             song.artist.toLowerCase().contains(query) ||
             song.album.toLowerCase().contains(query);
    }).toList();

    if (filteredSongs.isEmpty && !_isLoading) {
      return const Center(child: Text("No songs found. Drag and drop MP3s or configure scan folders in Settings!"));
    }

    return ListView.builder(
      itemCount: filteredSongs.length,
      itemBuilder: (context, index) {
        final song = filteredSongs[index];
        final currentSongs = _queueController?.currentSongs;
        final currentSong = (_queueController != null &&
                currentSongs != null &&
                _queueController!.activeIndex >= 0 &&
                _queueController!.activeIndex < currentSongs.length)
            ? currentSongs[_queueController!.activeIndex]
            : null;
        final isPlayingThis = currentSong == song;

        return ListTile(
          leading: ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: DefaultCoverImage(
              imageUrl: song.coverUrl,
              width: 50,
              height: 50,
            ),
          ),
          title: Text(
            song.title,
            style: TextStyle(
              color: isPlayingThis ? Theme.of(context).colorScheme.primary : Theme.of(context).colorScheme.onSurface,
              fontWeight: isPlayingThis ? FontWeight.bold : FontWeight.normal,
            ),
          ),
          subtitle: Text('${song.artist} • ${song.album}'),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                icon: Icon(
                  song.liked ? Icons.favorite : Icons.favorite_border,
                  color: song.liked ? Colors.red : Colors.grey,
                ),
                onPressed: () => _toggleLiked(song),
              ),
              IconButton(
                icon: const Icon(Icons.playlist_add, color: Colors.grey),
                onPressed: () => _showAddToPlaylistDialog(song),
              ),
              if (isPlayingThis)
                Padding(
                  padding: const EdgeInsets.only(left: 8.0),
                  child: Icon(Icons.equalizer, color: Theme.of(context).colorScheme.primary),
                ),
            ],
          ),
          onTap: () {
            _setQueueAndPlay(filteredSongs, index);
          },
        );
      },
    );
  }

  Widget _buildPlaylistsView() {
    if (_selectedPlaylist != null) {
      return _buildPlaylistDetailsView(_selectedPlaylist!);
    }

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16.0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Playlists',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
              IconButton(
                icon: const Icon(Icons.add),
                tooltip: 'Add Playlist',
                onPressed: _showAddPlaylistDialog,
              ),
            ],
          ),
        ),
        Expanded(
          child: _playlists.isEmpty
              ? const Center(child: Text('No playlists yet. Create one!'))
              : ListView.builder(
                  itemCount: _playlists.length,
                  itemBuilder: (context, index) {
                    final playlist = _playlists[index];
                    final playlistId = playlist['id'] as int;
                    final songCount = _playlistSongPaths[playlistId]?.length ?? 0;
                    return ListTile(
                      leading: SizedBox(
                        width: 40,
                        height: 40,
                        child: DefaultCoverImage(
                          imageUrl: playlist['coverUrl'] as String? ?? '',
                          width: 40,
                          height: 40,
                        ),
                      ),
                      title: Text(playlist['name'] as String),
                      subtitle: Text('$songCount ${songCount == 1 ? 'song' : 'songs'}'),
                      trailing: IconButton(
                        icon: const Icon(Icons.delete, color: Colors.redAccent),
                        onPressed: () => _deletePlaylist(playlistId),
                      ),
                      onTap: () {
                        setState(() {
                          _selectedPlaylist = playlist;
                        });
                      },
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildPlaylistDetailsView(Map<String, dynamic> playlist) {
    final playlistId = playlist['id'] as int;
    final playlistSongs = _getSongsInPlaylist(playlistId);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.all(16.0),
          child: Row(
            children: [
              IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: () {
                  setState(() {
                    _selectedPlaylist = null;
                  });
                },
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      playlist['name'] as String,
                      style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                    ),
                    Text(
                      '${playlistSongs.length} ${playlistSongs.length == 1 ? 'song' : 'songs'}',
                      style: const TextStyle(color: Colors.grey),
                    ),
                  ],
                ),
              ),
              if (playlistSongs.isNotEmpty)
                IconButton(
                  icon: const Icon(Icons.play_arrow),
                  tooltip: 'Play All',
                  onPressed: () {
                    _setQueueAndPlay(playlistSongs, 0);
                  },
                ),
            ],
          ),
        ),
        Expanded(
          child: playlistSongs.isEmpty
              ? const Center(child: Text('No songs in this playlist. Go to All Songs to add some!'))
              : ListView.builder(
                  itemCount: playlistSongs.length,
                  itemBuilder: (context, index) {
                    final song = playlistSongs[index];
                    final currentSongs = _queueController?.currentSongs;
                    final currentSong = (_queueController != null &&
                            currentSongs != null &&
                            _queueController!.activeIndex >= 0 &&
                            _queueController!.activeIndex < currentSongs.length)
                        ? currentSongs[_queueController!.activeIndex]
                        : null;
                    final isPlayingThis = currentSong == song;

                    return ListTile(
                      leading: ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: DefaultCoverImage(
                          imageUrl: song.coverUrl,
                          width: 50,
                          height: 50,
                        ),
                      ),
                      title: Text(
                        song.title,
                        style: TextStyle(
                          color: isPlayingThis ? Theme.of(context).colorScheme.primary : Theme.of(context).colorScheme.onSurface,
                          fontWeight: isPlayingThis ? FontWeight.bold : FontWeight.normal,
                        ),
                      ),
                      subtitle: Text('${song.artist} • ${song.album}'),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: Icon(
                              song.liked ? Icons.favorite : Icons.favorite_border,
                              color: song.liked ? Colors.red : Colors.grey,
                            ),
                            onPressed: () => _toggleLiked(song),
                          ),
                          IconButton(
                            icon: const Icon(Icons.remove_circle_outline, color: Colors.redAccent),
                            onPressed: () => _removeSongFromPlaylist(playlistId, song),
                          ),
                          if (isPlayingThis)
                            Padding(
                              padding: const EdgeInsets.only(left: 8.0),
                              child: Icon(Icons.equalizer, color: Theme.of(context).colorScheme.primary),
                            ),
                        ],
                      ),
                      onTap: () {
                        _setQueueAndPlay(playlistSongs, index);
                      },
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildLikedSongsView() {
    final likedSongs = _allSongs.where((song) => song.liked).toList();

    if (likedSongs.isEmpty) {
      return const Center(child: Text("No liked songs yet. Tap the Heart icon on any song!"));
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.all(16.0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Liked Songs',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
              if (likedSongs.isNotEmpty)
                IconButton(
                  icon: const Icon(Icons.play_arrow),
                  tooltip: 'Play All',
                  onPressed: () {
                    _setQueueAndPlay(likedSongs, 0);
                  },
                ),
            ],
          ),
        ),
        Expanded(
          child: ListView.builder(
            itemCount: likedSongs.length,
            itemBuilder: (context, index) {
              final song = likedSongs[index];
              final currentSongs = _queueController?.currentSongs;
              final currentSong = (_queueController != null &&
                      currentSongs != null &&
                      _queueController!.activeIndex >= 0 &&
                      _queueController!.activeIndex < currentSongs.length)
                  ? currentSongs[_queueController!.activeIndex]
                  : null;
              final isPlayingThis = currentSong == song;

              return ListTile(
                leading: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: DefaultCoverImage(
                    imageUrl: song.coverUrl,
                    width: 50,
                    height: 50,
                  ),
                ),
                title: Text(
                  song.title,
                  style: TextStyle(
                    color: isPlayingThis ? Theme.of(context).colorScheme.primary : Theme.of(context).colorScheme.onSurface,
                    fontWeight: isPlayingThis ? FontWeight.bold : FontWeight.normal,
                  ),
                ),
                subtitle: Text('${song.artist} • ${song.album}'),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.favorite, color: Colors.red),
                      onPressed: () => _toggleLiked(song),
                    ),
                    IconButton(
                      icon: const Icon(Icons.playlist_add, color: Colors.grey),
                      onPressed: () => _showAddToPlaylistDialog(song),
                    ),
                    if (isPlayingThis)
                      Padding(
                        padding: const EdgeInsets.only(left: 8.0),
                        child: Icon(Icons.equalizer, color: Theme.of(context).colorScheme.primary),
                      ),
                  ],
                ),
                onTap: () {
                  _setQueueAndPlay(likedSongs, index);
                },
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildSettingsView() {
    return SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Settings - Library Folders',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: TextField(
                  key: const Key('folder_input'),
                  controller: _folderController,
                  decoration: const InputDecoration(
                    hintText: 'Enter folder absolute path...',
                    filled: true,
                    fillColor: Colors.black26,
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              ElevatedButton.icon(
                icon: const Icon(Icons.add),
                label: const Text('Add Path'),
                onPressed: () {
                  final path = _folderController.text.trim();
                  if (path.isNotEmpty) {
                    _addFolder(path);
                    _folderController.clear();
                  }
                },
              ),
            ],
          ),
          const SizedBox(height: 16),
          ElevatedButton.icon(
            icon: const Icon(Icons.sync),
            label: const Text('Scan Library'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.primary,
              foregroundColor: Theme.of(context).colorScheme.onPrimary,
            ),
            onPressed: () async {
              setState(() => _isLoading = true);
              try {
                await http.post(Uri.parse('http://127.0.0.1:8000/api/scan'));
              } catch (e) {
                debugPrint("Error scanning: $e");
              }
              _fetchSongs();
            },
          ),
          const SizedBox(height: 16),
          const Divider(),
          const SizedBox(height: 16),
          const Text(
            'Theme Settings',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          ValueListenableBuilder<ThemeMode>(
            valueListenable: themeModeNotifier,
            builder: (context, currentMode, _) {
              return SegmentedButton<ThemeMode>(
                segments: const [
                  ButtonSegment(value: ThemeMode.system, label: Text('System')),
                  ButtonSegment(value: ThemeMode.light, label: Text('Light')),
                  ButtonSegment(value: ThemeMode.dark, label: Text('Dark')),
                ],
                selected: {currentMode},
                onSelectionChanged: (Set<ThemeMode> newSelection) {
                  themeModeNotifier.value = newSelection.first;
                },
              );
            },
          ),
          const SizedBox(height: 16),
          const Divider(),
          const SizedBox(height: 16),
          const Text(
            'Layout Settings',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          ElevatedButton.icon(
            icon: const Icon(Icons.dashboard_customize),
            label: const Text('Configure Layout'),
            onPressed: _showLayoutSettings,
          ),

          const SizedBox(height: 16),
          const Text('Select Primary Color:'),
          const SizedBox(height: 8),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              Colors.deepPurpleAccent,
              Colors.blueAccent,
              Colors.greenAccent,
              Colors.redAccent,
              Colors.orangeAccent,
              Colors.pinkAccent,
              Colors.tealAccent,
            ].map((color) {
              return GestureDetector(
                onTap: () {
                  themeColorNotifier.value = color;
                },
                child: ValueListenableBuilder<Color>(
                  valueListenable: themeColorNotifier,
                  builder: (context, currentColor, child) {
                    final isSelected = currentColor == color;
                    return Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: color,
                        shape: BoxShape.circle,
                        border: isSelected ? Border.all(color: Theme.of(context).colorScheme.onSurface, width: 3) : null,
                        boxShadow: isSelected
                            ? [BoxShadow(color: color.withOpacity(0.5), blurRadius: 8, spreadRadius: 2)]
                            : null,
                      ),
                    );
                  },
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 24),
          const Divider(),
          const SizedBox(height: 16),
          SizedBox(
            height: 300,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  flex: 3,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Registered Scan Folders:',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 8),
                      Expanded(
                        child: _folders.isEmpty
                            ? const Center(child: Text('No custom folders registered.'))
                            : ListView.builder(
                                itemCount: _folders.length,
                                itemBuilder: (context, index) {
                                  final folder = _folders[index];
                                  return ListTile(
                                    leading: const Icon(Icons.folder, color: Colors.amber),
                                    title: Text(folder['path'] as String),
                                    trailing: IconButton(
                                      icon: const Icon(Icons.delete, color: Colors.redAccent),
                                      onPressed: () => _deleteFolder(folder['id'] as int),
                                    ),
                                  );
                                },
                              ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  flex: 2,
                  child: DropTarget(
                    onDragDone: (details) async {
                      for (final file in details.files) {
                        await _addFolder(file.path);
                      }
                    },
                    onDragEntered: (details) => setState(() => _isFolderDragging = true),
                    onDragExited: (details) => setState(() => _isFolderDragging = false),
                    child: Container(
                      decoration: BoxDecoration(
                        border: Border.all(
                          color: _isFolderDragging ? Theme.of(context).colorScheme.primary : Colors.grey[700]!,
                          width: 2,
                          style: BorderStyle.solid,
                        ),
                        borderRadius: BorderRadius.circular(8),
                        color: _isFolderDragging ? Theme.of(context).colorScheme.primary.withOpacity(0.1) : Colors.transparent,
                      ),
                      child: const Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.folder_copy, size: 48, color: Colors.grey),
                            SizedBox(height: 8),
                            Text(
                              'Drag & Drop folders here\nto register them',
                              textAlign: TextAlign.center,
                              style: TextStyle(color: Colors.grey),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    ));
  }

  Widget _buildSidePanel() {
    final currentSongs = _queueController?.currentSongs;
    final currentSong = (_queueController != null &&
            currentSongs != null &&
            _queueController!.activeIndex >= 0 &&
            _queueController!.activeIndex < currentSongs.length)
        ? currentSongs[_queueController!.activeIndex]
        : null;
    if (currentSong == null) {
      return const Center(
        child: Text("Select a song to play", style: TextStyle(color: Colors.grey)),
      );
    }

    return Padding(
      padding: const EdgeInsets.all(24.0),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: DefaultCoverImage(
                  imageUrl: currentSong.coverUrl,
                  width: 200,
                  height: 200,
                ),
              ),
            ),
            const SizedBox(height: 24),
            Text(
              currentSong.title,
              style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              currentSong.artist,
              style: TextStyle(fontSize: 18, color: Theme.of(context).colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 32),
            const Text("Lyrics", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            FutureBuilder<String>(
              future: _fetchLyrics(currentSong),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting && currentSong.lyrics == 'Loading...') {
                  return const Center(child: Padding(padding: EdgeInsets.all(16), child: CircularProgressIndicator()));
                }
                return Text(
                  currentSong.lyrics,
                  style: TextStyle(fontSize: 16, height: 1.5, color: Theme.of(context).textTheme.bodyMedium?.color?.withOpacity(0.7)),
                );
              },
            )
          ],
        ),
      ),
    );
  }

  Widget _buildDynamicLayout() {
    switch (_layoutManager.currentMode) {
      case AppLayoutMode.spotify:
        return Row(
          children: [
            _buildSidebar(),
            const VerticalDivider(width: 1, color: Colors.grey),
            Expanded(flex: 3, child: _buildMainContent()),
            const VerticalDivider(width: 1, color: Colors.grey),
            Expanded(flex: 1, child: _buildSidePanel()),
          ],
        );
      case AppLayoutMode.ytMusic:
        return Row(
          children: [
            Expanded(flex: 4, child: _buildMainContent()),
            const VerticalDivider(width: 1, color: Colors.grey),
            Expanded(flex: 2, child: _buildSidePanel()),
          ],
        );
      case AppLayoutMode.custom:
        final children = <Widget>[];
        for (int i = 0; i < _layoutManager.customOrder.length; i++) {
          final panel = _layoutManager.customOrder[i];
          
          if (panel == 'sidebar' && _layoutManager.panelVisibility['sidebar'] == true) {
            if (_layoutManager.navStyle == 'sidebar') {
              children.add(_buildSidebar(width: _layoutManager.sidebarWidth));
              children.add(_buildDraggableDivider(onDrag: (dx) => _layoutManager.updateSidebarWidth(dx)));
            }
          } else if (panel == 'main' && _layoutManager.panelVisibility['main'] == true) {
            children.add(Expanded(child: _buildMainContent()));
          } else if (panel == 'sidepanel' && _layoutManager.panelVisibility['sidepanel'] == true) {
            if (children.isNotEmpty && children.last is Expanded) {
              children.add(_buildDraggableDivider(onDrag: (dx) => _layoutManager.updateSidePanelWidth(-dx)));
            }
            children.add(SizedBox(width: _layoutManager.sidePanelWidth, child: _buildSidePanel()));
          }
        }
        
        Widget row = Row(children: children);
        
        if (_layoutManager.navStyle == 'topBar' && _layoutManager.panelVisibility['sidebar'] == true) {
           return row;
        } else {
           return row;
        }
      case AppLayoutMode.classic:
      default:
        return Row(
          children: [
            _buildSidebar(),
            const VerticalDivider(width: 1, color: Colors.grey),
            Expanded(flex: 2, child: _buildMainContent()),
            const VerticalDivider(width: 1, color: Colors.grey),
            Expanded(flex: 1, child: _buildSidePanel()),
          ],
        );
    }
  }

  Widget _buildLayoutPreview() {
    return Container(
      height: 120,
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey.withOpacity(0.5)),
        borderRadius: BorderRadius.circular(8),
        color: Colors.black26,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            height: 12,
            decoration: BoxDecoration(color: Colors.blueGrey[800], borderRadius: const BorderRadius.vertical(top: Radius.circular(8))),
          ),
          if (_layoutManager.navStyle == 'topBar' && _layoutManager.panelVisibility['sidebar'] == true)
            Container(height: 12, color: Colors.blueGrey[700]),
          
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: _layoutManager.customOrder.map((panel) {
                if (_layoutManager.panelVisibility[panel] != true) return const SizedBox.shrink();
                if (panel == 'sidebar' && _layoutManager.navStyle == 'topBar') return const SizedBox.shrink();

                Color color = Colors.grey;
                int flex = 1;
                if (panel == 'sidebar') { color = Colors.green[900]!; flex = 1; }
                if (panel == 'main') { color = Colors.blue[900]!; flex = 3; }
                if (panel == 'sidepanel') { color = Colors.red[900]!; flex = 2; }
                
                return Expanded(
                  flex: flex,
                  child: Container(
                    margin: const EdgeInsets.all(2),
                    decoration: BoxDecoration(
                      color: color,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Center(
                      child: Text(
                        panel == 'sidebar' ? 'Nav' : panel == 'main' ? 'Main' : 'Side',
                        style: const TextStyle(fontSize: 10, color: Colors.white70),
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
          Container(
            height: 16, 
            decoration: BoxDecoration(color: Colors.purple[900], borderRadius: const BorderRadius.vertical(bottom: Radius.circular(8))),
          ),
        ],
      ),
    );
  }

  void _showLayoutSettings() {
    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('Layout Settings'),
              content: SizedBox(
                width: 400,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                    ...AppLayoutMode.values.map((mode) {
                      return RadioListTile<AppLayoutMode>(
                        title: Text(mode.name.toUpperCase()),
                        value: mode,
                        groupValue: _layoutManager.currentMode,
                        onChanged: (AppLayoutMode? value) {
                          if (value != null) {
                            _layoutManager.setMode(value);
                            setDialogState(() {});
                          }
                        },
                      );
                    }),
                    if (_layoutManager.currentMode == AppLayoutMode.custom) ...[
                      const Divider(height: 32),
                      const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                        child: Text('Navigation Style:', style: TextStyle(fontWeight: FontWeight.bold)),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16.0),
                        child: SegmentedButton<String>(
                          segments: const [
                            ButtonSegment(value: 'sidebar', label: Text('Sidebar')),
                            ButtonSegment(value: 'topBar', label: Text('Top Nav Bar')),
                          ],
                          selected: {_layoutManager.navStyle},
                          onSelectionChanged: (Set<String> newSelection) {
                            setDialogState(() {
                              _layoutManager.setNavStyle(newSelection.first);
                            });
                          },
                        ),
                      ),
                      const SizedBox(height: 16),
                      const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                        child: Text('Live Preview:', style: TextStyle(fontWeight: FontWeight.bold)),
                      ),
                      _buildLayoutPreview(),
                      const SizedBox(height: 16),
                      const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                        child: Text('Panel Visibility:', style: TextStyle(fontWeight: FontWeight.bold)),
                      ),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                          FilterChip(
                            label: const Text('Nav'),
                            selected: _layoutManager.panelVisibility['sidebar'] == true,
                            onSelected: (val) {
                              setDialogState(() => _layoutManager.setPanelVisibility('sidebar', val));
                            },
                          ),
                          FilterChip(
                            label: const Text('Main'),
                            selected: _layoutManager.panelVisibility['main'] == true,
                            onSelected: (val) {
                              setDialogState(() => _layoutManager.setPanelVisibility('main', val));
                            },
                          ),
                          FilterChip(
                            label: const Text('Side Panel'),
                            selected: _layoutManager.panelVisibility['sidepanel'] == true,
                            onSelected: (val) {
                              setDialogState(() => _layoutManager.setPanelVisibility('sidepanel', val));
                            },
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                        child: Text('Drag to Reorder Horizontal Panels:', style: TextStyle(fontWeight: FontWeight.bold)),
                      ),
                      SizedBox(
                        height: 200,
                        child: ReorderableListView(
                          shrinkWrap: true,
                          onReorder: (oldIndex, newIndex) {
                            setDialogState(() {
                              if (newIndex > oldIndex) newIndex -= 1;
                              final items = List<String>.from(_layoutManager.customOrder);
                              final item = items.removeAt(oldIndex);
                              items.insert(newIndex, item);
                              _layoutManager.setCustomOrder(items);
                            });
                          },
                          children: _layoutManager.customOrder.map((panel) {
                            String displayName = panel;
                            IconData icon = Icons.check_box_outline_blank;
                            if (panel == 'sidebar') { displayName = 'Navigation Area'; icon = Icons.view_sidebar; }
                            if (panel == 'main') { displayName = 'Main Library'; icon = Icons.library_music; }
                            if (panel == 'sidepanel') { displayName = 'Queue & Lyrics Panel'; icon = Icons.queue_music; }

                            return Card(
                              key: ValueKey(panel),
                              margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                              child: ListTile(
                                leading: Icon(icon),
                                title: Text(displayName),
                                enabled: _layoutManager.panelVisibility[panel] == true,
                              ),
                            );
                          }).toList(),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Close'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _buildBottomPlayer() {
    final currentSongs = _queueController?.currentSongs;
    final currentSong = (_queueController != null &&
            currentSongs != null &&
            _queueController!.activeIndex >= 0 &&
            _queueController!.activeIndex < currentSongs.length)
        ? currentSongs[_queueController!.activeIndex]
        : null;
    if (currentSong == null) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
      decoration: BoxDecoration(
        color: Theme.of(context).brightness == Brightness.dark ? Colors.grey[900] : Colors.grey[200],
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.5),
            blurRadius: 10,
            offset: const Offset(0, -2),
          )
        ],
      ),
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            StreamBuilder<PositionData>(
              stream: _positionDataStream,
              builder: (context, snapshot) {
                final positionData = snapshot.data;
                return ProgressBar(
                  progress: positionData?.position ?? Duration.zero,
                  buffered: positionData?.bufferedPosition ?? Duration.zero,
                  total: positionData?.duration ?? Duration.zero,
                  onSeek: _player.seek,
                  barHeight: 4,
                  thumbRadius: 6,
                );
              },
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                if (_layoutManager.currentMode != AppLayoutMode.spotify)
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: DefaultCoverImage(
                      imageUrl: currentSong.coverUrl,
                      width: 48,
                      height: 48,
                    ),
                  ),
                if (_layoutManager.currentMode != AppLayoutMode.spotify)
                  const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        currentSong.title,
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        currentSong.artist,
                        style: const TextStyle(color: Colors.grey, fontSize: 14),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.skip_previous),
                  onPressed: _queueController != null && (_queueController!.activeIndex > 0 || _queueController!.loopMode == CustomLoopMode.all) ? _playPrevious : null,
                ),
                StreamBuilder<PlayerState>(
                  stream: _player.playerStateStream,
                  builder: (context, snapshot) {
                    final playerState = snapshot.data;
                    final playing = playerState?.playing;
                    final processingState = playerState?.processingState;

                    if (processingState == ProcessingState.loading ||
                        processingState == ProcessingState.buffering) {
                      return const SizedBox(width: 48, height: 48, child: CircularProgressIndicator());
                    } else if (playing != true) {
                      return IconButton(
                        icon: const Icon(Icons.play_circle_fill),
                        iconSize: 48,
                        onPressed: _player.play,
                      );
                    } else {
                      return IconButton(
                        icon: const Icon(Icons.pause_circle_filled),
                        iconSize: 48,
                        onPressed: _player.pause,
                      );
                    }
                  },
                ),
                IconButton(
                  icon: const Icon(Icons.skip_next),
                  onPressed: _queueController != null && (_queueController!.activeIndex < _queueController!.currentSongs.length - 1 || _queueController!.loopMode == CustomLoopMode.all) ? _playNext : null,
                ),
                IconButton(
                  icon: const Icon(Icons.shuffle),
                  color: _queueController?.isShuffleEnabled == true ? Theme.of(context).colorScheme.primary : Colors.grey,
                  onPressed: () {
                    if (_queueController != null) {
                      setState(() {
                        _queueController!.setShuffleEnabled(!_queueController!.isShuffleEnabled);
                      });
                    }
                  },
                ),
                IconButton(
                  icon: Icon(
                    _queueController?.loopMode == CustomLoopMode.one ? Icons.repeat_one : Icons.repeat,
                  ),
                  color: _queueController?.loopMode == CustomLoopMode.off ? Colors.grey : Theme.of(context).colorScheme.primary,
                  onPressed: () {
                    if (_queueController != null) {
                      setState(() {
                        final currentMode = _queueController!.loopMode;
                        CustomLoopMode nextMode;
                        switch (currentMode) {
                          case CustomLoopMode.off:
                            nextMode = CustomLoopMode.all;
                            break;
                          case CustomLoopMode.all:
                            nextMode = CustomLoopMode.one;
                            break;
                          case CustomLoopMode.one:
                            nextMode = CustomLoopMode.off;
                            break;
                        }
                        _queueController!.setLoopMode(nextMode);
                      });
                    }
                  },
                ),
                IconButton(
                  icon: const Icon(Icons.equalizer),
                  onPressed: () {
                    showModalBottomSheet(
                      context: context,
                      backgroundColor: Colors.transparent,
                      builder: (context) {
                        return EQSheet(
                          eqController: _eqController,
                          onChanged: _applyEQ,
                        );
                      },
                    );
                  },
                ),
                const SizedBox(width: 8),
                StreamBuilder<double>(
                  stream: _player.volumeStream,
                  builder: (context, snapshot) {
                    final volume = snapshot.data ?? 1.0;
                    return HoverVolumeSlider(
                      volume: volume,
                      onChanged: _player.setVolume,
                    );
                  },
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<String> _fetchLyrics(Song song) async {
    if (song.lyrics != 'Loading...') {
      return song.lyrics;
    }
    try {
      final title = Uri.encodeComponent(song.title);
      final artist = Uri.encodeComponent(song.artist);
      final response = await http.get(Uri.parse('http://127.0.0.1:8000/api/lyrics?title=$title&artist=$artist'));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final fetched = data['lyrics'] as String? ?? 'No lyrics found.';
        final coverUrl = data['coverUrl'] as String?;
        if (mounted) {
          setState(() {
            song.lyrics = fetched;
            if (coverUrl != null && coverUrl.isNotEmpty) {
              song.coverUrl = coverUrl;
            }
          });
        }
        return fetched;
      }
    } catch (e) {
      debugPrint('Failed to fetch lyrics: $e');
    }
    return 'Failed to load lyrics.';
  }
}

class HoverVolumeSlider extends StatefulWidget {
  final double volume;
  final ValueChanged<double> onChanged;

  const HoverVolumeSlider({super.key, required this.volume, required this.onChanged});

  @override
  State<HoverVolumeSlider> createState() => _HoverVolumeSliderState();
}

class _HoverVolumeSliderState extends State<HoverVolumeSlider> {
  final LayerLink _layerLink = LayerLink();
  OverlayEntry? _overlayEntry;
  bool _isHoveringIcon = false;
  bool _isHoveringSlider = false;
  bool _isDragging = false;
  double _localVolume = 0.0;

  @override
  void initState() {
    super.initState();
    _localVolume = widget.volume;
  }

  void _showOverlay() {
    if (_overlayEntry != null) return;
    _localVolume = widget.volume;

    _overlayEntry = OverlayEntry(
      builder: (context) {
        return Positioned(
          width: 50,
          height: 160,
          child: CompositedTransformFollower(
            link: _layerLink,
            offset: const Offset(-9, -150),
            showWhenUnlinked: false,
            child: MouseRegion(
              onEnter: (_) {
                _isHoveringSlider = true;
              },
              onExit: (_) {
                _isHoveringSlider = false;
                _checkHide();
              },
              child: StatefulBuilder(
                builder: (context, setOverlayState) {
                  return Stack(
                    alignment: Alignment.topCenter,
                    children: [
                      // The actual visual slider container
                      Material(
                        elevation: 8,
                        borderRadius: BorderRadius.circular(20),
                        color: Theme.of(context).cardColor,
                        child: SizedBox(
                          width: 40,
                          height: 130,
                          child: RotatedBox(
                            quarterTurns: 3,
                            child: SliderTheme(
                              data: SliderTheme.of(context).copyWith(
                                trackHeight: 4.0,
                                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6.0),
                                overlayShape: const RoundSliderOverlayShape(overlayRadius: 12.0),
                              ),
                              child: Slider(
                                value: _localVolume,
                                min: 0.0,
                                max: 1.0,
                                onChangeStart: (_) => _isDragging = true,
                                onChangeEnd: (_) {
                                  _isDragging = false;
                                  _checkHide();
                                },
                                onChanged: (val) {
                                  setOverlayState(() {
                                    _localVolume = val;
                                  });
                                  widget.onChanged(val);
                                },
                              ),
                            ),
                          ),
                        ),
                      ),
                      // Transparent area to bridge the gap between slider and icon
                      Positioned(
                        bottom: 0,
                        left: 0,
                        right: 0,
                        height: 30,
                        child: Container(color: Colors.transparent),
                      ),
                    ],
                  );
                }
              ),
            ),
          ),
        );
      },
    );

    Overlay.of(context).insert(_overlayEntry!);
  }

  void _hideOverlay() {
    if (_isDragging) return;
    _overlayEntry?.remove();
    _overlayEntry = null;
  }

  void _checkHide() async {
    await Future.delayed(const Duration(milliseconds: 100));
    if (!_isHoveringIcon && !_isHoveringSlider && !_isDragging && mounted) {
      _hideOverlay();
    }
  }

  @override
  void dispose() {
    _hideOverlay();
    super.dispose();
  }

  @override
  void didUpdateWidget(HoverVolumeSlider oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_isDragging && oldWidget.volume != widget.volume) {
      _localVolume = widget.volume;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _overlayEntry != null) {
          _overlayEntry!.markNeedsBuild();
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return CompositedTransformTarget(
      link: _layerLink,
      child: MouseRegion(
        onEnter: (_) {
          _isHoveringIcon = true;
          _showOverlay();
        },
        onExit: (_) {
          _isHoveringIcon = false;
          _checkHide();
        },
        child: IconButton(
          icon: Icon(
            widget.volume == 0
                ? Icons.volume_off
                : widget.volume < 0.5
                    ? Icons.volume_down
                    : Icons.volume_up,
            color: Colors.grey,
          ),
          onPressed: () {
            widget.onChanged(widget.volume == 0 ? 1.0 : 0.0);
          },
        ),
      ),
    );
  }
}
