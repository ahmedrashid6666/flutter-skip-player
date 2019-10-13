import 'dart:async';
import 'dart:io';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:skip_player/player_widget.dart';
import 'package:path/path.dart' as path;
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() => runApp(AppConfig());

const String rootDir = "/storage/emulated/0";

class Prefs extends ChangeNotifier {
  bool _darkMode = true;
  bool get darkMode => _darkMode;
  set darkMode(bool newValue) {
    if (newValue == _darkMode) return;
    _darkMode = newValue;
    notifyListeners();
  }
}

class AppConfig extends StatefulWidget {
  _AppConfigState createState() => _AppConfigState();
}

class _AppConfigState extends State<AppConfig> {
  final Prefs prefs = Prefs();
  final ValueNotifier<PermissionStatus> permissionNotifier = ValueNotifier(null);
  SharedPreferences sharedPrefs;

  @override
  void initState() {
    super.initState();
    checkPermission();
    loadPrefs();
  }

  void loadPrefs() async {
    sharedPrefs = await SharedPreferences.getInstance();
    prefs.darkMode = sharedPrefs.getBool("darkMode") ?? false;
    prefs.addListener(() => sharedPrefs.setBool("darkMode", prefs.darkMode));
    setState(() {});
  }

  void checkPermission() async {
    permissionNotifier.value = await PermissionHandler().checkPermissionStatus(PermissionGroup.storage);
  }

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        Provider<SharedPreferences>.value(value: sharedPrefs),
        ChangeNotifierProvider<Prefs>.value(value: prefs),
        ChangeNotifierProvider<ValueNotifier<PermissionStatus>>.value(value: permissionNotifier),
      ],
      child: MyApp(),
    );
  }
}

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final prefs = Provider.of<Prefs>(context);
    return MaterialApp(
      title: 'Skip Player',
      theme: ThemeData(brightness: prefs.darkMode ? Brightness.dark : Brightness.light, primarySwatch: Colors.blue),
      home: buildHome(context),
    );
  }

  Widget buildHome(BuildContext context) {
    final permissionNotifier = Provider.of<ValueNotifier<PermissionStatus>>(context);
    final sharedPrefs = Provider.of<SharedPreferences>(context);

    if (permissionNotifier.value == null || sharedPrefs == null) {
      return LoadingPage();
    }

    if (permissionNotifier.value != PermissionStatus.granted) {
      return PermissionPage();
    }

    final path = sharedPrefs.getString('path') ?? rootDir;
    return FolderPage(Directory(path), home: true);
  }
}

class PermissionPage extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text("Permission Required"),
      ),
      body: Center(
        child: Column(
          children: [
            Expanded(flex: 2, child: Container()),
            Text("Permission is required to read storage."),
            SizedBox(height: 10),
            FlatButton(
              color: Theme.of(context).buttonColor,
              child: Text("Set Permission"),
              onPressed: () => _askPermission(context),
            ),
            Expanded(flex: 3, child: Container()),
          ],
        ),
      ),
    );
  }

  void _askPermission(BuildContext context) async {
    Map<PermissionGroup, PermissionStatus> permissions = await PermissionHandler().requestPermissions([PermissionGroup.storage]);
    final permissionNotifier = Provider.of<ValueNotifier<PermissionStatus>>(context);
    permissionNotifier.value = permissions[PermissionGroup.storage];
  }
}

class FolderPage extends StatefulWidget {
  final Directory directory;
  final bool home;
  FolderPage(this.directory, {this.home = false}) : super(key: ValueKey(directory.path));

  _FolderPageState createState() => _FolderPageState();
}

