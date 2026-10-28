"""Recreate the dependency-free Xcode project from checked-in sources."""
from pathlib import Path
import subprocess
import hashlib
import json

ROOT = Path(__file__).resolve().parent.parent
previous = {}
project_file = ROOT/'Polytech.xcodeproj/project.pbxproj'
if project_file.exists():
    result = subprocess.run(['plutil', '-convert', 'json', '-o', '-', str(project_file)], capture_output=True, text=True)
    if result.returncode == 0: previous = json.loads(result.stdout).get('objects', {})
objects = []
def uid(name): return hashlib.sha1(name.encode()).hexdigest()[:24].upper()
def q(value): return json.dumps(str(value), ensure_ascii=False)
def obj(name, body):
    objects.append(f'{uid(name)} = {{ {body} }};')
    return uid(name)
def arr(values): return '(' + ', '.join(values) + ',)'
def settings(values): return '{' + ' '.join(f'{key} = {q(value)};' for key, value in values.items()) + '}'

app = sorted(str(p.relative_to(ROOT)) for p in (ROOT/'App').glob('*.swift'))
shared = sorted(str(p.relative_to(ROOT)) for p in (ROOT/'Shared').glob('*.swift'))
mac = [file for file in app + shared if file not in ['App/PolytechApp.swift', 'Shared/LessonAttributes.swift']] + ['Mac/PolytechMacApp.swift']
widget = ['LiveActivity/PolytechLiveActivity.swift', 'Widgets/ScheduleWidget.swift'] + shared
macwidget = ['MacWidgets/MacWidgetBundle.swift', 'Widgets/ScheduleWidget.swift'] + [f for f in shared if f != 'Shared/LessonAttributes.swift']
files = sorted(set(app + shared + widget + mac + macwidget + ['MacWidgets/Info.plist', 'Mac/Info.plist', 'MacAssets.xcassets', 'App/Info.plist', 'LiveActivity/Info.plist', 'Assets.xcassets', 'README.md']))
refs = {}
for file in files:
    kind = 'sourcecode.swift' if file.endswith('.swift') else ('folder.assetcatalog' if file.endswith('xcassets') else ('text.plist.xml' if file.endswith('.plist') else 'text'))
    refs[file] = obj(file, f'isa = PBXFileReference; lastKnownFileType = {kind}; path = {q(file)}; sourceTree = "<group>";')
app_product = obj('app-product', 'isa = PBXFileReference; explicitFileType = wrapper.application; path = Polytech.app; sourceTree = BUILT_PRODUCTS_DIR;')
widget_product = obj('widget-product', 'isa = PBXFileReference; explicitFileType = "wrapper.app-extension"; path = PolytechLiveActivity.appex; sourceTree = BUILT_PRODUCTS_DIR;')
mac_product = obj('mac-product', 'isa = PBXFileReference; explicitFileType = wrapper.application; path = PolytechMac.app; sourceTree = BUILT_PRODUCTS_DIR;')
macwidget_product = obj('macwidget-product', 'isa = PBXFileReference; explicitFileType = "wrapper.app-extension"; path = PolytechMacWidgets.appex; sourceTree = BUILT_PRODUCTS_DIR;')
obj('products', f'isa = PBXGroup; children = {arr([app_product, widget_product, mac_product, macwidget_product])}; name = Products; sourceTree = "<group>";')
obj('main-group', f'isa = PBXGroup; children = {arr(list(refs.values()) + [uid("products")])}; sourceTree = "<group>";')
for target, sources in [('app', app + shared), ('widget', widget), ('mac', mac), ('macwidget', macwidget)]:
    builds=[]
    for file in sources:
        builds.append(obj(target+file, f'isa = PBXBuildFile; fileRef = {refs[file]};'))
    obj(target+'-sources', f'isa = PBXSourcesBuildPhase; buildActionMask = 2147483647; files = {arr(builds)}; runOnlyForDeploymentPostprocessing = 0;')
    resources=[]
    if target == 'mac':
        resources.append(obj('mac-assets-build', f'isa = PBXBuildFile; fileRef = {refs["MacAssets.xcassets"]};'))
        resources.append(obj('mac-shared-assets-build', f'isa = PBXBuildFile; fileRef = {refs["Assets.xcassets"]};'))
    if target == 'app': resources.append(obj('assets-build', f'isa = PBXBuildFile; fileRef = {refs["Assets.xcassets"]};'))
    obj(target+'-resources', f'isa = PBXResourcesBuildPhase; buildActionMask = 2147483647; files = {arr(resources) if resources else "()"}; runOnlyForDeploymentPostprocessing = 0;')
    obj(target+'-frameworks', 'isa = PBXFrameworksBuildPhase; buildActionMask = 2147483647; files = (); runOnlyForDeploymentPostprocessing = 0;')
