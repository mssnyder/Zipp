import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../config/theme.dart';
import '../../services/api_service.dart';

class GifPicker extends StatefulWidget {
  const GifPicker({super.key});

  @override
  State<GifPicker> createState() => _GifPickerState();
}

class _GifPickerState extends State<GifPicker> {
  final _searchCtrl = TextEditingController();
  List<dynamic> _results = [];
  bool _loading = false;
  String _query = '';

  @override
  void initState() {
    super.initState();
    _loadTrending();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadTrending() async {
    setState(() => _loading = true);
    try {
      final api = context.read<ApiService>();
      _results = await api.getTrendingGifs();
    } catch (_) {}
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _search(String q) async {
    _query = q;
    if (q.isEmpty) { _loadTrending(); return; }
    setState(() => _loading = true);
    try {
      final api = context.read<ApiService>();
      _results = await api.searchGifs(q);
    } catch (_) {}
    if (mounted) setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.6,
        maxChildSize: 0.9,
        minChildSize: 0.4,
        builder: (_, scrollCtrl) => Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(12),
              child: TextField(
                controller: _searchCtrl,
                decoration: InputDecoration(
                  hintText: 'Search GIFs…',
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: _searchCtrl.text.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear),
                          onPressed: () {
                            _searchCtrl.clear();
                            _search('');
                          },
                        )
                      : null,
                ),
                onChanged: (v) {
                  setState(() {});
                  _search(v);
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(
                children: [
                  const Icon(Icons.gif, color: ZippTheme.textSecondary, size: 16),
                  const SizedBox(width: 4),
                  Text(
                    _query.isEmpty ? 'Trending' : 'Results for "$_query"',
                    style: const TextStyle(color: ZippTheme.textSecondary, fontSize: 12),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _results.isEmpty
                      ? const Center(child: Text('No GIFs found'))
                      : GridView.builder(
                          controller: scrollCtrl,
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 2,
                            crossAxisSpacing: 6,
                            mainAxisSpacing: 6,
                            childAspectRatio: 1.5,
                          ),
                          itemCount: _results.length,
                          itemBuilder: (ctx, i) {
                            final r = _results[i] as Map<String, dynamic>;
                            final tinyUrl = r['file']?['xs']?['gif']?['url'] as String?;
                            if (tinyUrl == null) return const SizedBox.shrink();
                            return GestureDetector(
                              onTap: () => Navigator.of(context).pop(r),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(8),
                                child: CachedNetworkImage(
                                  imageUrl: tinyUrl,
                                  fit: BoxFit.cover,
                                  placeholder: (_, __) => Container(color: ZippTheme.surfaceVariant),
                                  errorWidget: (_, __, ___) => const Icon(Icons.broken_image),
                                ),
                              ),
                            );
                          },
                        ),
            ),
          ],
        ),
      );
}
