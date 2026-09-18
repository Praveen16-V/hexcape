import '../entities/pickup.dart';
import '../hex/hex_cell.dart';

/// The small set of symbols a player needs to learn during the campaign.
/// Legacy mechanics remain readable so older data and focused rule tests work,
/// but new campaign boards and the reference sheet use this roster.
abstract final class MechanicRoster {
  static const tiles = <HexType>{
    HexType.plain,
    HexType.heavy,
    HexType.anchor,
    HexType.mire,
    HexType.spring,
    HexType.thicket,
    HexType.fault,
    HexType.alarm,
    HexType.sunken,
    HexType.thorn,
  };

  static const powerups = <PickupKind>{
    PickupKind.freeze,
    PickupKind.radiusPlus,
    PickupKind.sprint,
    PickupKind.scent,
    PickupKind.cloak,
    PickupKind.pairwork,
    PickupKind.blast,
    PickupKind.dig,
    PickupKind.stake,
    PickupKind.wardown,
  };

  /// Treats are a resource and do not count against the ten powers.
  static const pickups = <PickupKind>{PickupKind.treat, ...powerups};
}