class _FolderPageState extends State<FolderPage> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(path.basename(widget.directory.path)),
        actions: <Widget>[
          IconButton(
            icon: Icon(Icons.home),
            onPressed: () {
              Navigator.pushAndRemoveUntil(context, CupertinoPageRoute(builder: (context) => FolderPage(Directory(rootDir))), (route) => false);
            },
          ),
          IconButton(
            icon: Icon(Provider.of<SharedPreferences>(context)?.getString('path') == widget.directory.path ? Icons.star : Icons.star_border),
            onPressed: () async {
              final prefs = Provider.of<SharedPreferences>(context);
              if (prefs != null) {
                final existingPath = prefs.getString('path');
                setState(() {
                  if (existingPath != widget.directory.path) {
                    prefs.setString('path', widget.directory.path);
                  } else {
                    prefs.remove('path');
                  }
                });
              }
            },
          )
        ],
      ),
      drawer: widget.home ? Drawer(child: SettingsDrawer()) : null,
      body: _buildFileAndDirectoryList(widget.directory),
    );
  }

  List<FileSystemEntity> _contents;

  Widget _buildFileAndDirectoryList(Directory dir) {
    var contentsFuture = _contents != null ? Future.value(_contents) : _listContents(dir);

    return FutureBuilder<List<FileSystemEntity>>(
      future: contentsFuture,
      builder: (BuildContext context, AsyncSnapshot<List<FileSystemEntity>> snapshot) {
        if (snapshot.hasData) {
          _contents = snapshot.data;
          final prefs = Provider.of<SharedPreferences>(context);
          return ListView.builder(
            itemCount: _contents.length,
            itemBuilder: (context, i) {
              final finished = prefs?.getBool(_contents[i].path + ".finished") ?? false;
              return ListTile(
                leading: Icon(
                  finished ? Icons.done : _icon(_contents[i]),
                  size: 40,
                ),
                title: Text(path.basename(_contents[i].path)),
                onTap: () {
                  if (_contents[i] is Directory) {
                    Navigator.push(context, CupertinoPageRoute(builder: (context) => FolderPage(_contents[i] as Directory)));
                  } else {
                    Navigator.push(context, MaterialPageRoute(builder: (context) {
                      return Scaffold(
                        appBar: AppBar(title: Text(path.basename(_contents[i].path))),
                        endDrawer: Drawer(child: SettingsDrawer()),
                        body: PlayerWidget(_contents[i]),
                      );
                    }));
                  }
                },
              );
            },
          );
        } else if (snapshot.hasError) {
          return ErrorWidget(snapshot.error.toString());
        } else {
          return LoadingWidget();
        }
      },
    );
  }

  Future<List<FileSystemEntity>> _listContents(Directory directory) async => await compute(_computeContents, directory);

  static List<FileSystemEntity> _computeContents(Directory directory) {
    var files = directory.listSync();
    files = _filterFiles(files);
    files.sort(_compareFilenames);
    return files;
  }

  IconData _icon(FileSystemEntity content) {
    if (content is Directory) {
      return Icons.folder;
    }
    final ext = path.extension(content.path).toLowerCase();
    if (ext == ".mp3" || ext == ".mp4") {
      return Icons.audiotrack;
    }
    return Icons.insert_drive_file;
  }

  static List<FileSystemEntity> _filterFiles(List<FileSystemEntity> files) {
    // hide .silence files
    return files.where((f) {
      var name = path.basename(f.path);
      var ext = path.extension(f.path).toLowerCase();
      return ext != ".silence" && name != ".nomedia";
    }).toList();
  }

  static final RegExp _compareRegex = RegExp(r"(\D+)|(\d+)", caseSensitive: false);
  static int _compareFilenames(FileSystemEntity a, FileSystemEntity b) {
    final pathA = path.basename(a.path).toLowerCase();
    final pathB = path.basename(b.path).toLowerCase();

    final matchesA = _compareRegex.allMatches(pathA).toList();
    final matchesB = _compareRegex.allMatches(pathB).toList();
    for (int i = 0; i < matchesA.length && i < matchesB.length; i++) {
      final matchA = matchesA[i];
      final matchB = matchesB[i];
      final aChars = matchA.group(1);
      final aNums = matchA.group(2);
      final bChars = matchB.group(1);
      final bNums = matchB.group(2);

      if (aChars == null && bChars != null) {
        return -1;
      }
      if (aChars != null && bChars == null) {
        return 1;
      }

      if (aChars != null && bChars != null) {
        int result = aChars.compareTo(bChars);
        if (result != 0) {
          return result;
        }
      }
      if (aNums != null && bNums != null) {
        int result = int.parse(aNums).compareTo(int.parse(bNums));
        if (result != 0) {
          return result;
        }
      }
    }
    return 0;
  }
}

class LoadingPage extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text("Loading...")),
      body: LoadingWidget(),
    );
  }
}

class LoadingWidget extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Center(
      child: SizedBox(
        width: 75,
        height: 75,
        child: CircularProgressIndicator(),
      ),
    );
  }
}

class ErrorWidget extends StatelessWidget {
  final String error;
  const ErrorWidget(this.error);

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(8.0),
      child: Text(error, style: TextStyle(color: Theme.of(context).errorColor)),
    );
  }
}

class SettingsDrawer extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final prefs = Provider.of<Prefs>(context);
    return Column(
      mainAxisAlignment: MainAxisAlignment.start,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: double.infinity,
          child: DrawerHeader(
            child: Text(
              'Settings',
              style: Theme.of(context).textTheme.display1,
            ),
          ),
        ),
        Expanded(
          child: ListView(
            padding: EdgeInsets.zero,
            children: [
              ListTile(
                leading: Text("Dark Mode"),
                trailing: Switch(
                  value: prefs.darkMode,
                  onChanged: (value) => prefs.darkMode = value,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
