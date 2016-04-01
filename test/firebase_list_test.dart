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
  var list;

  group('FirebaseList', () {
    setUp(() async {
      await fb.set({
        'a': {'hello': 'world', 'aNumber': 1, 'aBoolean': false},
        'b': {'foo': 'bar', 'aNumber': 2, 'aBoolean': true},
        'c': {'bar': 'baz', 'aNumber': 3, 'aBoolean': true}
      }).catchError((error) {
        print(error);
      });

      list = new FirebaseList(fb);
      await list.onReady;
    });

    test('loads initial data', () async {
      var val = {
        'a': {'hello': 'world', 'aNumber': 1, 'aBoolean': false},
        'b': {'foo': 'bar', 'aNumber': 2, 'aBoolean': true},
        'c': {'bar': 'baz', 'aNumber': 3, 'aBoolean': true}
      };

      expect(list.length, equals(val.length));
    });

    test('handles child_added from server', () async {
      var oldLength = list.length;
      fb.child('foo').set({'hello': 'world'});

      expect(list.length, equals(oldLength + 1));
    });

    test('handles child_removed from server', () {
      var oldLength = list.length;
      fb.child('b').remove();
      expect(list.length, equals(oldLength - 1));
    });

    test('handles child_moved from server', () {
      var oldLength = list.length;
      fb.child('a').setPriority(100);

      expect(list.length, equals(oldLength));
      expect(list[oldLength - 1][r'$id'], equals('a'));
    });

    test('triggers callback for add', () async {
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

  group('off', () {
    setUp(() async {
      await fb.set({
        'a': {'hello': 'world', 'aNumber': 1, 'aBoolean': false},
        'b': {'foo': 'bar', 'aNumber': 2, 'aBoolean': true},
        'c': {'bar': 'baz', 'aNumber': 3, 'aBoolean': true}
      }).catchError((error) {
        print(error);
      });

      list = new FirebaseList(fb);
      await list.onReady;
    });
    test('stops listening to events', () {
      var oldLength = list.length;

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
      list = new FirebaseList(fb);
      await list.onReady;
    });

    test('returns correct index for existing records', () async {
      var i = 0;

      var snap = await fb.once('value');
      snap.val().forEach((key, value) {
        expect(list.indexOf(key), i++);
      });
    });

    test('returns -1 for missing record', () {
      expect(list.length, greaterThan(0));
      expetc(list.indexOf('notakey'), -1);
    });
  });

  group('add', () {
    setUp(() async {
      await fb.set(null).catchError((error) {
        print(error);
      });
    });

    // TODO these methods are return futures in the dart api,
    // so it doesn't work to test the return value
    test('returns a Firebase ref containing the record id', () {
      expect(list.length, 0);
      var ref = list.add({'foo': 'bar'});
      expect(list.indexOf(ref.key()), 0);
    });

    test('adds primitives', () {
      expect(list.length, 0);
      list.add(true);

      expect(list[0]['.value'], true);
    });

    test('adds objects', () {
      expect(list.length, 0);
      var id = list.add({'foo': 'bar'}).key();

      expect(list[0], equals({r'$id': id, 'foo': 'bar'}));
    });
  });

  group('setAt', () {
    setUp(() async {
      return await fb.set({
        'a': {'hello': 'world', 'aNumber': 1, 'aBoolean': false},
        'b': 'bar',
        'c': {'bar': 'baz', 'aNumber': 3, 'aBoolean': true}
      });

      list = new FirebaseList(fb);
      await list.onReady;
    });
    test('updates existing primitive', () {
      expect(list[1]['.value'], 'bar');
      list.setAt(1, 'baz');

      expect(list[1]['.value'], 'baz');
    });
    test('updates existing object', () async {
      var dat = (await fb.child('a').once('value')).val();

      dat['test'] = true;

      list.setAt(0, dat);

      expect(list[0]['test'], true);
    });

    test('does not replace object references', () {
      // TODO is this the same as the js side?
      var listCopy = list.list;

      list.setAt(0, {'test': 'hello'});

      expect(list.length, greaterThan(0));
      for (int i = 0; i < list.length; i++) {
        expect(list[i], equals(listCopy[i]));
      }
    });

    test('does not create record if does not exist', () {
      var len = list.length;
      list.setAt(100, {'hello': 'world'});

      expect(list.length, len);
      // TODO this doesn't really make sense for the test anymore
      expect(list.indexOf('notakey'), -1);
    });
  });

  group('updateAt', () {
    setUp(() async {
      await fb.set({
        'a': {'hello': 'world', 'aNumber': 1, 'aBoolean': false},
        'b': {'foo': 'bar', 'aNumber': 2, 'aBoolean': true},
        'c': {'bar': 'baz', 'aNumber': 3, 'aBoolean': true},
        'foo': 'bar',
        'hello': 'world'
      }).catchError((error) {
        print(error);
      });

      list = new FirebaseList(fb);
      await list.onReady;
    });

    test('throws error if passed a primitive', () {
      expect(() {
        list.updateAt(3, true);
      }, throws);
    });

    test('replaces a primitive', () {
      list.updateA(3, {'hello': 'world'});

      expect(list[3], {r'$id': 'foo', 'hello': 'world'});
    });

    test('updates object', () {
      list.updateAt(0, {'test': true});

      expect(list[0]['test'], true);
    });

    test('does not affect data that is not part of the update', () {
      var copy = new Map.from(list[0]);

      list.updateAt(0, {'test': true});

      copy.forEach((key, value) {
        expect(list[0][key], value);
      });
    });

    test('does not replace object references', () {
      var listCopy = new List.from(list.list);

      list.updateAt(0, {'test': 'hello'});

      expect(list.length, greaterThan(0));
      for (int i = 0; i < list.length; i++) {
        expect(list[i], equals(listCopy[i]));
      }
    });

    test('does not create record if does not exist', () {
      var len = list.length;
      list.updateAt(100, {'hello': 'world'});

      expect(list.length, len);
      // TODO this doesn't make sense anymore
      expect(list.indexOf('notakey'), -1);
    });
  });

  group('removeAt', () {
    setUp(() async {
      await fb.set({
        'a': {'hello': 'world', 'aNumber': 1, 'aBoolean': false},
        'b': {'foo': 'bar', 'aNumber': 2, 'aBoolean': true},
        'c': {'bar': 'baz', 'aNumber': 3, 'aBoolean': true}
      }).catchError((error) {
        print(error);
      });

      list = new FireabaseList(fb);
      await list.onReady;
    });

    test('removes existing records', () {
      var len = list.length;
      list.removeAt(0);

      expect(list.length, len - 1);
      expect(list.indexOf('a'), -1);
    });

    test('does not blow up if record does not exist', () {
      var len = list.length;

      list.removeAt(-1);
      list.removeAt(100);

      expect(list.length, len);
      // TODO this doesn't make sense anymore
      expect(list.indexOf('notakey'), -1);
    });
  });

  group('move', () {
    setUp(() async {
      await fb.set({
        'a': {'hello': 'world', 'aNumber': 1, 'aBoolean': false},
        'b': {'foo': 'bar', 'aNumber': 2, 'aBoolean': true},
        'c': {'bar': 'baz', 'aNumber': 3, 'aBoolean': true}
      }).catchError((error) {
        print(error);
      });

      list = new FireabaseList(fb);
      await list.onReady;
    });

    test('moves existing records', () async {
      var snap = await fb.once('value');

      List keys = snap.val().keys.toList();
      keys.add(keys.removeAt(0));

      list.move(0, 100);

      for (int i = 0; i < list.length; i++) {
        expect(list.indexOf(keys[i]), i);
      }
    });

    test('does not change if record does not exist', () async {

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
      await fb.set(null);
      list = new FirebaseList(fb);
      await list.onReady;
    });

    test('returns a Firebase ref containing the record id', () {

      expect(list.length, 0);

      list.add({'foo': 'zero'});
      list.add({'foo': 'two'});

      var ref = list.insert(1, {'foo': 'one'});

      expect(list.indexOf(ref.key()), 1);
    });

    test('adds primitives', () {
      expect(list.length, 0);

      list.add(false);
      list.add(false);

      var ref = list.insert(1, true);

      expect(list[1]['.value'], true);
    });

    test('adds objects', () {

      expect(list.length, 0);
      list.add({'foo': 'zero'});
      list.add({'foo': 'two'});

      var id = list.insert(1, {'foo': 'one'}).key();

      expect(list[1], equals({r'$id': id, 'foo': 'one'}));
    });

    test('inserts into empty list', () {
      list.insert(0, 'zero');
      expect(list.length, 1);
    });

    test('inserts at end', () {
      list.add('zero');
      list.insert(1, 'one');

      expect(list.length, 2);
      expect(list[1]['.value'], 'one');
    });
  });
}
