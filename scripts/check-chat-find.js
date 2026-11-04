const assert = require('node:assert/strict');
const { matches, segments } = require('../Resources/Views/chat/chat-find.js');

assert.deepEqual(matches(['Hello Nero', 'nero again'], 'NERO').hits,
  [{message:0,start:6,end:10},{message:1,start:0,end:4}]);
assert.equal(matches(['abc', 'def'], 'cd').hits.length, 0); // Never bridge separate messages.
assert.equal(matches(['one'], '   ').hits.length, 0);
assert.deepEqual(matches(['Use [a+b].* literally'], '[a+b].*').hits, [{message:0,start:4,end:11}]);
assert.deepEqual(matches(['Hi café 🌿!'], 'CAFÉ 🌿').hits, [{message:0,start:3,end:10}]);
assert.equal(matches(['<script>stay text</script>'], '<script>').hits.length, 1);
assert.equal(matches(['x'.repeat(501)], 'x').hits.length, 500);
assert.equal(matches(['x'.repeat(501)], 'x').overflow, true);
assert.equal(matches(['x'.repeat(500)], 'x').overflow, false);
assert.deepEqual(segments([4,3,5],2,10), [{node:0,start:2,end:4},{node:1,start:0,end:3},{node:2,start:0,end:3}]);
assert.deepEqual(segments([0,3,0],0,3), [{node:1,start:0,end:3}]);
assert.deepEqual(segments([2,3],5,5), []);
assert.equal(matches(['one'], ' '.repeat(256)+'one').hits.length, 0); // Bound user input.
console.log('Chat Find: 13 local matcher/range checks passed.');
