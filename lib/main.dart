// Jamendo Music Player - single-file main.dart
// Requires pubspec.yaml with: http, just_audio
// Replace jamendoClientId if you have another one. Do NOT include the client secret.

import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:just_audio/just_audio.dart';

void main() {
  runApp(const JamendoApp());
}

/// -- PUBLIC Client ID (safe to use on client-side)
const String jamendoClientId = "d16803b0";

class JamendoApp extends StatelessWidget {
  const JamendoApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Musico — Jamendo Player',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark(useMaterial3: true).copyWith(
        scaffoldBackgroundColor: Colors.black,
        colorScheme: ColorScheme.dark(primary: Colors.orangeAccent),
      ),
      home: const MusicHomePage(),
    );
  }
}

class Track {
  final String id;
  final String name;
  final String artistName;
  final String albumName;
  final int duration; // seconds
  final String audioUrl;
  final String imageUrl;
  Track({
    required this.id,
    required this.name,
    required this.artistName,
    required this.albumName,
    required this.duration,
    required this.audioUrl,
    required this.imageUrl,
  });

  factory Track.fromJson(Map<String, dynamic> j) {
    return Track(
      id: (j['id'] ?? '').toString(),
      name: j['name'] ?? '',
      artistName: j['artist_name'] ?? '',
      albumName: j['album_name'] ?? '',
      duration: (j['duration'] ?? 0) as int,
      audioUrl: (j['audio'] ?? '') as String,
      imageUrl: (j['album_image'] ?? '') as String,
    );
  }
}

class MusicHomePage extends StatefulWidget {
  const MusicHomePage({super.key});
  @override
  State<MusicHomePage> createState() => _MusicHomePageState();
}

class _MusicHomePageState extends State<MusicHomePage> {
  final TextEditingController _searchController = TextEditingController();
  final AudioPlayer _player = AudioPlayer();
  List<Track> _searchResults = [];
  List<Track> _queue = [];
  int _currentIndexInQueue = -1;
  bool _isLoading = false;
  bool _isShuffle = false;
  String? _error;
  StreamSubscription<PlaybackEvent>? _playbackSub;

  @override
  void initState() {
    super.initState();
    _playbackSub = _player.playbackEventStream.listen(_onPlaybackEvent);
    // try a friendly default search
    WidgetsBinding.instance.addPostFrameCallback((_) => _search('lofi'));
  }

  @override
  void dispose() {
    _playbackSub?.cancel();
    _player.dispose();
    _searchController.dispose();
    super.dispose();
  }

  // Jamendo search for tracks
  Future<List<Track>> _fetchTracksForQuery(String query, {int limit = 30}) async {
    final uri = Uri.parse(
        'https://api.jamendo.com/v3.0/tracks/?client_id=$jamendoClientId&format=json&limit=$limit&audioformat=mp32&search=${Uri.encodeComponent(query)}');
    final r = await http.get(uri);
    if (r.statusCode != 200) throw Exception('HTTP ${r.statusCode}');
    final body = json.decode(r.body) as Map<String, dynamic>;
    final results = (body['results'] as List<dynamic>? ?? []);
    final tracks = results.map((e) => Track.fromJson(e as Map<String, dynamic>)).toList();
    return tracks;
  }

  // Fetch tracks by artist id/name: using search by artist name gives results
  Future<List<Track>> _fetchTracksByArtist(String artistName, {int limit = 30}) async {
    if (artistName.trim().isEmpty) return [];
    // use artists endpoint to get an artist id, then fetch tracks by artist_id
    final artistUri = Uri.parse(
        'https://api.jamendo.com/v3.0/artists/?client_id=$jamendoClientId&format=json&limit=5&search=${Uri.encodeComponent(artistName)}');
    final artResp = await http.get(artistUri);
    if (artResp.statusCode != 200) return [];
    final artBody = json.decode(artResp.body) as Map<String, dynamic>;
    final artResults = (artBody['results'] as List<dynamic>? ?? []);
    if (artResults.isEmpty) return [];
    final topArtistId = (artResults[0]['id'] ?? '').toString();
    final tracksUri = Uri.parse(
        'https://api.jamendo.com/v3.0/tracks/?client_id=$jamendoClientId&format=json&limit=$limit&audioformat=mp32&artist_id=$topArtistId');
    final trResp = await http.get(tracksUri);
    if (trResp.statusCode != 200) return [];
    final trBody = json.decode(trResp.body) as Map<String, dynamic>;
    final trResults = (trBody['results'] as List<dynamic>? ?? []);
    return trResults.map((e) => Track.fromJson(e as Map<String, dynamic>)).toList();
  }

