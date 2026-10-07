import 'package:flutter/material.dart';

/// Lightweight manual localization — avoids the extra build-time codegen
/// setup of flutter gen-l10n while still giving full Bangla support.
/// Usage: AppStrings.of(context).home
class AppStrings {
  final Locale locale;
  AppStrings(this.locale);

  static AppStrings of(BuildContext context) {
    final locale = Localizations.localeOf(context);
    return AppStrings(locale);
  }

  bool get _isBn => locale.languageCode == 'bn';

  String get appTitle => _isBn ? 'বিজি রিমুভার' : 'BG Remover';
  String get home => _isBn ? 'হোম' : 'Home';
  String get chooseFromGallery => _isBn ? 'গ্যালারি থেকে বাছুন' : 'Choose from Gallery';
  String get takeAPhoto => _isBn ? 'ছবি তুলুন' : 'Take a Photo';
  String get batchProcess => _isBn ? 'একসাথে একাধিক ছবি প্রসেস করুন' : 'Batch Process Multiple Images';
  String get recentProjects => _isBn ? 'সাম্প্রতিক প্রজেক্ট' : 'Recent Projects';
  String get settings => _isBn ? 'সেটিংস' : 'Settings';
  String get removeBackground => _isBn ? 'ব্যাকগ্রাউন্ড রিমুভ করুন' : 'Remove Background';
  String get export => _isBn ? 'এক্সপোর্ট' : 'Export';
  String get saveToGallery => _isBn ? 'গ্যালারিতে সেভ করুন' : 'Save to Gallery';
  String get share => _isBn ? 'শেয়ার করুন' : 'Share';
  String get language => _isBn ? 'ভাষা' : 'Language';
  String get theme => _isBn ? 'থিম' : 'Theme';
  String get getStarted => _isBn ? 'শুরু করুন' : 'Get Started';
  String get skip => _isBn ? 'স্কিপ' : 'Skip';
}
