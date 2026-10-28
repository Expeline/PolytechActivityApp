"""Checks the installed-platform declarations that previously broke Live Activities."""
from pathlib import Path
import plistlib

root = Path(__file__).resolve().parent.parent
for build in ['build', 'build-device']:
    platform = 'Debug-iphonesimulator' if build == 'build' else 'Debug-iphoneos'
    app = root/build/'Build/Products'/platform/'Polytech.app'
    info = plistlib.loads((app/'Info.plist').read_bytes())
    assert info.get('NSSupportsLiveActivities') is True, f'{build}: Live Activities disabled'
    assert set(info['UIDeviceFamily']) == {1, 2}, f'{build}: iPad support missing'
    extension = app/'PlugIns/PolytechLiveActivity.appex/Info.plist'
    assert plistlib.loads(extension.read_bytes())['NSExtension']['NSExtensionPointIdentifier'] == 'com.apple.widgetkit-extension'
    print(build, 'Live Activity + iPhone/iPad widget extension OK')
mac = root/'build-mac/Build/Products/Release/PolytechMac.app'
assert (mac/'Contents/PlugIns/PolytechMacWidgets.appex/Contents/Info.plist').exists()
print('macOS widget extension OK')
