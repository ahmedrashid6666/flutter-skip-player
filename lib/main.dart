import 'dart:io';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:skip_player/player_widget.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;

void main() => runApp(MyApp());

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Skip Player',
      theme: ThemeData(primarySwatch: Colors.blue),
      home: FolderPage(getExternalStorageDirectory(), isRoot: true),
    );
  }
}

class FolderPage extends StatefulWidget {
  final Future<Directory> directory;
  final bool isRoot;
  FolderPage(this.directory, {this.isRoot = false});

  _FolderPageState createState() => _FolderPageState();
}

class _FolderPageState extends State<FolderPage> {
  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Directory>(
      future: widget.directory,
      builder: (BuildContext context, AsyncSnapshot<Directory> snapshot) {
        if (snapshot.hasData) {
          final dir = snapshot.data;
          return Scaffold(
            appBar: AppBar(title: Text(widget.isRoot ? "Skip Player" : path.basename(dir.path))),
            body: _buildDirectoryList(dir),
          );
        } else if (snapshot.hasError) {
          return Text(snapshot.error.toString());
        } else {
          return LoadingPage();
        }
      },
    );
  }

  Widget _buildDirectoryList(Directory dir) {
    return FutureBuilder<List<FileSystemEntity>>(
      future: _listContents(dir),
      builder: (BuildContext context, AsyncSnapshot<List<FileSystemEntity>> snapshot) {
        if (snapshot.hasData) {
          final contents = _filterFiles(snapshot.data);
          return ListView.builder(
            itemCount: contents.length,
            itemBuilder: (context, i) {
              return ListTile(
                leading: Icon(
                  _icon(contents[i]),
                  size: 40,
                ),
                title: Text(path.basename(contents[i].path)),
                onTap: () {
                  if (contents[i] is Directory) {
                    Navigator.push(context, CupertinoPageRoute(builder: (context) => FolderPage(Future.value(contents[i] as Directory))));
                  } else {
                    Navigator.push(context, MaterialPageRoute(builder: (context) {
                      return Scaffold(
                          appBar: AppBar(title: Text("")),
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
          return Text(snapshot.error.toString());
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
    return files.where((f) => path.extension(f.path).toLowerCase() != ".silence").toList();
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
