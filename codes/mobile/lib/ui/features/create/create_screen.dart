import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/dot_grid_background.dart';
import '../../core/theme.dart';

/// Placeholder for poll creation. Creating a poll deploys a contract and needs
/// a funded wallet to sign — that's the organizer/web surface (Agile Plan §2.5),
/// not the recurring-member app. This screen explains that instead of routing to
/// a dead end.
class CreateScreen extends StatelessWidget {
  const CreateScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: DotGridBackground(
        child: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    InkWell(
                      onTap: () =>
                          context.canPop() ? context.pop() : context.go('/'),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        const Icon(Icons.arrow_back, size: 14, color: Db.mute),
                        const SizedBox(width: 6),
                        Text('BACK', style: dbLabel(size: 11, tracking: 0.16)),
                      ]),
                    ),
                    const SizedBox(height: 24),
                    Text('CREATE', style: dbHero(56)),
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.all(18),
                      decoration: const BoxDecoration(
                        color: Db.slate,
                        border: Border(left: BorderSide(color: Db.oltremare, width: 3)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(children: [
                            const Icon(Icons.account_balance_wallet_outlined,
                                color: Db.oltremare, size: 18),
                            const SizedBox(width: 8),
                            Text('ORGANIZER FLOW',
                                style: dbSans(13, 800, Db.oltremare,
                                    letterSpacing: 1.4)),
                          ]),
                          const SizedBox(height: 10),
                          Text(
                            'Creating a poll deploys a contract and needs a funded wallet to '
                            'sign the transaction. That runs on the web / organizer app. '
                            'This member app is for browsing, voting, and verifying receipts.',
                            style: dbMono(12, Db.chalkDim, height: 1.6),
                          ),
                        ],
                      ),
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
}
