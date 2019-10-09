import 'dart:io';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:skip_player/player_widget.dart';
import 'package:path/path.dart' as path;
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() => runApp(MyApp());

const String rootDir = "/storage/emulated/0";

class MyApp extends StatefulWidget {
  @override
  _MyAppState createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  ValueNotifier<PermissionStatus> permissionNotifier = ValueNotifier(null);
  SharedPreferences prefs;

  @override
  void initState() {
    permissionNotifier.addListener(() => setState(() {}));
    loadPrefs();
    super.initState();
  }

  void loadPrefs() async {
    final result = await SharedPreferences.getInstance();
    setState(() => prefs = result);
  }

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        Provider<SharedPreferences>.value(value: prefs),
      ],
      child: MaterialApp(
        title: 'Skip Player',
        theme: ThemeData(primarySwatch: Colors.blue),
        home: permissionNotifier.value == PermissionStatus.granted ? mainPage() : PermissionPage(permissionNotifier),
      ),
    );
  }

  Widget mainPage() {
    if (prefs == null) {
      return CircularProgressIndicator();
    }
    final path = prefs.getString('path') ?? rootDir;
    return FolderPage(Directory(path));
  }
}

class PermissionPage extends StatefulWidget {
  final ValueNotifier<PermissionStatus> permissionNotifier;
  PermissionPage(this.permissionNotifier);

  @override
  _PermissionPageState createState() => _PermissionPageState();
}

class _PermissionPageState extends State<PermissionPage> {
  @override
  void initState() {
    super.initState();
    _askPermission();
  }

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
              onPressed: _askPermission,
            ),
            Expanded(flex: 3, child: Container()),
          ],
        ),
      ),
    );
  }

  void _askPermission() async {
    Map<PermissionGroup, PermissionStatus> permissions = await PermissionHandler().requestPermissions([PermissionGroup.storage]);
    widget.permissionNotifier.value = permissions[PermissionGroup.storage];
  }
}

class FolderPage extends StatefulWidget {
  final Directory directory;
  FolderPage(this.directory);

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
            icon: Icon(Provider.of<SharedPreferences>(context)?.getString('path') == widget.directory.path ? Icons.star : Icons.star_border),
            onPressed: () async {
              final prefs = Provider.of<SharedPreferences>(context);
              if (prefs != null) {
                final existingPath = prefs.getString('path');
                setState(() {
                  if (existingPath == null) {
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
      body: _buildFileAndDirectoryList(widget.directory),
    );
  }

  Widget _buildFileAndDirectoryList(Directory dir) {
    return FutureBuilder<List<FileSystemEntity>>(
      future: _listContents(dir),
      builder: (BuildContext context, AsyncSnapshot<List<FileSystemEntity>> snapshot) {
        if (snapshot.hasData) {
          final contents = _filterFiles(snapshot.data);
          contents.sort(compareFilenames);
          final prefs = Provider.of<SharedPreferences>(context);
          return ListView.builder(
            itemCount: contents.length,
            itemBuilder: (context, i) {
              final finished = prefs?.getBool(contents[i].path + ".finished") ?? false;
              return ListTile(
                leading: Icon(
                  finished ? Icons.done : _icon(contents[i]),
                  size: 40,
                ),
                title: Text(path.basename(contents[i].path)),
                onTap: () {
                  if (contents[i] is Directory) {
                    Navigator.push(context, CupertinoPageRoute(builder: (context) => FolderPage(contents[i] as Directory)));
                  } else {
                    Navigator.push(context, MaterialPageRoute(builder: (context) {
                      return Scaffold(
                          appBar: AppBar(title: Text(path.basename(contents[i].path))),
                          body: Column(
                            children: <Widget>[
                              Expanded(flex: 1, child: Container()),
                              PlayerWidget(contents[i]),
                              Expanded(flex: 2, child: Container()),
                            ],
                          ));
                    }));
                  }
                },
              );
            },
          );
        } else if (snapshot.hasError) {
          return ErrorWidget(snapshot.error.toString());
        } else {
          return LoadingPage();
        }
      },
    );
  }

  Future<List<FileSystemEntity>> _listContents(Directory directory) async => directory.listSync();

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

  List<FileSystemEntity> _filterFiles(List<FileSystemEntity> files) {
    // hide .silence files
    return files.where((f) {
      var name = path.basename(f.path);
      var ext = path.extension(f.path).toLowerCase();
      return ext != ".silence" && name != ".nomedia";
    }).toList();
  }

  int compareFilenames(FileSystemEntity a, FileSystemEntity b) {
    final pathA = path.basename(a.path).toLowerCase();
    final pathB = path.basename(b.path).toLowerCase();
    RegExp exp = new RegExp(r"(\D+)|(\d+)");
    final matchesA = exp.allMatches(pathA).toList();
    final matchesB = exp.allMatches(pathB).toList();
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
      body: Center(
        child: SizedBox(
          width: 75,
          height: 75,
          child: CircularProgressIndicator(valueColor: AlwaysStoppedAnimation(Colors.red)),
        ),
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
