#!/usr/bin/env python3
"""Generate Keyboard.xcodeproj without XcodeGen. Run again after adding or removing Swift files."""
from pathlib import Path
import hashlib
import json

ROOT = Path(__file__).resolve().parents[1]
objects = {}

def identifier(value):
    return hashlib.sha256(value.encode()).hexdigest()[:24].upper()

def add(key, isa, **values):
    key = identifier(key)
    objects[key] = dict(isa=isa, **values)
    return key

def file(path, kind):
    return add("file:" + path, "PBXFileReference", lastKnownFileType=kind, path=path, sourceTree="<group>")

def phase(key, isa, files, **values):
    return add(key, isa, buildActionMask=2147483647, files=files, runOnlyForDeploymentPostprocessing=0, **values)

project_id = identifier("project")
app_id = identifier("target:Application")
keyboard_id = identifier("target:KeyboardExtension")
config = file("Config/Project.xcconfig", "text.xcconfig")
product_config = file("Config/Product.xcconfig", "text.xcconfig")
refs = {str(path.relative_to(ROOT)): file(str(path.relative_to(ROOT)), "sourcecode.swift") for folder in ("App", "Keyboard", "Shared") for path in sorted((ROOT / folder).glob("**/*.swift"))}
translations = [add("locale:" + str(path.relative_to(ROOT)), "PBXFileReference", lastKnownFileType="text.plist.strings", name=path.parent.stem, path=str(path.relative_to(ROOT)), sourceTree="<group>") for path in sorted((ROOT / "Resources").glob("*.lproj/Localizable.strings"))]
resource_refs = [file("Config/PrivacyInfo.xcprivacy", "text.xml"), add("localization:Localizable.strings", "PBXVariantGroup", children=translations, name="Localizable.strings", sourceTree="<group>")]
assets = file("Assets.xcassets", "folder.assetcatalog")
other_refs = [file("Config/App-Info.plist", "text.plist.xml"), file("Config/Keyboard-Info.plist", "text.plist.xml"), file("Config/Shared.entitlements", "text.plist.entitlements")]
app_product = add("product:app", "PBXFileReference", explicitFileType="wrapper.application", includeInIndex=0, path="Application.app", sourceTree="BUILT_PRODUCTS_DIR")
keyboard_product = add("product:keyboard", "PBXFileReference", explicitFileType="wrapper.app-extension", includeInIndex=0, path="KeyboardExtension.appex", sourceTree="BUILT_PRODUCTS_DIR")
products_group = add("group:products", "PBXGroup", children=[app_product, keyboard_product], name="Products", sourceTree="<group>")
main_group = add("group:main", "PBXGroup", children=list(refs.values()) + resource_refs + other_refs + [assets, config, product_config, products_group], sourceTree="<group>")
package = add("package:core", "XCLocalSwiftPackageReference", relativePath="KeyboardCore")

def configurations(name, settings, project=False):
    ids = []
    for mode in ("Debug", "Release"):
        merged = dict(settings)
        merged.update(SWIFT_OPTIMIZATION_LEVEL="-Onone" if mode == "Debug" else "-O", SWIFT_ACTIVE_COMPILATION_CONDITIONS="DEBUG" if mode == "Debug" else "", DEBUG_INFORMATION_FORMAT="dwarf" if mode == "Debug" else "dwarf-with-dsym", ONLY_ACTIVE_ARCH="YES" if mode == "Debug" else "NO")
        values = dict(buildSettings=merged, name=mode)
        if project:
            values["baseConfigurationReference"] = config
        ids.append(add(name + ":" + mode, "XCBuildConfiguration", **values))
    return add("configlist:" + name, "XCConfigurationList", buildConfigurations=ids, defaultConfigurationIsVisible=0, defaultConfigurationName="Release")

project_config = configurations("project", dict(CLANG_ENABLE_MODULES="YES", SDKROOT="iphoneos", SUPPORTED_PLATFORMS="iphoneos iphonesimulator", ENABLE_USER_SCRIPT_SANDBOXING="YES", SWIFT_STRICT_CONCURRENCY="targeted"), project=True)
proxy = add("proxy:keyboard", "PBXContainerItemProxy", containerPortal=project_id, proxyType=1, remoteGlobalIDString=keyboard_id, remoteInfo="KeyboardExtension")
dependency = add("dependency:keyboard", "PBXTargetDependency", target=keyboard_id, targetProxy=proxy)
embed_file = add("embed:keyboard", "PBXBuildFile", fileRef=keyboard_product, settings=dict(ATTRIBUTES=["RemoveHeadersOnCopy", "CodeSignOnCopy"]))
embed_phase = phase("phase:embed", "PBXCopyFilesBuildPhase", [embed_file], dstPath="", dstSubfolderSpec=13, name="Embed App Extensions")

