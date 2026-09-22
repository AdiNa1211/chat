import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:secure_chat_app/features/auth/domain/auth_repository.dart';
import 'package:secure_chat_app/features/auth/presentation/bloc/auth_bloc.dart';
import 'package:secure_chat_app/features/auth/presentation/bloc/auth_event.dart';
import 'package:secure_chat_app/features/auth/presentation/bloc/auth_state.dart';

/// Section 14 ("Screens should include at minimum: ... Login,
/// Registration, OTP verification") — combined here into one flow since
/// email/phone + OTP is the whole "login or register" path (Supabase OTP
/// auth doesn't distinguish new vs. returning users until after verify).
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _identifierController = TextEditingController();
  OtpChannel _channel = OtpChannel.email;

  @override
  void dispose() {
    _identifierController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Sign in')),
      body: BlocConsumer<AuthBloc, AuthState>(
        listener: (context, state) {
          if (state is AuthUnauthenticated && state.errorMessage != null) {
            ScaffoldMessenger.of(context)
                .showSnackBar(SnackBar(content: Text(state.errorMessage!)));
          }
        },
        builder: (context, state) {
          final isLoading = state is AuthOtpPending && state.isSubmitting;
          return Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 24),
                SegmentedButton<OtpChannel>(
                  segments: const [
                    ButtonSegment(value: OtpChannel.email, label: Text('Email')),
                    ButtonSegment(value: OtpChannel.phone, label: Text('Phone')),
                  ],
                  selected: {_channel},
                  onSelectionChanged: (s) => setState(() => _channel = s.first),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _identifierController,
                  keyboardType: _channel == OtpChannel.email
                      ? TextInputType.emailAddress
                      : TextInputType.phone,
                  decoration: InputDecoration(
                    labelText: _channel == OtpChannel.email ? 'Email address' : 'Phone number',
                    border: const OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: isLoading
                      ? null
                      : () => context.read<AuthBloc>().add(
                            OtpRequested(
                              identifier: _identifierController.text.trim(),
                              channel: _channel,
                            ),
                          ),
                  child: const Text('Send code'),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
