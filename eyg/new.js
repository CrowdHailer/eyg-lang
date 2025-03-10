let int_add = (x) => (y) => x + y;
let int_multiply = (x) => (y) => x * y;
let int_subtract = (x) => (y) => x - y;
let string_from_binary = (_) => { throw "string_from_binary" };
let binary_from_integers = (_) => { throw "binary_from_integers" };
let binary_fold = (_) => { throw "binary_fold" };
function Eff(label, value, k) {
  this.label = label;
  this.value = value;
  this.k = k;
}

let bind = (m, then) => {
  if (!(m instanceof Eff)) return then(m);
  let k = (x) => bind(m.k(x), then);
  return new Eff(m.label, m.value, k);
};

let perform = (label) => (value) => new Eff(label, value, (x) => x);

let extrinsic = {
  Alert: (message) => window.alert(message), 
  Ask: (x) => 10, 
  Log: (x) => console.log(x) 
};
let run = (exec) => {
  let m = exec
  while (m instanceof Eff) {
    m = m.k(extrinsic[m.label](m.value));
  }
  return m;
};
let list_pop = (items) =>
  items.length == 0
  ? {$T: "Error", $V: {}}
  : {$T: "Ok", $V: {head: items[0], tail: items[1]}};
let list_fold = (items) => (acc) => (f) => {
  let item;
  while (items.length != 0) {
    item = items[0];
    items = items[1];
    acc = f(acc)(item);
  }
  return acc
};
let handle = (label) => (handler) => (exec) => {
  return do_handle(label, handler, exec({}));
};

