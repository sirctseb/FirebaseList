import 'package:firebase/firebase.dart';
import 'package:firebase_list/firebase_list.dart';
import 'package:logging/logging.dart';
import 'package:logging_handlers/logging_handlers_shared.dart';
import 'package:test/test.dart';

main() {
  hierarchicalLoggingEnabled = true;
  Logger.root.onRecord.listen(new LogPrintHandler());
  Logger.root.level = Level.INFO;

  Firebase fb;
  fb = new Firebase('https://test-4892.firebaseio.com');

  group('FirebaseList', () {
    setUp(() async {
      await fb.set({
        'a': {'hello': 'world', 'aNumber': 1, 'aBoolean': false},
        'b': {'foo': 'bar', 'aNumber': 2, 'aBoolean': true},
        'c': {'bar': 'baz', 'aNumber': 3, 'aBoolean': true}
      }).catchError((error) {
        print(error);
      });
    });

    test('loads initial data', () async {
      var list = new FirebaseList(fb);
      await list.onReady;

      var val = {
        'a': {'hello': 'world', 'aNumber': 1, 'aBoolean': false},
        'b': {'foo': 'bar', 'aNumber': 2, 'aBoolean': true},
        'c': {'bar': 'baz', 'aNumber': 3, 'aBoolean': true}
      };

      expect(list.length, equals(val.length));
    });

    test('handles child_added from server', () async {
      var list = new FirebaseList(fb);
      await list.onReady;

      var oldLength = list.length;
      fb.child('foo').set({'hello': 'world'});

      expect(list.length, equals(oldLength + 1));
    });

    test('handles child_removed from server', () async {
      var list = new FirebaseList(fb);
      await list.onReady;

      var oldLength = list.length;
      fb.child('b').remove();
      expect(list.length, equals(oldLength - 1));
    });

    test('handles child_moved from server', () async {
      var list = new FirebaseList(fb);
      await list.onReady;

      var oldLength = list.length;
      fb.child('a').setPriority(100);

      expect(list.length, equals(oldLength));
      expect(list[oldLength - 1][r'$id'], equals('a'));
    });

    test('triggers callback for add', () async {
      var list = new FirebaseList(fb);
      await list.onReady;

      var s = list.onValueAdded.listen(expectAsync((event) {
        expect(event.type, FirebaseListEvent.VALUE_ADDED);
        expect(event.data, contains('foo'));
      }, count: 1));

      var len = list.length;
      expect(len, greaterThan(0));

      await fb.push().set({'foo': 'bar'});

      s.cancel();
    });

    test('triggers callback for remove', () async {
      var list = new FirebaseList(fb);
      await list.onReady;

      var s = list.onValueRemoved.listen(expectAsync((event) {
        expect(event.type, FirebaseListEvent.VALUE_REMOVED);
      }, count: 1));

      var len = list.length;
      expect(len, greaterThan(0));

      await fb.child('a').remove();

      expect(list.length, len - 1);

      s.cancel();
    });

    test('triggers callback for change', () async {
      var list = new FirebaseList(fb);
      await list.onReady;

      var s = list.onValueSet.listen(expectAsync((event) {
        expect(event.type, FirebaseListEvent.VALUE_SET);
      }, count: 1));

      var len = list.length;
      expect(len, greaterThan(0));

      await fb.child('a').set({'hello': 'world'});

      expect(list.length, len);

      s.cancel();
    });

    test('triggers callback for move', () async {
      var list = new FirebaseList(fb);
      await list.onReady;

      var sa = list.onValueAdded.listen(expectAsync((event) {
        expect(event.type, FirebaseListEvent.VALUE_ADDED);
      }, count: 1));
      var sr = list.onValueRemoved.listen(expectAsync((event) {
        expect(event.type, FirebaseListEvent.VALUE_REMOVED);
      }, count: 1));

      var len = list.length;
      expect(len, greaterThan(0));

      await fb.child('a').setPriority(100);

      expect(list.length, len);

      sa.cancel();
      sr.cancel();
    });

    // TODO after updating to index interface
    // test('should not cause events in existing lists', () {
    // });
  });

  // TODO ?
  //group(r'$rawData' () {});

  group('getSnapshot', () {
    setUp(() async {
      await fb.set({
        'a': {'hello': 'world', 'aNumber': 1, 'aBoolean': false},
        'b': {'foo': 'bar', 'aNumber': 2, 'aBoolean': true},
        'c': {'bar': 'baz', 'aNumber': 3, 'aBoolean': true}
      }).catchError((error) {
        print(error);
      });
    });

    test('returns correct snapshot', () async {
      var list = new FirebaseList(fb);
      await list.onReady;

      var snapshot = list.getSnapshot(1);
      expect(snapshot.key, list[1][r'$id']);
    });

    test('returns snapshot synchronously', () async {
      var list = new FirebaseList(fb);
      await list.onReady;

      var ref = list.add('newvalue');

      var snapshot = list.getSnapshot(3);
      expect(snapshot.key, ref.key);
      expect(snapshot.key, list[3][r'$id']);
    });
  });

  group('off', () {
    setUp(() async {
      await fb.set({
        'a': {'hello': 'world', 'aNumber': 1, 'aBoolean': false},
        'b': {'foo': 'bar', 'aNumber': 2, 'aBoolean': true},
        'c': {'bar': 'baz', 'aNumber': 3, 'aBoolean': true}
      }).catchError((error) {
        print(error);
      });
    });
    test('stops listening to events', () async {
      var list = new FirebaseList(fb);
      await list.onReady;

      var oldLength = list.length;

      list.off();

      fb.push(value: {'hello': 'world'});

      expect(list.length, oldLength);
    });
  });

  group('indexOf', () {
    setUp(() async {
      await fb.set({
        'a': {'hello': 'world', 'aNumber': 1, 'aBoolean': false},
        'b': {'foo': 'bar', 'aNumber': 2, 'aBoolean': true},
        'c': {'bar': 'baz', 'aNumber': 3, 'aBoolean': true}
      }).catchError((error) {
        print(error);
      });
    });

    test('returns correct index for existing records', () async {
      var list = new FirebaseList(fb);
      await list.onReady;

      var i = 0;

      var snap = await fb.once('value');
      snap.val().forEach((key, value) {
        expect(list.indexOf(key), i++);
      });
    });

    test('returns -1 for missing record', () async {
      var list = new FirebaseList(fb);
      await list.onReady;

      expect(list.length, greaterThan(0));
      expect(list.indexOf('notakey'), -1);
    });
  });

  group('add', () {
    setUp(() async {
      await fb.set(null).catchError((error) {
        print(error);
      });
    });

    test('returns a Firebase ref containing the record id', () async {
      var list = new FirebaseList(fb);
      await list.onReady;

      expect(list.length, 0);
      var ref = list.add({'foo': 'bar'});
      expect(list.indexOf(ref.key), 0);
    });

    test('adds primitives', () async {
      var list = new FirebaseList(fb);
      await list.onReady;

      expect(list.length, 0);
      list.add(true);

      expect(list[0]['.value'], true);
    });

    test('adds objects', () async {
      var list = new FirebaseList(fb);
      await list.onReady;

      expect(list.length, 0);
      var id = list.add({'foo': 'bar'}).key;

      expect(list[0], equals({r'$id': id, 'foo': 'bar'}));
    });

    test('emits event synchronously', () async {
      var list = new FirebaseList(fb);
      await list.onReady;

      bool flag = false;
      var s = list.onValueAdded.listen((event) {
        expect(event.type, FirebaseListEvent.VALUE_ADDED);
        expect(event.data, contains('foo'));
        expect(flag, false);
        flag = true;
      });

      list.add({'foo': 'bar'});
      expect(flag, true);

      s.cancel();
    });
  });

  group('set', () {
    setUp(() async {
      return await fb.set({
        'a': {'hello': 'world', 'aNumber': 1, 'aBoolean': false},
        'b': 'bar',
        'c': {'bar': 'baz', 'aNumber': 3, 'aBoolean': true}
      });
    });
    test('updates existing primitive', () async {
      var list = new FirebaseList(fb);
      await list.onReady;

      expect(list[1]['.value'], 'bar');
      list.set(1, 'baz');

      expect(list[1]['.value'], 'baz');
    });
    test('updates existing object', () async {
      var list = new FirebaseList(fb);
      await list.onReady;

      var dat = (await fb.child('a').once('value')).val();

      dat['test'] = true;

      list.set(0, dat);

      expect(list[0]['test'], true);
    });

    test('does not replace object references', () async {
      var list = new FirebaseList(fb);
      await list.onReady;

      // TODO is this the same as the js side?
      var listCopy = list.list;

      list.set(0, {'test': 'hello'});

      expect(list.length, greaterThan(0));
      for (int i = 0; i < list.length; i++) {
        expect(list[i], equals(listCopy[i]));
      }
    });

    test('does not create record if does not exist', () async {
      var list = new FirebaseList(fb);
      await list.onReady;

      var len = list.length;
      expect(() => list.set(100, {'hello': 'world'}), throws);

      expect(list.length, len);
    });
  });

  group('remove', () {
    setUp(() async {
      await fb.set({
        'a': {'hello': 'world', 'aNumber': 1, 'aBoolean': false},
        'b': {'foo': 'bar', 'aNumber': 2, 'aBoolean': true},
        'c': {'bar': 'baz', 'aNumber': 3, 'aBoolean': true}
      }).catchError((error) {
        print(error);
      });
    });

    test('removes existing records', () async {
      var list = new FirebaseList(fb);
      await list.onReady;

      var len = list.length;
      list.remove(0);

      expect(list.length, len - 1);
      expect(list.indexOf('a'), -1);
    });

    test('noop if record does not exist', () async {
      var list = new FirebaseList(fb);
      await list.onReady;

      var len = list.length;

      list.remove(-1);
      list.remove(100);

      expect(list.length, len);
    });
  });

  group('removeRange', () {
    setUp(() async {
      await fb.set({
        'a': {'hello': 'world', 'aNumber': 1, 'aBoolean': false},
        'b': {'foo': 'bar', 'aNumber': 2, 'aBoolean': true},
        'c': {'bar': 'baz', 'aNumber': 3, 'aBoolean': true}
      }).catchError((error) {
        print(error);
      });
    });

    test('removes existing records', () async {
      var list = new FirebaseList(fb);
      await list.onReady;

      var len = list.length;
      list.removeRange(0, 2);

      expect(list.length, len - 2);
      expect(list.indexOf('a'), -1);
      expect(list.indexOf('b'), -1);
      expect(list.indexOf('c'), 0);
    });

    test('noop if starting index is >= length', () async {
      var list = new FirebaseList(fb);
      await list.onReady;

      var len = list.length;
      list.removeRange(3, 5);

      expect(list.length, len);
      expect(list.indexOf('a'), 0);
      expect(list.indexOf('b'), 1);
      expect(list.indexOf('c'), 2);
    });

    test('accepts end indices larger than length', () async {
      var list = new FirebaseList(fb);
      await list.onReady;

      var len = list.length;
      list.removeRange(2, 5);

      expect(list.length, len - 1);
      expect(list.indexOf('a'), 0);
      expect(list.indexOf('b'), 1);
      expect(list.indexOf('c'), -1);
    });
  });

  group('removeByKey', () {
    setUp(() async {
      await fb.set({
        'a': {'hello': 'world', 'aNumber': 1, 'aBoolean': false},
        'b': {'foo': 'bar', 'aNumber': 2, 'aBoolean': true},
        'c': {'bar': 'baz', 'aNumber': 3, 'aBoolean': true}
      }).catchError((error) {
        print(error);
      });
    });

    test('removes existing records', () async {
      var list = new FirebaseList(fb);
      await list.onReady;

      var len = list.length;
      list.removeByKey('a');

      expect(list.length, len - 1);
      expect(list.indexOf('a'), -1);
    });

    test('does not blow up if record does not exist', () async {
      var list = new FirebaseList(fb);
      await list.onReady;

      var len = list.length;

      list.removeByKey('notakey');

      expect(list.length, len);
      // TODO this doesn't make sense anymore
      expect(list.indexOf('notakey'), -1);
    });
  });

  group('move', () {
    test('moves existing records', () async {
      var list = new FirebaseList(fb);
      await list.onReady;

      var snap = await fb.once('value');

      List keys = snap.val().keys.toList();
      keys.add(keys.removeAt(0));

      list.move(0, 100);

      for (int i = 0; i < list.length; i++) {
        expect(list.indexOf(keys[i]), i);
      }
    });

    test('does not change if record does not exist', () async {
      var list = new FirebaseList(fb);
      await list.onReady;

      var snap = await fb.once('value');
      var keys = snap.val().keys.toList();

      list.move(4, 100);

      for (int i = 0; i < list.length; i++) {
        expect(list.indexOf(keys[i]), i);
      }
    });
  });

  group('insert', () {
    setUp(() async {
      return await fb.set(null);
    });

    test('returns a Firebase ref containing the record id', () async {
      var list = new FirebaseList(fb);
      await list.onReady;

      expect(list.length, 0);

      list.add({'foo': 'zero'});
      list.add({'foo': 'two'});

      var ref = list.insert(1, {'foo': 'one'});

      expect(list.indexOf(ref.key), 1);
    });

    test('adds primitives', () async {
      var list = new FirebaseList(fb);
      await list.onReady;

      expect(list.length, 0);

      list.add(false);
      list.add(false);

      list.insert(1, true);

      expect(list[1]['.value'], true);
    });

    test('adds objects', () async {
      var list = new FirebaseList(fb);
      await list.onReady;

      expect(list.length, 0);
      list.add({'foo': 'zero'});
      list.add({'foo': 'two'});

      var id = list.insert(1, {'foo': 'one'}).key;

      expect(list[1], equals({r'$id': id, 'foo': 'one'}));
    });

    test('inserts into empty list', () async {
      var list = new FirebaseList(fb);
      await list.onReady;

      list.insert(0, 'zero');
      expect(list.length, 1);
    });

    test('inserts at end', () async {
      var list = new FirebaseList(fb);
      await list.onReady;

      list.add('zero');
      list.insert(1, 'one');

      expect(list.length, 2);
      expect(list[1]['.value'], 'one');
    });

    test('resets priorities to indices', () async {
      var list = new FirebaseList(fb);
      await list.onReady;

      list.add('zero');
      list.add('three');
      list.insert(1, 'two');

      // force priority reset
      list.insert(1, 'one', true);

      fb.once('value').then((snap) {
        int index = 0;
        snap.forEach((childSnap) {
          expect(childSnap.getPriority(), index++);
        });
      });
    });

    test('doesn\'t incur extra events on index reset', () async {
      var list = new FirebaseList(fb);
      await list.onReady;

      list.add('zero');
      list.add('three');
      list.insert(1, 'two');

      var sa = list.onValueAdded.listen(expectAsync((event) {
        expect(event.index, 1);
        expect(event.data['.value'], 'one');
        // print('got value added at index ${event.index}');
      }, count: 1));
      var sr = list.onValueRemoved.listen(expectAsync((event) {
        // expect(false, true);
      }, count: 0));
      var ss = list.onValueSet.listen(expectAsync((event) {
        // expect(event.index, 1);
      }, count: 0));

      // force priority reset
      list.insert(1, 'one', true);

      sa.cancel();
      sr.cancel();
      ss.cancel();
    });
  });

  group('clear', () {
    setUp(() async {
      await fb.set({
        'a': {'hello': 'world', 'aNumber': 1, 'aBoolean': false},
        'b': {'foo': 'bar', 'aNumber': 2, 'aBoolean': true},
        'c': {'bar': 'baz', 'aNumber': 3, 'aBoolean': true}
      }).catchError((error) {
        print(error);
      });
    });

    test('removes existing records', () async {
      var list = new FirebaseList(fb);
      await list.onReady;

      list.clear();

      expect(list.length, 0);
      expect(list.indexOf('a'), -1);
      expect(list.indexOf('b'), -1);
      expect(list.indexOf('c'), -1);
    });

    test('handles noop', () async {
      var list = new FirebaseList(fb);
      await list.onReady;

      fb.set(null);

      list.clear();

      expect(list.length, 0);
      expect(list.indexOf('a'), -1);
      expect(list.indexOf('b'), -1);
      expect(list.indexOf('c'), -1);
    });
  });
}
