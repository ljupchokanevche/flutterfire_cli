/*
 * Copyright (c) 2016-present Invertase Limited & Contributors
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this library except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *   http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 *
 */

import 'dart:convert';
import 'dart:io';

import 'package:ansi_styles/ansi_styles.dart';
import 'package:ci/ci.dart' as ci;
import 'package:interact/interact.dart' as interact;
import 'package:path/path.dart'
    show relative, normalize, windows, joinAll, dirname;

import '../flutter_app.dart';
import 'platform.dart';

/// Key for windows platform.
const String kWindows = 'windows';

/// Key for macos platform.
const String kMacos = 'macos';

/// Key for linux platform.
const String kLinux = 'linux';

/// Key for IPA (iOS) platform. Shared with key for firebase.json
const String kIos = 'ios';

/// Key for APK (Android) platform.
const String kAndroid = 'android';

/// Key for Web platform.
const String kWeb = 'web';

// Keys for firebase.json
const String kFlutter = 'flutter';
const String kPlatforms = 'platforms';
const String kBuildConfiguration = 'buildConfigurations';
const String kTargets = 'targets';
const String kUploadDebugSymbols = 'uploadDebugSymbols';
const String kAppId = 'appId';
const String kProjectId = 'projectId';
const String kServiceFileOutput = 'serviceFileOutput';
const String kDefaultConfig = 'default';

enum ProjectConfiguration {
  target,
  buildConfiguration,
  defaultConfig,
}

extension Let<T> on T? {
  R? let<R>(R Function(T value) cb) {
    if (this == null) return null;

    return cb(this as T);
  }
}

bool get isCI {
  return ci.isCI;
}

int get terminalWidth {
  if (stdout.hasTerminal) {
    return stdout.terminalColumns;
  }

  return 80;
}

String listAsPaddedTable(List<List<String>> table, {int paddingSize = 1}) {
  final output = <String>[];
  final maxColumnSizes = <int, int>{};
  for (final row in table) {
    var i = 0;
    for (final column in row) {
      if (maxColumnSizes[i] == null ||
          maxColumnSizes[i]! < AnsiStyles.strip(column).length) {
        maxColumnSizes[i] = AnsiStyles.strip(column).length;
      }
      i++;
    }
  }

  for (final row in table) {
    var i = 0;
    final rowBuffer = StringBuffer();
    for (final column in row) {
      final colWidth = maxColumnSizes[i]! + paddingSize;
      final cellWidth = AnsiStyles.strip(column).length;
      var padding = colWidth - cellWidth;
      if (padding < paddingSize) padding = paddingSize;

      // last cell of the list, no need for padding
      if (i + 1 >= row.length) padding = 0;

      rowBuffer.write('$column${List.filled(padding, ' ').join()}');
      i++;
    }
    output.add(rowBuffer.toString());
  }

  return output.join('\n');
}

bool promptBool(
  String prompt, {
  bool defaultValue = true,
}) {
  return interact.Confirm(
    prompt: prompt,
    defaultValue: defaultValue,
  ).interact();
}

int promptSelect(
  String prompt,
  List<String> choices, {
  int initialIndex = 0,
}) {
  return interact.Select(
    prompt: prompt,
    options: choices,
    initialIndex: initialIndex,
  ).interact();
}

List<int> promptMultiSelect(
  String prompt,
  List<String> choices, {
  List<bool>? defaultSelection,
}) {
  return interact.MultiSelect(
    prompt: prompt,
    options: choices,
    defaults: defaultSelection,
  ).interact();
}

String promptInput(
  String prompt, {
  String? defaultValue,
  dynamic Function(String)? validator,
}) {
  return interact.Input(
    prompt: prompt,
    defaultValue: defaultValue,
    validator: (String input) {
      if (validator == null) return true;
      final Object? validatorResult = validator(input);
      if (validatorResult is bool) {
        return validatorResult;
      }
      if (validatorResult is String) {
        // ignore: only_throw_errors
        throw interact.ValidationError(validatorResult);
      }
      return false;
    },
  ).interact();
}

