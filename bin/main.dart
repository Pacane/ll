import 'dart:io' as io;
import 'dart:math';

import 'package:collection/collection.dart';
import 'package:io/ansi.dart';

var regExp = RegExp(r'\s');

Future<void> lsWrapper(List<String> arguments) async {
  var workingDir =
      (arguments.firstWhereOrNull((element) => !element.startsWith('-')) ??
              io.Directory.current.absolute.path)
          .replaceFirst('~', io.Platform.environment['HOME']!);

  var options = arguments.where((element) => element.startsWith('-')).toList();

  var p = await io.Process.run(
    'gls',
    ['-lh', '--group-directories-first', ...options],
    workingDirectory: workingDir,
  );
  var out = (p.stdout as String).split('\n').map((e) {
    if (e.startsWith('total') || e.isEmpty) {
      return e;
    }
    return insertIcon(e, '');
  }).toList();

  int findMaxLengthOfColumn(List<String> input, int columnIndex) => () {
        var x = input
            .map((e) => e.split(regExp))
            .where((element) => element.length >= 10)
            .map((e) => e[columnIndex].length);

        if (x.isEmpty) {
          return 0;
        } else {
          return x.reduce(max);
        }
      }();

  var paddings =
      List.generate(10, (index) => findMaxLengthOfColumn(out, index));

  var formatted = out.map((e) {
    var split = e.split(regExp);

    if (split.length < 10) {
      return e;
    }

    var mode = split[0];
    var fileName2 = split.getRange(9, split.length).join(' ');

    var sb = StringBuffer();
    writeColumn(sb, split[0].padRight(paddings[0])); // permissions
    writeColumn(sb, split[1].padLeft(paddings[1])); // linkCount
    writeColumn(sb, split[2].padLeft(paddings[2])); // owner
    writeColumn(sb, split[3].padRight(paddings[3])); // group
    writeColumn(sb, split[4].padLeft(paddings[4])); // size
    writeColumn(sb, split[5].padLeft(paddings[5]), []); // Month
    writeColumn(sb, split[6].padLeft(paddings[6]), []); // Day
    writeColumn(
        sb, split[7].padLeft(paddings[7]), []); // date modified (year/hour)
    formatIcon(sb, mode, fileName2, workingDir);

    formatFileName(sb, fileName2, split[0], workingDir);

    return sb.toString();
  }).join('\n');

  print(formatted);
}

void formatIcon(
    StringBuffer sb, String mode, String fileName, String workingDir) {
  if (isDirectory(mode)) {
    writeColumn(sb, getDirectoryIcon(fileName), [styleBold]);
  } else if (isLink(mode)) {
    var fileNameOnly = fileName.split(' -> ')[0];
    var linkInfo = LinkInfo(mode, fileNameOnly, workingDir);

    if (linkInfo.targetIsDirectory) {
      writeColumn(sb, getDirectoryIcon(fileName), [styleBold, lightGreen]);
    } else if (linkInfo.targetIsFile) {
      writeColumn(sb, getIconFromFileName(fileName), [styleBold]);
    } else if (!linkInfo.targetExists) {
      writeColumn(sb, ' ', [styleBold]);
    }
  } else {
    writeColumn(sb, getIconFromFileName(fileName), [styleBold]);
  }
}

String getDirectoryIcon(String fileName) {
  var icon = () {
    return dirNodeExactMatches[fileName] ?? '';
  }();

  return '$icon ';
}

String getIconFromFileName(String fileName) {
  var icon = () {
    if (fileNodeExactMatches.containsKey(fileName)) {
      return fileNodeExactMatches[fileName];
    }

    if (fileName.startsWith('.') && fileName.endsWith('rc')) {
      return '';
    } else {
      var extension = () {
        if (fileName.startsWith('.')) {
          fileName = fileName.replaceFirst('.', '');
        }

        if (fileName.contains('.')) {
          return fileName.split('.').last;
        }

        return '';
      }()
          .toLowerCase();
      return fileNodeExtensions[extension] ?? '';
    }
  }();

  return '$icon ';
}

class LinkInfo {
  final String mode;
  final String fileName;
  final String workingDir;

  LinkInfo(this.mode, this.fileName, this.workingDir);

  bool get isDirectory2 => isDirectory(mode);

  bool get isSocket2 => isSocket(mode);

  bool get isExecutable2 => isExecutable(mode);

  bool get targetExists => targetIsDirectory || targetIsFile;

  String get targetPath => io.Link('$workingDir/$fileName').targetSync();

  bool get targetIsDirectory {
    var t = getLinkTarget();
    var target = io.Directory(t);

    return target.existsSync();
  }

