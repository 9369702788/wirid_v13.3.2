import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart' hide TextDirection;

import '../../core/data/app_sources.dart';
import '../../core/data/adhan_option.dart';
import '../../core/services/audio_download_service.dart';
import '../../core/services/azkar_repository.dart';
import '../../core/services/notification_service.dart';
import '../../core/services/prayer_display.dart';
import '../../core/services/daily_reminder_scheduler.dart';
import '../../core/services/quran_repository.dart';
import '../../core/services/quran_foundation_service.dart';
import '../../core/services/settings_service.dart';
import '../../core/services/user_progress_service.dart';
import '../../core/theme/app_theme.dart';
import '../../l10n/generated/app_localizations.dart';
import '../quran/tajweed_legend.dart';
import 'about_screen.dart';
import 'privacy_center_screen.dart';
import 'privacy_policy_screen.dart';
import 'sources_licenses_screen.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  int _wirdTarget = 5;
  late final TextEditingController _qfClientIdController =
      TextEditingController(text: appSettings.quranFoundationClientId);
  late final TextEditingController _qfClientSecretController =
      TextEditingController(text: appSettings.quranFoundationClientSecret);
  String? _qfTestResult;
  bool _qfTestSuccess = false;
  bool _qfTesting = false;
  final AudioPlayer _previewPlayer = AudioPlayer();
  String? _previewingAdhanId;
  DateTime? _quranCachedAt;
  DateTime? _azkarCachedAt;
  int _downloadedAudioBytes = 0;

  @override
  void initState() {
    super.initState();
    _loadWirdTarget();
    _loadCacheInfo();
    _loadDownloadedAudioSize();
    _previewPlayer.onPlayerComplete.listen((_) {
      if (mounted) setState(() => _previewingAdhanId = null);
    });
  }

  Future<void> _loadDownloadedAudioSize() async {
    final bytes = await AudioDownloadService.totalStorageUsedBytes();
    if (mounted) setState(() => _downloadedAudioBytes = bytes);
  }

  String _downloadedAudioSize(AppLocalizations l10n) {
    if (_downloadedAudioBytes == 0) return l10n.settingsNoDownloadedAudio;
    final mb = _downloadedAudioBytes / (1024 * 1024);
    return l10n.settingsMbDownloaded(mb.toStringAsFixed(1));
  }

  Future<void> _confirmDeleteAllDownloads() async {
    final l10n = AppLocalizations.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.settingsDeleteAllDownloadsTitle),
        content: Text(l10n.settingsDeleteAllDownloadsBody),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: Text(l10n.commonCancel)),
          TextButton(onPressed: () => Navigator.pop(context, true), child: Text(l10n.commonDelete, style: const TextStyle(color: Colors.red))),
        ],
      ),
    );
    if (confirmed == true) {
      await AudioDownloadService.deleteAllDownloads();
      _loadDownloadedAudioSize();
    }
  }

  @override
  void dispose() {
    _previewPlayer.dispose();
    _qfClientIdController.dispose();
    _qfClientSecretController.dispose();
    super.dispose();
  }

  Future<void> _testQfConnection() async {
    setState(() {
      _qfTesting = true;
      _qfTestResult = null;
    });
    final result = await QuranFoundationService.testConnection(
      _qfClientIdController.text,
      _qfClientSecretController.text,
    );
    if (!mounted) return;
    setState(() {
      _qfTesting = false;
      _qfTestSuccess = result.success;
      _qfTestResult = result.message;
    });
  }

  Future<void> _saveQfCredentials() async {
    await appSettings.setQuranFoundationCredentials(
      _qfClientIdController.text,
      _qfClientSecretController.text,
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(AppLocalizations.of(context).settingsQuranFoundationSaved)),
    );
  }

  Future<void> _togglePreviewAdhan(AdhanOption option) async {
    if (_previewingAdhanId == option.id) {
      try {
        await _previewPlayer.stop();
      } catch (_) {
        // Nothing loaded — fine.
      }
      setState(() => _previewingAdhanId = null);
      return;
    }

    setState(() => _previewingAdhanId = option.id);
    try {
      try {
        await _previewPlayer.stop();
      } catch (_) {
        // Nothing loaded yet — expected on first preview, safe to ignore.
      }
      await _previewPlayer.play(UrlSource(option.url));
    } catch (e) {
      if (mounted) {
        setState(() => _previewingAdhanId = null);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppLocalizations.of(context).settingsPreviewFailed)),
        );
      }
    }
  }

  Future<void> _loadCacheInfo() async {
    final quranAt = await QuranRepository.cachedAt();
    final azkarAt = await AzkarRepository.cachedAt();
    if (mounted) {
      setState(() {
        _quranCachedAt = quranAt;
        _azkarCachedAt = azkarAt;
      });
    }
  }

  String _formatCacheDate(DateTime? date, String languageCode, AppLocalizations l10n) {
    if (date == null) return l10n.settingsNotDownloadedYet;
    // Falls back to 'en' formatting for locales without an intl date
    // pattern registered (all four we ship are registered in main.dart).
    return DateFormat('d MMMM y, h:mm a', languageCode).format(date);
  }

  Future<void> _loadWirdTarget() async {
    final target = await UserProgressService.dailyWirdTarget();
    if (mounted) setState(() => _wirdTarget = target);
  }

  Future<void> _setWirdTarget(int value) async {
    if (value < 1) return;
    await UserProgressService.setDailyWirdTarget(value);
    setState(() => _wirdTarget = value);
  }

  Future<void> _confirmClearData() async {
    final l10n = AppLocalizations.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.settingsDeleteLocalData),
        content: Text(l10n.settingsDeleteLocalDataBody),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: Text(l10n.commonCancel)),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(l10n.commonDelete, style: const TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await UserProgressService.clearAllLocalData();
      await appSettings.load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.settingsLocalDataDeleted)),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final languageCode = Localizations.localeOf(context).languageCode;
    return Scaffold(
      appBar: AppBar(title: Text(l10n.settingsTitle), centerTitle: true),
      body: ListenableBuilder(
        listenable: appSettings,
        builder: (context, _) {
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _SectionLabel(l10n.settingsAppearance),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(l10n.settingsMode, style: const TextStyle(fontWeight: FontWeight.w700)),
                      const SizedBox(height: 10),
                      SegmentedButton<ThemeMode>(
                        segments: [
                          ButtonSegment(value: ThemeMode.light, label: Text(l10n.settingsModeLight), icon: const Icon(Icons.light_mode_outlined)),
                          ButtonSegment(value: ThemeMode.dark, label: Text(l10n.settingsModeDark), icon: const Icon(Icons.dark_mode_outlined)),
                          ButtonSegment(value: ThemeMode.system, label: Text(l10n.settingsModeAuto), icon: const Icon(Icons.brightness_auto_outlined)),
                        ],
                        selected: {appSettings.themeMode},
                        onSelectionChanged: (set) => appSettings.setThemeMode(set.first),
                      ),
                      const SizedBox(height: 20),
                      Text(l10n.settingsFontSize, style: const TextStyle(fontWeight: FontWeight.w700)),
                      Slider(
                        value: appSettings.fontScale,
                        min: 0.85,
                        max: 1.4,
                        divisions: 11,
                        label: '${(appSettings.fontScale * 100).round()}%',
                        onChanged: (value) => appSettings.setFontScale(value),
                      ),
                      Text(
                        l10n.settingsFontPreview,
                        style: TextStyle(fontSize: 16 * appSettings.fontScale),
                      ),
                      const SizedBox(height: 12),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(l10n.settingsShowTransliteration),
                        subtitle: Text(l10n.settingsShowTransliterationSubtitle),
                        value: appSettings.showTransliteration,
                        activeTrackColor: AppColors.primaryEmerald,
                        onChanged: (value) => appSettings.setShowTransliteration(value),
                      ),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(l10n.settingsShowTajweedColoring),
                        subtitle: Text(l10n.settingsShowTajweedColoringSubtitle),
                        value: appSettings.showTajweedColoring,
                        activeTrackColor: AppColors.primaryEmerald,
                        onChanged: (value) => appSettings.setShowTajweedColoring(value),
                      ),
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.info_outline, color: AppColors.mutedText),
                        title: Text(l10n.tajweedLegendTitle),
                        trailing: const Icon(Icons.chevron_left, color: AppColors.mutedText),
                        onTap: () => showTajweedLegend(context),
                      ),
                      const Divider(height: 24),
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.language_outlined, color: AppColors.mutedText),
                        title: Text(l10n.settingsLanguage),
                        subtitle: Text(l10n.settingsLanguageSubtitle),
                        trailing: Text(
                          appSettings.explicitLocale == null
                              ? l10n.settingsLanguageSystem
                              : {
                                  'ar': l10n.languageName_ar,
                                  'en': l10n.languageName_en,
                                  'de': l10n.languageName_de,
                                  'tr': l10n.languageName_tr,
                                }[appSettings.explicitLocale!.languageCode] ?? '',
                          style: const TextStyle(color: AppColors.mutedText),
                        ),
                        onTap: () async {
                          // Bottom sheet result convention: since both "no
                          // selection" (dismissed) and "System default"
                          // (explicit null choice) return null from
                          // showModalBottomSheet, we re-open with a
                          // dedicated picker rather than relying on that
                          // return value directly — see _showLanguageSheet.
                          await _showLanguageSheet(context, l10n);
                        },
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 20),

              _SectionLabel(l10n.settingsPrayerReminder),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(l10n.settingsRemindMeFor, style: const TextStyle(fontWeight: FontWeight.w700)),
                      const SizedBox(height: 4),
                      ...AppSettings.remindablePrayerKeys.map((prayerKey) {
                        return SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text(prayerDisplayName(l10n, prayerKey)),
                          value: appSettings.isPrayerReminderEnabledFor(prayerKey),
                          activeTrackColor: AppColors.primaryEmerald,
                          onChanged: (value) async {
                            await appSettings.setPrayerReminderEnabledFor(prayerKey, value);
                            if (value) {
                              unawaited(NotificationService.requestPermission());
                            }
                          },
                        );
                      }),
                      if (appSettings.prayerReminderEnabled) ...[
                        const Divider(height: 24),
                        SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text(l10n.settingsNotifyAtPrayerTime),
                          subtitle: Text(l10n.settingsNotifyAtPrayerTimeSubtitle),
                          value: appSettings.notifyAtPrayerTime,
                          activeTrackColor: AppColors.primaryEmerald,
                          onChanged: (value) => appSettings.setNotifyAtPrayerTime(value),
                        ),
                        const SizedBox(height: 8),
                        Text(l10n.settingsPrayerReminderMinutesBefore, style: const TextStyle(fontWeight: FontWeight.w700)),
                        Slider(
                          value: appSettings.prayerReminderMinutesBefore.toDouble(),
                          min: 0,
                          max: 30,
                          divisions: 6,
                          label: appSettings.prayerReminderMinutesBefore == 0
                              ? l10n.settingsReminderOff
                              : l10n.settingsPrayerReminderMinutesLabel(appSettings.prayerReminderMinutesBefore),
                          onChanged: (value) => appSettings.setPrayerReminderMinutesBefore(value.round()),
                        ),
                        const SizedBox(height: 8),
                        SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text(l10n.settingsPostPrayerReminder),
                          subtitle: Text(l10n.settingsPostPrayerReminderSubtitle),
                          value: appSettings.postPrayerReminderEnabled,
                          activeTrackColor: AppColors.primaryEmerald,
                          onChanged: (value) => appSettings.setPostPrayerReminderEnabled(value),
                        ),
                        if (appSettings.postPrayerReminderEnabled) ...[
                          const SizedBox(height: 4),
                          Slider(
                            value: appSettings.postPrayerReminderMinutesAfter.toDouble(),
                            min: 10,
                            max: 60,
                            divisions: 5,
                            label: l10n.settingsPostPrayerReminderMinutesLabel(appSettings.postPrayerReminderMinutesAfter),
                            onChanged: (value) => appSettings.setPostPrayerReminderMinutesAfter(value.round()),
                          ),
                        ],
                        const SizedBox(height: 8),
                        Text(l10n.settingsPrayerReminderMethod, style: const TextStyle(fontWeight: FontWeight.w700)),
                        const SizedBox(height: 8),
                        SegmentedButton<String>(
                          segments: [
                            ButtonSegment(value: 'banner', label: Text(l10n.settingsReminderBanner), icon: const Icon(Icons.notifications_outlined)),
                            ButtonSegment(value: 'beep', label: Text(l10n.settingsReminderBeep), icon: const Icon(Icons.volume_up_outlined)),
                            ButtonSegment(value: 'adhan', label: Text(l10n.settingsReminderAdhan), icon: const Icon(Icons.campaign_outlined)),
                          ],
                          selected: {appSettings.prayerReminderMode},
                          onSelectionChanged: (set) => appSettings.setPrayerReminderMode(set.first),
                        ),
                        if (appSettings.prayerReminderMode == 'beep') ...[
                          const SizedBox(height: 8),
                          OutlinedButton.icon(
                            onPressed: () => SystemSound.play(SystemSoundType.alert),
                            icon: const Icon(Icons.volume_up_outlined),
                            label: Text(l10n.settingsTestTone),
                          ),
                        ],
                        if (appSettings.prayerReminderMode == 'adhan') ...[
                          const SizedBox(height: 12),
                          Text(l10n.settingsAdhanSound, style: const TextStyle(fontWeight: FontWeight.w700)),
                          const SizedBox(height: 6),
                          Column(
                            children: AppSources.adhanOptions.map((option) {
                              final isSelected = appSettings.adhanId == option.id;
                              final isPreviewing = _previewingAdhanId == option.id;
                              return RadioListTile<String>(
                                contentPadding: EdgeInsets.zero,
                                value: option.id,
                                groupValue: appSettings.adhanId,
                                activeColor: AppColors.primaryEmerald,
                                title: Text(option.displayNameFor(languageCode)),
                                onChanged: (value) {
                                  if (value != null) appSettings.setAdhanId(value);
                                },
                                secondary: IconButton(
                                  tooltip: isPreviewing ? l10n.settingsStopPreview : l10n.settingsListen,
                                  icon: Icon(
                                    isPreviewing ? Icons.stop_circle_outlined : Icons.play_circle_outline,
                                    color: isSelected ? AppColors.primaryEmerald : AppColors.mutedText,
                                  ),
                                  onPressed: () => _togglePreviewAdhan(option),
                                ),
                              );
                            }).toList(),
                          ),
                        ],
                        const SizedBox(height: 8),
                        Text(
                          l10n.settingsReminderNote,
                          style: const TextStyle(fontSize: 12, color: AppColors.mutedText),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 20),

              _SectionLabel(l10n.settingsMoreReminders),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _DailyReminderTile(
                        reminderKey: 'friday',
                        title: l10n.settingsFridayReminder,
                        subtitle: l10n.settingsFridayReminderSubtitle,
                      ),
                      const Divider(height: 24),
                      _DailyReminderTile(
                        reminderKey: 'morningAzkar',
                        title: l10n.settingsMorningAzkarReminder,
                        subtitle: l10n.settingsMorningAzkarReminderSubtitle,
                      ),
                      const Divider(height: 24),
                      _DailyReminderTile(
                        reminderKey: 'eveningAzkar',
                        title: l10n.settingsEveningAzkarReminder,
                        subtitle: l10n.settingsEveningAzkarReminderSubtitle,
                      ),
                      const Divider(height: 24),
                      _DailyReminderTile(
                        reminderKey: 'dailyWird',
                        title: l10n.settingsDailyWirdReminder,
                        subtitle: l10n.settingsDailyWirdReminderSubtitle,
                      ),
                      const Divider(height: 24),
                      _DailyReminderTile(
                        reminderKey: 'sleepAzkar',
                        title: l10n.settingsSleepAzkarReminder,
                        subtitle: l10n.settingsSleepAzkarReminderSubtitle,
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 20),

              _SectionLabel(l10n.settingsDailyWird),
              Card(
                child: ListTile(
                  title: Text(l10n.settingsDailyWirdTarget),
                  subtitle: Text(l10n.settingsDailyWirdPerDay(_wirdTarget)),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(tooltip: l10n.commonDecreaseTooltip, onPressed: () => _setWirdTarget(_wirdTarget - 1), icon: const Icon(Icons.remove_circle_outline)),
                      IconButton(tooltip: l10n.commonIncreaseTooltip, onPressed: () => _setWirdTarget(_wirdTarget + 1), icon: const Icon(Icons.add_circle_outline)),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 20),

              _SectionLabel(l10n.settingsQuranFoundationTitle),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(l10n.settingsQuranFoundationIntro, style: const TextStyle(fontSize: 12, color: AppColors.mutedText)),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _qfClientIdController,
                        decoration: InputDecoration(
                          labelText: l10n.settingsQuranFoundationClientId,
                          border: const OutlineInputBorder(),
                          isDense: true,
                        ),
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        controller: _qfClientSecretController,
                        obscureText: true,
                        decoration: InputDecoration(
                          labelText: l10n.settingsQuranFoundationClientSecret,
                          border: const OutlineInputBorder(),
                          isDense: true,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              onPressed: _qfTesting ? null : _testQfConnection,
                              child: _qfTesting
                                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                                  : Text(l10n.settingsQuranFoundationTestConnection),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: FilledButton(
                              onPressed: _saveQfCredentials,
                              child: Text(l10n.settingsQuranFoundationSave),
                            ),
                          ),
                        ],
                      ),
                      if (_qfTestResult != null) ...[
                        const SizedBox(height: 10),
                        Text(
                          _qfTestResult!,
                          style: TextStyle(fontSize: 12, color: _qfTestSuccess ? AppColors.primaryEmerald : Colors.red),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 20),

              _SectionLabel(l10n.settingsAboutSupport),
              Card(
                child: Column(
                  children: [
                    ListTile(
                      leading: const Icon(Icons.info_outline),
                      title: Text(l10n.settingsAbout),
                      trailing: const Icon(Icons.chevron_left),
                      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AboutScreen())),
                    ),
                    const Divider(height: 1),
                    ListTile(
                      leading: const Icon(Icons.source_outlined),
                      title: Text(l10n.settingsSourcesLicenses),
                      trailing: const Icon(Icons.chevron_left),
                      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SourcesLicensesScreen())),
                    ),
                    const Divider(height: 1),
                    ListTile(
                      leading: const Icon(Icons.privacy_tip_outlined),
                      title: Text(l10n.settingsPrivacyPolicy),
                      trailing: const Icon(Icons.chevron_left),
                      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const PrivacyPolicyScreen())),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),

              _SectionLabel(l10n.settingsPrivacyCenter),
              Card(
                child: ListTile(
                  leading: const Icon(Icons.shield_outlined, color: AppColors.primaryEmerald),
                  title: Text(l10n.settingsPrivacyCenter),
                  subtitle: Text(l10n.settingsPrivacyCenterSubtitle),
                  trailing: const Icon(Icons.chevron_left, color: AppColors.mutedText),
                  onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const PrivacyCenterScreen())),
                ),
              ),
              const SizedBox(height: 20),

              _SectionLabel(l10n.settingsDataManagement),
              Card(
                child: Column(
                  children: [
                    ListTile(
                      leading: const Icon(Icons.menu_book_outlined, color: AppColors.mutedText),
                      title: Text(l10n.settingsQuranLastUpdate),
                      subtitle: Text(_formatCacheDate(_quranCachedAt, languageCode, l10n)),
                    ),
                    const Divider(height: 1),
                    ListTile(
                      leading: const Icon(Icons.favorite_outline, color: AppColors.mutedText),
                      title: Text(l10n.settingsAzkarLastUpdate),
                      subtitle: Text(_formatCacheDate(_azkarCachedAt, languageCode, l10n)),
                    ),
                    const Divider(height: 1),
                    ListTile(
                      leading: const Icon(Icons.refresh, color: AppColors.primaryEmerald),
                      title: Text(l10n.settingsUpdateNow),
                      subtitle: Text(l10n.settingsRequiresInternet),
                      onTap: () async {
                        await QuranRepository.load(forceRefresh: true);
                        await AzkarRepository.load(forceRefresh: true);
                        await _loadCacheInfo();
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text(l10n.settingsDataUpdated)),
                          );
                        }
                      },
                    ),
                    const Divider(height: 1),
                    ListTile(
                      leading: const Icon(Icons.download_outlined, color: AppColors.mutedText),
                      title: Text(l10n.settingsDownloadedAudio),
                      subtitle: Text(_downloadedAudioSize(l10n)),
                      trailing: _downloadedAudioBytes > 0
                          ? TextButton(
                              onPressed: _confirmDeleteAllDownloads,
                              child: Text(l10n.settingsDeleteAll, style: const TextStyle(color: Colors.red)),
                            )
                          : null,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Card(
                child: Column(
                  children: [
                    ListTile(
                      leading: const Icon(Icons.restart_alt, color: Colors.orange),
                      title: Text(l10n.settingsResetKhatma),
                      subtitle: Text(l10n.settingsResetKhatmaSubtitle),
                      onTap: () async {
                        final confirmed = await showDialog<bool>(
                          context: context,
                          builder: (context) => AlertDialog(
                            title: Text(l10n.settingsResetKhatma),
                            content: Text(l10n.settingsResetKhatmaBody),
                            actions: [
                              TextButton(onPressed: () => Navigator.pop(context, false), child: Text(l10n.commonCancel)),
                              TextButton(onPressed: () => Navigator.pop(context, true), child: Text(l10n.settingsResetKhatmaConfirm)),
                            ],
                          ),
                        );
                        if (confirmed == true) {
                          await UserProgressService.resetKhatmaProgress();
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text(l10n.settingsKhatmaResetDone)),
                            );
                          }
                        }
                      },
                    ),
                    const Divider(height: 1),
                    ListTile(
                      leading: const Icon(Icons.delete_outline, color: Colors.red),
                      title: Text(l10n.settingsDeleteLocalData, style: const TextStyle(color: Colors.red)),
                      onTap: _confirmClearData,
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  /// Shows the language picker sheet and applies the choice. Uses a
  /// dedicated "was it dismissed or was System default tapped" signal
  /// (a sentinel Locale) since both map to `null` from Navigator.pop
  /// otherwise.
  Future<void> _showLanguageSheet(BuildContext context, AppLocalizations l10n) async {
    String nameFor(Locale locale) {
      switch (locale.languageCode) {
        case 'ar':
          return l10n.languageName_ar;
        case 'de':
          return l10n.languageName_de;
        case 'tr':
          return l10n.languageName_tr;
        default:
          return l10n.languageName_en;
      }
    }

    final choice = await showModalBottomSheet<Locale>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
                child: Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: Text(l10n.settingsLanguage, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                ),
              ),
              RadioListTile<bool>(
                value: true,
                groupValue: appSettings.explicitLocale == null,
                activeColor: AppColors.primaryEmerald,
                title: Text(l10n.settingsLanguageSystem),
                onChanged: (_) => Navigator.pop(sheetContext, const Locale('system')),
              ),
              for (final locale in AppSettings.supportedLocales)
                RadioListTile<bool>(
                  value: true,
                  groupValue: appSettings.explicitLocale?.languageCode == locale.languageCode,
                  activeColor: AppColors.primaryEmerald,
                  title: Text(nameFor(locale)),
                  onChanged: (_) => Navigator.pop(sheetContext, locale),
                ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );

    if (choice == null) return; // sheet dismissed without a tap
    if (choice.languageCode == 'system') {
      await appSettings.setLocale(null); // "System default"
    } else {
      await appSettings.setLocale(choice);
    }
  }
}

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 4, 4, 8),
      child: Text(
        text,
        style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.mutedText, fontSize: 13),
      ),
    );
  }
}