interact.SpinnerState? activeSpinnerState;
interact.SpinnerState spinner(String Function(bool) rightPrompt) {
  activeSpinnerState = interact.Spinner(
    icon: AnsiStyles.blue('i'),
    rightPrompt: rightPrompt,
  ).interact();
  return activeSpinnerState!;
}

String firebaseRcPathForDirectory(Directory directory) {
  return joinAll([directory.path, '.firebaserc']);
}

String pubspecPathForDirectory(Directory directory) {
  return joinAll([directory.path, 'pubspec.yaml']);
}

String androidAppBuildGradlePathForAppDirectory(Directory directory) {
  return joinAll([directory.path, 'android', 'app', 'build.gradle']);
}

File xcodeProjectFileInDirectory(Directory directory, String platform) {
  return File(
    joinAll(
      [directory.path, platform, 'Runner.xcodeproj', 'project.pbxproj'],
    ),
  );
}

File xcodeAppInfoConfigFileInDirectory(Directory directory, String platform) {
  return File(
    joinAll(
      [directory.path, platform, 'Runner', 'Configs', 'AppInfo.xcconfig'],
    ),
  );
}

String androidManifestPathForAppDirectory(Directory directory) {
  return joinAll([
    directory.path,
    'android',
    'app',
    'src',
    'main',
    'AndroidManifest.xml',
  ]);
}

String relativePath(String path, String from) {
  if (currentPlatform.isWindows) {
    return windows
        .normalize(relative(path, from: from))
        .replaceAll(r'\', r'\\');
  }
  return normalize(relative(path, from: from));
}

String removeForwardSlash(String input) {
  if (input.startsWith('/')) {
    return input.substring(1);
  } else {
    return input;
  }
}

Future<Map> appleConfigFromFirebaseJson(
  String appleProjectPath,
  String platform,
) async {
  // Pull values from firebase.json in root of project
  final flutterAppPath = dirname(appleProjectPath);
  final firebaseJson =
      await File('$flutterAppPath/firebase.json').readAsString();

  final decodedMap = json.decode(firebaseJson) as Map;

  final flutterConfig = decodedMap[kFlutter] as Map;
  final applePlatform = flutterConfig[kPlatforms] as Map;
  final appleConfig =
      applePlatform[platform.toLowerCase() == 'ios' ? kIos : kMacos] as Map;

  return appleConfig;
}

String getProjectConfigurationProperty(
  ProjectConfiguration projectConfiguration,
) {
  switch (projectConfiguration) {
    case ProjectConfiguration.defaultConfig:
      return kDefaultConfig;
    case ProjectConfiguration.buildConfiguration:
      return kBuildConfiguration;
    case ProjectConfiguration.target:
      return kTargets;
  }
}

Map<String, dynamic> _generateFlutterMap() {
  return <String, dynamic>{
    kFlutter: {
      kPlatforms: {
        kIos: {
          kBuildConfiguration: <String, Object>{},
          kTargets: <String, Object>{},
          kDefaultConfig: <String, Object>{}
        },
        kMacos: {
          kBuildConfiguration: <String, Object>{},
          kTargets: <String, Object>{},
          kDefaultConfig: <String, Object>{}
        }
      }
    }
  };
}

Future<void> writeFirebaseJsonFile(
  FlutterApp flutterApp,
) async {
  final file = File('${flutterApp.package.path}/firebase.json');

  if (file.existsSync()) {
    final decodedMap =
        json.decode(await file.readAsString()) as Map<String, dynamic>;

    // Flutter map exists, exit
    if (decodedMap[kFlutter] != null) return;

    // Update existing map with Flutter map
    final updatedMap = <String, dynamic>{
      ...decodedMap,
      ..._generateFlutterMap(),
    };

    final mapJson = json.encode(updatedMap);

    file.writeAsStringSync(mapJson);
  } else {
    final map = _generateFlutterMap();

    final mapJson = json.encode(map);

    file.writeAsStringSync(mapJson);
  }
}