  bool get targetIsFile {
    var t = getLinkTarget();
    var target = io.File(t);

    return target.existsSync();
  }

  String getLinkTarget() {
    var link = io.Link('$workingDir/$fileName');
    var t = link.targetSync();
    return t;
  }
}

void formatFileName(
    StringBuffer sb, String fileName, String permissions, String workingDir) {
  var fileNameOnly = fileName.split(' -> ')[0];

  if (isLink(permissions)) {
    formatLink(sb, LinkInfo(permissions, fileNameOnly, workingDir));
  } else if (isDirectory(permissions)) {
    writeColumn(sb, fileName, [blue, styleBold]);
  } else if (isExecutable(permissions)) {
    writeColumn(sb, fileName, [styleBold, lightGreen]);
  } else if (isSocket(permissions)) {
    writeColumn(sb, fileName, [styleBold, magenta]);
  } else if (isZipFile(fileName)) {
    writeColumn(sb, fileName, [styleBold, red]);
  } else {
    writeColumn(sb, fileName);
  }
}

void formatLink(StringBuffer sb, LinkInfo linkInfo) {
  if (isExecutable(linkInfo.mode)) {
    writeColumn(sb, linkInfo.fileName, [cyan, styleBold]);
  } else {
    writeColumn(sb, linkInfo.fileName, [lightGreen, styleBold]);
  }
  writeColumn(sb, '->');

  try {
    var t = linkInfo.targetPath;
    if (!linkInfo.targetExists) {
      writeColumn(sb, t, [red, styleBold]);
    } else {
      if (linkInfo.targetIsFile) {
        var tFile = io.File(t);
        var tStat = tFile.statSync();
        var tMode = tStat.modeString();

        if (isExecutable(tMode)) {
          writeColumn(sb, t, [lightGreen, styleBold]);
        } else {
          writeColumn(sb, t);
        }
      } else if (linkInfo.targetIsDirectory) {
        writeColumn(sb, t, [blue, styleBold]);
      }
    }
  } catch (e) {
    print(e);
  }
}

void writeColumn(StringBuffer sb, String columnText,
    [List<AnsiCode> styles = const []]) {
  sb.write(wrapWith(columnText, styles)); // permissions
  sb.write(' ');
}

String insertIcon(String originalLine, String icon) {
  var parts = originalLine
      .split(regExp)
      .where((element) => element.isNotEmpty)
      .toList();
  parts.insert(8, icon);
  return parts.join(' ');
}

Future<void> main(List<String> arguments) async {
  await overrideAnsiOutput(true, () => lsWrapper(arguments));
}

bool isCharacterSame(String char, int codeUnit) =>
    codeUnit == char.codeUnitAt(0);

bool isDirectory(String mode) => isCharacterSame('d', mode.codeUnits.first);

bool isLink(String mode) => isCharacterSame('l', mode.codeUnits.first);

bool isSocket(String mode) => isCharacterSame('s', mode.codeUnits.first);

bool isExecutable(String mode) => isCharacterSame('x', mode.codeUnits.last);

bool isZipFile(String fileName) => fileName.endsWith('.zip');

