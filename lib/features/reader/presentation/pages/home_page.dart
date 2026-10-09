import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:digital_poth_gula/shared/widgets/adsterra_banner.dart';
import 'adsterra_interstitial_screen.dart';
import 'secure_reader_page.dart';
import 'package:digital_poth_gula/features/auth/login_page.dart';
import 'package:digital_poth_gula/features/writer/presentation/pages/writer_dashboard_page.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final _supabase = Supabase.instance.client;
  bool _isLoading = true;
  List<Map<String, dynamic>> _books = [];
  String? _userRole;
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _fetchBooks();
  }

  Future<void> _fetchBooks() async {
    setState(() => _isLoading = true);
    try {
      final user = _supabase.auth.currentUser;
      if (user == null) return;

      try {
        final userDoc = await _supabase
            .from('users')
            .select('role')
            .eq('id', user.id)
            .maybeSingle();
        if (userDoc != null && userDoc['role'] != null) {
          _userRole = userDoc['role'] as String;
        }
      } catch (_) {}

      final booksResponse = await _supabase.from('books').select();

      setState(() {
        _books = List<Map<String, dynamic>>.from(booksResponse);
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to load data: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _logout() async {
    await _supabase.auth.signOut();
    if (mounted) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const LoginPage()),
      );
    }
  }

  void _openBook(String bookId) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => AdsterraInterstitialScreen(
          bookId: bookId,
          onAdCompleted: () => _navigateToReader(bookId),
        ),
      ),
    );
  }

  void _navigateToReader(String bookId) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => SecureReaderPage(
          bookId: bookId,
          isPreview: false,
        ),
      ),
    );
  }

  Widget _buildBookCard(Map<String, dynamic> book) {
    final bookId = book['id'] as String;
    return Card(
      elevation: 4,
      margin: const EdgeInsets.only(bottom: 16),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (book['cover_image_url'] != null)
              GestureDetector(
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => FullScreenImageViewer(
                        imageUrl: book['cover_image_url'],
                        heroTag: 'cover_$bookId',
                      ),
                    ),
                  );
                },
                child: Hero(
                  tag: 'cover_$bookId',
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.network(
                      book['cover_image_url'],
                      width: 80,
                      height: 120,
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stackTrace) =>
                          const SizedBox(
                        width: 80,
                        height: 120,
                        child: Icon(Icons.book, size: 40, color: Colors.grey),
                      ),
                    ),
                  ),
                ),
              )
            else
              const SizedBox(
                width: 80,
                height: 120,
                child: Icon(Icons.book, size: 40, color: Colors.grey),
              ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    book['title'] ?? 'Unknown Title',
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    book['description'] ?? 'No description provided.',
                    style: TextStyle(color: Colors.grey[700]),
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton.icon(
                    icon: const Icon(Icons.menu_book),
                    label: const Text('Read Now'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blueAccent,
                      foregroundColor: Colors.white,
                    ),
                    onPressed: () => _openBook(bookId),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStore() {
    final filteredBooks = _books.where((book) {
      final title = (book['title'] ?? '').toString().toLowerCase();
      final desc = (book['description'] ?? '').toString().toLowerCase();
      final query = _searchQuery.toLowerCase();
      return title.contains(query) || desc.contains(query);
    }).toList();

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16.0),
          child: TextField(
            decoration: const InputDecoration(
              labelText: 'Search Books',
              prefixIcon: Icon(Icons.search),
              border: OutlineInputBorder(),
            ),
            onChanged: (value) {
              setState(() {
                _searchQuery = value;
              });
            },
          ),
        ),
        Expanded(
          child: filteredBooks.isEmpty
              ? const Center(child: Text('No books match your search.'))
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: filteredBooks.length,
                  itemBuilder: (context, index) {
                    final book = filteredBooks[index];
                    return _buildBookCard(book);
                  },
                ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Digital Poth Gula - Books'),
        actions: [
          if (_userRole == 'writer' || _userRole == 'admin')
            IconButton(
              icon: const Icon(Icons.dashboard_outlined),
              tooltip: 'Writer Dashboard',
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const WriterDashboardPage(),
                  ),
                ).then((_) => _fetchBooks());
              },
            ),
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: 'Logout',
            onPressed: _logout,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _buildStore(),
      bottomNavigationBar: const AdsterraBanner(height: 60),
    );
  }
}



class FullScreenImageViewer extends StatelessWidget {
  final String imageUrl;
  final String heroTag;

  const FullScreenImageViewer({
    super.key,
    required this.imageUrl,
    required this.heroTag,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      extendBodyBehindAppBar: true,
      body: InteractiveViewer(
        child: Center(
          child: Hero(
            tag: heroTag,
            child: Image.network(imageUrl),
          ),
        ),
      ),
    );
  }
}
