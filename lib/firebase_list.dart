library firebase_list;

import 'dart:async';
import 'package:firebase/firebase.dart';
import 'package:collection_helpers/equality.dart';

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
  StreamController _onValueAdded = new StreamController.broadcast(sync: true);
  StreamController _onValueRemoved = new StreamController.broadcast(sync: true);
  StreamController _onValueSet = new StreamController.broadcast(sync: true);

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

  DataSnapshot getSnapshot(int index) {
    return _snaps[_list[index][r'$id']];
  }

  DataSnapshot getSnapshotByKey(String key) {
    return _snaps[key];
  }

  int indexOf(String key) {
    return _posByKey(key);
  }

  /// Add the provided value to the end of the list
  Firebase add(data) {
    var update = getAddUpdate(data);
    firebase.update(update);
    return firebase.child(update.keys.first);
  }

  /// Produce a Map that can be passed to firebase.update to add to the list
  /// `list.firebase.update(list.getAddUpdate(data))` is equivalent to
  /// `list.add(data)`
  Map getAddUpdate(data) {
    var _data = _parseForUpdate(data);
    var ref = firebase.push();
    var priority = 0;
    if (_list.length != 0) {
      priority = _snaps[_list.last[r'$id']].getPriority() + 1;
    }
    _data['.priority'] = priority;
    return {ref.key: _data};
  }

  void set(int index, newValue) {
    firebase.update(getSetUpdate(index, newValue));
  }

  Map getSetUpdate(int index, newValue) {
    var result = {};
    if (index >= 0 && index < _list.length) {
      var key = _list[index][r'$id'];
      if (!_snaps.containsKey(key)) {
        throw new Exception('No child at $key');
      } else {
        var priority = _snaps[key].getPriority();
        result[key] = _parseForUpdate(newValue);
        result[key]['.priority'] = priority;
        return result;
      }
    } else {
      throw new IndexError(index, this);
    }
  }

  void remove(int index) {
    var update = getRemoveUpdate(index);
    if (update != null) {
      firebase.update(update);
    }
  }

  Map getRemoveUpdate(int index) {
    if (index >= 0 && index < _list.length) {
      return {_list[index][r'$id']: null};
    } else {
      return null;
    }
  }

  void removeRange(int startIndex, int endIndex) {
    var update = getRemoveRangeUpdate(startIndex, endIndex);
    if (update != null) {
      firebase.update(update);
    }
  }

  Map getRemoveRangeUpdate(int startIndex, int endIndex) {
    if (endIndex > _list.length) {
      endIndex = _list.length;
    }

    if (endIndex <= startIndex || startIndex < 0 || startIndex > _list.length) {
      return null;
    }

    // build update object to remove all keys
    Map update = {};
    for (int i = startIndex; i < endIndex; i++) {
      update[_list[i][r'$id']] = null;
    }
    return update;
  }

  void clear() {
    var update = getClearUpdate();
    if (update != null) {
      firebase.update(update);
    }
  }

  Map getClearUpdate() {
    return getRemoveRangeUpdate(0, length);
  }

  void removeByKey(String key) {
    firebase.update(getRemoveByKeyUpdate(key));
  }

  Map getRemoveByKeyUpdate(String key) {
    return {key: null};
  }

  void move(int index, destinationIndex) {
    var update = getMoveUpdate(index, destinationIndex);
    if (update != null) {
      firebase.update(update);
    }
  }

  Map getMoveUpdate(int index, destinationIndex) {
    // index has to be a valid current index
    if (index >= 0 && index < _list.length) {
      // destination has to be at least zero and not equal to index or one more
      if (destinationIndex >= 0 &&
          destinationIndex != index &&
          destinationIndex != index + 1) {
        // if moving to end, set priority after current last element
        if (destinationIndex > _list.length - 1) {
          return {
            _list[index][r'$id'] + '/.priority':
                _snaps[_list[_list.length - 1][r'$id']].getPriority() + 1
          };
        } else if (destinationIndex == 0) {
          // if moving to beginning, set to priority before first element
          return {
            _list[index][r'$id'] + '/.priority':
                _snaps[_list.first[r'$id']].getPriority() - 1
          };
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

            return update;
          } else {
            return {
              _list[index][r'$id'] + '/.priority':
                  (prevPriority + nextPriority) / 2
            };
          }
        }
      }
    }
    return null;
  }

  Firebase insert(int index, newValue, [bool forceIndexUpdate = false]) {
    var update = getInsertUpdate(index, newValue, forceIndexUpdate);
    firebase.update(update);
    return _lastInsertedRef;
  }

  Firebase _lastInsertedRef;

  Map getInsertUpdate(int index, newValue, [bool forceIndexUpdate = false]) {
    if (_list.length == 0 || index >= _list.length) {
      return getAddUpdate(newValue);
    }

    var ref = firebase.push();
    _lastInsertedRef = ref;
    var value = _parseForUpdate(newValue);

    if (index == 0) {
      var priority = _snaps[_list[0][r'$id']].getPriority();
      value['.priority'] = priority - 1;
      return {ref.key: value};
    } else {
      var prevPriority = _snaps[_list[index - 1][r'$id']].getPriority();
      var nextPriority = _snaps[_list[index][r'$id']].getPriority();

      // if diff is getting small, reset priorities
      if (nextPriority - prevPriority < _MIN_PRIORITY_DIFF ||
          forceIndexUpdate) {
        var update = {};
        for (var listIndex = 0; listIndex < this.list.length; listIndex++) {
          update[this.list[listIndex][r'$id'] + '/.priority'] =
              // skip index we are going to insert at
              ((listIndex >= index) ? listIndex + 1 : listIndex);
        }

        // do update without new value so moves get filtered for being the same
        // index
        value['.priority'] = index;
        update[ref.key] = value;
        return update;
      } else {
        value['.priority'] = (prevPriority + nextPriority) / 2;
        return {ref.key: value};
      }
    }
  }

  void off() {
    _dispose();
  }

  // TODO can reset priorities without providing update
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
      var ordered = true;
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
      // check if the non-priority value has changed
      var mapEq = const MapEquality();
      bool same = mapEq.equals(
          _list[pos], _parseVal(event.snapshot.key, event.snapshot.val()));
      if (!same) {
        _list[pos] = _applyToBase(
            _list[pos], _parseVal(event.snapshot.key, event.snapshot.val()));
        _onValueSet.add(new FirebaseListEvent(FirebaseListEvent.VALUE_SET,
            event.snapshot.key, _list[pos], pos, event));
      }
    }
  }

  void _serverMove(Event event) {
    var id = event.snapshot.key;
    var oldPos = _posByKey(id);
    if (oldPos != -1) {
      // if new index is the same as old index, don't do anything
      if (!(event.prevChild == null && oldPos == 0 ||
          _posByKey(event.prevChild) == oldPos - 1)) {
        var data = _list[oldPos];
        _list.removeAt(oldPos);
        _moveTo(id, data, event.prevChild);
        _onValueRemoved.add(new FirebaseListEvent(
            FirebaseListEvent.VALUE_REMOVED,
            event.snapshot.key,
            data,
            oldPos,
            event));
        _onValueAdded.add(new FirebaseListEvent(FirebaseListEvent.VALUE_ADDED,
            event.snapshot.key, data, _posByKey(event.snapshot.key), event));
      }
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

  // parse a value to store in the local list
  _parseVal(String key, data) {
    if (data is! Map) {
      data = {'.value': data};
    }
    data[r'$id'] = key;
    return data;
  }

  // parse a value to be sent to a firebase update
  _parseForUpdate(data) {
    // put in .value because there will be a priority
    if (data is! Map) {
      data = {'.value': data};
    }
    // make sure the id isn't stored in it
    data.remove(r'$id');
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