embed = obj('embed-build', f'isa = PBXBuildFile; fileRef = {widget_product}; settings = {{ ATTRIBUTES = (RemoveHeadersOnCopy,); }};')
obj('embed', f'isa = PBXCopyFilesBuildPhase; buildActionMask = 2147483647; dstPath = ""; dstSubfolderSpec = 13; files = {arr([embed])}; name = "Embed App Extensions"; runOnlyForDeploymentPostprocessing = 0;')
obj('proxy', f'isa = PBXContainerItemProxy; containerPortal = {uid("project")}; proxyType = 1; remoteGlobalIDString = {uid("widget-target")}; remoteInfo = PolytechLiveActivity;')
obj('dependency', f'isa = PBXTargetDependency; target = {uid("widget-target")}; targetProxy = {uid("proxy")};')
mac_embed = obj('mac-embed-build', f'isa = PBXBuildFile; fileRef = {macwidget_product}; settings = {{ ATTRIBUTES = (RemoveHeadersOnCopy, CodeSignOnCopy,); }};')
obj('mac-embed', f'isa = PBXCopyFilesBuildPhase; buildActionMask = 2147483647; dstPath = ""; dstSubfolderSpec = 13; files = {arr([mac_embed])}; name = "Embed Mac Widgets"; runOnlyForDeploymentPostprocessing = 0;')
obj('mac-proxy', f'isa = PBXContainerItemProxy; containerPortal = {uid("project")}; proxyType = 1; remoteGlobalIDString = {uid("macwidget-target")}; remoteInfo = PolytechMacWidgets;')
obj('mac-dependency', f'isa = PBXTargetDependency; target = {uid("macwidget-target")}; targetProxy = {uid("mac-proxy")};')
common = {'IPHONEOS_DEPLOYMENT_TARGET':'27.0', 'SDKROOT':'iphoneos', 'SWIFT_VERSION':'5.0', 'CLANG_ENABLE_MODULES':'YES', 'SWIFT_EMIT_LOC_STRINGS':'YES', 'ENABLE_USER_SCRIPT_SANDBOXING':'YES'}
for scope in ['project', 'app', 'widget', 'mac', 'macwidget']:
    configurations=[]
    for name in ['Debug', 'Release']:
        values = dict(common) if scope == 'project' else {
            'CODE_SIGN_STYLE':'Automatic', 'CURRENT_PROJECT_VERSION':'5', 'MARKETING_VERSION':'2.2',
            'GENERATE_INFOPLIST_FILE':'YES', 'TARGETED_DEVICE_FAMILY':'1,2', 'SUPPORTED_PLATFORMS':'iphoneos iphonesimulator',
            'SUPPORTS_MACCATALYST':'NO', 'SUPPORTS_MAC_DESIGNED_FOR_IPHONE_IPAD':'NO', 'SWIFT_STRICT_CONCURRENCY':'complete',
        }
        if scope == 'project':
            values.update({'SWIFT_OPTIMIZATION_LEVEL':'-Onone' if name == 'Debug' else '-O', 'DEBUG_INFORMATION_FORMAT':'dwarf' if name == 'Debug' else 'dwarf-with-dsym'})
            if name == 'Debug': values['SWIFT_ACTIVE_COMPILATION_CONDITIONS'] = 'DEBUG'
        elif scope == 'app':
            values.update({'PRODUCT_BUNDLE_IDENTIFIER':'ru.arthur.Polytech', 'PRODUCT_NAME':'Polytech',
                'CODE_SIGN_ENTITLEMENTS':'App/Polytech.entitlements', 'INFOPLIST_FILE':'App/Info.plist','ASSETCATALOG_COMPILER_APPICON_NAME':'AppIcon',
                'ASSETCATALOG_COMPILER_INCLUDE_ALL_APPICON_ASSETS':'YES', 'ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME':'AccentColor', 'LD_RUNPATH_SEARCH_PATHS':'$(inherited) @executable_path/Frameworks'})
        elif scope == 'widget':
            values.update({'PRODUCT_BUNDLE_IDENTIFIER':'ru.arthur.Polytech.LiveActivity', 'PRODUCT_NAME':'PolytechLiveActivity',
                'CODE_SIGN_ENTITLEMENTS':'LiveActivity/Polytech.entitlements', 'INFOPLIST_FILE':'LiveActivity/Info.plist', 'APPLICATION_EXTENSION_API_ONLY':'YES', 'SKIP_INSTALL':'YES',
                'LD_RUNPATH_SEARCH_PATHS':'$(inherited) @executable_path/Frameworks @executable_path/../../Frameworks'})
        elif scope == 'mac':
            values.update({'PRODUCT_BUNDLE_IDENTIFIER':'ru.arthur.Polytech.Mac', 'PRODUCT_NAME':'PolytechMac',
                'INFOPLIST_FILE':'Mac/Info.plist', 'SDKROOT':'macosx', 'SUPPORTED_PLATFORMS':'macosx',
                'INFOPLIST_KEY_CFBundleDisplayName':'Политех', 'INFOPLIST_KEY_CFBundleName':'Политех', 'MACOSX_DEPLOYMENT_TARGET':'14.0', 'ASSETCATALOG_COMPILER_APPICON_NAME':'MacAppIcon',
                'ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME':'AccentColor', 'CODE_SIGN_IDENTITY':'Apple Development', 'DEVELOPMENT_TEAM':'ZJ5493ZDP5',
                'LD_RUNPATH_SEARCH_PATHS':'$(inherited) @executable_path/../Frameworks',
                'ENABLE_APP_SANDBOX':'YES', 'CODE_SIGN_ENTITLEMENTS':'Mac/Polytech.entitlements',
                'ENABLE_HARDENED_RUNTIME':'YES'})
        else:
            values.update({'PRODUCT_BUNDLE_IDENTIFIER':'ru.arthur.Polytech.Mac.Widgets', 'PRODUCT_NAME':'PolytechMacWidgets',
                'INFOPLIST_FILE':'MacWidgets/Info.plist', 'SDKROOT':'macosx', 'SUPPORTED_PLATFORMS':'macosx',
                'MACOSX_DEPLOYMENT_TARGET':'14.0', 'CODE_SIGN_IDENTITY':'Apple Development', 'DEVELOPMENT_TEAM':'ZJ5493ZDP5', 'SKIP_INSTALL':'YES',
                'APPLICATION_EXTENSION_API_ONLY':'YES', 'ENABLE_APP_SANDBOX':'YES',
                'CODE_SIGN_ENTITLEMENTS':'MacWidgets/PolytechWidgets.entitlements',
                'LD_RUNPATH_SEARCH_PATHS':'$(inherited) @executable_path/../Frameworks @executable_path/../../../../Frameworks'})
        old = previous.get(uid(scope+name), {}).get('buildSettings', {})
        for setting in ['DEVELOPMENT_TEAM', 'PRODUCT_BUNDLE_IDENTIFIER', 'CODE_SIGN_STYLE'] + [key for key in old if key.startswith('INFOPLIST_KEY_')]:
            if setting in old and scope != 'project': values[setting] = old[setting]
        configurations.append(obj(scope+name, f'isa = XCBuildConfiguration; buildSettings = {settings(values)}; name = {name};'))
    obj(scope+'-configs', f'isa = XCConfigurationList; buildConfigurations = {arr(configurations)}; defaultConfigurationIsVisible = 0; defaultConfigurationName = Release;')