let do_handle = (label, handler, m) => {
  if (!(m instanceof Eff)) return m;
  let k = (x) => do_handle(label, handler, m.k(x));
  if (m.label == label) return handler(m.value)(k);
  return new Eff(m.label, m.value, k);
};
let fix = (_) => { throw "fix" };
let int_compare = (x) => (y) => {
  if (x < y) return {$T: "Lt", $V: {}}
  if (y > x) return {$T: "Gt", $V: {}}
  return {$T: "Eq", $V: {}}
};
let string_to_binary = (_) => { throw "string_to_binary" };
let $$0 = TODO;
let equal$2 = $$0.equal;
let boolean$6 = $$0.boolean;
let integer$10 = $$0.integer;
let list$14 = $$0.list;
let characters$18 = ({tab: 9, line_feed: 10, carriage_return: 13, space: 32, back_slash: 92, a: 97, e: 101, f: 102, l: 108, n: 110, r: 114, s: 115, t: 116, u: 117});
let whitespace$76 = [characters$18.tab, [characters$18.line_feed, [characters$18.carriage_return, [characters$18.space, []]]]];
let nonzero$102 = [49, [50, [51, [52, [53, [54, [55, [56, [57, []]]]]]]]]];
let read_true$140 = ((count$141) => {
  return ((char$142) => {
  return ((acc$143) => {
  let r$144 = boolean$6.and(equal$2(3)(count$141))(equal$2(char$142)(characters$18.r));
  let u$162 = boolean$6.and(equal$2(2)(count$141))(equal$2(char$142)(characters$18.u));
  let e$180 = boolean$6.and(equal$2(1)(count$141))(equal$2(char$142)(characters$18.e));
  return (function($) { switch ($.$T) {
case 'True':   return ((_$202) => {
  return ({state: {$T: "True", $V: integer$10.subtract(count$141)(1)}, acc: acc$143});
})($.$V)
case 'False':   return ((_$223) => {
  return (function($) { switch ($.$T) {
case 'True':   return ((_$228) => {
  return ({state: {$T: "Top", $V: ({})}, acc: [{$T: "True", $V: ({})}, acc$143]});
})($.$V)
case 'False':   return ((_$249) => {
  return ({state: {$T: "Top", $V: ({})}, acc: [{$T: "Unexpected", $V: char$142}, acc$143]});
})($.$V)
}})(e$180);
})($.$V)
}})(boolean$6.or(r$144)(u$162));
});
});
});
let read_false$277 = ((count$278) => {
  return ((char$279) => {
  return ((acc$280) => {
  let a$281 = boolean$6.and(equal$2(4)(count$278))(equal$2(char$279)(characters$18.a));
  let l$299 = boolean$6.and(equal$2(3)(count$278))(equal$2(char$279)(characters$18.l));
  let s$317 = boolean$6.and(equal$2(2)(count$278))(equal$2(char$279)(characters$18.s));
  let e$335 = boolean$6.and(equal$2(1)(count$278))(equal$2(char$279)(characters$18.e));
  return (function($) { switch ($.$T) {
case 'True':   return ((_$357) => {
  return ({state: {$T: "False", $V: integer$10.subtract(count$278)(1)}, acc: acc$280});
})($.$V)
case 'False':   return ((_$378) => {
  return (function($) { switch ($.$T) {
case 'True':   return ((_$383) => {
  return ({state: {$T: "Top", $V: ({})}, acc: [{$T: "False", $V: ({})}, acc$280]});
})($.$V)
case 'False':   return ((_$404) => {
  return ({state: {$T: "Top", $V: ({})}, acc: [{$T: "Unexpected", $V: char$279}, acc$280]});
})($.$V)
}})(e$335);
})($.$V)
}})(boolean$6.or(a$281)(boolean$6.or(l$299)(s$317)));
});
});
});
let read_null$438 = ((count$439) => {
  return ((char$440) => {
  return ((acc$441) => {
  let u$442 = boolean$6.and(equal$2(3)(count$439))(equal$2(char$440)(characters$18.u));
  let l$460 = boolean$6.and(equal$2(2)(count$439))(equal$2(char$440)(characters$18.l));
  let l2$478 = boolean$6.and(equal$2(1)(count$439))(equal$2(char$440)(characters$18.l));
  return (function($) { switch ($.$T) {
case 'True':   return ((_$500) => {
  return ({state: {$T: "Null", $V: integer$10.subtract(count$439)(1)}, acc: acc$441});
})($.$V)
case 'False':   return ((_$521) => {
  return (function($) { switch ($.$T) {
case 'True':   return ((_$526) => {
  return ({state: {$T: "Top", $V: ({})}, acc: [{$T: "Null", $V: ({})}, acc$441]});
})($.$V)
case 'False':   return ((_$547) => {
  return ({state: {$T: "Top", $V: ({})}, acc: [{$T: "Unexpected", $V: char$440}, acc$441]});
})($.$V)
}})(l2$478);
})($.$V)
}})(boolean$6.or(u$442)(l$460));
});
});
});
let read_decimal$575 = ((negative$576) => {
  return ((integer$577) => {
  return ((decimals$578) => {
  return ((char$579) => {
  return ((acc$580) => {
  return (function($) { switch ($.$T) {
case 'False':   return ((_$585) => {
  return (function($) { switch ($.$T) {
case 'True':   return ((_$590) => {
  return {$T: "Continue", $V: throw TODO};
})($.$V)
case 'False':   return ((_$597) => {
  return {$T: "Stop", $V: {$T: "Decimal", $V: ({negative: negative$576, integer: integer$577, decimals: list$14.reverse(decimals$578)})}};
})($.$V)
}})(equal$2(char$579)(65));
})($.$V)
case 'True':   return ((_$628) => {
  let decimals$629 = [char$579, decimals$578];
  return {$T: "Continue", $V: {$T: "Decimal", $V: ({negative: negative$576, integer: integer$577, decimals: decimals$629})}};
})($.$V)
}})(list$14.contains([48, nonzero$102])(char$579));
});
});
});
});
});
let read_integer$664 = ((negative$665) => {
  return ((integer$666) => {
  return ((char$667) => {
  return ((acc$668) => {
  return (function($) { switch ($.$T) {
case 'False':   return ((_$673) => {
  return (function($) { switch ($.$T) {
case 'True':   return ((_$678) => {
  return {$T: "Continue", $V: {$T: "Decimal", $V: ({negative: negative$665, integer: integer$666, decimals: []})}};
})($.$V)
case 'False':   return ((_$699) => {
  return {$T: "Stop", $V: {$T: "Integer", $V: ({negative: negative$665, integer: integer$666})}};
})($.$V)
}})(equal$2(char$667)(46));
})($.$V)
case 'True':   return ((_$722) => {
  let integer$723 = int_add(int_multiply(integer$666)(10))(int_subtract(char$667)(48));
  return {$T: "Continue", $V: {$T: "Integer", $V: ({negative: negative$665, integer: integer$723})}};
})($.$V)
}})(list$14.contains([48, nonzero$102])(char$667));
});
});
});
});
let read_string$762 = ((buffer$763) => {
  return ((char$764) => {
  return ((acc$765) => {
  return (function($) { switch ($.$T) {
case 'True':   return ((_$770) => {
  return ({state: {$T: "Escape", $V: buffer$763}, acc: acc$765});
})($.$V)
case 'False':   return ((_$785) => {
  return (function($) { switch ($.$T) {
case 'True':   return ((_$790) => {
  let value$791 = (function($) { switch ($.$T) {
case 'Ok':   return ((value$796) => {
  return {$T: "String", $V: value$796};
})($.$V)
case 'Error':   return ((_$803) => {
  return {$T: "Unexpected", $V: 0};
})($.$V)
}})(string_from_binary(binary_from_integers(list$14.reverse(buffer$763))));
  return ({state: {$T: "Top", $V: ({})}, acc: [value$791, acc$765]});
})($.$V)
case 'False':   return ((_$835) => {
  return ({state: {$T: "String", $V: [char$764, buffer$763]}, acc: acc$765});
})($.$V)
}})(equal$2(char$764)(34));
})($.$V)
}})(equal$2(char$764)(92));
});
});
});
let read_escape$863 = ((buffer$864) => {
  return ((char$865) => {
  return ((acc$866) => {
  return (function($) { switch ($.$T) {
case 'True':   return ((_$871) => {
  return ({state: {$T: "String", $V: [92, buffer$864]}, acc: acc$866});
})($.$V)
case 'False':   return ((_$890) => {
  return (function($) { switch ($.$T) {
case 'True':   return ((_$895) => {
  return ({state: {$T: "String", $V: [34, buffer$864]}, acc: acc$866});
})($.$V)
case 'False':   return ((_$914) => {
  return (function($) { switch ($.$T) {
case 'True':   return ((_$919) => {
  return ({state: {$T: "String", $V: [13, buffer$864]}, acc: acc$866});
})($.$V)
case 'False':   return ((_$938) => {
  return (function($) { switch ($.$T) {
case 'True':   return ((_$943) => {
  return ({state: {$T: "String", $V: [10, buffer$864]}, acc: acc$866});
})($.$V)
case 'False':   return ((_$962) => {
  return (function($) { switch ($.$T) {
case 'True':   return ((_$967) => {
  return ({state: {$T: "String", $V: [9, buffer$864]}, acc: acc$866});
})($.$V)
case 'False':   return ((_$986) => {
  return ({state: {$T: "Top", $V: ({})}, acc: [{$T: "UnexpectedEscape", $V: char$865}, acc$866]});
})($.$V)
}})(equal$2(char$865)(116));
})($.$V)
}})(equal$2(char$865)(110));
})($.$V)
}})(equal$2(char$865)(114));
})($.$V)
}})(equal$2(char$865)(34));
})($.$V)
}})(equal$2(char$865)(92));
});
});
});
let read_top$1034 = ((char$1035) => {
  return ((acc$1036) => {
  return (function($) { switch ($.$T) {
case 'True':   return ((_$1041) => {
  return ({state: {$T: "Top", $V: ({})}, acc: acc$1036});
})($.$V)
case 'False':   return ((_$1056) => {
  return (function($) { switch ($.$T) {
case 'True':   return ((_$1061) => {
  return ({state: {$T: "True", $V: 3}, acc: acc$1036});
})($.$V)
case 'False':   return ((_$1076) => {
  return (function($) { switch ($.$T) {
case 'True':   return ((_$1081) => {
  return ({state: {$T: "False", $V: 4}, acc: acc$1036});
})($.$V)
case 'False':   return ((_$1096) => {
  return (function($) { switch ($.$T) {
case 'True':   return ((_$1101) => {
  return ({state: {$T: "Null", $V: 3}, acc: acc$1036});
})($.$V)
case 'False':   return ((_$1116) => {
  return (function($) { switch ($.$T) {
case 'True':   return ((_$1121) => {
  return ({state: {$T: "Top", $V: ({})}, acc: [{$T: "LeftBracket", $V: ({})}, acc$1036]});
})($.$V)
case 'False':   return ((_$1142) => {
  return (function($) { switch ($.$T) {
case 'True':   return ((_$1147) => {
  return ({state: {$T: "Top", $V: ({})}, acc: [{$T: "RightBracket", $V: ({})}, acc$1036]});
})($.$V)
case 'False':   return ((_$1168) => {
  return (function($) { switch ($.$T) {
case 'True':   return ((_$1173) => {
  return ({state: {$T: "Top", $V: ({})}, acc: [{$T: "LeftBrace", $V: ({})}, acc$1036]});
})($.$V)
case 'False':   return ((_$1194) => {
  return (function($) { switch ($.$T) {
case 'True':   return ((_$1199) => {
  return ({state: {$T: "Top", $V: ({})}, acc: [{$T: "RightBrace", $V: ({})}, acc$1036]});
})($.$V)
case 'False':   return ((_$1220) => {
  return (function($) { switch ($.$T) {
case 'True':   return ((_$1225) => {
  return ({state: {$T: "Top", $V: ({})}, acc: [{$T: "Colon", $V: ({})}, acc$1036]});
})($.$V)
case 'False':   return ((_$1246) => {
  return (function($) { switch ($.$T) {
case 'True':   return ((_$1251) => {
  return ({state: {$T: "Top", $V: ({})}, acc: [{$T: "Comma", $V: ({})}, acc$1036]});
})($.$V)
case 'False':   return ((_$1272) => {
  return (function($) { switch ($.$T) {
case 'True':   return ((_$1277) => {
  return ({state: {$T: "String", $V: []}, acc: acc$1036});
})($.$V)
case 'False':   return ((_$1292) => {
  return (function($) { switch ($.$T) {
case 'True':   return ((_$1297) => {
  return ({state: {$T: "Integer", $V: ({negative: {$T: "True", $V: ({})}, integer: 0})}, acc: acc$1036});
})($.$V)
case 'False':   return ((_$1322) => {
  return (function($) { switch ($.$T) {
case 'True':   return ((_$1327) => {
  return ({state: {$T: "Integer", $V: ({negative: {$T: "False", $V: ({})}, integer: 0})}, acc: acc$1036});
})($.$V)
case 'False':   return ((_$1352) => {
  return (function($) { switch ($.$T) {
case 'True':   return ((_$1357) => {
  return ({state: {$T: "Integer", $V: ({negative: {$T: "False", $V: ({})}, integer: int_subtract(char$1035)(48)})}, acc: acc$1036});
})($.$V)
case 'False':   return ((_$1386) => {
  return ({state: {$T: "Top", $V: ({})}, acc: [{$T: "Unexpected", $V: char$1035}, acc$1036]});
})($.$V)
}})(list$14.contains(nonzero$102)(char$1035));
})($.$V)
}})(equal$2(char$1035)(48));
})($.$V)
}})(equal$2(char$1035)(45));
})($.$V)
}})(equal$2(char$1035)(34));
})($.$V)
}})(equal$2(char$1035)(44));
})($.$V)
}})(equal$2(char$1035)(58));
})($.$V)
}})(equal$2(char$1035)(125));
})($.$V)
}})(equal$2(char$1035)(123));
})($.$V)
}})(equal$2(char$1035)(93));
})($.$V)
}})(equal$2(char$1035)(91));
})($.$V)
}})(equal$2(char$1035)(110));
})($.$V)
}})(equal$2(char$1035)(102));
})($.$V)
}})(equal$2(char$1035)(116));
})($.$V)
}})(list$14.contains(whitespace$76)(char$1035));
});
});
let do_tokenise$1492 = ((bytes$1493) => {
  let state$1494 = ({state: {$T: "Top", $V: ({})}, acc: []});
  return binary_fold(bytes$1493)(state$1494)(((char$1512) => {
  return (($$1513) => {
  let state$1514 = $$1513.state;
  let acc$1518 = $$1513.acc;
  return (function($) { switch ($.$T) {
case 'Top':   return ((_$1526) => {
  return read_top$1034(char$1512)(acc$1518);
})($.$V)
case 'True':   return ((n$1535) => {
  return read_true$140(n$1535)(char$1512)(acc$1518);
})($.$V)
case 'False':   return ((n$1546) => {
  return read_false$277(n$1546)(char$1512)(acc$1518);
})($.$V)
case 'Null':   return ((n$1557) => {
  return read_null$438(n$1557)(char$1512)(acc$1518);
})($.$V)
case 'Integer':   return (($$1568) => {
  let negative$1569 = $$1568.negative;
  let integer$1573 = $$1568.integer;
  return (function($) { switch ($.$T) {
case 'Continue':   return ((state$1581) => {
  return ({state: state$1581, acc: acc$1518});
})($.$V)
case 'Stop':   return ((number$1594) => {
  return read_top$1034(char$1512)([number$1594, acc$1518]);
})($.$V)
}})(read_integer$664(negative$1569)(integer$1573)(char$1512)(acc$1518));
})($.$V)
case 'Decimal':   return (($$1617) => {
  let negative$1618 = $$1617.negative;
  let integer$1622 = $$1617.integer;
  let decimals$1626 = $$1617.decimals;
  return (function($) { switch ($.$T) {
case 'Continue':   return ((state$1634) => {
  return ({state: state$1634, acc: acc$1518});
})($.$V)
case 'Stop':   return ((number$1647) => {
  return read_top$1034(char$1512)([number$1647, acc$1518]);
})($.$V)
}})(read_decimal$575(negative$1618)(integer$1622)(decimals$1626)(char$1512)(acc$1518));
})($.$V)
case 'String':   return ((buffer$1672) => {
  return read_string$762(buffer$1672)(char$1512)(acc$1518);
})($.$V)
case 'Escape':   return ((buffer$1683) => {
  return read_escape$863(buffer$1683)(char$1512)(acc$1518);
})($.$V)
}})(state$1514);
});
}));
});
let tokenise$1693 = ((bytes$1694) => {
  let $$1695 = do_tokenise$1492(bytes$1694);
  let state$1699 = $$1695.state;
  let acc$1703 = $$1695.acc;
  let acc$1707 = (function($) { switch ($.$T) {
case 'Top':   return ((_$1712) => {
  return acc$1703;
})($.$V)
case 'Integer':   return ((integer$1717) => {
  return [{$T: "Integer", $V: integer$1717}, acc$1703];
})($.$V)
case 'Decimal':   return (($$1728) => {
  let negative$1729 = $$1728.negative;
  let decimals$1733 = $$1728.decimals;
  let integer$1737 = $$1728.integer;
  return [{$T: "Decimal", $V: ({negative: negative$1729, integer: integer$1737, decimals: list$14.reverse(decimals$1733)})}, acc$1703];
})($.$V)
default:   return ((_$1764) => {
  return [{$T: "UnexpectedEnd", $V: ({})}, acc$1703];
})($)}})(state$1699);
  return list$14.reverse(acc$1707);
});
let state$1778 = ({stack: [], acc: []});
let _$1788 = "stack cant be recursive data structure EYG doesn't support them";
let pop$1790 = ((stack$1791) => {
  return ((token$1792) => {
  return ((then$1793) => {
  return (function($) { switch ($.$T) {
case 'Ok':   return (($$1798) => {
  let head$1799 = $$1798.head;
  let tail$1803 = $$1798.tail;
  return bind(then$1793(head$1799), (($k0) => {
  return $k0(tail$1803);
}));
})($.$V)
case 'Error':   return ((_$1815) => {
  return perform ("Break")({$T: "UnexpectedChar", $V: token$1792});
})($.$V)
}})(list_pop(stack$1791));
});
});
});
let nudge_stack$1825 = ((stack$1826) => {
  return ((acc$1827) => {
  return (function($) { switch ($.$T) {
case 'Ok':   return (($$1832) => {
  let head$1833 = $$1832.head;
  let tail$1837 = $$1832.tail;
  return (function($) { switch ($.$T) {
case 'ArrayFirst':   return ((_$1845) => {
  return ({stack: [{$T: "ArraySeparator", $V: ({})}, tail$1837], acc: acc$1827});
})($.$V)
case 'ArrayElement':   return ((_$1864) => {
  return ({stack: [{$T: "ArraySeparator", $V: ({})}, tail$1837], acc: acc$1827});
})($.$V)
case 'ObjectValue':   return ((_$1883) => {
  return ({stack: [{$T: "ObjectSeparator", $V: ({})}, tail$1837], acc: acc$1827});
})($.$V)
default:   return ((_$1899) => {
  return perform ("Break")({$T: "InvalidState", $V: ({})});
})($)}})(head$1833);
})($.$V)
case 'Error':   return ((_$1909) => {
  return ({stack: stack$1826, acc: acc$1827});
})($.$V)
}})(list_pop(stack$1826));
});
});
let value$1923 = ((term$1924) => {
  return ((stack$1925) => {
  return ((acc$1926) => {
  let depth$1927 = list$14.length(stack$1925);
  return nudge_stack$1825(stack$1925)([({term: term$1924, depth: depth$1927}), acc$1926]);
});
});
});
let do_flat$1950 = ((bytes$1951) => {
  return list_fold(tokenise$1693(bytes$1951))(state$1778)(((item$1960) => {
  return (($$1961) => {
  let stack$1962 = $$1961.stack;
  let acc$1966 = $$1961.acc;
  let depth$1970 = list$14.length(stack$1962);
  return bind((function($) { switch ($.$T) {
case 'True':   return ((_$1981) => {
  return (function($) { switch ($.$T) {
case 'True':   return ((_$1986) => {
  return ({stack: stack$1962, acc: acc$1966});
})($.$V)
case 'False':   return ((_$1999) => {
  return perform ("Break")({$T: "UnexpectedChar", $V: item$1960});
})($.$V)
}})(equal$2(list$14.length(acc$1966))(0));
})($.$V)
case 'False':   return ((_$2018) => {
  return ({stack: stack$1962, acc: acc$1966});
})($.$V)
}})(equal$2(depth$1970)(0)), ((_$1976) => {
  return bind((function($) { switch ($.$T) {
case 'LeftBracket':   return ((_$2039) => {
  return ({stack: [{$T: "ArrayFirst", $V: ({})}, stack$1962], acc: [({term: {$T: "Array", $V: ({})}, depth: depth$1970}), acc$1966]});
})($.$V)
case 'RightBracket':   return ((_$2072) => {
  return pop$1790(stack$1962)(item$1960)(((node$2079) => {
  return ((stack$2080) => {
  return (function($) { switch ($.$T) {
case 'ArrayFirst':   return ((_$2085) => {
  return nudge_stack$1825(stack$2080)(acc$1966);
})($.$V)
case 'ArraySeparator':   return ((_$2094) => {
  return nudge_stack$1825(stack$2080)(acc$1966);
})($.$V)
default:   return ((_$2100) => {
  return perform ("Break")({$T: "UnexpectedChar", $V: item$1960});
})($)}})(node$2079);
});
}));
})($.$V)
case 'LeftBrace':   return ((_$2110) => {
  return ({stack: [{$T: "KeyFirst", $V: ({})}, stack$1962], acc: [({term: {$T: "Object", $V: ({})}, depth: depth$1970}), acc$1966]});
})($.$V)
case 'RightBrace':   return ((_$2143) => {
  return pop$1790(stack$1962)(item$1960)(((node$2150) => {
  return ((stack$2151) => {
  return (function($) { switch ($.$T) {
case 'KeyFirst':   return ((_$2156) => {
  return nudge_stack$1825(stack$2151)(acc$1966);
})($.$V)
case 'ObjectSeparator':   return ((_$2165) => {
  return nudge_stack$1825(stack$2151)(acc$1966);
})($.$V)
default:   return ((_$2171) => {
  return perform ("Break")({$T: "UnexpectedChar", $V: item$1960});
})($)}})(node$2150);
});
}));
})($.$V)
case 'Colon':   return ((_$2181) => {
  return pop$1790(stack$1962)(item$1960)(((node$2188) => {
  return ((stack$2189) => {
  return (function($) { switch ($.$T) {
case 'Colon':   return ((_$2194) => {
  return ({stack: [{$T: "ObjectValue", $V: ({})}, stack$2189], acc: acc$1966});
})($.$V)
default:   return ((_$2210) => {
  return perform ("Break")({$T: "UnexpectedChar", $V: item$1960});
})($)}})(node$2188);
});
}));
})($.$V)
case 'Comma':   return ((_$2220) => {
  return pop$1790(stack$1962)(item$1960)(((node$2227) => {
  return ((stack$2228) => {
  return (function($) { switch ($.$T) {
case 'ArraySeparator':   return ((_$2233) => {
  return ({stack: [{$T: "ArrayElement", $V: ({})}, stack$2228], acc: acc$1966});
})($.$V)
case 'ObjectSeparator':   return ((_$2252) => {
  return ({stack: [{$T: "Key", $V: ({})}, stack$2228], acc: acc$1966});
})($.$V)
default:   return ((_$2268) => {
  return perform ("Break")({$T: "UnexpectedChar", $V: item$1960});
})($)}})(node$2227);
});
}));
})($.$V)
case 'Unexpected':   return ((x$2278) => {
  return perform ("Break")({$T: "Unexpected", $V: x$2278});
})($.$V)
case 'True':   return ((_$2287) => {
  return value$1923({$T: "True", $V: ({})})(stack$1962)(acc$1966);
})($.$V)
case 'False':   return ((_$2300) => {
  return value$1923({$T: "False", $V: ({})})(stack$1962)(acc$1966);
})($.$V)
case 'Null':   return ((_$2313) => {
  return value$1923({$T: "Null", $V: ({})})(stack$1962)(acc$1966);
})($.$V)
case 'Integer':   return ((i$2326) => {
  return value$1923({$T: "Integer", $V: i$2326})(stack$1962)(acc$1966);
})($.$V)
case 'Decimal':   return ((i$2339) => {
  return value$1923({$T: "Decimal", $V: i$2339})(stack$1962)(acc$1966);
})($.$V)
case 'String':   return ((string$2352) => {
  return pop$1790(stack$1962)(item$1960)(((node$2359) => {
  return ((stack$2360) => {
  return (function($) { switch ($.$T) {
case 'KeyFirst':   return ((_$2365) => {
  return ({stack: [{$T: "Colon", $V: ({})}, stack$2360], acc: [({term: {$T: "Field", $V: string$2352}, depth: depth$1970}), acc$1966]});
})($.$V)
case 'Key':   return ((_$2398) => {
  return ({stack: [{$T: "Colon", $V: ({})}, stack$2360], acc: [({term: {$T: "Field", $V: string$2352}, depth: depth$1970}), acc$1966]});
})($.$V)
case 'ObjectValue':   return ((_$2431) => {
  return value$1923({$T: "String", $V: string$2352})([node$2359, stack$2360])(acc$1966);
})($.$V)
case 'ArrayFirst':   return ((_$2448) => {
  return value$1923({$T: "String", $V: string$2352})([node$2359, stack$2360])(acc$1966);
})($.$V)
case 'ArrayElement':   return ((_$2465) => {
  return value$1923({$T: "String", $V: string$2352})([node$2359, stack$2360])(acc$1966);
})($.$V)
default:   return ((_$2479) => {
  return perform ("Break")({$T: "UnexpectedChar", $V: item$1960});
})($)}})(node$2359);
});
}));
})($.$V)
case 'UnexpectedEscape':   return ((x$2489) => {
  return perform ("Break")({$T: "UnexpectedEscape", $V: x$2489});
})($.$V)
case 'UnexpectedEnd':   return ((x$2498) => {
  return perform ("Break")({$T: "UnexpectedEnd", $V: x$2498});
})($.$V)
}})(item$1960), ((x$2034) => {
  return x$2034;
}));
}));
});
}));
});
let flat$2507 = ((bytes$2508) => {
  return handle ("Break")(((value$2512) => {
  return ((resume$2513) => {
  return {$T: "Error", $V: value$2512};
});
}))(((_$2517) => {
  return bind(do_flat$1950(bytes$2508), (($k1) => {
  let parsed$2518 = list$14.reverse($k1.acc);
  return {$T: "Ok", $V: parsed$2518};
}));
}));
});
let describe$2532 = ((term$2533) => {
  return (function($) { switch ($.$T) {
case 'String':   return ((_$2538) => {
  return "String";
})($.$V)
default:   return ((_$2540) => {
  return "Unexpected";
})($)}})(term$2533);
});
let decode$2531 = let fail$2543 = ((expected$2544) => {
  return ((got$2545) => {
  return {$T: "Error", $V: ({expected: expected$2544, got: describe$2532(got$2545)})};
});
});
let null$2559 = ((packed$2560) => {
  return (function($) { switch ($.$T) {
case 'Ok':   return (($$2565) => {
  let head$2566 = $$2565.head;
  return (function($) { switch ($.$T) {
case 'Null':   return ((_$2574) => {
  return {$T: "Ok", $V: {$T: "Null", $V: ({})}};
})($.$V)
default:   return ((other$2580) => {
  return fail$2543("String")(other$2580);
})($)}})(head$2566.term);
})($.$V)
case 'Error':   return ((_$2592) => {
  return fail$2543("String")({$T: "UnexpectedEnd", $V: ({})});
})($.$V)
}})(list_pop(packed$2560));
});
let boolean$2604 = ((packed$2605) => {
  return (function($) { switch ($.$T) {
case 'Ok':   return (($$2610) => {
  let head$2611 = $$2610.head;
  return (function($) { switch ($.$T) {
case 'True':   return ((_$2619) => {
  return {$T: "Ok", $V: {$T: "True", $V: ({})}};
})($.$V)
case 'False':   return ((_$2628) => {
  return {$T: "Ok", $V: {$T: "False", $V: ({})}};
})($.$V)
default:   return ((other$2634) => {
  return fail$2543("String")(other$2634);
})($)}})(head$2611.term);
})($.$V)
case 'Error':   return ((_$2646) => {
  return fail$2543("String")({$T: "UnexpectedEnd", $V: ({})});
})($.$V)
}})(list_pop(packed$2605));
});
let string$2658 = ((packed$2659) => {
  return (function($) { switch ($.$T) {
case 'Ok':   return (($$2664) => {
  let head$2665 = $$2664.head;
  return (function($) { switch ($.$T) {
case 'String':   return ((string$2673) => {
  return {$T: "Ok", $V: string$2673};
})($.$V)
default:   return ((other$2677) => {
  return fail$2543("String")(other$2677);
})($)}})(head$2665.term);
})($.$V)
case 'Error':   return ((_$2689) => {
  return fail$2543("String")({$T: "UnexpectedEnd", $V: ({})});
})($.$V)
}})(list_pop(packed$2659));
});
let array$2701 = ((cast$2702) => {
  return ((packed$2703) => {
  return (function($) { switch ($.$T) {
case 'Ok':   return (($$2708) => {
  let head$2709 = $$2708.head;
  let tail$2713 = $$2708.tail;
  let $$2717 = head$2709;
  let term$2719 = $$2717.term;
  let depth$2723 = $$2717.depth;
  return (function($) { switch ($.$T) {
case 'Array':   return ((_$2731) => {
  let depth$2732 = int_add(depth$2723)(1);
  return bind(fix(((self$2742) => {
  return ((acc$2743) => {
  return ((packed$2744) => {
  return bind((function($) { switch ($.$T) {
case 'Ok':   return (($$2750) => {
  let head$2751 = $$2750.head;
  let tail$2755 = $$2750.tail;
  return (function($) { switch ($.$T) {
case 'Lt':   return ((_$2763) => {
  return {$T: "Ok", $V: list$14.reverse(acc$2743)};
})($.$V)
case 'Eq':   return ((_$2774) => {
  return bind(cast$2702(packed$2744), (($k3) => {
  return (function($) { switch ($.$T) {
case 'Ok':   return ((item$2779) => {
  return bind(self$2742([item$2779, acc$2743]), (($k2) => {
  return $k2(tail$2755);
}));
})($.$V)
case 'Error':   return ((reason$2792) => {
  return {$T: "Error", $V: reason$2792};
})($.$V)
}})($k3);
}));
})($.$V)
case 'Gt':   return ((_$2803) => {
  return bind(self$2742(acc$2743), (($k4) => {
  return $k4(tail$2755);
}));
})($.$V)
}})(int_compare(head$2751.depth)(depth$2732));
})($.$V)
case 'Error':   return ((_$2820) => {
  return {$T: "Ok", $V: list$14.reverse(acc$2743)};
})($.$V)
}})(list_pop(packed$2744)), ((acc$2745) => {
  return acc$2745;
}));
});
});
}))([]), (($k5) => {
  return $k5(tail$2713);
}));
})($.$V)
default:   return ((other$2835) => {
  return fail$2543("Array")(other$2835);
})($)}})(term$2719);
})($.$V)
case 'Error':   return ((_$2845) => {
  return fail$2543("String")({$T: "UnexpectedEnd", $V: ({})});
})($.$V)
}})(list_pop(packed$2703));
});
});
let _$2857 = ((todo$2858) => {
  return array$2701(string$2658)((function($) { switch ($.$T) {
case 'Error':   return ((_$2867) => {
  return throw TODO;
})($.$V)
case 'Ok':   return ((v$2872) => {
  return v$2872;
})($.$V)
}})(flat$2507(string_to_binary("[\"a\"]"))));
});
let leave$2880 = "leave";
({null: ({}), boolean: boolean$2604, string: string$2658, array: array$2701});
let leave$2899 = "leave";
let program = ({tokenise: tokenise$1693, flat: flat$2507, decode: decode$2531});
run(program)