# Player-facing mechanic roster

The campaign uses ten tile types and ten powerups, plus treats as a resource.
The enum cases for older mechanics remain in the engine so saved or handcrafted
boards can still be read, but campaign rules do not generate them and the
player reference hides them.

| Tiles | Decision |
| --- | --- |
| Plain | Clear a path with one tap. |
| Heavy | Spend a second tap or route around it. |
| Anchor | Route around a riveted wall or use Dig. |
| Mire | Trade time for a short route. |
| Spring | Use or avoid a push in the current direction. |
| Thicket | Clear it to reveal ground behind it. |
| Fault | Cross before the tile closes itself. |
| Alarm | Decide whether a shortcut is worth waking the lights. |
| Sunken | Open adjacent ground first. |
| Thorn | Trade time for a short route. |

| Powerups | Benefit |
| --- | --- |
| Freeze | Pause regrowth. |
| Reach | Tap farther. |
| Sprint | Move faster. |
| Scent | Show a route. |
| Cloak | Cross patrol light. |
| Pairwork | Make each tap strike twice. |
| Blast | Clear a cluster. |
| Dig | Remove an anchor. |
| Stake | Hold one open tile open. |
| Wardown | Tap through sentry light. |

Treats restore time and taps.

The `?` control reads a tile without clearing it. Holding a carried tool reads
its effect. Both work when optional hints are turned off. Fog still hides a
tile's type until the dog sees it.

Patrol and light behaviors are obstacles, not tile or pickup kinds. They keep
their existing campaign timing and reference entries.
