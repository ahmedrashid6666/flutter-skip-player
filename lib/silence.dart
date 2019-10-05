class Silence {
  final int start;
  final int end;
  Silence(this.start, this.end);

  Silence.fromJson(Map<String, dynamic> json)
      : start = json['start'],
        end = json['end'];
  
  @override
  String toString() {
    return "Silence[$start-$end]";
  }
}
