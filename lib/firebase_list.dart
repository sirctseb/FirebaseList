library firebase_list;

import 'dart:async';
import 'package:firebase/firebase.dart';

class FirebaseListEvent {
  /// The event type. FirebaseListEvent.VALUE_ADDED,
  /// FirebaseListEvent.VALUE_REMOVED, or FirebaseListEvent.VALUE_SET
  // TODO omit because they're separate streams?
  final String type;

  /// The key of the firebase location of the child
  final String key;

  /// The value of the child
  final Map data;

  /// The index where the child was added, removed, or set
  final int index;

  /// The original firebase event that prompted this event
  final Event event;

  FirebaseListEvent(this.type, this.key, this.data, this.index, this.event);

  static final String VALUE_ADDED = 'value_added';
  static final String VALUE_REMOVED = 'value_removed';
  static final String VALUE_SET = 'value_set';
}

/** A List-like object that remains synced to a location in a firebase
 * database.
 */
class FirebaseList {
  /// Reference to the [Firebase] location
  final Firebase firebase;

  List _list = [];

  // subscription to native firebase events
  List<StreamSubscription> _subs = [];

  // stream controllers for FirebaseListEvents
  StreamController _onValueAdded = new StreamController.broadcast();
  StreamController _onValueRemoved = new StreamController.broadcast();
  StreamController _onValueSet = new StreamController.broadcast();

  /// Event that occurs when a new value is added to the list
  Stream<FirebaseListEvent> get onValueAdded => _onValueAdded.stream;
  Stream<FirebaseListEvent> get onValueRemoved => _onValueRemoved.stream;
  Stream<FirebaseListEvent> get onValueSet => _onValueSet.stream;

  FirebaseList(Firebase this.firebase) {
    _initListeners();
  }

  /// The length of the list
  int get length => _list.length;

  /// An unmodifiable [List] representation of the list
  // TODO should _parseForJson the elements before returning like $rawData
  // TODO probably just shouldn't have this
  List get list => new List.unmodifiable(_list);

  Map operator[](int index) {
    return _list[index];
  }

  // TODO we should probably just return the futures from these?
  Future add(data) {
    var key = firebase.push().key;
    var ref = firebase.child(key);
    // TODO they check that arguments were passed to this method on js side
    // if (arguments.length > 0)
    return ref.set(_parseForJson(data));
  }

  Future set(key, data) {
    return firebase.child(key).set(_parseForJson(data));
  }

  Future update(key, data) {
    return firebase.child(key).update(_parseForJson(data));
  }

  Future setPriority(key, priority) {
    return firebase.child(key).setPriority(priority);
  }

  Future remove(key) {
    return firebase.child(key).remove();
  }

  void off() {
    _dispose();
  }

  void _initListeners() {
    _subs.add(firebase.onChildAdded.listen(_serverAdd));
    _subs.add(firebase.onChildRemoved.listen(_serverRemove));
    _subs.add(firebase.onChildChanged.listen(_serverChange));
    _subs.add(firebase.onChildMoved.listen(_serverMove));
  }

  void _serverAdd(Event event) {
    var data = _parseVal(event.snapshot.key, event.snapshot.val());
    _moveTo(event.snapshot.key, data, event.prevChild);
    _onValueAdded.add(new FirebaseListEvent(FirebaseListEvent.VALUE_ADDED,
        event.snapshot.key, data, _posByKey(event.snapshot.key), event));
  }

  void _serverRemove(Event event) {
    var pos = _posByKey(event.snapshot.key);
    if (pos != -1) {
      var data = _list[pos];
      _list.removeAt(pos);
      _onValueRemoved.add(new FirebaseListEvent(FirebaseListEvent.VALUE_REMOVED,
          event.snapshot.key, data, pos, event));
    }
  }

  void _serverChange(Event event) {
    var pos = _posByKey(event.snapshot.key);
    if (pos != -1) {
      _list[pos] = _applyToBase(
          _list[pos], _parseVal(event.snapshot.key, event.snapshot.val()));
      _onValueSet.add(new FirebaseListEvent(FirebaseListEvent.VALUE_SET,
          event.snapshot.key, _list[pos], pos, event));
    }
  }

  void _serverMove(Event event) {
    var id = event.snapshot.key;
    var oldPos = _posByKey(id);
    if (oldPos != -1) {
      var data = _list[oldPos];
      _list.removeAt(oldPos);
      _moveTo(id, data, event.prevChild);
      _onValueRemoved.add(new FirebaseListEvent(FirebaseListEvent.VALUE_REMOVED,
          event.snapshot.key, data, oldPos, event));
      _onValueAdded.add(new FirebaseListEvent(FirebaseListEvent.VALUE_ADDED,
          event.snapshot.key, data, _posByKey(event.snapshot.key), event));
    }
  }

  void _moveTo(String key, Map data, String prevChild) {
    var pos = _placeRecord(key, prevChild);
    _list.insert(pos, data);
  }

  int _placeRecord(String key, String prevChild) {
    if (prevChild == null) {
      return 0;
    } else {
      var i = _posByKey(prevChild);
      if (i == -1) {
        return _list.length;
      } else {
        return i + 1;
      }
    }
  }

  int _posByKey(String key) {
    for (var i = 0, len = _list.length; i < len; i++) {
      if (_list[i][r'$id'] == key) {
        return i;
      }
    }
    return -1;
  }

  _parseVal(String key, data) {
    if (data is! Map) {
      data = {'.value': data};
    }
    data[r'$id'] = key;
    return data;
  }

  _parseForJson(data) {
    if (data is Map) {
      data.remove(r'$id');
      if (data.containsKey('.value')) {
        data = data['.value'];
      }
    }
    // TODO this was on js side. When would this happen?
    // I think we just don't have to do it
    // if (data === undefined) {
    //   data = null
    // }
    return data;
  }

  _applyToBase(Map base, Map data) {
    if (base is Map && data is Map) {
      var id = base[r'$id'];
      base.clear();
      base.addAll(data);
      base[r'$id'] = id;
      return base;
    } else {
      return data;
    }
  }

  _dispose() {
    _subs.forEach((sub) {
      sub.cancel();
    });
    _subs.clear();
  }
}
