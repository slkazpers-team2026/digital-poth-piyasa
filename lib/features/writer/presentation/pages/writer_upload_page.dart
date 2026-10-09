import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class WriterUploadPage extends StatefulWidget {
  const WriterUploadPage({super.key});

  @override
  State<WriterUploadPage> createState() => _WriterUploadPageState();
}

class _WriterUploadPageState extends State<WriterUploadPage> {
  final _formKey = GlobalKey<FormState>();

  final TextEditingController _titleController = TextEditingController();
  final TextEditingController _descriptionController = TextEditingController();


  Uint8List? _coverImageBytes;
  String? _coverImageName;

  Uint8List? _fullBookBytes;
  String? _fullBookName;

  Uint8List? _previewBookBytes;
  String? _previewBookName;

  bool _isLoading = false;

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();

    super.dispose();
  }

  Future<void> _pickCoverImage() async {
    try {
      final ImagePicker picker = ImagePicker();
      final XFile? image = await picker.pickImage(source: ImageSource.gallery);
      
      if (image != null) {
        final bytes = await image.readAsBytes();
        setState(() {
          _coverImageBytes = bytes;
          _coverImageName = image.name;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error picking cover image: $e')),
        );
      }
    }
  }

  Future<void> _pickFullBook() async {
    try {
      final result = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['epub'],
      );

      if (result != null && result.isNotEmpty) {
        final platformFile = result.first;
        final bytes = await platformFile.readAsBytes();
        setState(() {
          _fullBookBytes = bytes;
          _fullBookName = platformFile.name;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error picking full book: $e')),
        );
      }
    }
  }

  Future<void> _pickPreviewBook() async {
    try {
      final result = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['epub'],
      );

      if (result != null && result.isNotEmpty) {
        final platformFile = result.first;
        final bytes = await platformFile.readAsBytes();
        setState(() {
          _previewBookBytes = bytes;
          _previewBookName = platformFile.name;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error picking preview book: $e')),
        );
      }
    }
  }

  Future<String> _uploadFileToR2(Uint8List fileBytes, String extension) async {
    final response = await Supabase.instance.client.functions.invoke(
      'get-upload-url',
      body: {'fileExtension': extension},
    );

    if (response.status != 200 || response.data == null) {
      final errorMsg = response.data?['error'] ?? 'Failed to get upload URL (status ${response.status})';
      throw Exception(errorMsg);
    }

    final uploadUrl = response.data['uploadUrl'] as String?;
    final fileKey = response.data['fileKey'] as String?;

    if (uploadUrl == null || fileKey == null) {
      throw Exception('Invalid response from upload service: missing URL or key');
    }

    final putResponse = await http.put(
      Uri.parse(uploadUrl),
      body: fileBytes,
      headers: {'Content-Type': extension == '.epub' ? 'application/epub+zip' : 'application/octet-stream'},
    );

    if (putResponse.statusCode != 200) {
      throw Exception('Failed to upload to storage: HTTP ${putResponse.statusCode} ${putResponse.reasonPhrase}');
    }

    return fileKey;
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    if (_coverImageBytes == null || _fullBookBytes == null || _previewBookBytes == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please select a Cover Image, Full Book, and Preview Book.'),
          backgroundColor: Colors.redAccent,
        ),
      );
      return;
    }

    final currentUser = Supabase.instance.client.auth.currentUser;
    if (currentUser == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('User not authenticated. Please log in.'),
          backgroundColor: Colors.redAccent,
        ),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      // Upload Cover Image to Supabase Storage
      final coverExtension = _coverImageName?.split('.').last ?? 'png';
      final coverPath = '${currentUser.id}/${DateTime.now().millisecondsSinceEpoch}.$coverExtension';
      await Supabase.instance.client.storage.from('covers').uploadBinary(
            coverPath,
            _coverImageBytes!,
          );
      final coverImageUrl = Supabase.instance.client.storage.from('covers').getPublicUrl(coverPath);

      // Upload Full Book EPUB to R2
      final fullFileKey = await _uploadFileToR2(_fullBookBytes!, '.epub');
      
      // Upload Preview Book EPUB to R2
      final previewFileKey = await _uploadFileToR2(_previewBookBytes!, '.epub');

      // Insert record into books table
      await Supabase.instance.client.from('books').insert({
        'title': _titleController.text.trim(),
        'description': _descriptionController.text.trim(),
        'author_id': currentUser.id,
        'cover_image_url': coverImageUrl,
        'r2_full_file_key': fullFileKey,
        'r2_preview_file_key': previewFileKey,

      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Book uploaded and registered successfully!'),
            backgroundColor: Colors.green,
          ),
        );
        _resetForm();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to submit book: $e'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _resetForm() {
    _formKey.currentState?.reset();
    _titleController.clear();
    _descriptionController.clear();

    setState(() {
      _coverImageBytes = null;
      _coverImageName = null;
      _fullBookBytes = null;
      _fullBookName = null;
      _previewBookBytes = null;
      _previewBookName = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Writer Studio - Upload Book'),
        backgroundColor: Colors.indigo,
        foregroundColor: Colors.white,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 600),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Card(
                      elevation: 2,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      child: Padding(
                        padding: const EdgeInsets.all(20.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('Book Details', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.indigo)),
                            const SizedBox(height: 16),
                            TextFormField(
                              controller: _titleController,
                              decoration: const InputDecoration(labelText: 'Book Title', border: OutlineInputBorder(), prefixIcon: Icon(Icons.title)),
                              validator: (val) => (val == null || val.trim().isEmpty) ? 'Please enter book title' : null,
                            ),
                            const SizedBox(height: 16),
                            TextFormField(
                              controller: _descriptionController,
                              maxLines: 3,
                              decoration: const InputDecoration(labelText: 'Description', border: OutlineInputBorder(), alignLabelWithHint: true, prefixIcon: Icon(Icons.description)),
                              validator: (val) => (val == null || val.trim().isEmpty) ? 'Please enter book description' : null,
                            ),

                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                    Card(
                      elevation: 2,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      child: Padding(
                        padding: const EdgeInsets.all(20.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('Book Files & Cover', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.indigo)),
                            const SizedBox(height: 16),
                            _buildFilePickerRow(
                              title: 'Cover Image',
                              fileName: _coverImageName,
                              icon: Icons.image,
                              onPressed: _pickCoverImage,
                            ),
                            const SizedBox(height: 16),
                            _buildFilePickerRow(
                              title: 'Full Book (EPUB)',
                              fileName: _fullBookName,
                              icon: Icons.book,
                              onPressed: _pickFullBook,
                            ),
                            const SizedBox(height: 16),
                            _buildFilePickerRow(
                              title: 'Preview Book (EPUB)',
                              fileName: _previewBookName,
                              icon: Icons.preview,
                              onPressed: _pickPreviewBook,
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 28),
                    ElevatedButton(
                      onPressed: _isLoading ? null : _submit,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.indigo,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      child: _isLoading
                          ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                          : const Text('Submit & Upload Book', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildFilePickerRow({required String title, required String? fileName, required IconData icon, required VoidCallback onPressed}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        OutlinedButton.icon(
          onPressed: _isLoading ? null : onPressed,
          icon: Icon(icon),
          label: Text(fileName == null ? 'Select $title' : 'Change $title'),
          style: OutlinedButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
            side: BorderSide(color: fileName == null ? Colors.grey : Colors.indigo),
          ),
        ),
        if (fileName != null) ...[
          const SizedBox(height: 8),
          Row(
            children: [
              const Icon(Icons.check_circle, color: Colors.green, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  fileName,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }
}
