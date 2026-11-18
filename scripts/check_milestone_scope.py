#!/usr/bin/env python3
"""Regression check for intentionally excluded milestone functionality."""
from pathlib import Path

root = Path(__file__).resolve().parents[1]
source = root / 'android/app/src/main/kotlin/com/terrastep/fyp'
checks = {
    'lib/ui/screens/live_map_screen.dart': ['hex-grid', 'hexPolygons', 'visitedHexCount', 'currentHexId'],
    'lib/services/native_tracker_bridge.dart': ['generateDemoWalk'],
    'lib/ui/screens/gpx_history_screen.dart': ['generateDemoWalk', 'Generate Abbottabad', 'auto_fix_high'],
    'lib/ui/screens/user_screen.dart': ['getSessionDetail', 'CustomPaint', '_PathPainter', 'Offset'],
    str((source / 'MainActivity.kt').relative_to(root)): ['HexGridEngine', 'hexPolygons', 'generateDemoWalk', 'createDemoAbbottabadWalk'],
    str((source / 'service/WalkRecorderService.kt').relative_to(root)): ['HexGridEngine', 'visitedHexIds.', 'hexPolygons', 'hexCount'],
    str((source / 'gpx/GpxFileWriter.kt').relative_to(root)): ['h3_res9', 'hexCellId'],
}
for filename, forbidden in checks.items():
    text = (root / filename).read_text()
    for token in forbidden:
        assert token not in text, f'{filename}: out-of-scope token {token!r}'
assert not (source / 'geo/HexGridEngine.kt').exists(), 'Hex engine must not be compiled'
# Legacy schema columns must remain, with unchanged names/types, to avoid data loss.
entities = (source / 'db/Entities.kt').read_text()
assert 'val visitedHexIdsJson: String' in entities
assert 'val hexCellId: String' in entities
assert 'version = 1' in (source / 'db/TerrastepDatabase.kt').read_text()
print('Scope checks passed: no active hex/demo features or User route renderer; Room v1 compatibility retained.')
