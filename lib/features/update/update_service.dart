import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

class UpdateService {
  static Future<bool> checkForUpdates(BuildContext context) async {
    try {
      final supabase = Supabase.instance.client;
      final response = await supabase
          .from('app_versions')
          .select()
          .order('version_code', ascending: false)
          .limit(1)
          .maybeSingle();

      if (response == null) return false;

      final int latestVersionCode = response['version_code'] as int;
      final String downloadUrl = response['download_url'] as String;
      final bool isMandatory = response['is_mandatory'] as bool? ?? false;
      final String? releaseNotes = response['release_notes'] as String?;

      final PackageInfo packageInfo = await PackageInfo.fromPlatform();
      final int currentVersionCode = int.tryParse(packageInfo.buildNumber) ?? 0;

      if (latestVersionCode > currentVersionCode) {
        if (!context.mounted) return false;
        _showUpdateDialog(context, downloadUrl, isMandatory, releaseNotes);
        return isMandatory; // Return true if it's mandatory, blocking further actions
      }
    } catch (e) {
      debugPrint('Error checking for updates: $e');
    }
    return false;
  }

  static void _showUpdateDialog(
      BuildContext context, String downloadUrl, bool isMandatory, String? releaseNotes) {
    showDialog(
      context: context,
      barrierDismissible: !isMandatory,
      builder: (BuildContext context) {
        return PopScope(
          canPop: !isMandatory,
          child: AlertDialog(
            title: const Text('Update Available'),
            content: SingleChildScrollView(
              child: ListBody(
                children: [
                  const Text('A new version of the app is available.'),
                  if (releaseNotes != null && releaseNotes.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    const Text('Release Notes:', style: TextStyle(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 5),
                    Text(releaseNotes),
                  ],
                ],
              ),
            ),
            actions: [
              if (!isMandatory)
                TextButton(
                  child: const Text('Later'),
                  onPressed: () {
                    Navigator.of(context).pop();
                  },
                ),
              ElevatedButton(
                child: const Text('Update Now'),
                onPressed: () async {
                  final Uri url = Uri.parse(downloadUrl);
                  if (await canLaunchUrl(url)) {
                    await launchUrl(url, mode: LaunchMode.externalApplication);
                  }
                },
              ),
            ],
          ),
        );
      },
    );
  }
}
