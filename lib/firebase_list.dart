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

  static final num _MIN_PRIORITY_DIFF = 0.00000005;

  List _list = [];
  Map _snaps = {};

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

  Future _onReady;
  Future get onReady => _onReady;

  /// The length of the list
  int get length => _list.length;

  /// An unmodifiable [List] representation of the list
  // TODO should _parseForJson the elements before returning like $rawData
  // TODO probably just shouldn't have this
  List get list => new List.unmodifiable(_list);

  Map operator [](int index) {
    return _list[index];
  }

  int indexOf(String key) {
    return _posByKey(key);
  }

  // TODO should we just return the futures from these?

  // TODO js side allows push without supplying data
  Firebase add(data) {
    var ref = firebase.push();
    ref.set(_parseForJson(data));
    return ref;
  }

  void set(int index, newValue) {
    if (index >= 0 && index < _list.length) {
      var key = _list[index][r'$id'];
      if (!_snaps.containsKey(key)) {
        throw new Exception('No child at $key');
      } else {
        var priority = _snaps[key].getPriority();
        firebase.child(key).setWithPriority(_parseForJson(newValue), priority);
      }
    }
  }

  // TODO probably remove and provide accessor to snapshots that they can
  // use to update. this isn't listy
  void update(int index, newValue) {
    if (index >= 0 && index < _list.length) {
      var key = _list[index][r'$id'];
      firebase.child(key).update(_parseForJson(newValue));
    }
  }

  void setPriority(key, priority) {
    firebase.child(key).setPriority(priority);
  }

  void remove(int index) {
    if (index >= 0 && index < _list.length) {
      firebase.child(_list[index][r'$id']).remove();
    }
  }

  void move(int index, destinationIndex) {
    // index has to be a valid current index
    if (index >= 0 && index < _list.length) {
      // destination has to be at least zero and not equal to index or one more
      if (destinationIndex >= 0 &&
          destinationIndex != index &&
          destinationIndex != index + 1) {}
      // if moving to end, set priority after current last element
      if (destinationIndex > _list.length - 1) {
        _snaps[_list[index][r'$id']].ref().setPriority(
            _snaps[_list[_list.length - 1][r'$id']].getPriority() + 1);
      } else {
        // otherwise, set priority between surrounding elements
        var prevPriority =
            _snaps[_list[destinationIndex - 1][r'$id']].getPriority();
        var nextPriority =
            _snaps[_list[destinationIndex][r'$id']].getPriority();

        // if surrounding priority diff is too small, reset to indices
        if (nextPriority - prevPriority < _MIN_PRIORITY_DIFF) {
          // figure out final index of moving element
          var finalIndex;
          if (destinationIndex > index) {
            finalIndex = destinationIndex - 1;
          } else {
            finalIndex = destinationIndex;
          }

          var update = {};
          var newIndex = 0;
          for (var listIndex = 0; listIndex < _list.length; listIndex++) {
            if (listIndex == index) {
              update[_list[listIndex][r'$id'] + '/.priority'] = finalIndex;
            } else if (listIndex < destinationIndex) {
              update[_list[listIndex][r'$id'] + '/.priority'] = newIndex;
              newIndex++;
            } else {
              update[_list[listIndex][r'$id'] + '/.priority'] = newIndex + 1;
              newIndex++;
            }
          }

          firebase.update(update);
        } else {
          firebase.setPriority((prevPriority + nextPriority) / 2);
        }
      }
    }
  }

  void off() {
    _dispose();
  }

  void _initListeners() {
    _subs.add(firebase.onChildAdded.listen(_serverAdd));
    _subs.add(firebase.onChildRemoved.listen(_serverRemove));
    _subs.add(firebase.onChildChanged.listen(_serverChange));
    _subs.add(firebase.onChildMoved.listen(_serverMove));
    // simulate childAddeds for the values already in the list because
    // on the dart side, we don't get back events if anyone has listened
    // on the firebase instance
    _onReady = firebase.once('value').then((snapshot) {
      var last = null;
      snapshot.forEach((childSnap) {
        _serverAdd(new Event(childSnap, last));
        last = childSnap.key;
      });

      // initialize priorities
      var ordered = false;
      var update = {};
      var index = 0;
      snapshot.forEach((childSnap) {
        update[childSnap.key + '/.priority'] = index++;

        if (childSnap.getPriority() == null) {
          ordered = false;
        }
      });

      if (!ordered) {
        return firebase.update(update);
      }
    });
  }

  void _serverAdd(Event event) {
    // Due to a bug in dart-firebase, onChildAdded doesn't get back events
    // except for the first one added to a given firebase instance, so
    // make sure the key doesn't already appear in the list, because on first
    // load, the _onReady and onChildAddeds will both add
    if (!_list.any((item) => item[r'$id'] == event.snapshot.key)) {
      _snaps[event.snapshot.key] = event.snapshot;
      var data = _parseVal(event.snapshot.key, event.snapshot.val());
      _moveTo(event.snapshot.key, data, event.prevChild);
      _onValueAdded.add(new FirebaseListEvent(FirebaseListEvent.VALUE_ADDED,
          event.snapshot.key, data, _posByKey(event.snapshot.key), event));
    }
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
    _snaps[event.snapshot.key] = event.snapshot;
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