for target, target_id, source_prefix, product_ref, product_type in [("Application", app_id, "App/", app_product, "com.apple.product-type.application"), ("KeyboardExtension", keyboard_id, "Keyboard/", keyboard_product, "com.apple.product-type.app-extension")]:
    is_app = target == "Application"
    build_files = [add("build:" + target + ":" + path, "PBXBuildFile", fileRef=ref) for path, ref in refs.items() if path.startswith(source_prefix) or path.startswith("Shared/")]
    resources = [add("resource:" + target + ":" + ref, "PBXBuildFile", fileRef=ref) for ref in resource_refs]
    if is_app:
        resources.append(add("resource:assets:" + target, "PBXBuildFile", fileRef=assets))
    core_product = add("productdep:" + target, "XCSwiftPackageProductDependency", package=package, productName="KeyboardCore")
    core_build = add("framework:" + target, "PBXBuildFile", productRef=core_product)
    phases = [phase("phase:sources:" + target, "PBXSourcesBuildPhase", build_files), phase("phase:frameworks:" + target, "PBXFrameworksBuildPhase", [core_build]), phase("phase:resources:" + target, "PBXResourcesBuildPhase", resources)]
    if is_app:
        phases.append(embed_phase)
    settings = dict(PRODUCT_NAME="$(TARGET_NAME)", PRODUCT_BUNDLE_IDENTIFIER="$(PRODUCT_BUNDLE_IDENTIFIER_PREFIX)" + ("" if is_app else ".keyboard"), INFOPLIST_FILE="Config/App-Info.plist" if is_app else "Config/Keyboard-Info.plist", GENERATE_INFOPLIST_FILE="NO", CODE_SIGN_ENTITLEMENTS="Config/Shared.entitlements", APPLICATION_EXTENSION_API_ONLY="NO" if is_app else "YES", SKIP_INSTALL="NO" if is_app else "YES", LD_RUNPATH_SEARCH_PATHS="$(inherited) @executable_path/Frameworks" + ("" if is_app else " @executable_path/../../Frameworks"))
    if is_app: settings["ASSETCATALOG_COMPILER_APPICON_NAME"] = "AppIcon"
    target_config = configurations(target, settings)
    add("target:" + target, "PBXNativeTarget", buildConfigurationList=target_config, buildPhases=phases, buildRules=[], dependencies=[dependency] if is_app else [], name=target, packageProductDependencies=[core_product], productName=target, productReference=product_ref, productType=product_type)

add("project", "PBXProject", attributes=dict(BuildIndependentTargetsInParallel="YES", LastUpgradeCheck="1600", TargetAttributes={app_id: dict(CreatedOnToolsVersion="16.0"), keyboard_id: dict(CreatedOnToolsVersion="16.0")}), buildConfigurationList=project_config, compatibilityVersion="Xcode 14.0", developmentRegion="ko", hasScannedForEncodings=0, knownRegions=["ko", "en", "Base"], mainGroup=main_group, packageReferences=[package], productRefGroup=products_group, projectDirPath="", projectRoot="", targets=[app_id, keyboard_id])

def render(value, depth=0):
    if isinstance(value, dict):
        padding = "\t" * (depth + 1)
        return "{\n" + "".join(padding + json.dumps(str(key)) + " = " + render(item, depth + 1) + ";\n" for key, item in value.items()) + "\t" * depth + "}"
    if isinstance(value, list):
        return "(" + ", ".join(render(item, depth) for item in value) + ("," if value else "") + ")"
    if isinstance(value, int):
        return str(value)
    return json.dumps(value)

folder = ROOT / "Keyboard.xcodeproj"
folder.mkdir(exist_ok=True)
document = dict(archiveVersion=1, classes={}, objectVersion=56, objects=objects, rootObject=project_id)
(folder / "project.pbxproj").write_text("// !$*UTF8*$!\n" + render(document) + "\n")
schemes = folder / "xcshareddata/xcschemes"
schemes.mkdir(parents=True, exist_ok=True)
(schemes / "Application.xcscheme").write_text(f'''<?xml version="1.0" encoding="UTF-8"?>
<Scheme LastUpgradeVersion="1600" version="1.3">
  <BuildAction parallelizeBuildables="YES" buildImplicitDependencies="YES"><BuildActionEntries><BuildActionEntry buildForTesting="YES" buildForRunning="YES" buildForProfiling="YES" buildForArchiving="YES" buildForAnalyzing="YES"><BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{app_id}" BuildableName="Application.app" BlueprintName="Application" ReferencedContainer="container:Keyboard.xcodeproj"/></BuildActionEntry></BuildActionEntries></BuildAction>
  <TestAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" shouldUseLaunchSchemeArgsEnv="YES"><Testables/></TestAction>
  <LaunchAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" launchStyle="0" useCustomWorkingDirectory="NO" ignoresPersistentStateOnLaunch="NO" debugDocumentVersioning="YES" debugServiceExtension="internal" allowLocationSimulation="YES"><BuildableProductRunnable runnableDebuggingMode="0"><BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{app_id}" BuildableName="Application.app" BlueprintName="Application" ReferencedContainer="container:Keyboard.xcodeproj"/></BuildableProductRunnable></LaunchAction>
  <ProfileAction buildConfiguration="Release" shouldUseLaunchSchemeArgsEnv="YES" savedToolIdentifier="" useCustomWorkingDirectory="NO" debugDocumentVersioning="YES"/>
  <AnalyzeAction buildConfiguration="Debug"/><ArchiveAction buildConfiguration="Release" revealArchiveInOrganizer="YES"/>
</Scheme>
''')
print("Generated", folder)
