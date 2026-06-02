import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../config.dart';
import '../features/wallet/wallet_button.dart';
import 'theme.dart';

/// App chrome for the mobile shell: a persistent bottom NavigationBar
/// (Polls / Verify / Create) plus a Drawer (wallet, network, about) wrapping the
/// three branch navigators. Poll detail pushes inside the Polls branch, so the
/// nav bar stays visible. Replaces the old web-port header buttons.
class AppShell extends StatelessWidget {
  final StatefulNavigationShell shell;
  const AppShell({super.key, required this.shell});

  void _goBranch(int i) =>
      shell.goBranch(i, initialLocation: i == shell.currentIndex);

  static String get _network {
    final host = Uri.tryParse(AppConfig.rpcUrl)?.host ?? '';
    const local = {'127.0.0.1', 'localhost', '10.0.2.2'};
    return local.contains(host) ? 'LOCAL' : 'REMOTE';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Db.void_,
      appBar: AppBar(
        backgroundColor: Db.void_,
        elevation: 0,
        iconTheme: const IconThemeData(color: Db.chalkDim),
        titleSpacing: 0,
        title: Row(mainAxisSize: MainAxisSize.min, children: [
          Container(width: 13, height: 13, color: Db.segnale),
          const SizedBox(width: 10),
          Text('TESSERA', style: dbSans(15, 800, Db.chalk, letterSpacing: 2.2)),
        ]),
        actions: [
          Center(
            child: Container(
              margin: const EdgeInsets.only(right: 14),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: const BoxDecoration(
                color: Db.slate,
                border: Border.fromBorderSide(BorderSide(color: Db.rule)),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Container(width: 6, height: 6, color: Db.success),
                const SizedBox(width: 7),
                Text(_network, style: dbLabel(size: 10, color: Db.chalkDim)),
              ]),
            ),
          ),
        ],
      ),
      drawer: const _AppDrawer(),
      body: shell,
      bottomNavigationBar: _NavBar(index: shell.currentIndex, onTap: _goBranch),
    );
  }
}

class _NavBar extends StatelessWidget {
  final int index;
  final ValueChanged<int> onTap;
  const _NavBar({required this.index, required this.onTap});

  @override
  Widget build(BuildContext context) => DecoratedBox(
        decoration: const BoxDecoration(
          color: Db.slate3,
          border: Border(top: BorderSide(color: Db.rule)),
        ),
        child: NavigationBarTheme(
          data: NavigationBarThemeData(
            backgroundColor: Colors.transparent,
            elevation: 0,
            height: 64,
            indicatorColor: Db.segnale,
            indicatorShape: const RoundedRectangleBorder(),
            labelTextStyle: WidgetStateProperty.resolveWith((s) => dbLabel(
                  size: 10,
                  color: s.contains(WidgetState.selected) ? Db.chalk : Db.mute,
                )),
            iconTheme: WidgetStateProperty.resolveWith((s) => IconThemeData(
                  size: 22,
                  color: s.contains(WidgetState.selected) ? Db.void_ : Db.mute,
                )),
          ),
          child: NavigationBar(
            selectedIndex: index,
            onDestinationSelected: onTap,
            labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
            destinations: const [
              NavigationDestination(
                  icon: Icon(Icons.ballot_outlined),
                  selectedIcon: Icon(Icons.ballot),
                  label: 'POLLS'),
              NavigationDestination(
                  icon: Icon(Icons.verified_outlined),
                  selectedIcon: Icon(Icons.verified),
                  label: 'VERIFY'),
              NavigationDestination(
                  icon: Icon(Icons.add_box_outlined),
                  selectedIcon: Icon(Icons.add_box),
                  label: 'CREATE'),
              NavigationDestination(
                  icon: Icon(Icons.fingerprint_outlined),
                  selectedIcon: Icon(Icons.fingerprint),
                  label: 'IDENTITY'),
            ],
          ),
        ),
      );
}

class _AppDrawer extends StatelessWidget {
  const _AppDrawer();

  @override
  Widget build(BuildContext context) => Drawer(
        backgroundColor: Db.slate3,
        shape: const RoundedRectangleBorder(
          side: BorderSide(color: Db.rule),
        ),
        child: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 24, 20, 8),
                child: Row(children: [
                  Container(width: 18, height: 18, color: Db.segnale),
                  const SizedBox(width: 12),
                  Text('TESSERA', style: dbSans(20, 800, Db.chalk, letterSpacing: 1.5)),
                ]),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 18),
                child: Text('Anonymous on-chain voting',
                    style: dbSans(12, 400, Db.chalkDim)),
              ),
              const Divider(color: Db.rule, height: 1),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 18, 16, 8),
                child: Text('WALLET', style: dbLabel(size: 10, tracking: 0.16)),
              ),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 16),
                child: WalletButton(),
              ),
              const SizedBox(height: 16),
              const Divider(color: Db.rule, height: 1),
              _DrawerRow(
                  icon: Icons.lan_outlined,
                  label: 'NETWORK',
                  value: AppShell._network),
              _DrawerRow(
                  icon: Icons.bolt_outlined,
                  label: 'RELAYER',
                  value: Uri.tryParse(AppConfig.relayerUrl)?.host ?? '—'),
              const Spacer(),
              const Divider(color: Db.rule, height: 1),
              _DrawerRow(
                  icon: Icons.info_outline,
                  label: 'ABOUT',
                  value: 'Semaphore ZK'),
              const SizedBox(height: 8),
            ],
          ),
        ),
      );
}

class _DrawerRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  const _DrawerRow(
      {required this.icon, required this.label, required this.value});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
        child: Row(children: [
          Icon(icon, size: 16, color: Db.mute),
          const SizedBox(width: 12),
          Text(label, style: dbLabel(size: 11, tracking: 0.12)),
          const Spacer(),
          Flexible(
            child: Text(value,
                overflow: TextOverflow.ellipsis,
                style: dbMono(11, Db.chalkDim)),
          ),
        ]),
      );
}