  // Public method triggered by search UI
  Future<void> _search(String query) async {
    setState(() {
      _isLoading = true;
      _error = null;
      _searchResults = [];
    });
    try {
      final results = await _fetchTracksForQuery(query, limit: 40);
      setState(() {
        _searchResults = results;
      });
    } catch (e) {
      setState(() {
        _error = 'Search failed: $e';
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  // Build queue from list and optionally start at index
  Future<void> _setQueue(List<Track> tracks, {int startIndex = 0, bool playImmediately = true}) async {
    if (tracks.isEmpty) return;
    final newQueue = List<Track>.from(tracks);
    if (_isShuffle) {
      newQueue.shuffle();
    }
    setState(() {
      _queue = newQueue;
      _currentIndexInQueue = startIndex.clamp(0, newQueue.length - 1);
    });
    if (playImmediately) {
      await _playAtIndex(_currentIndexInQueue);
    }
  }

  // Add tracks to queue (append)
  void _appendToQueue(List<Track> tracks) {
    setState(() {
      _queue.addAll(tracks);
    });
  }

  Future<void> _playAtIndex(int index) async {
    if (index < 0 || index >= _queue.length) return;
    final t = _queue[index];
    try {
      setState(() {
        _currentIndexInQueue = index;
      });
      await _player.setUrl(t.audioUrl);
      await _player.play();
    } catch (e) {
      // If playback fails, try to skip to next
      debugPrint('Playback error: $e');
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Playback failed: ${t.name}')));
      await _playNext();
    }
  }

  Future<void> _playNext() async {
    if (_queue.isEmpty) return;
    // Normal increment
    int nextIndex = _currentIndexInQueue + 1;
    if (nextIndex < _queue.length) {
      await _playAtIndex(nextIndex);
      return;
    }

    // Queue ended. Try to find similar tracks for last played track.
    final last = _queue[_currentIndexInQueue];
    final similar = await _fetchTracksByArtist(last.artistName, limit: 20);
    final filtered = similar.where((t) => t.id != last.id).toList();
    if (filtered.isNotEmpty) {
      // append some similar and play first appended
      _appendToQueue(filtered);
      await _playAtIndex(_currentIndexInQueue + 1);
      return;
    }

    // Fallback: use current search results (if any) to continue
    final fallback = _searchResults.where((t) => t.id != last.id).toList();
    if (fallback.isNotEmpty) {
      _appendToQueue(fallback);
      await _playAtIndex(_currentIndexInQueue + 1);
      return;
    }

    // Nothing else -> stop
    await _player.stop();
    setState(() {});
  }

  Future<void> _playPrevious() async {
    if (_queue.isEmpty) return;
    final prev = (_currentIndexInQueue - 1).clamp(0, _queue.length - 1);
    await _playAtIndex(prev);
  }

  void _toggleShuffle() {
    setState(() {
      _isShuffle = !_isShuffle;
    });
    // reshuffle current queue while keeping the current track at front
    if (_queue.isNotEmpty) {
      final current = _queue[_currentIndexInQueue];
      final rest = List<Track>.from(_queue)..removeAt(_currentIndexInQueue);
      if (_isShuffle) {
        rest.shuffle();
      }
      setState(() {
        _queue = [current, ...rest];
        _currentIndexInQueue = 0;
      });
    }
  }

  // Attempts to play a given "similar next" immediately by fetching artist tracks
  Future<void> _playSimilarNext() async {
    if (_queue.isEmpty) return;
    final current = _queue[_currentIndexInQueue];
    final similar = await _fetchTracksByArtist(current.artistName, limit: 20);
    final candidates = similar.where((t) => t.id != current.id).toList();
    if (candidates.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No similar tracks found')));
      return;
    }
    // Insert the first candidate right after current index
    setState(() {
      _queue.insert(_currentIndexInQueue + 1, candidates.first);
    });
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Queued similar: ${candidates.first.name}')));
  }

  void _onPlaybackEvent(PlaybackEvent event) {
    // When the player reports that playback completed, advance to next
    if (event.processingState == ProcessingState.completed) {
      _playNext();
    }
    setState(() {}); // to update UI (playing/paused)
  }

  Widget _buildSearchBar() {
    return Padding(
      padding: const EdgeInsets.all(12.0),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _searchController,
              textInputAction: TextInputAction.search,
              onSubmitted: (v) => _search(v),
              decoration: InputDecoration(
                hintText: 'Search Jamendo (artist, track, genre...)',
                prefixIcon: const Icon(Icons.search),
                filled: true,
              ),
            ),
          ),
          const SizedBox(width: 8),
          ElevatedButton(
            onPressed: () => _search(_searchController.text),
            child: const Text('Search'),
          ),
        ],
      ),
    );
  }

