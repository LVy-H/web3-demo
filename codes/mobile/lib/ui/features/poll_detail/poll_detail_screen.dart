import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme.dart';

/// Placeholder until the poll-detail ViewModel + reads UI land (next iteration).
/// Confirms routing + the back affordance work today.
class PollDetailScreen extends StatelessWidget {
  final String address;
  const PollDetailScreen({super.key, required this.address});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.canPop() ? context.pop() : context.go('/'),
        ),
        title: const Text('Poll'),
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Poll detail — coming next',
                  style: TextStyle(color: Db.chalk, fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
              Text(address, textAlign: TextAlign.center, style: dbMonoLabel),
            ],
          ),
        ),
      ),
    );
  }
}
