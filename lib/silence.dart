class Silence {
  final int start;
  final int end;
  Silence(this.start, this.end);

  Silence.fromJson(Map<String, dynamic> json)
      : start = json['start'],
        end = json['end'];
  
  @override
  String toString() {
    final strStart = Duration(milliseconds: start).toString();
    final strEnd = Duration(milliseconds: end).toString();
    final strLength = Duration(milliseconds: end - start).toString();
    return "Silence[$strStart - $strEnd : $strLength]";
    //return "Silence[$start - $end]";
  }
}