const fileNodeExtensions = {
  '7z': '',
  'a': '',
  'ai': '',
  'apk': '',
  'asm': '',
  'asp': '',
  'aup': '',
  'avi': '',
  'bak': '',
  'bat': '',
  'bmp': '',
  'bz2': '',
  'c': '',
  'c++': '',
  'cab': '',
  'cbr': '',
  'cbz': '',
  'cc': '',
  'class': '',
  'clj': '',
  'cljc': '',
  'cljs': '',
  'cmake': '',
  'coffee': '',
  'conf': '',
  'cp': '',
  'cpio': '',
  'cpp': '',
  'cs': '',
  'css': '',
  'cue': '',
  'cvs': '',
  'cxx': '',
  'd': '',
  'dart': '',
  'db': '',
  'deb': '',
  'diff': '',
  'dll': '',
  'doc': '',
  'docx': '',
  'dump': '',
  'edn': '',
  'efi': '',
  'ejs': '',
  'elf': '',
  'elm': '',
  'epub': '',
  'erl': '',
  'ex': '',
  'exe': '',
  'exs': '',
  'eex': '',
  'f#': '',
  'fifo': '|',
  'fish': '',
  'flac': '',
  'flv': '',
  'fs': '',
  'fsi': '',
  'fsscript': '',
  'fsx': '',
  'gem': '',
  'gif': '',
  'go': '',
  'gz': '',
  'gzip': '',
  'h': '',
  'hbs': '',
  'hrl': '',
  'hs': '',
  'htaccess': '',
  'htpasswd': '',
  'htm': '',
  'html': '',
  'ico': '',
  'img': '',
  'ini': '',
  'iso': '',
  'jar': '',
  'java': '',
  'jl': '',
  'jpeg': '',
  'jpg': '',
  'js': '',
  'json': '',
  'jsx': '',
  'key': '',
  'less': '',
  'lha': '',
  'lhs': '',
  'lock': '',
  'log': '',
  'logs': '',
  'lua': '',
  'lzh': '',
  'lzma': '',
  'm4a': '',
  'm4v': '',
  'markdown': '',
  'md': '',
  'mkv': '',
  'ml': 'λ',
  'mli': 'λ',
  'mov': '',
  'mp3': '',
  'mp4': '',
  'mpeg': '',
  'mpg': '',
  'msi': '',
  'mustache': '',
  'o': '',
  'ogg': '',
  'pdf': '',
  'php': '',
  'pl': '',
  'pm': '',
  'png': '',
  'pub': '',
  'ppt': '',
  'pptx': '',
  'psb': '',
  'psd': '',
  'py': '',
  'pyc': '',
  'pyd': '',
  'pyo': '',
  'rar': '',
  'rb': '',
  'rc': '',
  'rlib': '',
  'rom': '',
  'rpm': '',
  'rs': '',
  'rss': '',
  'rtf': '',
  's': '',
  'so': '',
  'scala': '',
  'scss': '',
  'sh': '',
  'slim': '',
  'sln': '',
  'sql': '',
  'styl': '',
  'suo': '',
  't': '',
  'tar': '',
  'tgz': '',
  'ts': '',
  'txt': '',
  'twig': '',
  'vim': '',
  'vimrc': '',
  'wav': '',
  'webm': '',
  'xbps': '',
  'xhtml': '',
  'xls': '',
  'xlsx': '',
  'xml': '',
  'xul': '',
  'xz': '',
  'yaml': '',
  'yml': '',
  'zip': '',
};

const dirNodeExactMatches = {
  '.git': '',
  'Desktop': '',
  'Documents': '',
  'Downloads': '',
  'Dotfiles': '',
  'Dropbox': '',
  'Music': '',
  'Pictures': '',
  'Public': '',
  'Templates': '',
  'Videos': '',
};

var fileNodeExactMatches = {
  '.Xauthority': '',
  '.Xdefaults': '',
  '.Xresources': '',
  '.bash_aliases': '',
  '.bashprofile': '',
  '.bash_profile': '',
  '.bash_logout': '',
  '.bash_history': '',
  '.bashrc': '',
  '.dmrc': '',
  '.DS_Store': '',
  '.fasd': '',
  '.fehbg': '',
  '.gitconfig': '',
  '.gitattributes': '',
  '.gitignore': '',
  '.inputrc': '',
  '.jack-settings': '',
  '.mime.types': '',
  '.nvidia-settings-rc': '',
  '.pam_environment': '',
  '.profile': '',
  '.recently-used': '',
  '.selected_editor': '',
  '.vim': '',
  '.vimrc': '',
  '.viminfo': '',
  '.xinitrc': '',
  '.xinputrc': '',
  'config': '',
  'Dockerfile': '',
  'docker-compose.yml': '',
  'dropbox': '',
  'exact-match-case-sensitive-1.txt': 'X1',
  'exact-match-case-sensitive-2': 'X2',
  'favicon.ico': '',
  'a.out': '',
  'bspwmrc': '',
  'sxhkdrc': '',
  'Makefile': '',
  'Makefile.in': '',
  'Makefile.ac': '',
  'config.mk': '',
  'config.m4': '',
  'config.ac': '',
  'configure': '',
  'Rakefile': '',
  'gruntfile.coffee': '',
  'gruntfile.js': '',
  'gruntfile.ls': '',
  'gulpfile.coffee': '',
  'gulpfile.js': '',
  'gulpfile.ls': '',
  'ini': '',
  'ledger': '',
  'package.json': '',
  'package-lock.json': '',
  '.ncmpcpp': '',
  'playlists': '',
  'known_hosts': '',
  'authorized_keys': '',
  'license': '',
  'LICENSE.md': '',
  'LICENSE': '',
  'LICENSE.txt': '',
  'mimeapps.list': '',
  'node_modules': '',
  'procfile': '',
  'react.jsx': '',
  'README.rst': '',
  'README.md': '',
  'README.markdown': '',
  'README': '',
  'README.txt': '',
  'user-dirs.dirs': '',
  'webpack.config.js': '',
};