for target, name, product, kind in [('app','Polytech',app_product,'application'),('widget','PolytechLiveActivity',widget_product,'app-extension'),('mac','PolytechMac',mac_product,'application'),('macwidget','PolytechMacWidgets',macwidget_product,'app-extension')]:
    phases=[uid(target+'-sources'),uid(target+'-frameworks'),uid(target+'-resources')]
    if target == 'app': phases.append(uid('embed'))
    if target == 'mac': phases.append(uid('mac-embed'))
    obj(target+'-target', f'isa = PBXNativeTarget; buildConfigurationList = {uid(target+"-configs")}; buildPhases = {arr(phases)}; buildRules = (); dependencies = {arr([uid("dependency")]) if target == "app" else (arr([uid("mac-dependency")]) if target == "mac" else "()")}; name = {name}; productName = {name}; productReference = {product}; productType = "com.apple.product-type.{kind}";')
obj('project', f'isa = PBXProject; attributes = {{ BuildIndependentTargetsInParallel = YES; LastSwiftUpdateCheck = 2710; LastUpgradeCheck = 2710; }}; buildConfigurationList = {uid("project-configs")}; compatibilityVersion = "Xcode 14.0"; developmentRegion = ru; hasScannedForEncodings = 0; knownRegions = (ru, en, Base,); mainGroup = {uid("main-group")}; productRefGroup = {uid("products")}; projectDirPath = ""; projectRoot = ""; targets = {arr([uid("app-target"),uid("widget-target"),uid("mac-target"),uid("macwidget-target")])};')
project=ROOT/'Polytech.xcodeproj'
(project/'project.pbxproj').write_text('// !$*UTF8*$!\n{ archiveVersion = 1; classes = {}; objectVersion = 56; objects = {\n'+'\n'.join(objects)+f'\n}}; rootObject = {uid("project")}; }}\n')
scheme=f'''<?xml version="1.0" encoding="UTF-8"?>
<Scheme LastUpgradeVersion="2710" version="1.3">
<BuildAction parallelizeBuildables="YES" buildImplicitDependencies="YES"><BuildActionEntries><BuildActionEntry buildForTesting="YES" buildForRunning="YES" buildForProfiling="YES" buildForArchiving="YES" buildForAnalyzing="YES"><BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{uid('app-target')}" BuildableName="Polytech.app" BlueprintName="Polytech" ReferencedContainer="container:Polytech.xcodeproj"/></BuildActionEntry></BuildActionEntries></BuildAction>
<TestAction buildConfiguration="Debug" shouldUseLaunchSchemeArgsEnv="YES"/>
<LaunchAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" launchStyle="0" useCustomWorkingDirectory="NO" ignoresPersistentStateOnLaunch="NO" debugDocumentVersioning="YES" allowLocationSimulation="YES"><BuildableProductRunnable runnableDebuggingMode="0"><BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{uid('app-target')}" BuildableName="Polytech.app" BlueprintName="Polytech" ReferencedContainer="container:Polytech.xcodeproj"/></BuildableProductRunnable></LaunchAction>
<ProfileAction buildConfiguration="Release" shouldUseLaunchSchemeArgsEnv="YES" savedToolIdentifier="" useCustomWorkingDirectory="NO" debugDocumentVersioning="YES"><BuildableProductRunnable runnableDebuggingMode="0"><BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{uid('app-target')}" BuildableName="Polytech.app" BlueprintName="Polytech" ReferencedContainer="container:Polytech.xcodeproj"/></BuildableProductRunnable></ProfileAction>
<AnalyzeAction buildConfiguration="Debug"/><ArchiveAction buildConfiguration="Release" revealArchiveInOrganizer="YES"/>
</Scheme>'''
(project/'xcshareddata/xcschemes/Polytech.xcscheme').write_text(scheme)

mac_scheme = scheme.replace(uid('app-target'), uid('mac-target')).replace('Polytech.app', 'PolytechMac.app').replace('BlueprintName="Polytech"', 'BlueprintName="PolytechMac"')
(project/'xcshareddata/xcschemes/PolytechMac.xcscheme').write_text(mac_scheme)
