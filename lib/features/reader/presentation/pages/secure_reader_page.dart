import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:screen_protector/screen_protector.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:epub_view/epub_view.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SecureReaderPage extends StatefulWidget {
  final String bookId;
  final bool isPreview;

  const SecureReaderPage({
    super.key,
    required this.bookId,
    this.isPreview = false,
  });

  @override
  State<SecureReaderPage> createState() => _SecureReaderPageState();
}

class _SecureReaderPageState extends State<SecureReaderPage> with WidgetsBindingObserver {
  EpubController? _epubController;
  bool _isLoading = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _secureScreen();
    _fetchBookUrl();
  }

  Future<void> _secureScreen() async {
    // Add FLAG_SECURE to prevent screenshots and screen recording on Android
    if (!kIsWeb) {
      await ScreenProtector.preventScreenshotOn();
    }
  }

  Future<void> _fetchBookUrl() async {
    try {
      final response = await Supabase.instance.client.functions.invoke(
        'generate-book-url',
        body: {
          'book_id': widget.bookId,
          'bookId': widget.bookId,
          'isPreview': widget.isPreview,
        },
      );

      if (response.status == 200 && response.data != null) {
        final url = response.data['signedUrl'] as String?;
        if (url != null) {
          // Fetch bytes directly to bypass Flutter Web iframe/network viewer quirks
          final pdfResponse = await http.get(
            Uri.parse(url),
            headers: {
              'Accept': 'application/pdf',
              'Access-Control-Allow-Origin': '*',
            },
          );

          if (pdfResponse.statusCode == 200 && pdfResponse.bodyBytes.isNotEmpty) {
            setState(() {
              _epubController = EpubController(
                document: EpubDocument.openData(pdfResponse.bodyBytes),
              );
              _isLoading = false;
            });
          } else {
            // Handle empty bytes error
            debugPrint('Error: Fetched bytes are empty or status is not 200');
            setState(() {
              _errorMessage =
                  'Failed to fetch EPUB content (HTTP ${pdfResponse.statusCode}, size: ${pdfResponse.bodyBytes.length} bytes)';
              _isLoading = false;
            });
          }
        } else {
          setState(() {
            _errorMessage = response.data['error'] ?? 'No signed URL returned.';
            _isLoading = false;
          });
        }
      } else {
        setState(() {
          _errorMessage = response.data?['error'] ?? 'Failed to load book.';
          _isLoading = false;
        });
      }
    } on FunctionException catch (e) {
      // Supabase specific function exceptions
      setState(() {
        _errorMessage = e.details?['error'] ?? 'Not authorized to read this book.';
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _errorMessage = 'An error occurred while trying to load the book: $e';
        _isLoading = false;
      });
    }
  }

  void _saveBookmark() {
    if (_epubController != null && _epubController!.currentValue != null) {
      final currentChapter = _epubController!.currentValue?.chapterNumber;
      final currentParagraph = _epubController!.currentValue?.paragraphNumber;
      
      if (currentChapter != null) {
        SharedPreferences.getInstance().then((prefs) {
          prefs.setInt('bookmark_chap_${widget.bookId}', currentChapter);
          if (currentParagraph != null) {
            prefs.setInt('bookmark_para_${widget.bookId}', currentParagraph);
          }
        });
      }
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused || state == AppLifecycleState.inactive) {
      _saveBookmark();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _saveBookmark();

    // Ensure we remove the secure flag when the user leaves the reader page
    if (!kIsWeb) {
      ScreenProtector.preventScreenshotOff();
    }
    _epubController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.isPreview ? 'Book Preview' : 'Secure Book Reader'),
        backgroundColor: Colors.black87,
        foregroundColor: Colors.white,
      ),
      backgroundColor: Colors.grey[200],
      body: SafeArea(
        child: _buildBody(),
      ),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(),
      );
    }

    if (_errorMessage != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline, color: Colors.redAccent, size: 64),
              const SizedBox(height: 16),
              Text(
                _errorMessage!,
                style: const TextStyle(color: Colors.redAccent, fontSize: 16),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: () {
                  setState(() {
                    _isLoading = true;
                    _errorMessage = null;
                  });
                  _fetchBookUrl();
                },
                icon: const Icon(Icons.refresh),
                label: const Text('Try Again'),
              ),
            ],
          ),
        ),
      );
    }

    if (_epubController != null) {
      return EpubView(
        controller: _epubController!,
        onDocumentLoaded: (document) async {
          final prefs = await SharedPreferences.getInstance();
          final savedChapter = prefs.getInt('bookmark_chap_${widget.bookId}');
          
          if (savedChapter != null) {
            // Restore chapter position safely after a short delay
            Future.delayed(const Duration(milliseconds: 250), () {
              if (mounted && _epubController != null) {
                _epubController!.scrollTo(index: savedChapter);
              }
            });
          }
        },
      );
    }

    return const Center(child: Text('Failed to retrieve the book data.'));
  }
}