  Widget _buildResultsList() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(child: Text(_error!, style: const TextStyle(color: Colors.redAccent)));
    }
    if (_searchResults.isEmpty) {
      return const Center(child: Text('No results — try broader terms like "lofi" or "piano".'));
    }
    return ListView.builder(
      itemCount: _searchResults.length,
      itemBuilder: (context, index) {
        final t = _searchResults[index];
        return ListTile(
          leading: t.imageUrl.isNotEmpty
              ? Image.network(t.imageUrl, width: 56, height: 56, fit: BoxFit.cover)
              : const SizedBox(width: 56, height: 56),
          title: Text(t.name, maxLines: 1, overflow: TextOverflow.ellipsis),
          subtitle: Text('${t.artistName} • ${t.albumName}'),
          trailing: IconButton(
            icon: const Icon(Icons.queue_music),
            onPressed: () {
              // append this single track to queue
              _appendToQueue([t]);
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Added to queue: ${t.name}')));
            },
          ),
          onTap: () async {
            // make this track the start of a new queue and play
            await _setQueue([t, ..._searchResults.where((x) => x.id != t.id)], startIndex: 0, playImmediately: true);
          },
        );
      },
    );
  }

  Widget _buildPlaybackBar() {
    final playing = _player.playing;
    final currentTrack = (_currentIndexInQueue >= 0 && _currentIndexInQueue < _queue.length) ? _queue[_currentIndexInQueue] : null;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (currentTrack != null)
          ListTile(
            leading: currentTrack.imageUrl.isNotEmpty
                ? Image.network(currentTrack.imageUrl, width: 56, height: 56, fit: BoxFit.cover)
                : const SizedBox(width: 56, height: 56),
            title: Text(currentTrack.name, maxLines: 1, overflow: TextOverflow.ellipsis),
            subtitle: Text(currentTrack.artistName),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(onPressed: _playPrevious, icon: const Icon(Icons.skip_previous)),
                IconButton(
                  onPressed: () async {
                    if (playing) {
                      await _player.pause();
                    } else {
                      await _player.play();
                    }
                    setState(() {});
                  },
                  icon: Icon(playing ? Icons.pause_circle_filled : Icons.play_circle_fill, size: 36),
                ),
                IconButton(onPressed: _playNext, icon: const Icon(Icons.skip_next)),
              ],
            ),
          ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 6),
          child: Row(
            children: [
              IconButton(
                onPressed: _toggleShuffle,
                icon: Icon(_isShuffle ? Icons.shuffle_on : Icons.shuffle),
                tooltip: 'Shuffle',
              ),
              const SizedBox(width: 8),
              ElevatedButton.icon(
                onPressed: _playSimilarNext,
                icon: const Icon(Icons.auto_fix_high),
                label: const Text('Play Similar Next'),
              ),
              const Spacer(),
              Text('Queue: ${_queue.length}', style: const TextStyle(fontSize: 12)),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildQueueView() {
    if (_queue.isEmpty) return const SizedBox.shrink();
    return SizedBox(
      height: 160,
      child: ReorderableListView.builder(
        scrollDirection: Axis.horizontal,
        onReorder: (oldIndex, newIndex) {
          setState(() {
            if (oldIndex < newIndex) newIndex -= 1;
            final moved = _queue.removeAt(oldIndex);
            _queue.insert(newIndex, moved);
            // adjust current index if necessary
            if (_currentIndexInQueue == oldIndex) {
              _currentIndexInQueue = newIndex;
            } else if (oldIndex < _currentIndexInQueue && newIndex >= _currentIndexInQueue) {
              _currentIndexInQueue -= 1;
            } else if (oldIndex > _currentIndexInQueue && newIndex <= _currentIndexInQueue) {
              _currentIndexInQueue += 1;
            }
          });
        },
        itemCount: _queue.length,
        itemBuilder: (context, index) {
          final t = _queue[index];
          final selected = index == _currentIndexInQueue;
          return SizedBox(
            key: ValueKey(t.id),
            width: 220,
            child: Card(
              color: selected ? Colors.orange.shade900 : null,
              child: ListTile(
                title: Text(t.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                subtitle: Text(t.artistName, maxLines: 1, overflow: TextOverflow.ellipsis),
                onTap: () => _playAtIndex(index),
                trailing: IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () {
                    setState(() {
                      final removedBeforeCurrent = index < _currentIndexInQueue;
                      _queue.removeAt(index);
                      if (removedBeforeCurrent) _currentIndexInQueue -= 1;
                      if (_queue.isEmpty) {
                        _currentIndexInQueue = -1;
                        _player.stop();
                      } else if (_currentIndexInQueue >= _queue.length) {
                        _currentIndexInQueue = _queue.length - 1;
                      }
                    });
                  },
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final body = Column(
      children: [
        _buildSearchBar(),
        Expanded(child: _buildResultsList()),
        const Divider(height: 1),
        _buildQueueView(),
        const Divider(height: 1),
        _buildPlaybackBar(),
      ],
    );

    return Scaffold(
      appBar: AppBar(
        title: const Text('Musico — Jamendo Music'),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => _search(_searchController.text.isEmpty ? 'lofi' : _searchController.text),
            tooltip: 'Refresh search',
          ),
        ],
      ),
      body: body,
    );
  }
}
