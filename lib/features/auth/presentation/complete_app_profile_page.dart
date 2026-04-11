import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/utils/error_handler.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_input.dart';
import '../data/models/register_request_dto.dart';
import '../data/services/auth_service.dart';
import 'backend_email_verification_page.dart';

/// Firebase oturumu var, backend’de kayıt yoksa profilden açılır (/register tamamlar).
class CompleteAppProfilePage extends StatefulWidget {
  const CompleteAppProfilePage({super.key});

  @override
  State<CompleteAppProfilePage> createState() => _CompleteAppProfilePageState();
}

class _CompleteAppProfilePageState extends State<CompleteAppProfilePage> {
  final _formKey = GlobalKey<FormState>();
  final _authService = AuthService();

  final _userName = TextEditingController();
  final _name = TextEditingController();
  final _surname = TextEditingController();
  final _birthdate = TextEditingController();

  bool _submitted = false;
  bool _isLoading = false;
  String? _fieldError;
  DateTime? _selectedDate;

  @override
  void initState() {
    super.initState();
    final d = AuthService.peekRegisterFormDraft;
    if (d == null) return;
    _userName.text = d.userName;
    _name.text = d.name;
    _surname.text = d.surname;
    _birthdate.text = d.birthdate;
    if (d.birthdate.isNotEmpty) {
      try {
        final parts = d.birthdate.split('-');
        if (parts.length == 3) {
          _selectedDate = DateTime(
            int.parse(parts[0]),
            int.parse(parts[1]),
            int.parse(parts[2]),
          );
        }
      } catch (_) {}
    }
  }

  @override
  void dispose() {
    _userName.dispose();
    _name.dispose();
    _surname.dispose();
    _birthdate.dispose();
    super.dispose();
  }

  String? _userNameValidator(String? v) {
    if (_fieldError != null && _fieldError!.toLowerCase().contains('username')) {
      return _fieldError;
    }
    final value = (v ?? '').trim();
    if (value.isEmpty) return 'Username is required';
    if (value.length < 3) return 'Min 3 characters';
    return null;
  }

  String? _nameValidator(String? v) {
    final value = (v ?? '').trim();
    if (value.isEmpty) return 'Name is required';
    return null;
  }

  String? _surnameValidator(String? v) {
    final value = (v ?? '').trim();
    if (value.isEmpty) return 'Surname is required';
    return null;
  }

  String? _birthdateValidator(String? v) {
    if (_selectedDate == null) return 'Birthdate is required';
    return null;
  }

  Future<void> _selectDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime.now().subtract(const Duration(days: 365 * 18)),
      firstDate: DateTime(1900),
      lastDate: DateTime.now(),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(
              primary: AppColors.primary,
              onPrimary: Colors.white,
              onSurface: AppColors.textPrimary,
            ),
          ),
          child: child!,
        );
      },
    );
    if (picked != null && picked != _selectedDate) {
      setState(() {
        _selectedDate = picked;
        _birthdate.text =
            '${picked.year}-${picked.month.toString().padLeft(2, '0')}-${picked.day.toString().padLeft(2, '0')}';
      });
    }
  }

  Future<void> _submit() async {
    setState(() {
      _fieldError = null;
      _submitted = true;
    });
    final ok = _formKey.currentState?.validate() ?? false;
    if (!ok) return;

    final fb = FirebaseAuth.instance.currentUser;
    if (fb == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Oturum bulunamadı. Lütfen tekrar giriş yapın.'),
            backgroundColor: AppColors.error,
          ),
        );
      }
      return;
    }

    setState(() => _isLoading = true);

    try {
      await _authService.syncFirebaseUserAndRefreshIdToken();
      final dto = RegisterRequestDto(
        userName: _userName.text.trim(),
        name: _name.text.trim(),
        surname: _surname.text.trim(),
        birthdate: _birthdate.text.trim(),
      );
      await _authService.registerOnBackend(dto, requireFirebaseEmailVerified: false);
      if (!mounted) return;
      setState(() => _isLoading = false);
      final verified = await Navigator.push<bool>(
        context,
        MaterialPageRoute(
          builder: (_) => BackendEmailVerificationPage(
            email: fb.email ?? '',
            popWithSuccessResult: true,
            navigateHomeOnSuccess: false,
            refreshProfileOnlyOnContinue: false,
          ),
        ),
      );
      if (!mounted) return;
      if (verified == true) {
        Navigator.of(context).pop(true);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _fieldError = ErrorHandler.getUserFriendlyMessage(e);
        _isLoading = false;
      });
      _formKey.currentState?.validate();
    }
  }

  @override
  Widget build(BuildContext context) {
    final fb = FirebaseAuth.instance.currentUser;
    final email = fb?.email ?? '';

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: AppColors.textPrimary),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(
          'Profili tamamla',
          style: AppTextStyles.heading3.copyWith(color: AppColors.textPrimary),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppSpacing.xLarge),
          child: Form(
            key: _formKey,
            autovalidateMode: _submitted
                ? AutovalidateMode.always
                : AutovalidateMode.disabled,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  AuthService.peekRegisterFormDraft != null
                      ? 'Kayıt sırasında girdiğiniz bilgiler aşağıya getirildi; gerekirse '
                          'düzenleyip kaydı tamamlayın.'
                      : 'Uygulama hesabınız henüz oluşturulmadı. Firebase ile giriş yaptınız; '
                          'aşağıdaki bilgilerle kaydınızı sunucuya tamamlayın.',
                  style: AppTextStyles.bodySecondary,
                ),
                if (email.isNotEmpty) ...[
                  const SizedBox(height: AppSpacing.medium),
                  Text(
                    email,
                    style: AppTextStyles.bodyMedium.copyWith(
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ],
                const SizedBox(height: AppSpacing.xLarge),
                AppInput(
                  controller: _userName,
                  hint: 'Kullanıcı adı',
                  validator: _userNameValidator,
                  onChanged: () {
                    if (_fieldError != null) setState(() => _fieldError = null);
                  },
                ),
                const SizedBox(height: AppSpacing.medium),
                AppInput(
                  controller: _name,
                  hint: 'Ad',
                  validator: _nameValidator,
                ),
                const SizedBox(height: AppSpacing.medium),
                AppInput(
                  controller: _surname,
                  hint: 'Soyad',
                  validator: _surnameValidator,
                ),
                const SizedBox(height: AppSpacing.medium),
                GestureDetector(
                  onTap: _selectDate,
                  child: AbsorbPointer(
                    child: AppInput(
                      controller: _birthdate,
                      hint: 'Doğum tarihi (seçmek için dokunun)',
                      validator: _birthdateValidator,
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.xLarge),
                AppButton(
                  text: 'Kaydı tamamla',
                  isLoading: _isLoading,
                  onPressed: _isLoading ? null : _submit,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
