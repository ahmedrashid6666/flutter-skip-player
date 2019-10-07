import 'dart:io';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
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

  @override
  void initState() {
    super.initState();
    permissionNotifier.addListener(() => setState(() {}));
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Skip Player',
      theme: ThemeData(primarySwatch: Colors.blue),
      home: permissionNotifier.value == PermissionStatus.granted ? 
      FutureBuilder<SharedPreferences>(future: SharedPreferences.getInstance(), builder: (context, snapshot) {
        if(snapshot.hasData) {
          SharedPreferences prefs = snapshot.data;
          final path = prefs.getString('path') ?? rootDir;
          return FolderPage(Directory(path));
        } else {
          return CircularProgressIndicator();
        }
      })
       : PermissionPage(permissionNotifier),
    );
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
            icon: Icon(Icons.star),
            onPressed: () async {
              SharedPreferences prefs = await SharedPreferences.getInstance();
              prefs.setString('path', widget.directory.path);
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
          bool showParent = false; //path.isWithin(rootDir, dir.path);

          final contents = _filterFiles(snapshot.data);
          return ListView.builder(
            itemCount: contents.length + (showParent ? 1 : 0),
            itemBuilder: (context, index) {
              int i = showParent ? index - 1 : index;
              return ListTile(
                leading: Icon(
                  i == -1 ? Icons.subdirectory_arrow_left : _icon(contents[i]),
                  size: 40,
                ),
                title: Text(i == -1 ? "Parent Directory" : path.basename(contents[i].path)),
                onTap: () {
                  if (i == -1) {
                    Navigator.push(context, CupertinoPageRoute(builder: (context) => FolderPage(Directory(dir.parent.path))));
                  } else if (contents[i] is Directory) {
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
    if (path.extension(content.path).toLowerCase() == ".mp3") {
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
