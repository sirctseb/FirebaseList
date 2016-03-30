import 'package:firebase/firebase.dart';
import 'package:firebase_list/firebase_list.dart';
import 'package:logging/logging.dart';
import 'package:logging_handlers/logging_handlers_shared.dart';
import 'package:test/test.dart';

main() {
  hierarchicalLoggingEnabled = true;
  Logger.root.onRecord.listen(new LogPrintHandler());
  Logger.root.level = Level.INFO;

  group('FirebaseList', () {
    Firebase fb;
    setUp(() async {
      fb = new Firebase('https://test-4892.firebaseio.com');
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

      Map val = (await fb.once('value')).val();

      expect(list.length, equals(val.length));
    });

    test('handles child_added from server', () {
      var list = new FirebaseList(fb);

      var oldLength = list.length;
      fb.child('foo').set({'hello': 'world'});

      expect(list.length, equals(oldLength + 1));
    });

    test('handles child_removed from server', () {
      var list = new FirebaseList(fb);
      var oldLength = list.length;
      fb.child('b').remove();
      expect(list.length, equals(oldLength - 1));
    });

    test('handles child_moved from server', () {
      var list = new FirebaseList(fb);

      var oldLength = list.length;
      fb.child('a').setPriority(100);

      expect(list.length, equals(oldLength));
      expect(list[oldLength - 1][r'$id'], equals('a'));
    });

    test('triggers callback for add', () async {
      var list = new FirebaseList(fb);
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
}