class _DailyReminderTile extends StatelessWidget {
  final String reminderKey;
  final String title;
  final String subtitle;
  const _DailyReminderTile({required this.reminderKey, required this.title, required this.subtitle});

  String _formatTime(BuildContext context, int hour, int minute) {
    return TimeOfDay(hour: hour, minute: minute).format(context);
  }

  @override
  Widget build(BuildContext context) {
    final setting = appSettings.dailyReminder(reminderKey);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(title),
          subtitle: Text(subtitle),
          value: setting.enabled,
          activeTrackColor: AppColors.primaryEmerald,
          onChanged: (value) async {
            final l10n = AppLocalizations.of(context);
            await appSettings.setDailyReminder(reminderKey, setting.copyWith(enabled: value));
            unawaited(DailyReminderScheduler.rescheduleAll(l10n));
            if (value) {
              unawaited(NotificationService.requestPermission());
            }
          },
        ),
        if (setting.enabled)
          Padding(
            padding: const EdgeInsets.only(left: 16, bottom: 4),
            child: OutlinedButton.icon(
              onPressed: () async {
                final picked = await showTimePicker(
                  context: context,
                  initialTime: TimeOfDay(hour: setting.hour, minute: setting.minute),
                );
                if (picked == null) return;
                if (!context.mounted) return;
                final l10n = AppLocalizations.of(context);
                await appSettings.setDailyReminder(
                  reminderKey,
                  setting.copyWith(hour: picked.hour, minute: picked.minute),
                );
                unawaited(DailyReminderScheduler.rescheduleAll(l10n));
              },
              icon: const Icon(Icons.access_time_outlined),
              label: Text(_formatTime(context, setting.hour, setting.minute)),
            ),
          ),
      ],
    );
  }
}
