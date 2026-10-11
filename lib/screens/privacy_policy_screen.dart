import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/app_links.dart';

/// Shows the privacy policy inside the app (works offline).
class PrivacyPolicyScreen extends StatelessWidget {
  const PrivacyPolicyScreen({super.key});

  static const String _text = r'''PRIVACY POLICY - BG Remover
Package: com.albonik.bgremover
Developer: Albonik
Last updated: October 2026

1. Overview
BG Remover ("the app") removes image backgrounds and edits photos using AI models that run on your device. This policy explains what information the app handles.

2. Your photos
- Photos you pick or capture are processed on your device. They are not uploaded to our servers and we do not keep copies.
- Projects and exports are stored only in the app's private storage on your device. You can delete them at any time from within the app or by clearing the app's data.

3. Information we do not collect
We do not ask you to create an account. We do not collect your name, email address, phone number, contacts, or location.

4. AI model downloads
Some tools (Object Removal, Upscale, Select Subjects, and some background removal models) download model files the first time you use them. This is a normal file download; no photos or personal data are sent.

5. Advertising
The app shows ads through Unity LevelPlay and its partner ad networks. These services may collect and use device information such as the advertising ID, IP address, device model, operating system, and ad interaction data to deliver and measure ads and to prevent fraud. They may show personalized ads depending on your device settings and your consent choices. You can reset or opt out of personalized ads in your device settings (Settings > Privacy > Ads on Android). Each partner's use of data is governed by its own privacy policy:
- Unity: https://unity.com/legal/privacy-policy
- Google (AdMob): https://policies.google.com/privacy
Other networks are listed in the LevelPlay mediation documentation.

6. Permissions
- Camera: only to take a photo you ask to edit.
- Photos / media access: only to select images you choose and to save your results.
- Internet: for ads, model downloads, and update checks.

7. Data sharing
We do not sell your personal data. Data is shared only with the advertising services described above.

8. Data security and retention
Your images stay on your device. We keep no copies of your images on any server. Uninstalling the app removes its stored data.

9. Children
The app is not directed to children under 13, and we do not knowingly collect personal information from children.

10. Changes
We may update this policy from time to time. The latest version is always available at https://albonik.com/privacy-policy/bgremover.txt.

11. Contact
For questions about this policy, use the contact details on the app's Google Play page.''';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Privacy Policy'),
        actions: [
          IconButton(
            icon: const Icon(Icons.open_in_new),
            tooltip: 'Open online',
            onPressed: () => launchUrl(
              Uri.parse(AppLinks.privacyPolicyUrl),
              mode: LaunchMode.externalApplication,
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: SelectableText(
            _text,
            style: const TextStyle(fontSize: 14, height: 1.5),
          ),
        ),
      ),
    );
  }
}
