import 'package:flutter/material.dart';

import '../game/entitlements.dart';
import '../game/level_rules.dart';
import '../game/store.dart';
import '../theme/palette.dart';

/// The offer.
///
/// Deliberately quiet. No countdown, no crossed-out price, no "last chance" —
/// the game is a still, dark thing and a paywall that shouts would be the only
/// part of it that does. It says what you get, what it costs, and gives you a
/// way to restore a purchase you already made.
class PaywallSheet extends StatefulWidget {
  const PaywallSheet({required this.store, super.key});

  final Store store;

  @override
  State<PaywallSheet> createState() => _PaywallSheetState();
}

class _PaywallSheetState extends State<PaywallSheet> {
  @override
  void initState() {
    super.initState();
    widget.store.addListener(_onStore);
  }

  @override
  void dispose() {
    widget.store.removeListener(_onStore);
    super.dispose();
  }

  void _onStore() {
    if (!mounted) {
      return;
    }
    setState(() {});
    // Close on success rather than leaving the player looking at a Buy button
    // for something they now own.
    if (widget.store.owned) {
      Navigator.of(context).maybePop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final store = widget.store;
    final paidLevels = Campaign.length - Entitlements.freeThrough;

    return Container(
      decoration: const BoxDecoration(
        color: Palette.background,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      padding: const EdgeInsets.fromLTRB(22, 14, 22, 26),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Palette.lockedEdge,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              'The rest of the campaign',
              style: TextStyle(
                color: Colors.white,
                fontSize: 23,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 14),
            _Point(
              colour: Palette.bandPressure,
              text: '$paidLevels more levels, through Pressure and Mastery',
            ),
            _Point(
              colour: Palette.guard,
              text: 'Patrols, and boards that close faster than you can carve',
            ),
            _Point(
              colour: Palette.bandEndless,
              text: 'Endless, which keeps going as deep as you can take her',
            ),
            const SizedBox(height: 6),
            Text(
              'One payment. No adverts, no subscription, nothing to renew.',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.42),
                fontSize: 12.5,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 20),

            if (!store.available)
              _Unavailable(
                message: 'The store is not reachable on this device right now. '
                    'Everything you have already unlocked still works.',
              )
            else if (store.product == null)
              _Unavailable(
                message: 'Still fetching the price. Give it a moment.',
              )
            else ...[
              SizedBox(
                height: 54,
                child: FilledButton(
                  onPressed: store.busy ? null : store.buy,
                  style: FilledButton.styleFrom(
                    backgroundColor: Palette.dogBody,
                    foregroundColor: Palette.background,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  child: store.busy
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Text(
                          'Unlock  ·  ${store.price}',
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 1.2,
                          ),
                        ),
                ),
              ),
              TextButton(
                onPressed: store.busy ? null : store.restore,
                style: TextButton.styleFrom(
                  foregroundColor: Colors.white.withValues(alpha: 0.5),
                ),
                child: const Text('Already bought it? Restore'),
              ),
            ],

            if (store.error != null)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  store.error!,
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Palette.danger, fontSize: 12),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _Point extends StatelessWidget {
  const _Point({required this.colour, required this.text});

  final Color colour;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 5),
            child: Icon(Icons.circle, size: 8, color: colour),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.8),
                fontSize: 14,
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Unavailable extends StatelessWidget {
  const _Unavailable({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    // A Buy button that cannot work is worse than none. This says why.
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Palette.lockedEdge),
      ),
      child: Text(
        message,
        style: TextStyle(
          color: Colors.white.withValues(alpha: 0.55),
          fontSize: 12.5,
          height: 1.4,
        ),
      ),
    );
  }
}
